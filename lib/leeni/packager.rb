# frozen_string_literal: true

# ==============================================================================
# lib/leeni/packager.rb
#
# Bundles LaTeX documents, active styles, and figure sources into portable
# zip archives (-z / --zip). Verifies self-contained build in sandbox (-t).
# ==============================================================================

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative 'flattener'

class LatexPackager
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

    deps = collect_fls_dependencies(fls_path)
    fig_sources = discover_figure_sources(deps[:figures])
    zip_filename = @options[:zip_name] || "#{@bfilename}.zip"

    candidate = stage_and_create_zip(zip_filename, deps, fig_sources)
    return false unless candidate

    publish_packaged_archive(candidate, zip_filename)
  ensure
    FileUtils.rm_f(candidate) if candidate && File.file?(candidate)
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

      path = line.sub(/^INPUT\s+/, '').strip
      next if path.empty? || path.start_with?("#{junk_dir}/") || path.start_with?('junk/') || path.start_with?('.junk/') || system_texmf_file?(path)

      clean_path = normalize_dep_path(path)
      next if clean_path == @filename || clean_path == "#{@bfilename}.pdf"

      categorize_fls_dep(clean_path, styles, figures, tex_inputs)
    end

    { styles: styles.uniq, figures: figures.uniq, tex_inputs: tex_inputs.uniq }
  end

  def categorize_fls_dep(clean_path, styles, figures, tex_inputs)
    case File.extname(clean_path).downcase
    when '.sty', '.cls', '.clo', '.def', '.bbx', '.cbx', '.rtx'
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
      LaTeXUtils.safe_read(bcf_file).scan(/<bcf:datasource[^>]*>([^<]+)<\/bcf:datasource>/).flatten.each do |ds|
        candidates << ds if File.file?(ds)
      end
    end

    cwd = Dir.pwd
    candidates.map { |p| normalize_dep_path(p) }.uniq.select do |p|
      expanded = File.expand_path(p)
      File.file?(p) && (expanded.start_with?(cwd + '/') || expanded == cwd || !p.start_with?('/'))
    end.reject do |p|
      p =~ %r{(^|/)(junk|\.junk|bak|old|archive)/} || p.end_with?('.bak', '~')
    end
  end

  def stage_all_assets(stage_dir, deps, fig_sources)
    copy_target_outputs(stage_dir)

    if @options[:zip_flat]
      return false unless stage_flattened_main_tex(stage_dir, !deps[:styles].empty?)
      return stage_remaining_assets(stage_dir, deps, fig_sources)
    end

    stage_main_tex(stage_dir, !deps[:styles].empty?)
    deps[:tex_inputs].each { |f| copy_preserving_path(f, stage_dir) if File.file?(f) }
    stage_remaining_assets(stage_dir, deps, fig_sources)
  end

  def stage_remaining_assets(stage_dir, deps, fig_sources)
    stage_styles(deps[:styles], stage_dir)

    discover_local_bib_files.each { |f| copy_preserving_path(f, stage_dir) if File.file?(f) }
    (deps[:figures] + fig_sources).uniq.each { |f| copy_preserving_path(f, stage_dir) if File.file?(f) }

    extra_files = Array(@options[:extra_files]).flat_map { |g| Dir.glob(g).empty? ? [g] : Dir.glob(g) }
    extra_files.uniq.each { |f| copy_preserving_path(f, stage_dir) if File.exist?(f) }
    true
  end

  def stage_flattened_main_tex(stage_dir, has_styles = false)
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

    if @options[:inject_styles] && has_styles && !content.include?('input@path')
      injection = "\\makeatletter\n\\def\\input@path{{styles/}{./}}\n\\makeatother\n"
      content = inject_into_tex(content, injection)
    end

    File.write(dest_path, content)
    true
  end

  def stage_and_create_zip(zip_filename, deps, fig_sources)
    unless LaTeXUtils.command_available?('zip')
      warn Rainbow("[ERROR] 'zip' command not found in PATH! Cannot create archive.").red.bright
      return false
    end

    candidate = archive_candidate_path(zip_filename)
    FileUtils.rm_f(candidate)
    succeeded = Dir.mktmpdir('leeni_stage_') do |stage_dir|
      return false unless stage_all_assets(stage_dir, deps, fig_sources)

      zip_out, zip_status = Dir.chdir(stage_dir) { Open3.capture2e('zip', '-q', '-r', candidate, '.') }
      unless zip_status.success? && File.file?(candidate) && File.size(candidate).positive?
        warn Rainbow("[FAIL] Failed to create #{zip_filename}: #{zip_out}").red.bright
        return false
      end
      true
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
    if bbl_source && LaTeXUtils.bbl_has_entries?(bbl_source)
      FileUtils.cp(bbl_source, File.join(stage_dir, "#{@bfilename}.bbl"))
    end
  end

  def stage_main_tex(stage_dir, has_styles = false)
    dest_path = File.join(stage_dir, @filename)
    FileUtils.mkdir_p(File.dirname(dest_path))

    content = LaTeXUtils.safe_read(@filename)
    if @options[:inject_styles] && has_styles && !content.include?('input@path')
      injection = "\\makeatletter\n\\def\\input@path{{styles/}{./}}\n\\makeatother\n"
      injected_content = inject_into_tex(content, injection)
      File.write(dest_path, injected_content)
    else
      File.write(dest_path, content)
    end
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
    return unless File.exist?(src)

    cwd = Dir.pwd
    real_cwd = begin
      File.realpath(cwd)
    rescue StandardError
      cwd
    end
    real_src = begin
      File.realpath(src)
    rescue StandardError
      nil
    end
    return unless real_src && (real_src == real_cwd || real_src.start_with?(real_cwd + File::SEPARATOR))

    expanded = File.expand_path(src)
    rel_path = if expanded.start_with?(cwd + File::SEPARATOR)
                 expanded.sub(cwd + File::SEPARATOR, '')
               elsif real_src.start_with?(real_cwd + File::SEPARATOR)
                 real_src.sub(real_cwd + File::SEPARATOR, '')
               else
                 return
               end

    dest = File.join(dest_root, rel_path)
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp_r(src, dest)
  end

  def verify_archive!(zip_filename)
    zip_abs = File.expand_path(zip_filename)
    puts Rainbow("==> Verifying archive portability in isolated sandbox...").cyan.bright

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

    ruby_bin = RbConfig.ruby
    script_bin = LEENI_EXECUTABLE
    cmd = [ruby_bin, script_bin, '--no-env', '--engine', @builder.engine_name]
    cmd += ['--timeout', @options[:timeout].to_s] if @options[:timeout]
    cmd << @filename

    compile_out, compile_stat = Open3.capture2e(sandbox_environment(tmpdir), *cmd, chdir: tmpdir)
    new_pdf = File.join(tmpdir, "#{@bfilename}.pdf")

    if compile_stat.success? && File.file?(new_pdf)
      return false unless verify_pdf_diff(backup_pdf, new_pdf)

      puts Rainbow("[VERIFIED] Archive successfully verified: self-contained and compiles in clean environment.").green.bright
      true
    else
      warn Rainbow("[FAIL] Verification failed! Document did not compile in clean environment.").red.bright
      warn compile_out
      false
    end
  end

  def verify_pdf_diff(orig_pdf, new_pdf)
    unless LaTeXUtils.command_available?('pdftotext')
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
      puts Rainbow(" -- Text layout exact match confirmed between bundled PDF and test build.").green
      return true
    end

    warn Rainbow(' -- PDF text layout differs between bundled PDF and test build.').red.bright
    false
  end

  def sandbox_environment(tmpdir)
    home = File.join(tmpdir, 'home')
    texmf_home = File.join(tmpdir, 'texmf-home')
    texmf_var = File.join(tmpdir, 'texmf-var')
    texmf_config = File.join(tmpdir, 'texmf-config')
    texmf_cache = File.join(tmpdir, 'texmf-cache')
    xdg_config = File.join(tmpdir, 'config')
    xdg_cache = File.join(tmpdir, 'cache')
    [home, texmf_home, texmf_var, texmf_config, texmf_cache, xdg_config, xdg_cache].each { |dir| FileUtils.mkdir_p(dir) }
    ENV.to_h.merge(
      'HOME' => home,
      'TEXMFHOME' => texmf_home,
      'TEXMFVAR' => texmf_var,
      'TEXMFCONFIG' => texmf_config,
      'TEXMFCACHE' => texmf_cache,
      'XDG_CONFIG_HOME' => xdg_config,
      'XDG_CACHE_HOME' => xdg_cache,
      'LEENI_DISABLE_BUNDLED_REVTeX' => '1'
    )
  end
end
