# frozen_string_literal: true

# ==============================================================================
# lib/leeni/error_catalog.rb
#
# Declarative catalog of known LaTeX/TeX compilation errors, pattern matching,
# token extraction, and actionable remediation hints.
# ==============================================================================

require_relative 'utils'
require_relative 'macro_harvester'
require_relative 'key_suggester'

module LaTeXErrorCatalog
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
      requirement = sug_pkg ? " (requires \\usepackage{#{sug_pkg}})" : ''
      "Did you mean '\\#{suggestion}'?#{macro_ctx}#{requirement}"
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

    return true if best[:dist] >= 1.5 && runner_up[:dist] < best[:dist] + 0.5 && !(best[:is_proj].zero? && runner_up[:is_proj] == 1)

    false
  end

  def self.extract_undefined_cs_info(err_block)
    block_text = err_block.join("\n")
    return [Regexp.last_match(1), nil] if block_text =~ /<recently read>\s*(\\[a-zA-Z@]+|\\[^\s])/
    return [Regexp.last_match(1), nil] if block_text =~ /<to be read again>\s*(\\[a-zA-Z@]+|\\[^\s])/

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
    return [nil, nil] unless source_file && line&.to_i&.positive?

    lines = begin
      File.readlines(source_file)
    rescue StandardError
      nil
    end
    return [nil, nil] unless lines

    err_idx = line.to_i - 1
    return [nil, nil] if err_idx.negative? || err_idx >= lines.size

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
    clean_line = LaTeXUtils.strip_latex_comments(line)
    matches = []
    clean_line.scan(/\\(begin|end)\{([a-zA-Z0-9_*@-]+)\}|(\\\[|\\\])/) do |b_or_e, env, bracket|
      matches << if bracket
                   [bracket == '\\[' ? 'begin' : 'end', '\\[ ... \\]']
                 else
                   [b_or_e, env]
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
    return nil unless source_file && error_line&.to_i&.positive?

    lines = File.readlines(source_file)
    idx = [error_line.to_i - 1, lines.size - 1].min
    return nil if idx.negative?

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
    idx -= 1 while idx.positive? && (lines[idx].strip.empty? || lines[idx].strip =~ /\A(?:\\par|\s*\\end\{)/)

    start_idx = idx
    while start_idx.positive? && (idx - start_idx) < 25
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
      line = LaTeXUtils.strip_latex_comments(lines[l_idx]).gsub('$$', '  ')
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

      chunk = if spans
                lines[d_open[:line_idx]..d_close[:line_idx]].join(' ')
              else
                lines[d_open[:line_idx]][d_open[:col]...(d_close[:col] - 1)] || ''
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
    clean = LaTeXUtils.strip_latex_comments(line.to_s)
    if clean =~ /(?<!\\)_/
      "Subscript '_' outside math mode; wrap in $...$ or escape as '\\_'"
    elsif clean =~ /(?<!\\)\^/
      "Superscript '^' outside math mode; wrap in $...$ or escape as '\\^'"
    else
      match = clean.match(/\\([a-zA-Z]+)/)
      if match && COMMON_COMMANDS.include?(match[1])
        "Math command '\\#{match[1]}' outside math mode; wrap in $...$"
      else
        'Math symbol (like _ or ^) outside math mode; wrap in $...$'
      end
    end
  end

  def self.detect_missing_dollar(file_path, error_line)
    source_file = find_source_file(file_path)
    return nil unless source_file && error_line&.to_i&.positive?

    lines = File.readlines(source_file)
    err_idx = [error_line.to_i - 1, lines.size - 1].min
    return nil if err_idx.negative?

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
    tok || 'Math symbol (like _ or ^) outside math mode; wrap in $...$'
  end

  def self.extract_missing_dollar_info(err_block, file, line)
    resolved_file, resolved_line = resolve_file_and_line(err_block, file, line)
    detect_missing_dollar(resolved_file, resolved_line)
  end

  MATH_MODE_EQUIVALENTS = {
    '\\bfseries' => '\\mathbf', '\\itshape' => '\\mathit', '\\em' => '\\mathit', '\\slshape' => '\\mathit',
    '\\rmfamily' => '\\mathrm', '\\upshape' => '\\mathrm', '\\sffamily' => '\\mathsf', '\\ttfamily' => '\\mathtt',
    '\\normalfont' => '\\mathnormal'
  }.freeze
  SIZE_SWITCHES = %w[\\tiny \\scriptsize \\footnotesize \\small \\normalsize \\large \\Large \\LARGE \\huge \\Huge].freeze

  def self.math_mode_advice(command)
    if (equivalent = MATH_MODE_EQUIVALENTS[command])
      "use #{equivalent}{...}"
    elsif SIZE_SWITCHES.include?(command)
      "wrap the whole formula: {#{command} $...$}"
    else
      'use its \\math... equivalent or move it outside the formula'
    end
  end

  def self.math_mode_hint(command)
    subject = command ? "'#{command}' does not work in math" : 'Text font command does not work in math'
    "#{subject}; #{math_mode_advice(command)}"
  end

  def self.classify(err_text, err_block = [], file: nil, line: nil, junk_dir: nil)
    text = err_text.to_s
    CATALOG.each do |entry|
      match = entry[:pattern].match(text)
      next unless match

      token = extract_token(entry, match, err_block, file: file, line: line)
      _cs, macro = entry[:id] == :undefined_control_sequence ? extract_undefined_cs_info(err_block) : [token, nil]
      hint = resolve_hint(entry[:hint], token, file: file, macro: macro, junk_dir: junk_dir)
      root_line, root_col = extract_root_location(entry, token, hint, file, line, err_block: err_block)
      why, fix = explanation(entry, token, macro)

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

  # An undefined command met while expanding a macro is explained in terms of
  # that macro; every other entry keeps its catalogue text.
  def self.explanation(entry, token, macro)
    return [entry[:why], entry[:fix]] unless entry[:id] == :undefined_control_sequence && macro

    ["LaTeX does not recognize '#{token}' (encountered while expanding '#{macro}').",
     "Check definition of '#{macro}' or define '#{token}' in preamble."]
  end

  def self.extract_root_location(entry, token, hint, file, line, err_block: [])
    return [Regexp.last_match(1).to_i, Regexp.last_match(2)&.to_i] if hint =~ /opened on line (\d+)(?:\s*\(col\s*(\d+)\))?/i

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
    return nil unless source_file && line&.to_i&.positive?

    lines = File.readlines(source_file)
    idx = line.to_i - 1
    return nil if idx.negative? || idx >= lines.size

    pos = lines[idx].index(/(?<!\\)&/)
    pos ? pos + 1 : nil
  rescue StandardError
    nil
  end

  def self.extract_token_col(file, line, token)
    return nil unless token && !token.empty?

    source_file = find_source_file(file)
    return nil unless source_file && line&.to_i&.positive?

    lines = File.readlines(source_file)
    idx = line.to_i - 1
    return nil if idx.negative? || idx >= lines.size

    pos = lines[idx].index(token)
    pos ? pos + 1 : nil
  rescue StandardError
    nil
  end

  def self.extract_token(entry, match, err_block, file: nil, line: nil)
    extractor = entry[:token_extractor]
    return nil unless extractor || match&.captures&.any?

    if extractor
      extractor.arity == 2 ? extractor.call(match, err_block) : extractor.call(match, err_block, file, line)
    else
      match.captures.first
    end
  end

  # Names the project file a missing one was probably meant to be (the
  # diagnostics run in the document directory, where TeX resolves the name).
  def self.file_not_found_hint(tok)
    return 'File not found; check file path or spelling' unless tok

    found = LeeniKeySuggester.suggest_file(tok)
    return "File '#{tok}' not found; check file path or spelling" if found.empty?

    "Did you mean #{found.map { |path| "'#{path}'" }.join(' or ')}? File '#{tok}' not found"
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

  def self.find_by_id(id)
    sym = id.to_sym
    CATALOG.find { |e| e[:id] == sym } || WARNING_EXPLANATIONS[sym]
  end
end

require_relative 'error_catalog_data'
require_relative 'error_catalog_lookup'
