# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/arxiv.rb
#
# arXiv submission preparation manager: inlines inputs, bundles active assets,
# shields biblatex versions, and validates compilation and visual layout.
# ==============================================================================

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

class LatexArxivPackager
  attr_reader :builder, :filename, :bfilename, :bdir, :options

  def initialize(builder, options = {})
    @builder = builder
    @filename = builder.filename
    @bfilename = builder.bfilename
    @bdir = builder.bdir
    @options = builder.options.merge(options)
  end

  def package!
    Dir.chdir(File.expand_path(@bdir)) { do_package }
  end

  private

  def junk_dir
    @builder.junk_dir
  end

  def build_artifact(extension)
    File.join(junk_dir, "#{@bfilename}.#{extension}")
  end

  def do_package
    return false unless ensure_compiled!

    zip_filename = @options[:arxiv_name] || "arxiv_#{@bfilename}.zip"
    meta_filename = "arxiv_#{@bfilename}_meta.txt"

    Dir.mktmpdir('latex_it_arxiv_stage_') do |stage_dir|
      return false unless stage_arxiv_files(stage_dir)
      candidate = build_arxiv_zip(stage_dir, zip_filename)
      return false unless candidate

      reference_pdf = arxiv_reference_pdf
      if @options[:arxiv_verify] != false
        verified = verify_arxiv_sandbox!(candidate, reference_pdf)
        return quarantine_unverified_package(candidate, zip_filename) unless verified
      end

      metadata_candidate = metadata_candidate_path(meta_filename)
      write_arxiv_metadata(metadata_candidate)
      File.rename(candidate, zip_filename)
      File.rename(metadata_candidate, meta_filename)
      file_count = count_zip_entries(zip_filename)
      announce_arxiv_completion(zip_filename, meta_filename, file_count)
      true
    ensure
      FileUtils.rm_f(candidate) if candidate && File.file?(candidate)
      FileUtils.rm_f(metadata_candidate) if metadata_candidate && File.file?(metadata_candidate)
    end
  end

  def quarantine_unverified_package(candidate, zip_filename)
    quarantined = "#{zip_filename}.unverified"
    FileUtils.mv(candidate, quarantined, force: true) if File.file?(candidate)
    warn Rainbow("[FAIL] Verification failed. Package renamed to #{quarantined} -- do not submit it.").red.bright
    false
  end

  def ensure_compiled!
    puts Rainbow("==> Pre-flight compilation of #{@filename} for arXiv submission...").cyan.bright
    @builder.options[:no_env] = true
    return false unless @builder.run_in_current_directory!

    fls_path = build_artifact('fls')
    pdf_path = arxiv_reference_pdf
    unless File.file?(fls_path) && pdf_path
      warn Rainbow('[FAIL] Pre-flight compilation did not produce a usable PDF and recorder file.').red.bright
      return false
    end
    true
  end

  def arxiv_reference_pdf
    junk_pdf = build_artifact('pdf')
    return File.expand_path(junk_pdf) if File.file?(junk_pdf) && File.size(junk_pdf).positive?

    root_pdf = "#{@bfilename}.pdf"
    return File.expand_path(root_pdf) if File.file?(root_pdf) && File.size(root_pdf).positive?

    nil
  end

  def stage_arxiv_files(stage_dir)
    begin
      flattened_tex = LaTeXFlattener.flatten(@filename, '.', @options[:strip_host_patterns],
                                             strip_comments: @options[:strip_comments] != false)
    rescue StandardError => e
      warn Rainbow("[FAIL] Could not flatten LaTeX source: #{e.message}").red.bright
      return false
    end
    File.write(File.join(stage_dir, @filename), flattened_tex)

    stage_bbl(stage_dir)
    stage_active_figures(stage_dir)
    stage_local_styles(stage_dir)
    stage_revtex4_files(stage_dir)
    stage_biblatex_shield(stage_dir) unless @options[:biblatex_shield] == false
    true
  end

  def stage_revtex4_files(stage_dir)
    fls_path = build_artifact('fls')
    files = LaTeXCompatibility.files_used_by_fls(fls_path, @options)
    files.each do |source|
      destination = File.join(stage_dir, File.basename(source))
      next if File.exist?(destination)

      FileUtils.cp(source, destination)
      puts Rainbow(" -- Bundled REVTeX compatibility file: #{File.basename(source)}").cyan
    end
  end

  def stage_bbl(stage_dir)
    bbl_source = File.file?("#{@bfilename}.bbl") ? "#{@bfilename}.bbl" : build_artifact('bbl')
    if File.file?(bbl_source) && LaTeXUtils.bbl_has_entries?(bbl_source)
      FileUtils.cp(bbl_source, File.join(stage_dir, "#{@bfilename}.bbl"))
    else
      warn Rainbow("[WARN] No bibliography entries found in #{bbl_source}!").yellow
    end
  end

  def stage_active_figures(stage_dir)
    fls_path = build_artifact('fls')
    return unless File.file?(fls_path)

    fls_content = LaTeXUtils.safe_read(fls_path)
    figures = []
    fls_content.each_line do |line|
      next unless line =~ /^INPUT\s+(\S+)/

      p = Regexp.last_match(1)
      next if p.include?('/usr/share/texlive') || p.include?('texmf-dist')
      next unless p =~ /\.(pdf|png|jpg|jpeg|mps|eps)$/i

      figures << p
    end

    figures.uniq.each do |fig|
      copy_preserving_path(fig, stage_dir) if File.file?(fig)
    end
  end

  def stage_local_styles(stage_dir)
    fls_path = build_artifact('fls')
    return unless File.file?(fls_path)

    fls_content = LaTeXUtils.safe_read(fls_path)
    cwd = Dir.pwd
    fls_content.each_line do |line|
      next unless line =~ /^INPUT\s+(\S+)/

      p = Regexp.last_match(1)
      next if p.include?('/usr/share/texlive') || p.include?('texmf-dist')
      next unless p =~ /\.(sty|cls|def)$/i

      exp = File.expand_path(p)
      if exp.start_with?(cwd + '/') || exp == cwd || !p.start_with?('/')
        FileUtils.cp(p, File.join(stage_dir, File.basename(p))) if File.file?(p)
      end
    end
  end

  def stage_biblatex_shield(stage_dir)
    return unless detect_biblatex?

    puts Rainbow(' -- BibLaTeX detected: bundling local distribution files for arXiv shielding...').cyan
    harvested = []
    fls_path = build_artifact('fls')
    if File.file?(fls_path)
      content = LaTeXUtils.safe_read(fls_path)
      content.scan(/^INPUT\s+(\S*\/biblatex\/\S+\.(?:sty|cfg|bbx|cbx|lbx|def))$/).flatten.each do |f|
        harvested << f if File.file?(f)
      end
    end

    harvest_kpsewhich_core_files(harvested)

    harvested.uniq.each do |f|
      dest = File.join(stage_dir, File.basename(f))
      FileUtils.cp(f, dest) unless File.exist?(dest)
    end
  end

  def harvest_kpsewhich_core_files(harvested)
    return unless LaTeXUtils.command_available?('kpsewhich')

    %w[biblatex.sty biblatex.cfg standard.bbx english.lbx].each do |core|
      next if harvested.any? { |h| File.basename(h) == core }

      begin
        path, stat = Open3.capture2('kpsewhich', core)
        harvested << path.strip if stat&.success? && File.file?(path.strip)
      rescue SystemCallError => e
        warn Rainbow(" -- Warning: kpsewhich execution failed: #{e.message}").yellow
      end
    end
  end

  def detect_biblatex?
    return true if File.file?(build_artifact('bcf'))

    main_content = LaTeXUtils.safe_read(@filename)
    main_content.include?('biblatex')
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
    FileUtils.cp(src, dest)
  end

  def build_arxiv_zip(stage_dir, zip_filename)
    unless LaTeXUtils.command_available?('zip')
      warn Rainbow("[ERROR] 'zip' command not found in PATH! Cannot create archive.").red.bright
      return false
    end

    candidate = archive_candidate_path(zip_filename)
    FileUtils.rm_f(candidate)
    zip_out, status = Dir.chdir(stage_dir) do
      Open3.capture2e('zip', '-q', '-r', candidate, '.')
    end
    valid = status.success? && File.file?(candidate) && File.size(candidate).positive?
    return candidate if valid

    warn Rainbow("[FAIL] Failed to create #{zip_filename}: #{zip_out}").red.bright
    false
  ensure
    FileUtils.rm_f(candidate) if candidate && !valid && File.file?(candidate)
  end

  def archive_candidate_path(zip_filename)
    absolute = File.expand_path(zip_filename)
    File.join(File.dirname(absolute), ".#{File.basename(absolute, '.zip')}.tmp.#{Process.pid}.zip")
  end

  def metadata_candidate_path(meta_filename)
    absolute = File.expand_path(meta_filename)
    File.join(File.dirname(absolute), ".#{File.basename(absolute, '.txt')}.tmp.#{Process.pid}.txt")
  end

  def write_arxiv_metadata(meta_filename)
    pdf_path = File.file?("#{@bfilename}.pdf") ? "#{@bfilename}.pdf" : build_artifact('pdf')
    fls_path = build_artifact('fls')
    log_path = build_artifact('log')
    comments = @options[:comments]

    meta = LaTeXMetaExtractor.extract(@filename, '.', pdf_path, fls_path, log_path, comments)
    meta_txt = LaTeXMetaExtractor.format_meta_txt(meta)
    LaTeXMetaExtractor.write_meta_file(meta_filename, meta_txt)
  end

  def verify_arxiv_sandbox!(zip_filename, reference_pdf = arxiv_reference_pdf)
    zip_abs = File.expand_path(zip_filename)
    puts Rainbow("==> Verifying arXiv archive in isolated /tmp sandbox...").cyan.bright

    unless LaTeXUtils.command_available?('unzip')
      warn Rainbow("[ERROR] 'unzip' command not found in PATH! Cannot verify archive.").red.bright
      return false
    end

    Dir.mktmpdir('latex_it_arxiv_verify_') do |tmpdir|
      unzip_out, unzip_stat = Open3.capture2e('unzip', '-q', zip_abs, '-d', tmpdir)
      unless unzip_stat.success?
        warn Rainbow("[FAIL] Failed to extract #{zip_filename}: #{unzip_out}").red.bright
        return false
      end

      run_sandbox_verify(tmpdir, reference_pdf)
    end
  end

  def run_sandbox_verify(tmpdir, reference_pdf)
    ruby_bin = RbConfig.ruby
    script_bin = LATEX_IT_EXECUTABLE
    cmd = [ruby_bin, script_bin, '--no-env', '--engine', @builder.engine_name]
    cmd += ['--timeout', @options[:timeout].to_s] if @options[:timeout]
    cmd << @filename
    compile_out, compile_stat = Open3.capture2e(sandbox_environment(tmpdir), *cmd, chdir: tmpdir)
    new_pdf = File.join(tmpdir, "#{@bfilename}.pdf")

    if compile_stat.success? && File.file?(new_pdf)
      check_arxiv_type3_fonts(new_pdf)
      return false unless verify_arxiv_pdf_match(reference_pdf, new_pdf)
      return false unless verify_arxiv_authors_match(new_pdf)

      if @options[:arxiv_visual_verify] == false
        puts Rainbow('[VERIFIED] arXiv package matches the original PDF text; visual comparison skipped.').green.bright
      else
        return false unless verify_arxiv_pdf_visual_match(reference_pdf, new_pdf)

        puts Rainbow('[VERIFIED] arXiv package compiles cleanly and matches the original PDF text and page visuals.').green.bright
      end
      true
    else
      warn Rainbow("[FAIL] Sandbox verification failed for arXiv package!").red.bright
      warn compile_out
      false
    end
  end

  def check_arxiv_type3_fonts(pdf_path)
    type3 = LaTeXUtils.check_type3_fonts(pdf_path)
    return unless type3

    pages_str = type3[:pages].empty? ? '' : " on page #{type3[:pages].join(', ')}"
    warn Rainbow("[ALERT] arXiv package PDF contains Type 3 (raster bitmap) fonts: #{type3[:fonts].join(', ')}#{pages_str}.").yellow.bright
    warn Rainbow('        arXiv/IEEE submission portals may reject this document. Use vector fonts (e.g. lmodern).').yellow
  end

  def verify_arxiv_pdf_match(reference_pdf, rebuilt_pdf)
    unless LaTeXUtils.command_available?('pdftotext')
      warn Rainbow("[FAIL] arXiv verification requires 'pdftotext' to compare PDF text.").red.bright
      return false
    end

    unless reference_pdf && File.file?(reference_pdf) && File.size(reference_pdf).positive?
      warn Rainbow('[FAIL] arXiv verification could not find the fresh original PDF.').red.bright
      return false
    end
    unless File.file?(rebuilt_pdf) && File.size(rebuilt_pdf).positive?
      warn Rainbow('[FAIL] arXiv verification could not find the rebuilt PDF.').red.bright
      return false
    end

    original_text, original_err, original_status = Open3.capture3('pdftotext', '-layout', reference_pdf, '-')
    rebuilt_text, rebuilt_err, rebuilt_status = Open3.capture3('pdftotext', '-layout', rebuilt_pdf, '-')
    unless original_status.success? && rebuilt_status.success?
      warn Rainbow('[FAIL] arXiv verification could not extract PDF text with pdftotext.').red.bright
      warn original_err unless original_status.success? || original_err.empty?
      warn rebuilt_err unless rebuilt_status.success? || rebuilt_err.empty?
      return false
    end

    if original_text == rebuilt_text
      puts Rainbow(' -- Original and rebuilt PDF text layout exactly matches.').green
      return true
    end

    warn Rainbow(' -- Original and rebuilt PDF text layout differs.').red.bright
    false
  end

  def verify_arxiv_authors_match(rebuilt_pdf)
    source = LaTeXUtils.safe_read(@filename)
    authors = LaTeXMetaExtractor.extract_author_names(source)
    if authors.empty?
      warn Rainbow('[FAIL] arXiv verification could not extract any authors from the original source. Add a non-empty \\author declaration.').red.bright
      return false
    end

    placeholders = authors.select { |name| arxiv_placeholder_author?(name) }
    unless placeholders.empty?
      warn Rainbow("[FAIL] arXiv verification found placeholder author name(s): #{placeholders.join(', ')}. Replace Unknown/Anonymous with real names.").red.bright
      return false
    end

    # A residual backslash means the metadata extractor did not understand a
    # macro in the name. Name the macro rather than blaming the user's \author
    # formatting, which is what the old combined message did.
    unresolved = authors.select { |name| name.include?('\\') }
    unless unresolved.empty?
      macros = unresolved.flat_map { |name| name.scan(/\\[a-zA-Z]+|\\./) }.uniq
      warn Rainbow("[FAIL] arXiv verification could not resolve author name(s): #{unresolved.join(', ')}.").red.bright
      warn Rainbow("        Unrecognised macro(s): #{macros.join(' ')}. Add them to LaTeXMetaExtractor::SYMBOL_ACCENTS, LETTER_ACCENTS or LIGATURE_MACROS.").red
      return false
    end

    first_page, error, status = Open3.capture3('pdftotext', '-f', '1', '-l', '1', '-layout', rebuilt_pdf, '-')
    unless status.success?
      warn Rainbow('[FAIL] arXiv verification could not extract the rebuilt PDF first page for author verification.').red.bright
      warn error unless error.to_s.empty?
      return false
    end

    missing = authors.reject { |name| arxiv_author_in_text?(name, first_page) }
    unless missing.empty?
      report_missing_authors(missing, first_page)
      return false
    end

    puts Rainbow(' -- All extracted author names appear on the rebuilt PDF first page.').green
    true
  rescue StandardError => e
    warn Rainbow("[FAIL] arXiv author verification failed while reading the original source: #{e.message}").red.bright
    false
  end

  def report_missing_authors(missing, first_page)
    details = missing.map do |name|
      suggestion = arxiv_author_suggestion(name, first_page)
      suggestion ? "#{name} (near match: #{suggestion})" : name
    end
    warn Rainbow("[FAIL] arXiv verification could not find author name(s) on the PDF first page: #{details.join(', ')}.").red.bright
  end

  def arxiv_placeholder_author?(name)
    normalized = arxiv_normalize_name(name)
    normalized.empty? || normalized.match?(/\A(?:unknown|anonymous|anonymous authors|author|authors|author name|author names)\z/)
  end

  def arxiv_author_in_text?(name, text)
    normalized_name = arxiv_normalize_name(name)
    normalized_text = arxiv_normalize_name(text)
    return false if normalized_name.empty? || normalized_text.empty?

    escaped = Regexp.escape(normalized_name).gsub('\\ ', '\\s+')
    normalized_text.match?(Regexp.new("(?<![\\p{L}\\p{N}])#{escaped}(?!\\p{L})"))
  end

  def arxiv_author_suggestion(name, text)
    expected = arxiv_normalize_name(name)
    return nil if expected.empty? || expected.length < 5

    bound = [2, [1, expected.length / 8].max].min
    words = arxiv_normalize_name(text).split
    count = expected.split.size
    return nil if count.zero?

    candidates = words.each_cons(count).map { |window| window.join(' ') }
    candidates.select! { |item| (expected.length - item.length).abs <= bound }
    candidate = candidates.min_by { |item| arxiv_edit_distance(expected, item) }
    return nil unless candidate && (expected.length - candidate.length).abs <= bound

    arxiv_edit_distance(expected, candidate) <= bound ? candidate : nil
  end

  def arxiv_edit_distance(left, right)
    LaTeXUtils.edit_distance(left, right)
  end

  def arxiv_normalize_name(value)
    utf8 = value.to_s.dup.force_encoding(Encoding::UTF_8).scrub
    utf8.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').unicode_normalize(:nfkc).downcase
        .gsub(/[^\p{L}\p{N}]+/, ' ').strip.gsub(/\s+/, ' ')
  end

  def verify_arxiv_pdf_visual_match(reference_pdf, rebuilt_pdf)
    unless LaTeXUtils.command_available?('pdftoppm')
      warn Rainbow("[FAIL] arXiv visual verification requires 'pdftoppm'.").red.bright
      return false
    end

    paths = [reference_pdf, rebuilt_pdf]
    unless paths.all? { |path| path && File.file?(path) && File.size(path).positive? }
      warn Rainbow('[FAIL] arXiv visual verification could not find both PDFs.').red.bright
      return false
    end
    paths.map! { |path| File.expand_path(path) }

    Dir.mktmpdir('latex_it_arxiv_visual_') do |tmpdir|
      rendered = paths.each_with_index.map { |pdf, idx| render_arxiv_pdf_pages(pdf, File.join(tmpdir, idx.to_s)) }
      return false unless rendered.all?

      compare_rendered_pages(rendered[0], rendered[1])
    end
  end

  def compare_rendered_pages(original_pages, rebuilt_pages)
    unless original_pages.size == rebuilt_pages.size
      warn Rainbow("[FAIL] arXiv visual verification page count differs (#{original_pages.size} vs #{rebuilt_pages.size}).").red.bright
      return false
    end
    return false if original_pages.empty?

    original_pages.each_with_index do |original, index|
      rebuilt = rebuilt_pages[index]
      next if FileUtils.compare_file(original, rebuilt)

      warn Rainbow("[FAIL] arXiv visual verification differs on page #{index + 1}.").red.bright
      return false
    end
    true
  end

  def render_arxiv_pdf_pages(pdf, directory)
    FileUtils.mkdir_p(directory)
    prefix = File.join(directory, 'page')
    output, status = Open3.capture2e('pdftoppm', '-r', '150', pdf, prefix)
    unless status.success?
      detail = output.to_s.strip
      detail = ": #{detail}" unless detail.empty?
      warn Rainbow("[FAIL] arXiv visual verification could not render #{File.basename(pdf)} with pdftoppm#{detail}.").red.bright
      return nil
    end

    pages = Dir.glob("#{prefix}-*.ppm").select { |path| File.file?(path) }
    pages.sort_by! { |path| path[/-(\d+)\.ppm\z/, 1].to_i }
    if pages.empty? || pages.any? { |path| File.size(path).zero? }
      warn Rainbow("[FAIL] arXiv visual verification rendered no pages for #{File.basename(pdf)}.").red.bright
      return nil
    end
    pages
  rescue SystemCallError => e
    warn Rainbow("[FAIL] arXiv visual verification could not run pdftoppm: #{e.message}").red.bright
    nil
  end

  def count_zip_entries(zip_filename)
    return 0 unless LaTeXUtils.command_available?('unzip')

    out, stat = Open3.capture2('unzip', '-l', zip_filename)
    return 0 unless stat.success?

    lines = out.lines[3..-3] || []
    lines.size
  rescue SystemCallError
    0
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
      'LATEX_IT_DISABLE_BUNDLED_REVTeX' => '1'
    )
  end

  def announce_arxiv_completion(zip_filename, meta_filename, file_count)
    size_str = if File.file?(zip_filename)
                 sz = File.size(zip_filename)
                 sz > 1024 * 1024 ? "#{(sz / (1024.0 * 1024.0)).round(1)} MB" : "#{(sz / 1024.0).round(1)} KB"
               else
                 'unknown size'
               end

    puts Rainbow("\n==> arXiv Preparation Complete!").green.bright
    puts "  [1] Submission Archive : #{Rainbow(zip_filename).bold} (#{size_str}, #{file_count} files)"
    puts "  [2] Paper Metadata     : #{Rainbow(meta_filename).bold} (ready to copy-paste into arXiv form)\n\n"
  end
end
