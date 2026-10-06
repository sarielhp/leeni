# frozen_string_literal: true

# ==============================================================================
# lib/leeni/error_catalog.rb
#
# Declarative catalog of known LaTeX/TeX compilation errors, pattern matching,
# token extraction, and actionable remediation hints.
# ==============================================================================

require_relative 'utils'
require_relative 'macro_harvester'

module LaTeXErrorCatalog
  PACKAGE_COMMANDS = {
    'toprule' => 'booktabs',
    'midrule' => 'booktabs',
    'bottomrule' => 'booktabs',
    'cmidrule' => 'booktabs',
    'specialrule' => 'booktabs',
    'mathbb' => 'amssymb',
    'mathfrak' => 'amssymb',
    'checkmark' => 'amssymb',
    'triangleq' => 'amssymb',
    'coloneqq' => 'mathtools',
    'DeclarePairedDelimiter' => 'mathtools',
    'bm' => 'bm',
    'url' => 'hyperref or url',
    'nolinkurl' => 'hyperref or url',
    'href' => 'hyperref',
    'hypersetup' => 'hyperref',
    'includegraphics' => 'graphicx',
    'graphicspath' => 'graphicx',
    'rotatebox' => 'graphicx',
    'resizebox' => 'graphicx',
    'color' => 'xcolor',
    'textcolor' => 'xcolor',
    'colorbox' => 'xcolor',
    'definecolor' => 'xcolor',
    'subcaption' => 'subcaption',
    'subfloat' => 'subcaption',
    'cancel' => 'cancel',
    'sout' => 'ulem',
    'hl' => 'soul',
    'lstinline' => 'listings',
    'lstinputlisting' => 'listings',
    'tikz' => 'tikz',
    'node' => 'tikz',
    'coordinate' => 'tikz',
    'microtypesetup' => 'microtype',
    'text' => 'amsmath',
    'eqref' => 'amsmath',
    'DeclareMathOperator' => 'amsmath',
    'boldsymbol' => 'amsmath',
    'intertext' => 'amsmath'
  }.freeze

  COMMON_COMMANDS = %w[
    acute addcontentsline alpha appendix appendixname approx arabic atop
    author bar begin beginend beta bfseries bibitem bibliography
    bibliographystyle bigcap bigcup Bigg bigg Biggl biggl Bigl
    bigl bigskip boldmath breve cap caption cdot cdots
    centering chapter chaptermark chaptername check chi circ cite
    citep citet citeyear cleardoublepage clearpage cline columnwidth contentsline
    contentsname cos cup date ddot ddots Delta delta
    det displaystyle div documentclass dot dots emph end
    enlargethispage ensuremath epsilon equiv eta exists exp fbox
    figurename flushbottom fontencoding fontfamily fontseries fontshape fontsize footnote
    footnotemark footnotesize footnotetext footref forall fpeval frac frame
    framebox Gamma gamma ge geq glossary glossaryentry grave
    hat hline hlinefill hrule hspace Huge huge i
    iff iint IJ ij implies in include includegraphics
    includeonly index indexname indexspace inf infty input inputlineno
    int inteval iota item itshape kappa kill label
    Lambda lambda LARGE Large large LaTeX LaTeXe ldots
    le left Leftarrow leftarrow lefteqn Leftrightarrow leq lim
    linebreak linespread linethickness linewidth listfigurename listfiles listoffigures listoftables
    listtablename ln log makeatletter makeatother makeglossary makeindex maketitle
    mapsto marginpar markboth markright mathbb mathbf mathcal mathdollar
    mathds mathellipsis mathgroup mathit mathnormal mathparagraph mathring mathrm
    mathscr mathsection mathsf mathsterling mathtt mathunderscore max mbox
    medskip medspace mid min mu multicolumn nabla ne
    neg negmedspace negthickspace neq newcommand newenvironment newlength newline
    newpage newtheorem nocite nofiles noindent nolinebreak nonumber nopagebreak
    normalcolor normalfont normalsize notin nu OE oe oint
    oldstylenums Omega omega onecolumn over overbrace overline pagebreak
    pagename pagenumbering pageref pagestyle paragraph parbox parencite part
    partial partname Phi phi Pi pi pm poptabs
    pounds prime prod protect providecommand Psi psi pushtabs
    r raggedleft raggedright Ref ref refname renewcommand renewenvironment
    rho right Rightarrow rightarrow rightmargin rightmark rmfamily Roman
    roman rule sbox scriptsize scshape section selectfont setlength
    setminus sffamily shortcite shortstack Sigma sigma sim simeq
    sin slshape small smallskip sqrt SS stackrel stepcounter
    stop subitem subparagraph subsection subset subseteq subsubitem subsubsection
    sum sup suppressfloats supset supseteq symbol tablename tableofcontents
    tabularnewline tan tau text textasciicircum textasciitilde textasteriskcentered textbackslash
    textbar textbf textbraceleft textbraceright textbullet textcircled textcite textcommaabove
    textcommabelow textcompwordmark textcopyright textdagger textdaggerdbl textdollar textellipsis textemdash
    textendash textexclamdown textgreater textheight textit textless textmd textnormal
    textparagraph textperiodcentered textquestiondown textquotedblleft textquotedblright textquoteleft textquoteright textregistered
    textrm textsc textsection textsf textsl textsterling textsubscript textsuperscript
    texttrademark texttt textunderscore textup textvisiblespace textwidth thanks Theta
    theta thickspace thispagestyle tilde time times tiny title
    to today ttfamily twocolumn unboldmath underbrace underline upshape
    Upsilon upsilon usepackage varbigtriangledown varbigtriangleup varepsilon varphi varpi
    varrho varsigma vartheta vdots vec vee verb vline
    vspace wedge widehat widetilde width Xi xi zeta
  ].freeze

  def self.suggest_command(raw_tok, file: nil, macro: nil, junk_dir: nil)
    return 'Undefined command; check spelling or \\usepackage' if raw_tok.nil? || raw_tok.empty?

    cmd = raw_tok.to_s.strip.sub(/\A\\/, '')
    return "Undefined command '\\#{cmd}'; check spelling or \\usepackage" if cmd.empty?

    macro_ctx = macro ? " (in expansion of '#{macro}')" : ''

    pkg = PACKAGE_COMMANDS[cmd]
    return "Command '\\#{cmd}'#{macro_ctx} requires \\usepackage{#{pkg}}" if pkg

    project_macros = LaTeXMacroHarvester.harvest(file, junk_dir: junk_dir)
    suggestion = find_closest_command(cmd, project_macros)
    if suggestion
      sug_pkg = project_macros.include?(suggestion) ? nil : PACKAGE_COMMANDS[suggestion]
      sug_pkg ? "Did you mean '\\#{suggestion}'?#{macro_ctx} (requires \\usepackage{#{sug_pkg}})" : "Did you mean '\\#{suggestion}'?#{macro_ctx}"
    else
      "Undefined command '\\#{cmd}'#{macro_ctx}; check spelling or \\usepackage"
    end
  end

  def self.find_closest_command(cmd, project_macros = [])
    return nil if cmd.length < 3

    ci_match = (project_macros + COMMON_COMMANDS + PACKAGE_COMMANDS.keys).find do |c|
      c.casecmp(cmd).zero? && c != cmd
    end
    return ci_match if ci_match

    max_dist = [cmd.length / 3, 1].max
    candidates = (COMMON_COMMANDS + PACKAGE_COMMANDS.keys + project_macros).uniq
    candidates.select! { |c| (c.length - cmd.length).abs <= max_dist }

    scored = score_command_candidates(cmd, candidates, project_macros)
    return nil if scored.empty?

    scored.sort_by! { |s| [s[:dist], s[:is_proj], s[:same_first]] }
    best = scored[0]
    return nil if ambiguous_match?(best, scored[1])

    best[:cand]
  end

  def self.score_command_candidates(cmd, candidates, project_macros)
    scored = []
    threshold = candidate_threshold(cmd.length)

    candidates.each do |c|
      next if c == cmd

      same_first = c[0] == cmd[0] ? 0 : 1
      dist = LaTeXUtils.keyboard_edit_distance(cmd, c)
      next if same_first == 1 && dist > 0.85
      next if dist > threshold

      is_proj = project_macros.include?(c) ? 0 : 1
      scored << { cand: c, dist: dist, is_proj: is_proj, same_first: same_first }
    end
    scored
  end

  def self.candidate_threshold(len)
    if len <= 4
      0.85
    elsif len <= 7
      1.25
    else
      [len * 0.18, 1.8].max
    end
  end

  def self.ambiguous_match?(best, runner_up)
    return false unless runner_up
    return false if best[:is_proj].zero? && runner_up[:is_proj] == 1 && best[:dist] <= runner_up[:dist]
    return true if (best[:dist] - runner_up[:dist]).abs < 0.05

    if best[:dist] >= 1.5 && runner_up[:dist] < best[:dist] + 0.5
      return true unless best[:is_proj].zero? && runner_up[:is_proj] == 1
    end

    false
  end

  def self.extract_undefined_cs_info(err_block)
    block_text = err_block.join("\n")
    if block_text =~ /<recently read>\s*(\\[a-zA-Z@]+|\\[^\s])/
      return [Regexp.last_match(1), nil]
    end
    if block_text =~ /<to be read again>\s*(\\[a-zA-Z@]+|\\[^\s])/
      return [Regexp.last_match(1), nil]
    end

    # Check macro expansion lines: \macro ...->... \badcs
    # TeX breaks the line immediately after the offending token, so the culprit
    # is the last control sequence on the line after '->'.
    macro_line = err_block.find { |l| l =~ /->/ }
    if macro_line
      before_arrow, after_arrow = macro_line.split('->', 2)
      enclosing = before_arrow&.scan(/\\[a-zA-Z@]+|\\[^\s]/)&.first
      cs = after_arrow&.scan(/\\[a-zA-Z@]+|\\[^\s]/)&.last
      return [cs, enclosing] if cs
    end

    # Check <argument> lines: <argument> ... \badcs
    arg_line = err_block.find { |l| l =~ /<argument>/ }
    if arg_line
      after_arg = arg_line.sub(/\A.*<argument>\s*/, '')
      cs = after_arg.scan(/\\[a-zA-Z@]+|\\[^\s]/).last
      return [cs, nil] if cs
    end

    # Fallback to l.N line
    context = err_block.find { |l| l =~ /\Al\.\d+/ }
    if context
      tokens = context.scan(/\\[a-zA-Z@]+|\\[^\s]/)
      tokens.reject! { |t| t == '\end' } if tokens.size > 1
      return [tokens.last, nil] if tokens.last
    end

    [nil, nil]
  end

  def self.find_undefined_cs_source_location(file, line, token, err_block)
    source_file = find_source_file(file)
    return [nil, nil] unless source_file && line && line.to_i > 0

    lines = File.readlines(source_file) rescue nil
    return [nil, nil] unless lines

    err_idx = line.to_i - 1
    return [nil, nil] if err_idx < 0 || err_idx >= lines.size

    _cs, macro = extract_undefined_cs_info(err_block)

    start_search = [err_idx - 1, 0].max
    min_search = [err_idx - 50, 0].max

    # Pass 1: Look for the undefined token itself on preceding lines
    if token && !token.empty?
      start_search.downto(min_search) do |i|
        pos = lines[i].index(token)
        return [i + 1, pos + 1] if pos
      end
    end

    # Pass 2: If inside a macro expansion, look for the enclosing macro on preceding lines
    if macro && !macro.empty?
      start_search.downto(min_search) do |i|
        pos = lines[i].index(macro)
        return [i + 1, pos + 1] if pos
      end
    end

    [nil, nil]
  rescue StandardError
    [nil, nil]
  end

  # TeX breaks the error context line immediately after the offending token.
  # If inside a macro definition/expansion (e.g. \DotProd #1#2->\permut),
  # or argument (<argument> ...), the culprit is on that line, NOT on the outer l.N context.
  UNDEFINED_CS_EXTRACTOR = lambda do |_match, err_block|
    token, _macro = extract_undefined_cs_info(err_block)
    token
  end

  MATH_NON_ALIGN_ENVS = (
    %w[equation equation* gather gather* multline multline* displaymath math] + ['\\[ ... \\]']
  ).freeze

  TABLE_MATRIX_ENVS = %w[
    tabular tabular* tabularx tabulary longtable array
    matrix pmatrix bmatrix Bmatrix vmatrix Vmatrix cases
  ].freeze

  ALIGN_ENVS = %w[
    align align* flalign flalign* alignat alignat* split aligned alignedat
  ].freeze

  def self.suggest_alignment_tab(env)
    return "'&' outside align*/tabular; switch environment or escape as '\\&'" if env.nil? || env.empty?

    if MATH_NON_ALIGN_ENVS.include?(env)
      target = env.end_with?('*') || env == '\\[ ... \\]' || %w[displaymath math].include?(env) ? 'align*' : 'align'
      "Misplaced '&' in '#{env}'; switch to '#{target}' (or use 'aligned' / 'split')"
    elsif TABLE_MATRIX_ENVS.include?(env)
      "Extra '&' in '#{env}'; too many columns or missing newline '\\\\'"
    elsif ALIGN_ENVS.include?(env)
      "Misplaced '&' in '#{env}'; check for extra '&' or missing '\\\\'"
    else
      "Unescaped '&' in text; escape as '\\&'"
    end
  end

  def self.find_source_file(file_path)
    return nil if file_path.nil? || file_path.to_s.strip.empty?

    clean = file_path.to_s.strip.delete_prefix('"').delete_suffix('"')
    return clean if File.file?(clean)

    base = File.basename(clean)
    File.file?(base) ? base : nil
  end

  def self.parse_env_tags(line)
    clean_line = line.sub(/(?<!\\)%.*\z/, '')
    matches = []
    clean_line.scan(/\\(begin|end)\{([a-zA-Z0-9_\*@\-]+)\}|(\\\[|\\\])/) do |b_or_e, env, bracket|
      if bracket
        matches << [bracket == '\\[' ? 'begin' : 'end', '\\[ ... \\]']
      else
        matches << [b_or_e, env]
      end
    end
    matches
  end

  def self.process_env_tag(env_stack, type, name)
    if type == 'end'
      env_stack << name
      nil
    elsif env_stack.include?(name)
      env_stack.slice!(env_stack.rindex(name)..-1)
      nil
    else
      name
    end
  end

  def self.detect_enclosing_environment(file_path, error_line)
    source_file = find_source_file(file_path)
    return nil unless source_file && error_line && error_line.to_i > 0

    lines = File.readlines(source_file)
    idx = [error_line.to_i - 1, lines.size - 1].min
    return nil if idx < 0

    env_stack = []
    idx.downto(0) do |i|
      raw_line = lines[i]
      raw_line = raw_line.split(/(?<!\\)&/, 2).first if i == idx && raw_line =~ /(?<!\\)&/
      tags = parse_env_tags(raw_line)
      tags.reverse_each do |type, name|
        found = process_env_tag(env_stack, type, name)
        return found if found
      end
    end
    nil
  rescue StandardError
    nil
  end

  def self.resolve_file_and_line(err_block, file, line)
    target_file = file
    target_line = line
    block_text = err_block.join("\n")

    if (target_file.nil? || target_file.empty?) && block_text =~ /(?:\A|\n)(\S+?):(\d+):/
      target_file = Regexp.last_match(1)
      target_line ||= Regexp.last_match(2).to_i
    end

    if (target_line.nil? || target_line.to_i <= 0) && block_text =~ /(?:\A|\n).*?:(\d+):|l\.(\d+)/
      target_line = (Regexp.last_match(1) || Regexp.last_match(2)).to_i
    end

    [target_file, target_line]
  end

  def self.extract_misplaced_tab_env(err_block, file, line)
    resolved_file, resolved_line = resolve_file_and_line(err_block, file, line)
    detect_enclosing_environment(resolved_file, resolved_line)
  end

  def self.find_paragraph_bounds(lines, err_idx)
    idx = [err_idx, lines.size - 1].min
    idx -= 1 while idx > 0 && (lines[idx].strip.empty? || lines[idx].strip =~ /\A(?:\\par|\s*\\end\{)/)

    start_idx = idx
    while start_idx > 0 && (idx - start_idx) < 25
      prev = lines[start_idx - 1].strip
      break if prev.empty? || prev =~ /\A\\par\b/ || prev =~ /\A\\(?:section|chapter|subsection|subsubsection)\b/
      break if prev =~ /\A\\(?:begin|end)\{/

      start_idx -= 1
    end

    [start_idx, idx]
  end

  def self.extract_dollars_in_range(lines, start_idx, end_idx)
    dollars = []
    (start_idx..end_idx).each do |l_idx|
      line = lines[l_idx].sub(/(?<!\\)%.*\z/, '').gsub(/\$\$/, '  ')
      line.enum_for(:scan, /(?<!\\)\$/).each do
        col = Regexp.last_match.begin(0) + 1
        rest = line[col..] || ''
        curr = rest.match(/\A(\d+(?:[.,]\d+)?)/)
        dollars << { line_idx: l_idx, file_line: l_idx + 1, col: col, currency: curr ? curr[1] : nil }
      end
    end
    dollars
  end

  def self.score_math_chunk(chunk, spans_lines)
    clean = chunk.gsub(/\\text\{[^}]*\}/, '')
    penalty = 0
    penalty += 100 if clean =~ /\.\s+[A-Z]/
    words = clean.split(/\s+/)
    penalty += (words.size * 5) if words.size > 3
    penalty += 15 if spans_lines
    penalty
  end

  def self.calculate_pairing_penalty(lines, remaining)
    total = 0
    (0...remaining.size).step(2) do |p_idx|
      d_open = remaining[p_idx]
      d_close = remaining[p_idx + 1]
      spans = d_open[:line_idx] != d_close[:line_idx]

      chunk = if !spans
        lines[d_open[:line_idx]][d_open[:col]...(d_close[:col] - 1)] || ''
      else
        lines[d_open[:line_idx]..d_close[:line_idx]].join(' ')
      end
      total += score_math_chunk(chunk, spans)
    end
    total
  end

  def self.find_best_unclosed_dollar(lines, dollars)
    return dollars.first if dollars.size == 1

    best_cand = nil
    best_score = Float::INFINITY

    dollars.each_with_index do |cand, c_idx|
      remaining = dollars.dup
      remaining.delete_at(c_idx)
      penalty = calculate_pairing_penalty(lines, remaining)
      penalty -= 20 if cand[:currency]

      if penalty < best_score
        best_score = penalty
        best_cand = cand
      end
    end

    best_cand
  end

  def self.diagnose_text_math_token(line)
    clean = line.to_s.sub(/(?<!\\)%.*\z/, '')
    if clean =~ /(?<!\\)_/
      "Subscript '_' outside math mode; wrap in $...$ or escape as '\\_'"
    elsif clean =~ /(?<!\\)\^/
      "Superscript '^' outside math mode; wrap in $...$ or escape as '\\^'"
    else
      match = clean.match(/\\([a-zA-Z]+)/)
      if match && COMMON_COMMANDS.include?(match[1])
        "Math command '\\#{match[1]}' outside math mode; wrap in $...$"
      else
        "Math symbol (like _ or ^) outside math mode; wrap in $...$"
      end
    end
  end

  def self.detect_missing_dollar(file_path, error_line)
    source_file = find_source_file(file_path)
    return nil unless source_file && error_line && error_line.to_i > 0

    lines = File.readlines(source_file)
    err_idx = [error_line.to_i - 1, lines.size - 1].min
    return nil if err_idx < 0

    start_idx, end_idx = find_paragraph_bounds(lines, err_idx)
    dollars = extract_dollars_in_range(lines, start_idx, end_idx)

    if dollars.size.odd?
      cand = find_best_unclosed_dollar(lines, dollars)
      if cand[:currency]
        "Literal '$' in '$#{cand[:currency]}'; escape as '\\$' for currency"
      else
        "Unclosed '$' opened on line #{cand[:file_line]} (col #{cand[:col]}); insert closing '$'"
      end
    else
      candidate_line = (lines[end_idx] || lines[err_idx]).to_s
      diagnose_text_math_token(candidate_line)
    end
  rescue StandardError
    nil
  end

  def self.suggest_missing_dollar(tok)
    tok || "Math symbol (like _ or ^) outside math mode; wrap in $...$"
  end

  def self.extract_missing_dollar_info(err_block, file, line)
    resolved_file, resolved_line = resolve_file_and_line(err_block, file, line)
    detect_missing_dollar(resolved_file, resolved_line)
  end

  CATALOG = [
    {
      id: :misplaced_alignment_tab,
      pattern: /Misplaced alignment tab character &/i,
      title: 'Misplaced Alignment Tab Character (&)',
      token_extractor: lambda do |_match, err_block, file = nil, line = nil|
        extract_misplaced_tab_env(err_block, file, line)
      end,
      hint: ->(tok) { suggest_alignment_tab(tok) },
      why: "An alignment tab '&' was encountered outside a table or align environment.",
      fix: "Use an environment that supports '&' (e.g., align*, tabular) or write '\\&'.",
      doc_slug: '01_misplaced_alignment_tab'
    },
    {
      id: :undefined_control_sequence,
      pattern: /Undefined control sequence/i,
      title: 'Undefined Control Sequence',
      token_extractor: UNDEFINED_CS_EXTRACTOR,
      hint: lambda do |tok, file = nil, macro = nil, junk_dir = nil|
        suggest_command(tok, file: file, macro: macro, junk_dir: junk_dir)
      end,
      why: 'LaTeX does not recognize this macro or command name.',
      fix: 'Check for typos or include the package defining this macro in preamble.',
      doc_slug: '02_undefined_control_sequence'
    },
    {
      id: :missing_item,
      pattern: /perhaps a missing \\item/i,
      title: "Something's wrong--perhaps a missing \\item",
      hint: 'Text inside list without \\item; add \\item before list entries',
      why: 'Text was typed directly inside an itemize, enumerate, or description environment before any \\item.',
      fix: 'Add \\item before the text or check if \\begin{itemize} is misplaced.',
      doc_slug: '03_missing_item'
    },
    {
      id: :missing_dollar,
      pattern: /Missing \$ inserted/i,
      title: 'Missing $ inserted',
      token_extractor: lambda do |_match, err_block, file = nil, line = nil|
        extract_missing_dollar_info(err_block, file, line)
      end,
      hint: ->(tok) { suggest_missing_dollar(tok) },
      why: "A math-mode token was used in text mode or an unclosed '$' crossed a paragraph break.",
      fix: "Close the open '$' delimiter, enclose math in $...$, or escape literal characters (e.g., '\\_').",
      doc_slug: '04_missing_dollar'
    },
    {
      id: :extra_closing_brace,
      pattern: /(?:Too many }'s|Extra }, or forgotten \$)/i,
      title: "Too many }'s / Extra closing brace",
      hint: "Unmatched closing brace '}'; remove extra '}' or check balance",
      why: "A closing brace '}' was encountered without a matching opening brace '{'.",
      fix: "Remove the stray '}' or check brace nesting with 'leeni --check-braces'.",
      doc_slug: '05_extra_closing_brace'
    },
    {
      id: :paragraph_ended_before_complete,
      pattern: /(?:Paragraph ended before \S+ was complete|Runaway argument\?)/i,
      title: 'Paragraph ended before macro was complete / Runaway argument',
      hint: 'Unclosed brace across paragraph or blank line inside short macro argument',
      why: 'A macro argument containing an unclosed brace encountered a blank line / paragraph break.',
      fix: "Close the unclosed brace '{' or ensure no blank lines are inside macro arguments.",
      doc_slug: '06_paragraph_ended_before_complete'
    },
    {
      id: :environment_undefined,
      pattern: /Environment (\S+) undefined/i,
      title: 'Environment undefined',
      hint: ->(tok) { tok ? "Undefined environment '#{tok}'; check spelling or \\usepackage" : 'Undefined environment; check spelling or \\usepackage' },
      why: 'The environment named in \\begin{...} is not defined by any loaded package.',
      fix: 'Check environment name spelling or load the package that provides it.',
      doc_slug: '07_environment_undefined'
    },
    {
      id: :no_line_here_to_end,
      pattern: /There's no line here to end/i,
      title: "There's no line here to end",
      hint: "Line break '\\\\' at start of paragraph or after section/math",
      why: "A line break '\\\\' or '\\newline' was issued when LaTeX was not in horizontal text mode.",
      fix: "Remove '\\\\' and use a blank line for paragraph separation, or \\vspace for vertical space.",
      doc_slug: '08_no_line_here_to_end'
    },
    {
      id: :file_not_found,
      pattern: /File `?([^']+)'? not found/i,
      title: 'File not found',
      hint: ->(tok) { tok ? "File '#{tok}' not found; check file path or spelling" : 'File not found; check file path or spelling' },
      why: 'An \\input{...}, \\include{...}, or \\usepackage{...} targeted a file that does not exist in TeX search path.',
      fix: 'Verify that the file exists and that the relative path is correct.',
      doc_slug: '09_file_not_found'
    },
    {
      id: :command_already_defined,
      pattern: /Command (\S+) already defined/i,
      title: 'Command already defined',
      hint: ->(tok) { tok ? "Command '#{tok}' already defined; use \\renewcommand or rename" : 'Command already defined; use \\renewcommand or rename' },
      why: '\\newcommand tried to define a macro that already exists in LaTeX or a loaded package.',
      fix: 'Use \\renewcommand instead of \\newcommand, or choose a different macro name.',
      doc_slug: '10_command_already_defined'
    },
    {
      id: :extra_alignment_tab,
      pattern: /Extra alignment tab has been changed to \\cr/i,
      title: 'Extra alignment tab has been changed to \\cr',
      hint: "Too many '&' columns in table row; check column specifier",
      why: "A table or matrix row contains more '&' separators than defined in the column specification.",
      fix: 'Add another column to the environment preamble (e.g., {c|c|c}) or remove the extra ampersand.',
      doc_slug: '11_extra_alignment_tab'
    },
    {
      id: :missing_number_treated_as_zero,
      pattern: /Missing number, treated as zero/i,
      title: 'Missing number, treated as zero',
      hint: 'Missing numeric value; provide a number before dimension unit',
      why: 'TeX expected a numeric constant or dimension value but found text or a unit without a leading number.',
      fix: 'Provide a numeric value before the unit (e.g. \\hspace{10pt} instead of \\hspace{pt}).',
      doc_slug: '12_missing_number_treated_as_zero'
    },
    {
      id: :illegal_unit_of_measure,
      pattern: /Illegal unit of measure \(pt inserted\)/i,
      title: 'Illegal unit of measure (pt inserted)',
      hint: 'Missing length unit; append pt, cm, mm, in, or em',
      why: 'A dimension had a numeric value but omitted the measurement unit.',
      fix: 'Specify a valid TeX unit after the number (e.g. \\vspace{10pt} or \\setlength{\\parindent}{1cm}).',
      doc_slug: '13_illegal_unit_of_measure'
    },
    {
      id: :double_subscript,
      pattern: /Double subscript/i,
      title: 'Double subscript',
      hint: "Consecutive '_' subscripts; wrap in braces like 'x_{a_b}'",
      why: "Multiple subscript operators '_' were applied directly to the same base.",
      fix: 'Group the subscripts with curly braces: $x_{a_b}$ or $x_{a,b}$.',
      doc_slug: '14_double_subscript'
    },
    {
      id: :double_superscript,
      pattern: /Double superscript/i,
      title: 'Double superscript',
      hint: "Consecutive '^' superscripts; wrap in braces like 'x^{a^b}'",
      why: "Multiple superscript operators '^' were applied directly to the same base.",
      fix: 'Group the superscripts with curly braces: $x^{a^b}$ or $x^{a,b}$.',
      doc_slug: '15_double_superscript'
    },
    {
      id: :option_clash_for_package,
      pattern: /Option clash for package ([a-zA-Z0-9_\-]+)/i,
      title: 'Option clash for package',
      hint: ->(tok) { tok ? "Conflicting options for package '#{tok}'; pass all options in first \\usepackage" : 'Conflicting package options; unify options in first \\usepackage' },
      why: 'A package was loaded multiple times with mutually conflicting options.',
      fix: 'Move all required package options to the first \\usepackage call or use \\PassOptionsToPackage.',
      doc_slug: '16_option_clash_for_package'
    },
    {
      id: :lonely_item,
      pattern: /Lonely \\item--perhaps a missing list environment/i,
      title: 'Lonely \\item--perhaps a missing list environment',
      hint: '\\item used outside list; wrap in \\begin{itemize} or \\begin{enumerate}',
      why: 'An \\item command was used outside any list environment.',
      fix: 'Enclose items within \\begin{itemize}...\\end{itemize} or \\begin{enumerate}...\\end{enumerate}.',
      doc_slug: '17_lonely_item'
    },
    {
      id: :cannot_determine_size_of_graphic,
      pattern: /Cannot determine size of graphic in (\S+)/i,
      title: 'Cannot determine size of graphic',
      hint: ->(tok) { tok ? "Invalid image format or missing BoundingBox for '#{tok}'" : 'Invalid image format or missing BoundingBox' },
      why: 'The graphics driver cannot read the image file format or find its bounding box dimensions.',
      fix: 'Ensure the file is a valid PDF, PNG, or JPG, or convert it to a supported format.',
      doc_slug: '18_cannot_determine_size_of_graphic'
    },
    {
      id: :not_in_outer_par_mode,
      pattern: /Not in outer par mode/i,
      title: 'Not in outer par mode',
      hint: 'Float (figure/table) inside a box or minipage; move float outside or use minipage',
      why: 'A floating environment (figure or table) was placed inside a box (\\mbox, \\fbox) or inside another float.',
      fix: 'Move the figure/table outside the box, or use a non-floating minipage with \\captionof.',
      doc_slug: '19_not_in_outer_par_mode'
    },
    {
      id: :missing_delimiter,
      pattern: /Missing delimiter \(\. inserted\)/i,
      title: 'Missing delimiter (. inserted)',
      hint: "\\left or \\right without delimiter; use '.' for empty delimiter (e.g. '\\right.')",
      why: 'A \\left or \\right command was not followed by a valid delimiter character.',
      fix: "Specify a delimiter after \\left or \\right. Use a period '.' if no visible delimiter is desired.",
      doc_slug: '20_missing_delimiter'
    },
    {
      id: :only_in_preamble,
      pattern: /Can be used only in preamble/i,
      title: 'Can be used only in preamble',
      hint: 'Preamble command (like \\usepackage) used after \\begin{document}; move before \\begin{document}',
      why: 'A configuration command that can only run in the document preamble was executed in the document body.',
      fix: 'Move \\usepackage and configuration declarations before \\begin{document}.',
      doc_slug: '21_only_in_preamble'
    },
    {
      id: :extra_right,
      pattern: /Extra \\right\b/i,
      title: 'Extra \\right',
      hint: '\\right without matching \\left; check delimiter balance',
      why: 'A \\right delimiter was closed without a corresponding \\left delimiter earlier in the formula.',
      fix: "Ensure every \\right has a corresponding \\left, or use '\\left.' for an invisible opening delimiter.",
      doc_slug: '22_extra_right'
    },
    {
      id: :missing_begin_document,
      pattern: /Missing \\begin\{document\}/i,
      title: 'Missing \\begin{document}',
      hint: 'Printable text in preamble; move text after \\begin{document}',
      why: 'Text, characters, or typesetting commands appeared in the preamble before \\begin{document}.',
      fix: 'Move body text after \\begin{document} or remove stray characters from preamble.',
      doc_slug: '23_missing_begin_document'
    },
    {
      id: :dimension_too_large,
      pattern: /Dimension too large/i,
      title: 'Dimension too large',
      hint: 'Coordinate or dimension exceeds TeX maximum (~5.75m / 16383pt); check scaling',
      why: "A length, coordinate, or calculation exceeded TeX's arithmetic limit (16383.99999pt).",
      fix: 'Scale down coordinates, font size, or TikZ graph dimensions.',
      doc_slug: '24_dimension_too_large'
    },
    {
      id: :misplaced_noalign,
      pattern: /(?:Misplaced \\noalign|Misplaced \\omit)/i,
      title: 'Misplaced \\noalign / \\omit',
      hint: "\\hline or \\cline placed after content; must follow '\\\\' immediately",
      why: "\\hline or \\cline was placed in a table row after table cells rather than immediately after a newline '\\\\'.",
      fix: "Place \\hline or \\cline directly after '\\\\' with no intervening text.",
      doc_slug: '25_misplaced_noalign'
    },
    {
      id: :bad_math_environment_delimiter,
      pattern: /Bad math environment delimiter/i,
      title: 'Bad math environment delimiter',
      hint: "Mismatched inline/display math delimiters; match '\\(' with '\\)' or '\\[ ' with '\\]'",
      why: 'A LaTeX math delimiter was closed with a mismatched counterpart (e.g. \\( ... \\]).',
      fix: 'Match opening and closing delimiters: \\( ... \\) or \\[ ... \\].',
      doc_slug: '26_bad_math_environment_delimiter'
    },
    {
      id: :counter_too_large,
      pattern: /Counter(?: (\S+))? too large/i,
      title: 'Counter too large',
      hint: ->(tok) { tok ? "Counter '#{tok}' exceeded limit (e.g. fnsymbol pool); reset or switch to numeric" : 'Counter exceeded limit (e.g. fnsymbol pool); reset or switch to numeric' },
      why: 'A counter representation (such as \\fnsymbol for footnotes) exceeded its fixed symbol pool.',
      fix: 'Reset the counter per page or switch to arabic numerals.',
      doc_slug: '27_counter_too_large'
    },
    {
      id: :amsmath_multiple_tag,
      pattern: /Multiple \\tag/i,
      title: 'Package amsmath: Multiple \\tag',
      hint: 'Multiple \\tag commands on same equation line; keep only one \\tag',
      why: 'More than one \\tag{...} was specified for a single equation.',
      fix: 'Remove the duplicate \\tag or use \\split / \\align for multi-line formulas.',
      doc_slug: '28_amsmath_multiple_tag'
    },
    {
      id: :undefined_color,
      pattern: /Undefined color `?([^']+)'?/i,
      title: 'Package xcolor: Undefined color',
      hint: ->(tok) { tok ? "Undefined color '#{tok}'; define with \\definecolor or load colornames" : 'Undefined color; define with \\definecolor or load colornames' },
      why: 'A color name was passed to \\textcolor or \\colorbox that has not been defined.',
      fix: 'Define the color using \\definecolor or load \\usepackage[dvipsnames]{xcolor}.',
      doc_slug: '29_undefined_color'
    },
    {
      id: :mismatched_environment,
      pattern: /\\begin\{([^\}]+)\} (?:on input line \d+ )?ended by \\end\{([^\}]+)\}/i,
      title: 'Mismatched \\begin and \\end environments',
      token_extractor: ->(match, _block) { "#{match[1]} vs #{match[2]}" },
      hint: ->(tok) { tok ? "Environment mismatch ('#{tok}'); ensure \\begin{foo} matches \\end{foo}" : 'Environment mismatch; ensure \\begin matches \\end' },
      why: 'An environment was opened with \\begin{foo} but closed with \\end{bar}.',
      fix: 'Ensure the environment name in \\end matches the opening \\begin.',
      doc_slug: '30_mismatched_environment'
    },
    {
      id: :missing_closing_brace,
      pattern: /Missing \} inserted/i,
      title: 'Missing } inserted',
      hint: "Unclosed math group or argument; insert matching '}'",
      why: 'A group or macro argument was opened with { but never closed before math mode or the line ended.',
      fix: 'Add the missing closing brace } before ending math or group.',
      doc_slug: '31_missing_closing_brace'
    },
    {
      id: :missing_endcsname,
      pattern: /Missing \\endcsname inserted/i,
      title: 'Missing \\endcsname inserted',
      hint: "Unclosed \\csname; terminate macro name with '\\endcsname'",
      why: 'A \\csname command was evaluated without finding a matching \\endcsname.',
      fix: 'Add \\endcsname to close the dynamic macro name.',
      doc_slug: '32_missing_endcsname'
    },
    {
      id: :cant_use_hrule_here,
      pattern: /You can't use `?\\hrule'? here/i,
      title: "You can't use \\hrule here except with leaders",
      hint: "\\hrule inside \\hbox; use '\\vrule' in horizontal boxes or move \\hrule outside",
      why: 'A horizontal rule \\hrule was placed inside a horizontal box (\\hbox).',
      fix: 'Use \\vrule for vertical rules in \\hbox, or place \\hrule in vertical mode.',
      doc_slug: '33_cant_use_hrule_here'
    },
    {
      id: :cant_use_spacefactor,
      pattern: /You can't use `?\\spacefactor'? in vertical mode/i,
      title: "You can't use \\spacefactor in vertical mode",
      hint: '\\spacefactor in vertical mode; set within paragraph or text mode',
      why: '\\spacefactor controls spacing between words and is only meaningful in horizontal mode.',
      fix: 'Ensure \\spacefactor is used within a paragraph.',
      doc_slug: '34_cant_use_spacefactor'
    },
    {
      id: :illegal_parameter_number,
      pattern: /Illegal parameter number in definition of (\S+)/i,
      title: 'Illegal parameter number in definition',
      hint: ->(tok) { tok ? "Macro '#{tok}' uses parameters (#1) without declaring argument count [n]" : 'Macro uses parameters without declaring argument count' },
      why: 'A macro definition referenced #1 or #2 but omitted the parameter count declaration.',
      fix: 'Declare the number of arguments: \\newcommand{\\cmd}[1]{...}.',
      doc_slug: '35_illegal_parameter_number'
    },
    {
      id: :two_documentclass_commands,
      pattern: /Two \\documentclass(?: or \\documentstyle)? commands/i,
      title: 'LaTeX Error: Two \\documentclass commands',
      hint: 'Multiple \\documentclass declarations; keep only one in preamble',
      why: 'A LaTeX document can only have exactly one \\documentclass command.',
      fix: 'Remove the redundant \\documentclass declaration.',
      doc_slug: '36_two_documentclass_commands'
    },
    {
      id: :verb_illegal_in_argument,
      pattern: /\\verb illegal in argument/i,
      title: 'LaTeX Error: \\verb illegal in argument',
      hint: "\\verb inside command argument; use '\\texttt' or 'cprotect' package",
      why: '\\verb changes character category codes and cannot be passed inside command arguments.',
      fix: 'Use \\texttt{...} instead of \\verb, or load the cprotect package.',
      doc_slug: '37_verb_illegal_in_argument'
    },
    {
      id: :caption_outside_float,
      pattern: /\\caption outside float/i,
      title: 'LaTeX Error: \\caption outside float',
      hint: "\\caption outside figure/table; place in float or use '\\captionof' from 'caption' package",
      why: '\\caption was placed in standard text outside a figure or table environment.',
      fix: 'Move inside \\begin{figure} / \\begin{table}, or use \\captionof{figure}{...}.',
      doc_slug: '38_caption_outside_float'
    },
    {
      id: :use_of_doesnt_match_definition,
      pattern: /Use of (\S+) doesn't match its definition/i,
      title: "Use of command doesn't match its definition",
      hint: ->(tok) { tok ? "Argument mismatch for delimited macro '#{tok}'; check delimiter syntax" : "Argument mismatch for delimited macro; check delimiter syntax" },
      why: 'A delimited macro was defined with custom argument syntax but invoked with different delimiters.',
      fix: 'Match the macro delimiter structure (e.g. \\cmd(arg) instead of \\cmd{arg}).',
      doc_slug: '39_use_of_doesnt_match_definition'
    },
    {
      id: :ambiguous_math_fractions,
      pattern: /Ambiguous; you need another \{ and \}/i,
      title: 'Ambiguous; you need another { and }',
      hint: "Multiple '\\over' in same group; add braces or use '\\frac{a}{b}'",
      why: 'Multiple \\over commands in the same math subformula created ambiguity.',
      fix: 'Enclose each fraction in braces: ${{a \\over b} \\over c}$ or use \\frac.',
      doc_slug: '40_ambiguous_math_fractions'
    },
    {
      id: :cant_use_eqno_in_math,
      pattern: /You can't use `?\\eqno'? in math mode/i,
      title: "You can't use \\eqno in math mode",
      hint: "\\eqno used in inline math; use display math '\\[ ... \\]' or '\\tag'",
      why: '\\eqno attaches an equation number and is only valid in display math ($$).',
      fix: 'Switch from inline math ($...$) to display math (\\[ ... \\] or equation).',
      doc_slug: '41_cant_use_eqno_in_math'
    },
    {
      id: :package_babel_unknown_language,
      pattern: /Package babel Error: Unknown (?:language|option) [`']([^`'.]+)['`]/i,
      title: 'Package babel Error: Unknown language',
      hint: ->(tok) { tok ? "Unknown babel language '#{tok}'; check spelling or texlive-lang" : 'Unknown babel language; check spelling or texlive-lang' },
      why: 'The language option passed to babel is not defined or installed.',
      fix: 'Verify language spelling (e.g. english, french, german) and install language packs.',
      doc_slug: '42_package_babel_unknown_language'
    },
    {
      id: :bad_register_code,
      pattern: /Bad register code/i,
      title: 'Bad register code',
      hint: 'Register number out of bounds; must be non-negative (use \\newcount)',
      why: 'A TeX register number was negative or exceeded the maximum register index.',
      fix: 'Use non-negative register numbers or allocate with \\newcount / \\newdimen.',
      doc_slug: '43_bad_register_code'
    },
    {
      id: :nested_include,
      pattern: /\\include cannot be nested/i,
      title: 'LaTeX Error: \\include cannot be nested',
      hint: "\\include called inside included file; replace secondary with '\\input'",
      why: '\\include manages page clears and aux files and cannot be called recursively.',
      fix: 'Use \\input{...} instead of \\include{...} inside secondary files.',
      doc_slug: '44_nested_include'
    },
    {
      id: :no_counter_defined,
      pattern: /No counter [`']([^`']+)['`] defined/i,
      title: 'LaTeX Error: No counter defined',
      hint: ->(tok) { tok ? "Counter '#{tok}' does not exist; declare with \\newcounter{#{tok}}" : 'Counter does not exist; declare with \\newcounter' },
      why: 'A counter operation was performed on an undeclared counter name.',
      fix: 'Declare the counter with \\newcounter{...} or check spelling.',
      doc_slug: '45_no_counter_defined'
    },
    {
      id: :command_undefined,
      pattern: /Command `?(\\?\S+?)'? undefined/i,
      title: 'LaTeX Error: Command undefined',
      hint: ->(tok) { tok ? "Command '#{tok}' is not defined; use \\newcommand instead of \\renewcommand" : 'Command is not defined; use \\newcommand instead of \\renewcommand' },
      why: '\\renewcommand was used on a macro that has not yet been declared.',
      fix: 'Use \\newcommand to define the command or check for typos in the name.',
      doc_slug: '46_command_undefined'
    },
    {
      id: :file_ended_while_scanning,
      pattern: /File ended while scanning (?:use|text) of (\\\S+?|\S+?)\.?$/i,
      title: 'File ended while scanning macro',
      hint: ->(tok) { tok ? "Unclosed brace in argument of '#{tok}'; add missing '}' before EOF" : "Unclosed brace before end of file; add missing '}'" },
      why: 'End of file was reached while TeX was still looking for a closing brace.',
      fix: 'Add the missing closing curly brace } to terminate the macro argument.',
      doc_slug: '47_file_ended_while_scanning'
    },
    {
      id: :package_amsmath_split_wont_work,
      pattern: /\\begin\{split\} won't work here/i,
      title: "Package amsmath Error: \\begin{split} won't work here",
      hint: "\\begin{split} outside display math; wrap inside '\\begin{equation}'",
      why: 'split environment is only allowed inside an existing math display (equation, gather).',
      fix: 'Wrap \\begin{split} ... \\end{split} inside \\begin{equation} ... \\end{equation}.',
      doc_slug: '48_package_amsmath_split_wont_work'
    },
    {
      id: :package_amsmath_invalid_intertext,
      pattern: /Invalid use of \\intertext/i,
      title: 'Package amsmath Error: Invalid use of \\intertext',
      hint: "\\intertext inside 'equation'; switch to '\\begin{align}' or move outside",
      why: '\\intertext can only be used inside multi-line alignment environments like align.',
      fix: 'Use align instead of equation, or place text outside the math environment.',
      doc_slug: '49_package_amsmath_invalid_intertext'
    },
    {
      id: :unknown_float_option,
      pattern: /Unknown float option [`']([^`']+)['`]/i,
      title: 'LaTeX Error: Unknown float option',
      hint: ->(tok) { tok == 'H' ? "Float option '[H]' requires '\\usepackage{float}'" : "Invalid float option '#{tok}'; use [!htbp]" },
      why: 'An unrecognized float placement specifier was provided.',
      fix: 'Load \\usepackage{float} for [H] placement, or use standard specifiers [!htbp].',
      doc_slug: '50_unknown_float_option'
    },
    {
      id: :package_tikz_missing_semicolon,
      pattern: /Giving up on this path\. Did you forget a semicolon\?/i,
      title: 'Package tikz Error: Missing semicolon',
      hint: "Missing semicolon ';' at end of TikZ path command; append ';'",
      why: 'A TikZ \\draw, \\node, or \\path command was not terminated with a semicolon.',
      fix: 'Append a semicolon ; to the end of the path statement.',
      doc_slug: '51_package_tikz_missing_semicolon'
    },
    {
      id: :package_pgfkeys_unknown_key,
      pattern: /Package pgfkeys Error: I do not know the key [`']([^`']+)['`]/i,
      title: 'Package pgfkeys Error: Unknown key',
      hint: ->(tok) { tok ? "Unknown pgfkeys option '#{tok}'; check spelling or load library" : 'Unknown pgfkeys option; check spelling or load library' },
      why: 'A key passed to a TikZ/PGF command is not recognized.',
      fix: 'Check the key spelling or load the required library (\\usetikzlibrary{...}).',
      doc_slug: '52_package_pgfkeys_unknown_key'
    },
    {
      id: :not_allowed_in_lr_mode,
      pattern: /Not allowed in LR mode/i,
      title: 'LaTeX Error: Not allowed in LR mode',
      hint: 'Block environment in LR mode; provide required arguments (e.g. \\begin{thebibliography}{99})',
      why: 'A paragraph-level or list environment was invoked inside horizontal LR mode.',
      fix: 'Check for missing mandatory arguments to environments or move outside LR box.',
      doc_slug: '53_not_allowed_in_lr_mode'
    },
    {
      id: :package_enumitem_key_undefined,
      pattern: /Package enumitem Error: (\S+) undefined/i,
      title: 'Package enumitem Error: Key undefined',
      hint: ->(tok) { tok ? "Undefined enumitem key '#{tok}'; check documentation (e.g. label, leftmargin)" : 'Undefined enumitem key; check documentation' },
      why: 'An invalid option key was passed to an enumitem list environment.',
      fix: 'Use valid enumitem options like label, leftmargin, itemsep, or topsep.',
      doc_slug: '54_package_enumitem_key_undefined'
    },
    {
      id: :package_kvsetkeys_undefined_key,
      pattern: /Package kvsetkeys Error: Undefined key `?([^']+)'?/i,
      title: 'Package kvsetkeys Error: Undefined key',
      hint: ->(tok) { tok ? "Undefined setup key '#{tok}'; check macro setup options" : 'Undefined setup key; check macro setup options' },
      why: 'An unknown key was passed to a package setup command (e.g. \\hypersetup).',
      fix: 'Verify option name spelling in the setup declaration.',
      doc_slug: '55_package_kvsetkeys_undefined_key'
    }
  ].freeze

  def self.classify(err_text, err_block = [], file: nil, line: nil, junk_dir: nil)
    text = err_text.to_s
    CATALOG.each do |entry|
      match = entry[:pattern].match(text)
      next unless match

      token = extract_token(entry, match, err_block, file: file, line: line)
      _cs, macro = (entry[:id] == :undefined_control_sequence) ? extract_undefined_cs_info(err_block) : [token, nil]
      hint = resolve_hint(entry[:hint], token, file: file, macro: macro, junk_dir: junk_dir)
      root_line, root_col = extract_root_location(entry, token, hint, file, line, err_block: err_block)

      why = if entry[:id] == :undefined_control_sequence && macro
              "LaTeX does not recognize '#{token}' (encountered while expanding '#{macro}')."
            else
              entry[:why]
            end
      fix = if entry[:id] == :undefined_control_sequence && macro
              "Check definition of '#{macro}' or define '#{token}' in preamble."
            else
              entry[:fix]
            end

      return {
        id: entry[:id],
        title: entry[:title],
        token: token,
        hint: hint,
        root_line: root_line,
        root_col: root_col,
        why: why,
        fix: fix,
        doc_slug: entry[:doc_slug]
      }
    end
    nil
  end

  def self.extract_root_location(entry, token, hint, file, line, err_block: [])
    if hint =~ /opened on line (\d+)(?:\s*\(col\s*(\d+)\))?/i
      return [Regexp.last_match(1).to_i, Regexp.last_match(2) ? Regexp.last_match(2).to_i : nil]
    end

    if entry[:id] == :misplaced_alignment_tab
      col = extract_misplaced_tab_col(file, line)
      return [line, col] if col
    end

    if entry[:id] == :undefined_control_sequence && token
      col = extract_token_col(file, line, token)
      return [line, col] if col

      root_l, root_c = find_undefined_cs_source_location(file, line, token, err_block)
      return [root_l, root_c] if root_l
    end

    [line, nil]
  end

  def self.extract_misplaced_tab_col(file, line)
    source_file = find_source_file(file)
    return nil unless source_file && line && line.to_i > 0

    lines = File.readlines(source_file)
    idx = line.to_i - 1
    return nil if idx < 0 || idx >= lines.size

    pos = lines[idx].index(/(?<!\\)&/)
    pos ? pos + 1 : nil
  rescue StandardError
    nil
  end

  def self.extract_token_col(file, line, token)
    return nil unless token && !token.empty?

    source_file = find_source_file(file)
    return nil unless source_file && line && line.to_i > 0

    lines = File.readlines(source_file)
    idx = line.to_i - 1
    return nil if idx < 0 || idx >= lines.size

    pos = lines[idx].index(token)
    pos ? pos + 1 : nil
  rescue StandardError
    nil
  end

  def self.extract_token(entry, match, err_block, file: nil, line: nil)
    extractor = entry[:token_extractor]
    return nil unless extractor || (match && match.captures.any?)

    if extractor
      extractor.arity == 2 ? extractor.call(match, err_block) : extractor.call(match, err_block, file, line)
    else
      match.captures.first
    end
  end

  def self.resolve_hint(hint, token, file: nil, macro: nil, junk_dir: nil)
    return hint.to_s unless hint.respond_to?(:call)

    case hint.parameters.size
    when 1 then hint.call(token)
    when 2 then hint.call(token, file)
    when 3 then hint.call(token, file, macro)
    else hint.call(token, file, macro, junk_dir)
    end
  end

  WARNING_EXPLANATIONS = {
    multiply_defined_label: {
      title: 'Alert: Multiply-Defined Label',
      why: 'Two or more \\label{...} tags share the identical key; references will be ambiguous.',
      fix: 'Search your .tex sources for \\label{<key>} and rename or delete one.'
    },
    overfull_hbox_alert: {
      title: 'Alert: Severe Overfull \\hbox (≥24pt)',
      why: 'Content spills significantly (≥24pt / ~8.4mm) into the page margin.',
      fix_label: 'Might fix:',
      fix: 'Reword text, insert discretionary hyphens \\-, break equations, or resize figures.'
    },
    overfull_hbox_warning: {
      title: 'Warning: Overfull \\hbox',
      why: 'Line exceeds column width; TeX could not hyphenate within standard tolerances.',
      fix_label: 'Might fix:',
      fix: 'Reword sentence, insert \\-, or wrap code in \\sloppy / \\emergencystretch.'
    },
    overfull_hbox_whatever: {
      title: 'Whatever: Micro Overfull \\hbox (≤2.5pt)',
      why: 'Minor margin protrusion (≤2.5pt / ~0.88mm), often memoir TOC page numbers.',
      fix: 'Harmless typesetting quirk; safely ignored.'
    },
    underfull_hbox: {
      title: 'Note: Underfull \\hbox (Loose Line)',
      why: 'TeX stretched inter-word spacing excessively (badness 10000 = infinite stretch) because there were too few words to fill the line. Typically caused by a trailing \\\\ before an empty line or \\end{...}, double \\\\\\\\, using \\linebreak, or unhyphenated words in narrow columns.',
      fix_label: 'Might fix:',
      fix: 'Remove trailing \\\\ before blank lines or \\end{...}, avoid double \\\\\\\\ (use \\vspace or a blank line), replace \\linebreak with \\newline, or reword text.',
      doc_url: 'https://sarielhp.github.io/leeni/docs/guides/underfull_boxes/'
    },
    underfull_vbox: {
      title: 'Warning: Underfull \\vbox (Vertical Stretch)',
      why: 'TeX could not stretch vertical whitespace enough to fill the column or page height.',
      fix_label: 'Might fix:',
      fix: 'Add \\raggedbottom to preamble, adjust figure/table heights, or balance text across pages.',
      doc_url: 'https://sarielhp.github.io/leeni/docs/guides/underfull_boxes/'
    },
    underfull_box: {
      title: 'Warning: Underfull \\vbox or \\hbox',
      why: 'LaTeX could not stretch whitespace enough to fill the target dimension.',
      fix_label: 'Might fix:',
      fix: 'Add \\raggedbottom to preamble, adjust figure heights, or reword text.',
      doc_url: 'https://sarielhp.github.io/leeni/docs/guides/underfull_boxes/'
    },
    undefined_reference: {
      title: 'Warning: Undefined Reference',
      why: 'A \\ref{...} or \\pageref{...} references a label that does not exist in any .aux.',
      fix: 'Check spelling of the key, ensure target chapter is included, and recompile.'
    },
    undefined_citation: {
      title: 'Warning: Undefined Citation',
      why: 'A \\cite{...} key was not found in the bibliography database (.bib).',
      fix: 'Verify key spelling, check \\bibliography / \\addbibresource, and run BibTeX/Biber.'
    },
    hyperref_token: {
      title: 'Whatever: Hyperref PDF Bookmark Token Sanitization',
      why: 'Math or formatting in a heading was stripped for plain-text PDF bookmarks.',
      fix: 'Harmless. Use \\texorpdfstring{$math$}{text} in headings to clean cleanly.'
    },
    float_specifier: {
      title: 'Whatever: Float Specifier Auto-Adjusted',
      why: "'!h' (strictly here) violated page layout rules, so LaTeX added 't' (top of page).",
      fix: "Harmless. Use '[!htbp]' to give LaTeX standard placement flexibility."
    },
    font_shape: {
      title: 'Whatever: Font Shape Substitution',
      why: 'Requested font weight/style combination was unavailable; fallback substituted.',
      fix: 'Harmless fallback. Check font declarations if unexpected styling appears.'
    },
    summary_warning: {
      title: 'Whatever: Redundant Summary Notice',
      why: 'Document-level summary emitted at end of LaTeX run.',
      fix: 'Harmless recap; individual items are already reported above.'
    },
    etex_allocation: {
      title: 'Whatever: Extended Allocation In Use',
      why: 'Modern LaTeX formats already provide extended allocation; etex.sty code was skipped.',
      fix: 'Harmless notice on modern TeX engines; safely ignored.'
    },
    inverted_label: {
      title: 'Alert: Inverted \\label Before \\caption',
      why: '\\label{...} was placed before \\caption in a float. Cross-references (\\ref) will resolve to the Section number instead of the float number.',
      fix: 'Move \\label{...} after or inside \\caption{...}.'
    },
    unnumbered_label: {
      title: 'Alert: \\label Inside Unnumbered Math',
      why: '\\label was placed inside an unnumbered environment (e.g. equation* or align*). Cross-references will bind to the prior section or theorem.',
      fix: 'Remove \\label or switch to a numbered math environment (equation or align).'
    },
    type3_font: {
      title: 'Alert: Type 3 (Raster Bitmap) Font in PDF',
      why: 'PDF contains unscaled bitmapped fonts. IEEE, ACM, and arXiv submission portals will reject this document.',
      fix: 'Ensure scalable vector fonts are used (e.g. \\usepackage[T1]{fontenc} and \\usepackage{lmodern}), or replace bitmap EPS/figures.'
    }
  }.freeze

  def self.find_by_id(id)
    sym = id.to_sym
    CATALOG.find { |e| e[:id] == sym } || WARNING_EXPLANATIONS[sym]
  end
end
