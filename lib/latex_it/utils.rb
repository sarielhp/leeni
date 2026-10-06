# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/utils.rb
#
# Core utility functions for LaTeX engine detection, main document resolution,
# noise filtering, environment sanitization, and cleanup.
# ==============================================================================

require 'fileutils'
require 'io/console'
require 'pathname'
begin
  require 'unicode/display_width'
rescue LoadError
  # Optional dependency; fallback used in visible_width
end

module LaTeXUtils
  class << self
    attr_accessor :initial_pwd
  end

  @initial_pwd = Dir.pwd
  # `figs/bak` is deliberately absent: the packager treats it as a user-owned
  # backup directory to exclude from bundles, so cleaning must not delete it.
  JUNK_BUILD_DIRS = %w[junk .junk styles/junk styles/.junk figs/junk figs/.junk refs/junk refs/.junk].freeze

  # Every scratch file this tool writes lives under `junk/`, which is removed
  # wholesale via JUNK_BUILD_DIRS. These patterns therefore only ever run over
  # the project root, where a match can only be a TeX-generated artifact or a
  # file the user wrote by hand. Patterns that cannot distinguish the two --
  # `log.txt`, `err_*`, `*.err*` -- were removed for that reason; the tool's own
  # copies of those are `junk/log.txt`, `junk/log.txt.1` and `junk/err_<engine>`.
  JUNK_PATTERNS = [
    '*.{aux,blg,bcf,run.xml}',
    '*.{log,out,toc,lof,lot,thm,idx,ind,ilg}',
    '*.{nav,snm,vrb,synctex.gz,synctex,dvi,ps}',
    '*.{fls,fdb_latexmk,rel,vtc,axp,dpth,md5,soc,build_state.json}',
    '.build_state.json',
    'texput.log', 'missfont.log', 'mfput.log',
    'flycheck_*.tex'
  ].freeze

  TEX_ENV_VARS = %w[
    BIBINPUTS BSTINPUTS TEXINPUTS PDFTEXINPUTS XETEXINPUTS LUATEXINPUTS
    LUAINPUTS BBLINPUTS TEXMFOUTPUT TEXFORMATS TEXFONTS TFMFONTS T1FONTS
    OFMFONTS AFMFONTS TTFONTS OPENTYPEFONTS MFINPUTS MPINPUTS TEXPICTS
    TEXDOCS TEXSOURCES TEXPOOL INDEXSTYLE BIBTEX_PREFIX TEXMFHOME TEXMFVAR
    TEXMFCONFIG TEXMFLOCAL TEXMFSYSCONFIG TEXMFSYSVAR TEXMFCNF TEXMF
    TEXMFDBS TEXMFCACHE
  ].freeze

  DEFAULT_EXCLUDE_MAIN_PATTERNS = [
    'prefix*.tex', 'prelim*.tex', 'preamble*.tex',
    '*.num.tex', 'pratenddefaultcategory.tex'
  ].freeze

  # Bibliography documents routinely need latex, bib, latex, latex, latex, so the
  # old ceiling of 3 stopped short of convergence without saying so.
  DEFAULT_PASSES = 5
  MAX_PASSES = 10

  DEFAULT_EXCLUDE_SOURCE_PATTERNS = [
    'styles/*', 'macros/*', 'pkg/*', 'packages/*',
    '*prefix*.tex', '*preamble*.tex', '*macros*.tex', '*styles*.tex'
  ].freeze

  DEFAULT_BIB_DIRS = %w[refs bib bibliography].freeze
  DEFAULT_JUNK_SUBDIRS = %w[figs fragment].freeze
  DEFAULT_STRIP_HOST_PATTERNS = %w[computer local private].freeze

  # Engines this tool is willing to execute. The engine name reaches here from a
  # project-local .l.jsonc, from a `% !TEX program =` magic comment, and from
  # PDFBIN/LATEX_ENGINE -- all of which travel inside a repository or an
  # environment the user may not control. Anything outside this list is refused
  # rather than passed through to Open3 as a program name.
  KNOWN_ENGINES = %w[xelatex lualatex pdflatex latex tectonic].freeze

  def self.normalize_engine(engine)
    return 'xelatex' if engine.nil? || engine.to_s.strip.empty?

    eng = engine.to_s.strip.downcase
    first_token = eng.split.first || ''
    base = File.basename(first_token, '.*')
    case base
    when 'l', 'lua', 'lualatex', 'luatex'
      'lualatex'
    when 'x', 'xe', 'xelatex', 'xetex'
      'xelatex'
    when 'p', 'pdf', 'pdflatex', 'pdftex'
      'pdflatex'
    when *KNOWN_ENGINES
      base
    else
      warn " -- Warning: unknown LaTeX engine #{base.inspect}; using xelatex."
      'xelatex'
    end
  end

  def self.detect_engine_from_file(path)
    return nil unless path && File.file?(path)

    raw_content = safe_read(path)
    return nil if raw_content.empty?

    engine = detect_engine_from_magic_comments(raw_content) || detect_engine_from_auctex(raw_content)
    return engine if engine

    active = strip_latex_comments(raw_content)
    return 'lualatex' if active_source_needs_lualatex?(active)
    return 'pdflatex' if active_source_needs_pdflatex?(active)

    nil
  end

  def self.detect_engine_from_magic_comments(content)
    (content.lines.first(50) || []).each do |line|
      if line =~ /^\s*%\s*!T[eE]X\s+(?:TS-)?(?:program|engine)\s*=\s*(\S+)/i
        return normalize_engine(Regexp.last_match(1).strip)
      end
    end
    nil
  end

  def self.detect_engine_from_auctex(content)
    (content.lines.last(40) || []).each do |line|
      if line =~ /TeX-engine:\s*([a-zA-Z0-9_-]+)/i
        return normalize_engine(Regexp.last_match(1).strip)
      end
    end
    nil
  end

  def self.active_source_needs_lualatex?(content)
    content =~ /\\usepackage(?:\[.*?\])?\{luacode\}/ ||
      content =~ /\\usepackage(?:\[.*?\])?\{luamplib\}/ ||
      content =~ /\\usepackage(?:\[.*?\])?\{luatex85\}/ ||
      content.include?('\\directlua')
  end

  def self.active_source_needs_pdflatex?(content)
    content.match?(/\\(?:usepackage|RequirePackage)\s*(?:\[[^\]]*\])?\s*\{\s*inputenc\s*\}/i)
  end

  def self.source_requires_pdflatex?(path)
    !source_pdflatex_reasons(path).empty?
  end

  def self.source_pdflatex_reasons(path)
    return [] unless path && File.file?(path)

    content = strip_latex_comments(safe_read(path))
    reasons = []
    reasons << 'inputenc' if active_source_needs_pdflatex?(content)
    if content.match?(/\\includegraphics\s*(?:\[[^\]]*\])?\s*\{[^}\n]*\.eps(?:\s*\})/i) ||
       content.match?(/\\epsfig\s*\{[^}\n]*\bfile\s*=\s*[^,}\n]*\.eps(?:\s*[,}])/i)
      reasons << 'EPS graphics'
    end
    reasons
  end

  def self.strip_latex_comments(content)
    return '' if content.nil? || content.empty?

    content.gsub(/\r\n?/, "\n").lines.map do |line|
      comment_at = latex_comment_start(line)
      comment_at ? line[0...comment_at] + (line.end_with?("\n") ? "\n" : '') : line
    end.join
  end

  def self.latex_comment_start(line)
    line.each_char.with_index do |char, index|
      next unless char == '%'

      slashes = 0
      cursor = index - 1
      while cursor >= 0 && line[cursor] == '\\'
        slashes += 1
        cursor -= 1
      end
      return index if slashes.even?
    end
    nil
  end

  def self.compatible_engine(engine, path)
    normalized = normalize_engine(engine)
    return 'pdflatex' if %w[xelatex lualatex].include?(normalized) && source_requires_pdflatex?(path)

    normalized
  end

  def self.edit_distance(left, right)
    return 0 if left == right
    return right.length if left.empty?
    return left.length if right.empty?

    d = Array.new(left.length + 1) { Array.new(right.length + 1, 0) }
    (0..left.length).each { |i| d[i][0] = i }
    (0..right.length).each { |j| d[0][j] = j }

    (1..left.length).each do |i|
      (1..right.length).each do |j|
        cost = left[i - 1] == right[j - 1] ? 0 : 1
        d[i][j] = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost].min
        d[i][j] = [d[i][j], d[i - 2][j - 2] + 1].min if transposition?(left, right, i, j)
      end
    end

    d[left.length][right.length]
  end

  def self.transposition?(left, right, i, j)
    i > 1 && j > 1 && left[i - 1] == right[j - 2] && left[i - 2] == right[j - 1]
  end

  QWERTY_COORDS = {
    'q' => [0.0, 1.0], 'w' => [1.0, 1.0], 'e' => [2.0, 1.0], 'r' => [3.0, 1.0], 't' => [4.0, 1.0],
    'y' => [5.0, 1.0], 'u' => [6.0, 1.0], 'i' => [7.0, 1.0], 'o' => [8.0, 1.0], 'p' => [9.0, 1.0],
    'a' => [0.25, 2.0], 's' => [1.25, 2.0], 'd' => [2.25, 2.0], 'f' => [3.25, 2.0], 'g' => [4.25, 2.0],
    'h' => [5.25, 2.0], 'j' => [6.25, 2.0], 'k' => [7.25, 2.0], 'l' => [8.25, 2.0],
    'z' => [0.75, 3.0], 'x' => [1.75, 3.0], 'c' => [2.75, 3.0], 'v' => [3.75, 3.0], 'b' => [4.75, 3.0],
    'n' => [5.75, 3.0], 'm' => [6.75, 3.0]
  }.freeze

  def self.key_distance(c1, c2)
    p1 = QWERTY_COORDS[c1.downcase]
    p2 = QWERTY_COORDS[c2.downcase]
    return 1.0 unless p1 && p2

    dist = Math.hypot(p1[0] - p2[0], p1[1] - p2[1])
    [0.35 + (dist * 0.15), 1.0].min
  end

  def self.keyboard_edit_distance(left, right)
    return 0.0 if left == right
    return right.length.to_f if left.empty?
    return left.length.to_f if right.empty?

    d = Array.new(left.length + 1) { Array.new(right.length + 1, 0.0) }
    (0..left.length).each { |i| d[i][0] = i * 0.8 }
    (0..right.length).each { |j| d[0][j] = j * 0.8 }

    (1..left.length).each do |i|
      (1..right.length).each do |j|
        cost = left[i - 1] == right[j - 1] ? 0.0 : key_distance(left[i - 1], right[j - 1])
        d[i][j] = [d[i - 1][j] + 0.8, d[i][j - 1] + 0.8, d[i - 1][j - 1] + cost].min
        d[i][j] = [d[i][j], d[i - 2][j - 2] + 0.5].min if transposition?(left, right, i, j)
      end
    end

    d[left.length][right.length]
  end

  # Glob with `dir` taken literally: interpolating it into the pattern would let
  # [ ] { } * ? in a --junk-dir name match (and act on) unrelated directories.
  def self.glob_under(dir, pattern)
    return [] unless dir && File.directory?(dir)

    Dir.glob(pattern, base: dir).map { |rel| File.join(dir, rel) }
  end

  def self.safe_read(path)
    return '' unless path && File.file?(path)

    raw = File.read(path, mode: 'r:binary', invalid: :replace, undef: :replace)
    raw.force_encoding('UTF-8').scrub
  rescue StandardError
    ''
  end

  def self.filter_subcommand_noise(text)
    return '' if text.nil? || text.empty?

    filtered = text.gsub(/(?:kpathsea: Running mktex\S+|mktex\S+: Running mf).*?(?:failed to make \S+|Transcript written on mfput\.log\.)\n?/m, '')
    unwrap_log_lines(filtered)
  end

  def self.unwrap_log_lines(text, wrap_col = 79)
    return '' if text.nil? || text.empty?

    lines = text.lines
    result = []
    i = 0
    while i < lines.size
      line = lines[i].chomp
      while line.length == wrap_col && i + 1 < lines.size && !log_boundary_start?(lines[i + 1])
        i += 1
        line += lines[i].chomp
      end
      result << "#{line}\n"
      i += 1
    end
    result.join
  end

  def self.log_boundary_start?(next_line)
    str = next_line.to_s.strip
    return true if str.empty?
    return true if str.start_with?('(', ')', '!', '[')
    return true if str =~ /^(?:Package|Class|LaTeX|\*|\s*(?:Overfull|Underfull))\b/
    return true if str =~ /^.+?:\d+:/
    return true if str =~ /^l\.\d+\b/

    false
  end

  def self.bbl_has_entries?(path)
    return false unless path && File.file?(path) && File.size(path) > 0

    content = safe_read(path)
    content.include?('\bibitem') || content.include?('\entry{')
  end

  def self.extract_citation_keys(aux_str, bcf_content = nil)
    keys = aux_str.to_s.scan(/\\citation\{([^}]+)\}/).flatten.flat_map { |s| s.split(',') }.map(&:strip)
    if bcf_content
      keys.concat(bcf_content.to_s.scan(/<bcf:citekey[^>]*>([^<]+)<\/bcf:citekey>/).flatten.map(&:strip))
    end
    keys.reject(&:empty?).sort.uniq
  end

  def self.bib_fatal_error?(tool, bib_out, status_ok)
    out = bib_out.to_s
    if tool == :bibtex
      return false if status_ok
      return false if out =~ /I found no \\citation commands/i && out !~ /Illegal end of database|syntax error|I couldn't open/i
      true
    elsif tool == :biber
      return false if status_ok && out !~ /> (?:FATAL|ERROR) -/i && out !~ /INFO - ERRORS: [1-9]/i
      return false if out =~ /does not contain any citations/i && out !~ /syntax error/i
      true
    else
      !status_ok
    end
  end

  def self.command_available?(cmd)
    ENV['PATH'].to_s.split(File::PATH_SEPARATOR).any? do |dir|
      bin = File.join(dir, cmd.to_s)
      File.file?(bin) && File.executable?(bin)
    end
  end

  def self.check_program(cmd)
    return if command_available?(cmd)

    warn "ERROR: #{cmd} could not be found in PATH"
    exit 1
  end

  def self.candidate_tex_files(dir, exclude_patterns = nil)
    patterns = exclude_patterns || DEFAULT_EXCLUDE_MAIN_PATTERNS
    search_path = (dir == '.' ? '*.tex' : File.join(dir, '*.tex'))
    Dir[search_path].map { |f| File.basename(f) }.reject do |f|
      f.start_with?('flycheck_', '.') || f.end_with?('~', '.bak') ||
        patterns.any? { |pat| File.fnmatch?(pat, f, File::FNM_CASEFOLD | File::FNM_EXTGLOB) }
    end
  end

  def self.find_main_latex_file(dir = '.', exclude_patterns = nil)
    mainfile = File.join(dir, '.mainfile')
    if File.exist?(mainfile)
      mf = File.read(mainfile).strip
      return mf unless mf.empty?
    end

    candidates = candidate_tex_files(dir, exclude_patterns)
    if candidates.empty?
      warn "Error: No LaTeX (.tex) files found in directory '#{File.expand_path(dir)}'."
      exit 1
    end
    return candidates.first if candidates.size == 1

    dir_match = "#{File.basename(File.expand_path(dir))}.tex"
    return dir_match if candidates.include?(dir_match)

    with_doc = candidates.select do |f|
      c = strip_latex_comments(safe_read(File.join(dir, f)))
      c.include?('\begin{document}') || c.include?('\documentclass')
    end
    return with_doc.first if with_doc.size == 1

    with_pdf = candidates.select do |f|
      base = File.basename(f, '.tex')
      File.exist?(File.join(dir, "#{base}.pdf")) ||
        File.exist?(File.join(dir, 'junk', "#{base}.pdf")) ||
        File.exist?(File.join(dir, '.junk', "#{base}.pdf"))
    end
    return with_pdf.first if with_pdf.size == 1

    warn 'Error: Multiple candidate .tex files found. Please specify which file to compile, or'
    warn '       create a .mainfile containing the name of the main LaTeX file:'
    candidates.each { |f| warn "  #{f}" }
    exit 1
  end

  def self.relative_path_to_pwd(dir, base = (initial_pwd || Dir.pwd))
    target_abs = File.expand_path(dir)
    base_abs   = File.expand_path(base)
    rel = Pathname.new(target_abs).relative_path_from(Pathname.new(base_abs)).to_s
    rel = '.' if rel.empty?
    rel
  rescue ArgumentError
    dir.to_s
  end

  def self.clean_directory(dir = '.', verbose = true)
    target_dir = File.expand_path(dir)
    return unless File.directory?(target_dir)

    rel_path = relative_path_to_pwd(target_dir)
    puts "Cleaning LaTeX auxiliary files in #{rel_path}..." if verbose

    Dir.chdir(target_dir) do
      JUNK_BUILD_DIRS.each { |d| FileUtils.rm_rf(d) }
      JUNK_PATTERNS.each do |pat|
        Dir.glob(pat).each { |f| FileUtils.rm_f(f) }
      end
    end
  end

  def self.reset_latex_environment!
    TEX_ENV_VARS.each { |var| ENV.delete(var) }
    ENV.keys.each do |key|
      ENV.delete(key) if key =~ /\A(?:TEX|BIB|BST|LUA|MF|MP)INPUTS/i
    end
  end

  def self.detailed_examples(banner = nil)
    lines = []
    lines << banner if banner && !banner.empty?
    lines << '' if banner && !banner.empty?
    lines << 'Detailed Examples & Common Workflows:'
    lines << ''
    lines << '  1. Standard Compilation:'
    lines << '     l                              Auto-detect main .tex and compile using xelatex'
    lines << '     l paper.tex                    Compile specified paper.tex'
    lines << '     l -f                           Force first pass (skip up-to-date check), continuing if needed'
    lines << '     l -u                           Fast single pass only (no BibTeX/Biber, no extra passes)'
    lines << '     l                              Incremental by default; skips passes when nothing changed'
    lines << ''
    lines << '  2. Compiler Engines:'
    lines << '     l -e l paper.tex               Compile using LuaLaTeX (short: -e l, -e p, -e x)'
    lines << '     l --engine=pdflatex paper.tex  Compile using pdfLaTeX'
    lines << '     l --engine=xelatex paper.tex   Explicitly compile using XeLaTeX (default)'
    lines << ''
    lines << '  3. Diagnostics & Error Handling:'
    lines << '     l -x                           Display plain-English diagnostic explanations & fixes'
    lines << '     l -a                           Show all diagnostics (including suppressed Whatevers)'
    lines << '     l -c                           Clean regenerable artifacts; preserve .bbl and metadata'
    lines << '     l -C                           Clean directory artifacts and exit without building'
    lines << '     l -s                           Quiet score mode (prints error/alert/warning counts)'
    lines << '     l -W                           Treat compilation warnings as fatal errors'
    lines << ''
    lines << '  4. Output Protection & Update Guard:'
    lines << '     l --update-if-changed          Only replace PDF if rendered text layout changed'
    lines << ''
    lines << '  5. Portable Paper Bundling & Verification:'
    lines << '     l -z                           Bundle paper, active styles, and figures into paper.zip'
    lines << '     l -z -t                        Bundle paper into zip and verify build in /tmp sandbox'
    lines << '     l -z -- figs/extra.png         Include extra supplemental files in the portable bundle'
    lines << ''
    lines << '  6. arXiv Submission Preparation:'
    lines << '     l --arxiv                      Flatten inputs, strip comments, and bundle arXiv package'
    lines << '     l --meta                       Extract title, authors, abstract, and comments metadata'
    lines << ''
    lines << '  7. Configuration & Utilities:'
    lines << '     l -m                           Print detected main LaTeX file and exit'
    lines << '     l --config-init                Generate a starter .l.jsonc configuration file'
    lines << '     l --vscode-init                Generate .vscode/tasks.json and settings.json for VS Code'
    lines << '     l --gitignore-init             Generate or update .gitignore with standard LaTeX & junk/ rules'
    lines.join("\n")
  end

  def self.pdf_page_count(pdf_path)
    return 1 unless command_available?('pdfinfo') && File.file?(pdf_path)

    out, status = Open3.capture2e('pdfinfo', pdf_path)
    return 1 unless status.success?

    out =~ /Pages:\s+(\d+)/ ? Regexp.last_match(1).to_i : 1
  rescue StandardError
    1
  end

  def self.check_type3_fonts(pdf_path)
    return nil unless command_available?('pdffonts') && File.file?(pdf_path) && File.size(pdf_path) > 0

    stdout, status = Open3.capture2e('pdffonts', pdf_path)
    return nil unless status.success? && stdout.include?('Type 3')

    names = extract_type3_font_names(stdout)
    return nil if names.empty?

    pages = find_type3_font_pages(pdf_path)
    { fonts: names, pages: pages }
  rescue StandardError
    nil
  end

  def self.extract_type3_font_names(stdout)
    names = []
    stdout.each_line do |line|
      next if line.start_with?('name ', '---')
      next unless line =~ /\s+Type 3\s+/

      parts = line.split
      names << (parts[0] || '[none]')
    end
    names.uniq
  end

  def self.find_type3_font_pages(pdf_path)
    total_pages = pdf_page_count(pdf_path)
    return [] if total_pages > 100

    pages = []
    (1..total_pages).each do |p|
      out, status = Open3.capture2e('pdffonts', '-f', p.to_s, '-l', p.to_s, pdf_path)
      pages << p if status.success? && out.include?('Type 3')
    end
    pages
  rescue StandardError
    []
  end

  def self.strip_ansi(str)
    str.to_s.gsub(/\e\]8;;[^\e]*\e\\/, '').gsub(/\e\[[0-9;]*[a-zA-Z]/, '')
  end

  def self.visible_width(str)
    plain = strip_ansi(str)
    width = if defined?(Unicode::DisplayWidth)
              Unicode::DisplayWidth.of(plain)
            else
              extra = plain.scan(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B50}]/).size
              plain.length + extra
            end
    width += plain.scan(/\u{26A0}\u{FE0F}/).size if defined?(Unicode::DisplayWidth)
    width
  end

  def self.terminal_width(default: 80, max: nil)
    w = if ENV['COLUMNS'] =~ /^\d+$/
          ENV['COLUMNS'].to_i
        else
          (IO.console&.winsize&.last rescue nil) ||
            ($stdout.tty? ? ($stdout.winsize[1] rescue nil) : nil)
        end
    return default unless w && w > 30

    max ? [w, max].min : w
  end

  def self.wrap_text(text, width: nil, prefix: nil, indent: nil)
    return '' if text.nil? || text.empty?

    width ||= terminal_width(default: 80)
    text.to_s.split("\n", -1).map do |line|
      wrap_single_line(line, width: width, prefix: prefix, indent: indent)
    end.join("\n")
  end

  def self.wrap_single_line(line, width: 80, prefix: nil, indent: nil)
    return line if line.strip.empty?

    first_pfx, sub_pfx, content = resolve_wrap_prefixes(line, prefix, indent)
    words = content.split(/\s+/)
    return "#{first_pfx}#{content}" if words.empty?

    assemble_wrapped_lines(words, width, first_pfx, sub_pfx)
  end

  def self.resolve_wrap_prefixes(line, prefix, indent)
    if prefix
      content = line.start_with?(prefix) ? line[prefix.length..] : line
      [prefix, indent || (' ' * visible_width(prefix)), content]
    elsif (m = strip_ansi(line).match(/\A(\s*(?:[▸•\-*]|\d+[.)])\s+)(.*)\z/m))
      pfx_len = m[1].length
      first_pfx = line[0...pfx_len]
      [first_pfx, indent || (' ' * visible_width(first_pfx)), line[pfx_len..]]
    elsif (m = strip_ansi(line).match(/\A(\s+)(.*)\z/m))
      pfx_len = m[1].length
      first_pfx = line[0...pfx_len]
      [first_pfx, indent || first_pfx, line[pfx_len..]]
    else
      ['', indent || '', line]
    end
  end

  def self.assemble_wrapped_lines(words, width, first_pfx, sub_pfx)
    first_avail = [width - visible_width(first_pfx), 10].max
    sub_avail = [width - visible_width(sub_pfx), 10].max
    wrapped = []
    curr = []
    curr_len = 0
    avail = first_avail

    words.each do |w|
      w_len = visible_width(w)
      if curr.empty?
        curr << w
        curr_len = w_len
      elsif curr_len + 1 + w_len <= avail
        curr << w
        curr_len += 1 + w_len
      else
        pfx = wrapped.empty? ? first_pfx : sub_pfx
        wrapped << "#{pfx}#{curr.join(' ')}"
        curr = [w]
        curr_len = w_len
        avail = sub_avail
      end
    end
    unless curr.empty?
      pfx = wrapped.empty? ? first_pfx : sub_pfx
      wrapped << "#{pfx}#{curr.join(' ')}"
    end
    wrapped.join("\n")
  end

  ProcessResultStatus = Struct.new(:exitstatus, :success, :termsig, :signaled) do
    def success?
      self[:success] == true
    end

    def signaled?
      self[:signaled] == true
    end
  end

  def self.shell_quote(str)
    s = str.to_s
    return s if s.match?(%r{\A[a-zA-Z0-9_.\-\/=:]+\z})

    "'#{s.gsub("'", "'\\\\''")}'"
  end

  def self.format_trace_command(env, cmd_args, cwd = Dir.pwd)
    overrides = []
    tracked = %w[TEXINPUTS BIBINPUTS max_print_line]
    tracked.each do |k|
      overrides << "#{k}=#{shell_quote(env[k])}" if env[k] && env[k] != ENV[k]
    end
    (env.keys - ENV.keys).each do |k|
      next if tracked.include?(k)

      overrides << "#{k}=#{shell_quote(env[k])}"
    end
    (env.keys & ENV.keys).each do |k|
      next if tracked.include?(k) || env[k] == ENV[k]

      overrides << "#{k}=#{shell_quote(env[k])}"
    end

    cmd_str = cmd_args.map { |arg| shell_quote(arg.to_s) }.join(' ')
    prefix = overrides.empty? ? '' : "#{overrides.join(' ')} "
    "(cd #{shell_quote(cwd)} && #{prefix}#{cmd_str})"
  end

  def self.trace_command(env, cmd_args, cwd = Dir.pwd)
    puts Rainbow("[trace] #{format_trace_command(env, cmd_args, cwd)}").cyan
  end

  def self.trace_status(status)
    code = if status.nil?
             1
           else
             status.exitstatus || (status.respond_to?(:termsig) && status.termsig ? 128 + status.termsig : 1)
           end
    status_str = "[trace] => exit status #{code}"
    puts(code.zero? ? Rainbow(status_str).green : Rainbow(status_str).yellow)
  end
end

class LaTeXIndicator
  @thr = nil
  @t0 = nil
  @active = false

  def self.start(label, enabled: true, delay: 0.2)
    return unless enabled

    stop(clear: false, enabled: true)
    already_active = @active
    @t0 ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)

    if already_active
      print "\r\e[2K#{Rainbow('  ▸ ').cyan}#{label}"
      $stdout.flush
    end

    @thr = Thread.new do
      unless already_active
        sleep delay
        @active = true
        print "\r\e[2K#{Rainbow('  ▸ ').cyan}#{label}"
        $stdout.flush
      end

      loop do
        sleep 1.0
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @t0).round
        print "\r\e[2K#{Rainbow('  ▸ ').cyan}#{label} [#{elapsed}s]"
        $stdout.flush
      end
    rescue StandardError
      nil
    end
  end

  def self.stop(clear: false, enabled: true)
    return unless enabled

    if @thr
      @thr.kill rescue nil
      @thr.join(0.05) rescue nil
      @thr = nil
    end

    if clear
      print "\r\e[2K" if @active
      $stdout.flush
      @active = false
      @t0 = nil
    end
  end
end
