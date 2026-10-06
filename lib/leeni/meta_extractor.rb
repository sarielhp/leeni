# frozen_string_literal: true

# ==============================================================================
# lib/leeni/meta_extractor.rb
#
# Metadata extractor for LaTeX papers (Title, Authors, Abstract, Page Count).
# Formats output for arXiv submissions, preserving supported inline MathJax.
# ==============================================================================

require 'open3'

module LaTeXMetaExtractor
  ARXIV_ABSTRACT_SYMBOLS = {
    '–' => '-', '—' => '--', '−' => '-', '‐' => '-', '…' => '...',
    '“' => '"', '”' => '"', '‘' => "'", '’' => "'", ' ' => ' ',
    '≤' => '\\leq', '≥' => '\\geq', '≠' => '\\ne', '×' => '\\times',
    '·' => '\\cdot', '∞' => '\\infty', '∈' => '\\in', '→' => '\\to',
    'α' => '\\alpha', 'β' => '\\beta', 'γ' => '\\gamma', 'δ' => '\\delta',
    'ε' => '\\epsilon', 'θ' => '\\theta', 'λ' => '\\lambda', 'μ' => '\\mu',
    'π' => '\\pi', 'ρ' => '\\rho', 'σ' => '\\sigma', 'φ' => '\\phi',
    'ω' => '\\omega'
  }.freeze

  ARXIV_ACCENTS = {
    "\u0301" => "\\'", "\u0300" => "\\`", "\u0302" => "\\^",
    "\u0308" => '\\"', "\u0303" => '\\~', "\u0327" => '\\c',
    "\u030a" => '\\r', "\u0304" => '\\=', "\u0306" => '\\u',
    "\u030c" => '\\v', "\u0328" => '\\k', "\u0307" => '\\.'
  }.freeze

  GREEK_SYMBOLS = {
    'alpha' => 'α', 'beta' => 'β', 'gamma' => 'γ', 'delta' => 'δ',
    'epsilon' => 'ε', 'varepsilon' => 'ε', 'zeta' => 'ζ', 'eta' => 'η',
    'theta' => 'θ', 'vartheta' => 'θ', 'iota' => 'ι', 'kappa' => 'κ',
    'lambda' => 'λ', 'mu' => 'μ', 'nu' => 'ν', 'xi' => 'ξ',
    'pi' => 'π', 'varpi' => 'π', 'rho' => 'ρ', 'varrho' => 'ρ',
    'sigma' => 'σ', 'varsigma' => 'σ', 'tau' => 'τ', 'upsilon' => 'υ',
    'phi' => 'φ', 'varphi' => 'φ', 'chi' => 'χ', 'psi' => 'ψ', 'omega' => 'ω',
    'Gamma' => 'Γ', 'Delta' => 'Δ', 'Theta' => 'Θ', 'Lambda' => 'Λ',
    'Xi' => 'Ξ', 'Pi' => 'Π', 'Sigma' => 'Σ', 'Upsilon' => 'Υ',
    'Phi' => 'Φ', 'Psi' => 'Ψ', 'Omega' => 'Ω'
  }.freeze

  MATH_SYMBOLS = {
    'leq' => '≤', 'le' => '≤', 'geq' => '≥', 'ge' => '≥',
    'neq' => '≠', 'ne' => '≠', 'approx' => '≈', 'times' => '×',
    'cdot' => '·', 'in' => '∈', 'notin' => '∉', 'subset' => '⊂',
    'subseteq' => '⊆', 'cap' => '∩', 'cup' => '∪', 'to' => '→',
    'rightarrow' => '→', 'leftarrow' => '←', 'gets' => '←',
    'infty' => '∞', 'pm' => '±', 'mp' => '∓',
    'sum' => '∑', 'prod' => '∏', 'int' => '∫'
  }.freeze

  TEXT_MACROS_TO_STRIP = %w[thanks footnote].freeze
  TEXT_MACROS_TO_UNWRAP = %w[textbf textit texttt textmd textsc textsl textnormal emph text mathsf mathbf mathit mathrm].freeze
  MATH_FUNCTIONS = %w[log ln exp min max sin cos tan det dim ker].freeze
  MATH_REPLACEMENTS = GREEK_SYMBOLS.merge(MATH_SYMBOLS).merge(MATH_FUNCTIONS.to_h { |f| [f, f] }).freeze
  MATH_TOKEN_PATTERN = /\\(#{Regexp.union(MATH_REPLACEMENTS.keys.sort_by { |k| -k.length }).source})\b/.freeze
  MATH_FONT_PATTERN = /\\(?:mathbb|mathcal|mathfrak)\{([A-Za-z])\}/.freeze
  MATH_SQRT_PATTERN = /\\sqrt\{([^}]+)\}/.freeze
  MATH_INLINE_PATTERN = /\$([^\$]+)\$/.freeze

  def self.extract(main_tex, base_dir = '.', pdf_path = nil, fls_path = nil, log_path = nil, extra_comments = nil)
    raw_content = LaTeXUtils.safe_read(File.join(base_dir, main_tex))
    title = extract_title(raw_content)
    authors = extract_authors(raw_content)
    abstract = extract_abstract(raw_content)
    page_count = extract_page_count(pdf_path, log_path)
    fig_count = extract_figure_count(fls_path, base_dir)
    comments = format_comments(page_count, fig_count, extra_comments)

    {
      title: title,
      authors: authors,
      abstract: abstract,
      abstract_form: extract_abstract_for_arxiv(raw_content),
      page_count: page_count,
      fig_count: fig_count,
      comments: comments
    }
  end

  def self.preceding_backslash_count(text, idx)
    count = 0
    k = idx - 1
    while k >= 0 && text[k] == '\\'
      count += 1
      k -= 1
    end
    count
  end

  def self.extract_balanced_braces(text, start_pos)
    return nil if start_pos.nil? || text[start_pos] != '{'

    depth = 0
    i = start_pos
    len = text.length
    while i < len
      c = text[i]
      if c == '{' && preceding_backslash_count(text, i).even?
        depth += 1
      elsif c == '}' && preceding_backslash_count(text, i).even?
        depth -= 1
        return text[(start_pos + 1)...i] if depth == 0
      end
      i += 1
    end
    nil
  end

  def self.find_macro_content(text, macro_name)
    pattern = /\\#{Regexp.escape(macro_name)}(?:\[[^\]]*\])?\s*\{/
    idx = text.index(pattern)
    return nil unless idx

    brace_start = text.index('{', idx)
    extract_balanced_braces(text, brace_start)
  end

  def self.unwrap_macros(str, macros, replace_with_inner: false)
    macros.each do |macro|
      while (idx = str.index(/\\#{macro}\s*\{/))
        brace_start = str.index('{', idx)
        inner = extract_balanced_braces(str, brace_start)
        break unless inner

        replacement = replace_with_inner ? inner : ''
        str[idx..(brace_start + inner.length + 1)] = replacement
      end
    end
    str
  end

  def self.clean_latex_formatting(text)
    return '' if text.nil?

    str = text.dup
    unwrap_macros(str, TEXT_MACROS_TO_STRIP, replace_with_inner: false)
    unwrap_macros(str, TEXT_MACROS_TO_UNWRAP, replace_with_inner: true)

    str.gsub!(/\\\\(\[[^\]]*\])?/, ' ')
    str.gsub!(/\\newline/, ' ')
    str.gsub!(/~/, ' ')
    str.gsub!(/\\%/, '%')
    strip_accent_macros(str)
    str
  end

  # Accent macros taking an argument. The set used to be only ' " ` ^ ~ = .
  # plus \c, so every other one survived into the extracted name -- and
  # verify_arxiv_authors_match rejects any name containing a backslash, so
  # Erdos, Novak, Jorgensen and Ulam each blocked --arxiv outright with a
  # message blaming the user's \author formatting for a gap in this cleaner.
  # Split by spelling, not by meaning. A symbol accent may sit directly against
  # its letter (\'e), but a letter accent may not: \vS is a different macro from
  # \v S, and treating them alike made \b swallow the start of \beta.
  SYMBOL_ACCENTS = %w[' " ` ^ ~ = .].freeze
  LETTER_ACCENTS = %w[c v u r H k b d t].freeze

  # Standalone letter macros, which have no argument and may be written either
  # as \o or as \o{} and may be followed directly by text (\o rgensen).
  LIGATURE_MACROS = {
    'ss' => 'ss', 'AA' => 'AA', 'aa' => 'aa', 'AE' => 'AE', 'ae' => 'ae',
    'OE' => 'OE', 'oe' => 'oe', 'O' => 'O', 'o' => 'o', 'L' => 'L',
    'l' => 'l', 'i' => 'i', 'j' => 'j', 'DH' => 'D', 'dh' => 'd',
    'TH' => 'Th', 'th' => 'th', 'NG' => 'N', 'ng' => 'n'
  }.freeze

  def self.strip_accent_macros(str)
    symbols = SYMBOL_ACCENTS.map { |a| Regexp.escape(a) }.join('|')
    letters = LETTER_ACCENTS.join('|')

    str.gsub!(/\\(?:#{symbols})\s*\{([^{}]*)\}/, '\\1')
    str.gsub!(/\\(?:#{symbols})\s*([A-Za-z])/, '\\1')
    str.gsub!(/\\(?:#{letters})(?![a-zA-Z])\s*\{([^{}]*)\}/, '\\1')
    str.gsub!(/\\(?:#{letters})(?![a-zA-Z])\s+([A-Za-z])/, '\\1')

    # Longest first, so \AA is not consumed as \A followed by 'A'.
    LIGATURE_MACROS.keys.sort_by { |k| -k.length }.each do |macro|
      str.gsub!(/\\#{macro}(?![a-zA-Z])\s*(?:\{\})?/, LIGATURE_MACROS[macro])
    end
    str
  end

  def self.clean_latex_math(text)
    return '' if text.nil?

    str = text.dup
    str.gsub!(MATH_TOKEN_PATTERN) { MATH_REPLACEMENTS[Regexp.last_match(1)] }
    str.gsub!(MATH_FONT_PATTERN, '\1')
    str.gsub!(MATH_SQRT_PATTERN, '√(\1)')
    str.gsub!(MATH_INLINE_PATTERN, '\1')
    str.delete('$')
  end

  def self.extract_title(content)
    raw = find_macro_content(content, 'title')
    return 'Untitled' if raw.nil? || raw.strip.empty?

    clean = clean_latex_formatting(raw)
    clean = clean_latex_math(clean)
    clean.gsub(/\s+/, ' ').strip
  end

  def self.extract_authors(content)
    names = extract_author_names(content)
    names.empty? ? 'Unknown' : names.join(', ')
  end

  def self.extract_author_blocks(content)
    raw_blocks = []
    content.scan(/\\author(?:\[[^\]]*\])?\s*\{/) do
      idx = Regexp.last_match.begin(0)
      brace_start = content.index('{', idx)
      raw = extract_balanced_braces(content, brace_start)
      raw_blocks << raw if raw
    end
    raw_blocks
  end

  def self.clean_author_block(raw)
    str = raw.dup
    %w[thanks footnote affil orcid email inst institution address].each do |macro|
      while (idx = str.index(/\\#{macro}\s*\{/))
        brace_start = str.index('{', idx)
        inner = extract_balanced_braces(str, brace_start)
        break unless inner

        str[idx..(brace_start + inner.length + 1)] = ''
      end
    end
    str
  end

  def self.parse_single_author_line(l)
    clean = clean_latex_formatting(l)
    clean = clean_latex_math(clean)
    clean.gsub(/\\orcid\S*/, '')
         .gsub(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/, '')
         .gsub(/\s+/, ' ')
         .strip
  end

  def self.extract_author_names(content)
    raw_blocks = extract_author_blocks(content)
    return [] if raw_blocks.empty?

    authors = []
    raw_blocks.each do |raw|
      str = clean_author_block(raw)
      str.split(/\\and/).each do |block|
        lines = block.split(/\\\\|\\newline/).map { |l| parse_single_author_line(l) }
        lines.reject! do |l|
          l.empty? || l =~ /department|university|institute|laboratory|school|college|center|address|\b(?:USA|UK|IL|CA|NY)\b|\d{4,}/i
        end
        authors.concat(lines)
      end
    end
    authors
  end

  def self.extract_abstract(content)
    raw = abstract_source(content)
    return '' if raw.nil?

    raw = strip_latex_comments(raw)
    raw.gsub!(/\\begin\{(?:itemize|enumerate)\}/, '')
    raw.gsub!(/\\end\{(?:itemize|enumerate)\}/, '')
    raw.gsub!(/\\item\s*/, '- ')

    clean = clean_latex_formatting(raw)
    clean = clean_latex_math(clean)

    paragraphs = clean.split(/\n[^\S\r\n]*\n+/).map do |p|
      p.gsub(/[[:space:]]+/, ' ').strip
    end.reject(&:empty?)

    paragraphs.join("\n\n")
  end

  def self.extract_abstract_for_arxiv(content)
    raw = abstract_source(content)
    return '' if raw.nil?

    raw = strip_latex_comments(raw)
    raw.gsub!(/\\begin\{(?:itemize|enumerate)\}/, '')
    raw.gsub!(/\\end\{(?:itemize|enumerate)\}/, '')
    raw.gsub!(/\\item\s*/, '- ')
    clean = protect_math(raw) do |text|
      text = clean_latex_formatting(text)
      text = clean_form_commands(text)
      ascii_form_text(text)
    end
    clean = ascii_form_text(clean)
    paragraphs = clean.split(/\n[^\S\r\n]*\n+/).filter_map do |paragraph|
      value = paragraph.gsub(/[[:space:]]+/, ' ').strip
      value.empty? ? nil : value
    end
    paragraphs.join("\n ")
  end

  def self.abstract_source(content)
    if content =~ /\\begin\{abstract\}(.*?)\\end\{abstract\}/m
      Regexp.last_match(1)
    elsif (idx = content.index(/\\abstract\s*\{/))
      extract_balanced_braces(content, content.index('{', idx))
    end
  end

  def self.protect_math(text)
    math = []
    protected = text.gsub(/\$[^$\n]*\$|\\\([^\n]*?\\\)|\\\[[\s\S]*?\\\]/) do |value|
      math << value
      "\u0000M#{math.length - 1}\u0000"
    end
    result = yield(protected)
    math.each_with_index { |value, index| result = result.gsub("\u0000M#{index}\u0000", value) }
    result
  end

  def self.clean_form_commands(text)
    text.gsub(/\\[A-Za-z@]+\*?(?:\s*\{([^{}]*)\})?/, '\\1').gsub(/[{}]/, '')
  end

  def self.ascii_form_text(text)
    result = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub
    ARXIV_ABSTRACT_SYMBOLS.each { |character, replacement| result.gsub!(character, replacement) }
    result = result.unicode_normalize(:nfkd)
    result = result.gsub(/([A-Za-z])([\u0300-\u036f]+)/) do
      base = Regexp.last_match(1)
      accents = Regexp.last_match(2).each_char.filter_map { |mark| ARXIV_ACCENTS[mark] }
      accents.empty? ? base : accents.join + base
    end
    result = result.gsub(/[\u0300-\u036f]/, '')
    result.encode(Encoding::US_ASCII, invalid: :replace, undef: :replace, replace: '')
  end

  def self.strip_latex_comments(text)
    text.gsub(/\r\n?/, "\n").lines.map do |line|
      comment_at = LaTeXUtils.latex_comment_start(line)
      next line unless comment_at

      prefix = line[0...comment_at]
      prefix.strip.empty? ? '' : prefix + (line.end_with?("\n") ? "\n" : '')
    end.join
  end

  def self.extract_page_count(pdf_path, log_path)
    if pdf_path && File.file?(pdf_path) && LaTeXUtils.command_available?('pdfinfo')
      out, _err, status = Open3.capture3('pdfinfo', pdf_path)
      return Regexp.last_match(1).to_i if status.success? && out =~ /^Pages:\s*(\d+)/
    end

    if log_path && File.file?(log_path)
      content = LaTeXUtils.safe_read(log_path)
      return Regexp.last_match(1).to_i if content =~ /Output written on .*?\((\d+)\s+pages?/
    end

    nil
  end

  def self.extract_figure_count(fls_path, base_dir = '.')
    return 0 unless fls_path && File.file?(fls_path)

    fls_content = LaTeXUtils.safe_read(fls_path)
    cwd = File.expand_path(base_dir)
    count = 0
    fls_content.each_line do |line|
      next unless line =~ /^INPUT\s+(\S+)/

      path = Regexp.last_match(1)
      next if path.include?('/usr/share/texlive') || path.include?('texmf-dist')
      next unless path =~ /\.(pdf|png|jpg|jpeg|mps)$/i

      expanded = File.expand_path(path, cwd)
      count += 1 if expanded.start_with?(cwd + '/') || expanded == cwd
    end
    count
  end

  def self.format_comments(page_count, fig_count, extra_comments = nil)
    parts = []
    parts << "#{page_count} #{page_count == 1 ? 'page' : 'pages'}" if page_count && page_count > 0
    parts << "#{fig_count} #{fig_count == 1 ? 'figure' : 'figures'}" if fig_count && fig_count > 0
    base = parts.join(', ')
    base += '.' unless base.empty? || base.end_with?('.')
    if extra_comments && !extra_comments.strip.empty?
      base.empty? ? extra_comments.strip : "#{base} #{extra_comments.strip}"
    else
      base.empty? ? nil : base
    end
  end

  def self.format_meta_txt(meta)
    out = []
    out << 'Title:'
    out << meta[:title]
    out << ''
    out << 'Authors:'
    out << meta[:authors]
    out << ''
    if meta[:comments]
      out << 'Comments:'
      out << meta[:comments]
      out << ''
    end
    out << 'Abstract:'
    out << (meta[:abstract_form] || meta[:abstract])
    out << ''
    out.join("\n")
  end

  def self.write_meta_file(filename, meta_txt)
    File.write(filename, meta_txt)
  end
end
