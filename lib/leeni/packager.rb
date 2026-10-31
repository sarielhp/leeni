# frozen_string_literal: true

# ==============================================================================
# lib/leeni/packager.rb
#
# Bundles LaTeX documents, active styles, and figure sources into portable
# zip archives (-z / --zip). Verifies self-contained build in sandbox (-t).
# ==============================================================================

require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative 'flattener'
require_relative 'packaging_shared'

class LatexPackager
  STYLE_EXTS = %w[.sty .cls .clo .def .bbx .cbx .rtx].freeze

  attr_reader :builder, :filename, :bfilename, :bdir, :options

  def initialize(builder)
    @builder = builder
    @filename = builder.filename
    @bfilename = builder.bfilename
    @bdir = builder.bdir
    @options = builder.options
  end

  def package!
    Dir.chdir(File.expand_path(@bdir)) { do_package }
  end

  # Copies everything the paper uses into stage_dir (-z staging, --sandbox).
  # The caller is in the document directory, after a build.
  def stage_into(stage_dir)
    deps = collect_fls_dependencies(File.join(junk_dir, "#{@bfilename}.fls"))
    return false unless stage_all_assets(stage_dir, deps, discover_figure_sources(deps[:figures]))

    LaTeXPackagingShared.drop_nested_archives!(stage_dir)
    true
  end

  private

  def junk_dir
    @builder.respond_to?(:junk_dir) ? @builder.junk_dir : 'junk'
  end

  def do_package
    fls_path = File.join(junk_dir, "#{@bfilename}.fls")
    unless File.exist?(fls_path)
      puts "==> Compiling #{@filename} to collect dependencies for zip..."
      return false unless @builder.run_in_current_directory!
    end

    zip_filename = @options[:zip_name] || "#{@bfilename}.zip"
    return package_from_sandbox(zip_filename) if @options[:zip_alone]

    candidate = stage_and_create_zip(zip_filename)
    return false unless candidate

    publish_packaged_archive(candidate, zip_filename)
  ensure
    FileUtils.rm_f(candidate) if candidate && File.file?(candidate)
  end

  # --zip-alone archives the sandbox it has just checked, so the zip is
  # exactly what built without the environment.
  def package_from_sandbox(zip_filename)
    sandbox = LatexSandbox.new(@builder)
    unless sandbox.run!
      warn Rainbow("[FAIL] Verification failed. Preserved existing #{zip_filename}.").red.bright
      return false
    end

    candidate = archive_candidate_path(zip_filename)
    return false unless zip_directory(sandbox.paper_dir, candidate, zip_filename, '*.synctex.gz', '*.bak')

    File.rename(candidate, zip_filename)
    puts Rainbow("==> Created portable zip: #{zip_filename}").green.bright
    zip_filename
  ensure
    FileUtils.rm_f(candidate) if candidate && File.file?(candidate)
  end

  def zip_directory(dir, candidate, zip_filename, *excluded)
    unless LaTeXUtils.command_available?('zip')
      warn Rainbow("[ERROR] 'zip' command not found in PATH! Cannot create archive.").red.bright
      return false
    end

    FileUtils.rm_f(candidate)
    args = excluded.empty? ? [] : ['-x', *excluded]
    out, status = Open3.capture2e('zip', '-q', '-r', candidate, '.', *args, chdir: dir)
    return true if status.success? && File.file?(candidate) && File.size(candidate).positive?

    warn Rainbow("[FAIL] Failed to create #{zip_filename}: #{out}").red.bright
    false
  end

  def publish_packaged_archive(candidate, zip_filename)
    if @options[:verify] && !verify_archive!(candidate)
      warn Rainbow("[FAIL] Verification failed. Preserved existing #{zip_filename}.").red.bright
      return false
    end

    File.rename(candidate, zip_filename)
    kind = @options[:zip_flat] ? 'flat ' : ''
    puts Rainbow("==> Created portable #{kind}zip: #{zip_filename}").green.bright
    zip_filename
  end

  def collect_fls_dependencies(fls_path)
    content = LaTeXUtils.safe_read(fls_path)
    styles = []
    figures = []
    tex_inputs = []

    content.each_line do |line|
      next unless line.start_with?('INPUT ')

      path = LaTeXPackagingShared.project_twin(line.sub(/^INPUT\s+/, '').strip, junk_dir, STYLE_EXTS)
      next if path.empty? || path.start_with?("#{junk_dir}/") || path.start_with?('junk/') ||
              path.start_with?('.junk/') || system_texmf_file?(path)

      workspace_abs = File.expand_path(junk_dir)
      next if File.expand_path(path).start_with?(workspace_abs + File::SEPARATOR)

      clean_path = normalize_dep_path(path)
      next if [@filename, "#{@bfilename}.pdf"].include?(clean_path)

      categorize_fls_dep(clean_path, styles, figures, tex_inputs)
    end

    { styles: styles.uniq, figures: figures.uniq, tex_inputs: tex_inputs.uniq }
  end

  def categorize_fls_dep(clean_path, styles, figures, tex_inputs)
    case File.extname(clean_path).downcase
    when *STYLE_EXTS
      styles << clean_path
    when '.pdf', '.png', '.jpg', '.jpeg', '.eps', '.mps'
      figures << clean_path unless clean_path.end_with?("#{@bfilename}.pdf")
    when '.tex'
      tex_inputs << clean_path
    end
  end

  def system_texmf_file?(path)
    path =~ %r{/(texmf-dist|texmf-var|texlive/20\d\d|texlive/debian|share/texlive)/}
  end

  def normalize_dep_path(path)
    return path unless path.start_with?('./')

    path.sub(%r{^\./}, '')
  end

  def discover_figure_sources(figures)
    valid_exts = @options[:fig_sources] || ['.fig', '.ipe', '.svg', '.asy', '.gp', '.gnuplot', '.py', '.R']
    discovered = []

    figures.each do |fig|
      dir = File.dirname(fig)
      stem = fig.sub(/\.[^.]+\z/, '')

      valid_exts.each do |ext|
        cand = "#{stem}#{ext}"
        discovered << cand if File.file?(cand)
      end

      base_stem = stem.sub(/[-_]([0-9]+|[a-z]|fig[0-9]+)\z/i, '')
      if base_stem != stem
        valid_exts.each do |ext|
          cand = "#{base_stem}#{ext}"
          discovered << cand if File.file?(cand)
        end
      end

      Dir.glob(File.join(dir, '*.isy')).each do |isy|
        discovered << isy if File.file?(isy)
      end
    end

    discovered.uniq.reject do |p|
      p =~ %r{(^|/)(bak|old|old_ipe)/} || p.end_with?('.bak', '~')
    end
  end

  def scan_bib_from_logs_and_aux
    candidates = []
    blg_file = File.join(junk_dir, "#{@bfilename}.blg")
    if File.file?(blg_file)
      blg_content = LaTeXUtils.safe_read(blg_file)
      blg_content.scan(/(?:Found BibTeX data source|Looking for bibtex file)\s+'([^']+)'/) { |m| candidates << m[0] }
      blg_content.scan(/Database file #\d+:\s*([^\s]+)/) { |m| candidates << m[0] }
    end

    Dir.glob(File.join(junk_dir, '**', '*.aux')).each do |f|
      LaTeXUtils.safe_read(f).scan(/\\bibdata\{([^}]+)\}/).flatten.flat_map { |s| s.split(',') }.each do |stem|
        cand = "#{stem.strip}.bib"
        candidates << cand if File.file?(cand)
      end
    end
    candidates
  end

  def discover_local_bib_files
    candidates = Dir.glob('*.bib') + Dir.glob('{refs,bib,bibliography}/**/*.bib')
    candidates.concat(scan_bib_from_logs_and_aux)

    bcf_file = File.join(junk_dir, "#{@bfilename}.bcf")
    if File.file?(bcf_file)
      LaTeXUtils.safe_read(bcf_file).scan(%r{<bcf:datasource[^>]*>([^<]+)</bcf:datasource>}).flatten.each do |ds|
        candidates << ds if File.file?(ds)
      end
    end

    cwd = Dir.pwd
    selected = candidates.map { |p| normalize_dep_path(p) }.uniq.select do |p|
      expanded = File.expand_path(p)
      File.file?(p) && (expanded.start_with?(cwd + '/') || expanded == cwd || !p.start_with?('/'))
    end
    selected.reject do |p|
      p =~ %r{(^|/)(junk|\.junk|bak|old|archive)/} || p.end_with?('.bak', '~')
    end
  end

  def stage_all_assets(stage_dir, deps, fig_sources)
    copy_target_outputs(stage_dir)

    if @options[:zip_flat]
      return false unless stage_flattened_main_tex(stage_dir, has_styles: !deps[:styles].empty?)

      return stage_remaining_assets(stage_dir, deps, fig_sources)
    end

    stage_main_tex(stage_dir, has_styles: !deps[:styles].empty?)
    deps[:tex_inputs].each { |f| copy_preserving_path(f, stage_dir) if File.file?(f) }
    stage_remaining_assets(stage_dir, deps, fig_sources)
  end

  def stage_remaining_assets(stage_dir, deps, fig_sources)
    stage_styles(deps[:styles], stage_dir)

    discover_local_bib_files.each { |f| copy_preserving_path(f, stage_dir) if File.file?(f) }
    local_bib_styles.each { |f| copy_preserving_path(f, stage_dir) }
    (deps[:figures] + fig_sources).uniq.each { |f| copy_preserving_path(f, stage_dir) if File.file?(f) }

    extra_files = Array(@options[:extra_files]).flat_map { |g| Dir.glob(g).empty? ? [g] : Dir.glob(g) }
    extra_files.uniq.each { |f| copy_preserving_path(f, stage_dir) if File.exist?(f) }
    true
  end

  # BibTeX reruns in the sandbox, so a .bst kept next to the paper must travel.
  def local_bib_styles
    styles = Dir.glob(File.join(junk_dir, '**', '*.aux')).flat_map do |aux|
      LaTeXUtils.safe_read(aux).scan(/\\bibstyle\{([^}]+)\}/).flatten
    end
    styles.uniq.map { |style| "#{style.strip}.bst" }.select { |bst| File.file?(bst) }
  end

  def stage_flattened_main_tex(stage_dir, has_styles: false)
    dest_path = File.join(stage_dir, @filename)
    FileUtils.mkdir_p(File.dirname(dest_path))

    strip_comments = @options[:strip_comments] == true
    begin
      content = LaTeXFlattener.flatten(
        @filename,
        '.',
        @options[:strip_host_patterns],
        strip_comments: strip_comments
      )
    rescue StandardError => e
      warn Rainbow("[FAIL] Could not flatten LaTeX source: #{e.message}").red.bright
      return false
    end

    File.write(dest_path, inject_style_search_path(content, has_styles))
    true
  end

  def stage_and_create_zip(zip_filename)
    candidate = archive_candidate_path(zip_filename)
    succeeded = Dir.mktmpdir('leeni_stage_') do |stage_dir|
      stage_into(stage_dir) && zip_directory(stage_dir, candidate, zip_filename)
    end
    succeeded ? candidate : false
  ensure
    FileUtils.rm_f(candidate) if candidate && !succeeded && File.file?(candidate)
  end

  def archive_candidate_path(zip_filename)
    absolute = File.expand_path(zip_filename)
    File.join(File.dirname(absolute), ".#{File.basename(absolute, '.zip')}.tmp.#{Process.pid}.zip")
  end

  def copy_target_outputs(stage_dir)
    pdf_candidates = ["#{@bfilename}.pdf", File.join(junk_dir, "#{@bfilename}.pdf")]
    pdf_source = pdf_candidates.find { |f| File.file?(f) }
    FileUtils.cp(pdf_source, File.join(stage_dir, "#{@bfilename}.pdf")) if pdf_source

    bbl_candidates = ["#{@bfilename}.bbl", File.join(junk_dir, "#{@bfilename}.bbl")]
    bbl_source = bbl_candidates.find { |f| File.file?(f) }
    return unless bbl_source && LaTeXUtils.bbl_has_entries?(bbl_source)

    FileUtils.cp(bbl_source, File.join(stage_dir, "#{@bfilename}.bbl"))
  end

  def stage_main_tex(stage_dir, has_styles: false)
    dest_path = File.join(stage_dir, @filename)
    FileUtils.mkdir_p(File.dirname(dest_path))

    content = LaTeXUtils.safe_read(@filename)
    File.write(dest_path, inject_style_search_path(content, has_styles))
  end

  def inject_style_search_path(content, has_styles)
    return content unless @options[:inject_styles] && has_styles
    return content if content.include?('input@path') && !@options[:zip_alone]

    definition = if content.include?('input@path')
                   "\\providecommand\\input@path{}\n\\g@addto@macro\\input@path{{styles/}{./}}"
                 else
                   '\\def\\input@path{{styles/}{./}}'
                 end
    inject_into_tex(content, "\\makeatletter\n#{definition}\n\\makeatother\n")
  end

  def inject_into_tex(content, injection)
    lines = content.lines
    insert_idx = lines.find_index { |l| l =~ /^\s*\\(documentclass|RequirePackage|input)/ } || 0
    lines.insert(insert_idx, injection).join
  end

  def stage_styles(styles, stage_dir)
    if @options[:inject_styles]
      dest_dir = File.join(stage_dir, 'styles')
      FileUtils.mkdir_p(dest_dir)
      styles.each do |style|
        FileUtils.cp(style, File.join(dest_dir, File.basename(style))) if File.file?(style)
      end
    else
      styles.each do |style|
        copy_preserving_path(style, stage_dir) if File.file?(style)
      end
    end
  end

  def copy_preserving_path(src, dest_root)
    LaTeXPackagingShared.copy_preserving_path(src, dest_root, recursive: true)
  end

  def verify_archive!(zip_filename)
    zip_abs = File.expand_path(zip_filename)
    puts Rainbow('==> Verifying archive portability in isolated sandbox...').cyan.bright

    unless LaTeXUtils.command_available?('unzip')
      warn Rainbow("[ERROR] 'unzip' command not found in PATH! Cannot verify archive.").red.bright
      return false
    end

    Dir.mktmpdir('leeni_verify_') do |tmpdir|
      unzip_out, unzip_stat = Open3.capture2e('unzip', '-q', zip_abs, '-d', tmpdir)
      unless unzip_stat.success?
        warn Rainbow("[FAIL] Failed to extract #{zip_filename}: #{unzip_out}").red.bright
        return false
      end

      run_sandbox_compile(tmpdir)
    end
  end

  def run_sandbox_compile(tmpdir)
    bundled_pdf = File.join(tmpdir, "#{@bfilename}.pdf")
    backup_pdf = File.join(tmpdir, "#{@bfilename}.pdf.bundled")
    FileUtils.mv(bundled_pdf, backup_pdf) if File.file?(bundled_pdf)
    compile_in_sandbox(tmpdir, backup_pdf, tmpdir)
  end

  # Builds the paper in dir with --no-env (HOME and TeX trees under env_root)
  # and compares the result with reference_pdf.
  def compile_in_sandbox(dir, reference_pdf, env_root)
    compile_out, compile_err, compile_stat = Open3.capture3(sandbox_environment(env_root), *sandbox_command, chdir: dir)
    new_pdf = File.join(dir, "#{@bfilename}.pdf")

    unless compile_stat.success? && File.file?(new_pdf) && File.size(new_pdf).positive?
      warn Rainbow('[FAIL] Verification failed! Document did not compile in clean environment.').red.bright
      warn compile_out
      warn compile_err unless compile_err.empty?
      return false
    end
    return false if @options[:zip_alone] && !verify_clean_diagnostics(compile_out)
    return false unless verify_pdf_diff(reference_pdf, new_pdf)
    return false if visual_check? && !verify_pdf_visual_match(reference_pdf, new_pdf)

    puts Rainbow(verified_message).green.bright
    true
  end

  def sandbox_command
    cmd = [RbConfig.ruby, LEENI_EXECUTABLE, '--no-env', '--engine', @builder.engine_name]
    cmd += ['--json', '--all', '--force'] if @options[:zip_alone]
    cmd << '--errors-only' if @options[:errors_only]
    cmd << '--werror' if @options[:errors_only] && @options[:werror]
    cmd += ['--timeout', @options[:timeout].to_s] if @options[:timeout]
    cmd << @filename
  end

  # --zip-alone requires the page comparison; --make-indep runs it whenever
  # pdftoppm is installed, since its text check alone misses swapped figures.
  def visual_check?
    return true if @options[:zip_alone]
    return false unless @options[:make_indep] || @options[:sandbox]
    return true if LaTeXUtils.command_available?('pdftoppm')

    puts Rainbow(" -- Page comparison skipped: 'pdftoppm' is unavailable.").yellow
    false
  end

  def verified_message
    return '[VERIFIED] Converted project compiles with --no-env and matches the original PDF.' if @options[:make_indep]
    return "[VERIFIED] Sandbox build with --no-env matches #{@bfilename}.pdf." if @options[:sandbox] || @options[:zip_alone]

    '[VERIFIED] Archive successfully verified: self-contained and compiles in clean environment.'
  end

  def verify_clean_diagnostics(output)
    result = JSON.parse(output)
    raise TypeError, 'expected a diagnostic result object' unless result.is_a?(Hash)

    summary = result.fetch('summary')
    raise TypeError, 'expected diagnostic counts' unless summary.is_a?(Hash)

    rejected_tiers = @options[:errors_only] ? %w[errors] : %w[errors alerts]
    tier_names = rejected_tiers.join(' or ')
    if result['success'] == true && rejected_tiers.all? { |tier| summary.fetch(tier).zero? }
      puts Rainbow(" -- Isolated build has no #{tier_names}.").green
      return true
    end

    warn Rainbow("[FAIL] Isolated build reported #{tier_names}.").red.bright
    warn output
    false
  rescue JSON::ParserError, KeyError, TypeError => e
    warn Rainbow("[FAIL] Could not verify isolated build diagnostics: #{e.message}").red.bright
    false
  end

  def verify_pdf_visual_match(original, rebuilt)
    unless LaTeXUtils.command_available?('pdftoppm')
      warn Rainbow("[FAIL] --zip-alone verification requires 'pdftoppm'.").red.bright
      return false
    end

    Dir.mktmpdir('leeni_zip_visual_') do |directory|
      pages = [original, rebuilt].each_with_index.map do |pdf, index|
        prefix = File.join(directory, "pdf#{index}")
        output, status = Open3.capture2e('pdftoppm', '-r', '150', pdf, prefix)
        unless status.success?
          warn Rainbow("[FAIL] Could not render PDF for verification: #{output}").red.bright
          return false
        end
        Dir.glob("#{prefix}-*.ppm").sort_by { |path| path[/-(\d+)\.ppm\z/, 1].to_i }
      end
      matching = !pages[0].empty? && pages[0].size == pages[1].size &&
                 pages[0].zip(pages[1]).all? { |left, right| File.size(left).positive? && FileUtils.compare_file(left, right) }
      unless matching
        warn Rainbow('[FAIL] Rebuilt PDF pages differ visually from the bundled PDF.').red.bright
        return false
      end
      puts Rainbow(' -- All PDF pages match visually at 150 dpi.').green
      true
    end
  rescue SystemCallError => e
    warn Rainbow("[FAIL] Could not compare PDF pages: #{e.message}").red.bright
    false
  end

  def verify_pdf_diff(orig_pdf, new_pdf)
    unless LaTeXUtils.command_available?('pdftotext')
      if @options[:zip_alone]
        warn Rainbow("[FAIL] --zip-alone verification requires 'pdftotext'.").red.bright
        return false
      end
      puts Rainbow(" -- PDF text comparison skipped: 'pdftotext' is unavailable.").yellow
      return true
    end

    unless File.file?(orig_pdf) && File.file?(new_pdf)
      warn Rainbow(' -- PDF text comparison failed: bundled or rebuilt PDF is missing.').red.bright
      return false
    end

    t1, s1 = Open3.capture2e('pdftotext', '-layout', orig_pdf, '-')
    t2, s2 = Open3.capture2e('pdftotext', '-layout', new_pdf, '-')
    return false unless s1.success? && s2.success?

    if t1 == t2
      puts Rainbow(' -- Text layout exact match confirmed between bundled PDF and test build.').green
      return true
    end

    warn Rainbow(' -- PDF text layout differs between bundled PDF and test build.').red.bright
    false
  end

  def sandbox_environment(tmpdir)
    LaTeXPackagingShared.sandbox_environment(tmpdir)
  end

  # Also used by --make-indep to check a converted project tree.
  public :run_sandbox_compile, :compile_in_sandbox
end
