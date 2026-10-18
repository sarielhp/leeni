# frozen_string_literal: true

# ==============================================================================
# lib/leeni/box_context.rb
#
# Source-side context for overfull/underfull boxes: which environment holds the
# box, and, for multi-row displays, which row is probably the widest. TeX reports
# a display or alignment as "detected at line N" where N is the line of the
# closing \end{...} (or closing $$), so the environment is found by walking
# back from that line. Everything here is a heuristic hint, not a proof.
# ==============================================================================

require_relative 'error_catalog'

module LaTeXBoxContext
  MAX_SCAN_LINES = 400
  IGNORED_ENVS = %w[document].freeze
  SECTION_PATTERN = /\A\s*\\(?:chapter|section|subsection|subsubsection)\*?\s*(?:\[[^\]]*\])?\s*\{/
  THEOREM_ENVS = %w[
    theorem lemma defn definition proposition corollary claim conjecture remark
    observation example exercise problem fact property assumption question
  ].freeze
  HEAD_PRELUDE = /\A\s*(?:%.*|\\(?:index|label|thmlab|lemlab|deflab|exelab|clmlab|seclab|eqlab)\b.*)?\s*\z/
  MATH_ENV_PATTERN = /\\begin\{math\}(.*?)\\end\{math\}/m
  PAREN_MATH_PATTERN = /\\\((.*?)\\\)/m
  MIN_MATH_CHARS = 20
  ROW_TOKEN = /\\\\|\\begin\{[^}]*\}|\\end\{[^}]*\}|\\[{}]|[{}]|\\[A-Za-z@]+|\\.|[^\\{}]+/m

  # Splits the body of one environment into rows at top-level `\\`, ignoring
  # separators inside braces or nested environments (cases, array, substack...).
  class RowSplitter
    def initialize(env)
      @env = env
      @brace = 0
      @nested = 0
      @opened = false
      @rows = []
      @current = nil
    end

    def feed(raw_line, line_no)
      raw_line.sub(/(?<!\\)%.*$/, '').scan(ROW_TOKEN) { handle(Regexp.last_match(0), line_no) }
    end

    def rows
      flush
      @rows
    end

    private

    def handle(token, line_no)
      case token
      when '\\\\' then top_level? ? flush : add(token, line_no)
      when '{' then open_brace(token, line_no)
      when '}' then close_brace(token, line_no)
      when /\A\\begin\{(.*)\}\z/ then begin_tag(Regexp.last_match(1), token, line_no)
      when /\A\\end\{(.*)\}\z/ then end_tag(Regexp.last_match(1), token, line_no)
      else add(token, line_no)
      end
    end

    def top_level?
      @brace.zero? && @nested.zero?
    end

    def open_brace(token, line_no)
      @brace += 1
      add(token, line_no)
    end

    def close_brace(token, line_no)
      @brace -= 1 if @brace.positive?
      add(token, line_no)
    end

    def begin_tag(name, token, line_no)
      if !@opened && name == @env
        @opened = true
      else
        @nested += 1
        add(token, line_no)
      end
    end

    def end_tag(name, token, line_no)
      return if @nested.zero? && name == @env

      @nested -= 1 if @nested.positive?
      add(token, line_no)
    end

    def add(token, line_no)
      size = token.gsub(/\s+/, '').size
      return if size.zero?

      @current ||= { first: line_no, last: line_no, size: 0 }
      @current[:last] = line_no
      @current[:size] += size
    end

    def flush
      @rows << @current if @current
      @current = nil
    end
  end

  # Returns {env:, env_start:, rows:, widest:, heading:, math_line:, math_chars:}
  # (keys present only when known). `line_end` is the span end of a paragraph box.
  def self.describe(file, line, kind, line_end = nil)
    path = LaTeXErrorCatalog.find_source_file(file)
    return {} unless path && line.to_i.positive?

    lines = LaTeXUtils.safe_read(path).lines
    return describe_display(lines, line.to_i) if kind == 'detected_line'

    describe_span(lines, line.to_i, (line_end || line).to_i)
  rescue StandardError
    {}
  end

  def self.describe_display(lines, line_no)
    last = tags_of(lines[line_no - 1].to_s).last
    return describe_dollar_display(lines, line_no) unless last && last[0] == 'end'

    start = find_begin_line(lines, line_no - 1, last[1])
    return {} unless start

    { env: last[1], env_start: start }.merge(display_rows(lines, start, line_no, last[1]))
  end

  def self.describe_span(lines, line_no, line_end)
    name, start = enclosing_env(lines, line_no - 1)
    info = name ? { env: name, env_start: start } : {}
    heading = heading_kind(lines, line_no, name, start)
    return info.merge(heading: heading) if heading

    info.merge(longest_inline_math(lines, line_no, [line_end, line_no].max))
  end

  # The head line of a section, or of a theorem-like environment that has a
  # title (`\begin{theorem}[Title]`) and whose text starts right after the
  # opening lines: TeX typesets "Theorem N (Title). text" as one unbreakable
  # head, so the title is the likely culprit and `\\` cannot fix it.
  def self.heading_kind(lines, first, env, env_start)
    return 'section' if lines[first - 1].to_s.match?(SECTION_PATTERN)
    return nil unless env && env_start && THEOREM_ENVS.include?(env.delete_suffix('*'))
    return nil unless lines[env_start - 1].to_s.match?(/\\begin\{#{Regexp.escape(env)}\}\s*\[/)
    return nil unless lines[env_start...[first - 1, env_start].max].all? { |l| l.match?(HEAD_PRELUDE) }

    env
  end

  # Longest inline math span (`$..$`, `\(..\)`, `\begin{math}`) in the box's
  # source lines. `$` pairing is claimed only for an even count without `$$`.
  def self.longest_inline_math(lines, first, last)
    spans = inline_math_spans(lines, first, last)
    best = spans.max_by { |s| s[:chars] }
    return {} unless best && best[:chars] >= MIN_MATH_CHARS

    { math_line: best[:line], math_chars: best[:chars] }
  end

  def self.inline_math_spans(lines, first, last)
    code = (first..last).map { |n| lines[n - 1].to_s.sub(/(?<!\\)%.*$/, '') }
    offset = 0
    starts = code.map { |src_line| offset.tap { offset += src_line.length } }
    text = code.join
    found = []
    text.scan(MATH_ENV_PATTERN) { found << [Regexp.last_match.begin(1), Regexp.last_match(1)] }
    text.scan(PAREN_MATH_PATTERN) { found << [Regexp.last_match.begin(1), Regexp.last_match(1)] }
    found.concat(dollar_spans(text))
    found.map { |pos, body| { line: first + starts.rindex { |s| s <= pos }, chars: body.gsub(/\s+/, '').length } }
  end

  def self.dollar_spans(text)
    return [] if text.include?('$$')

    marks = text.enum_for(:scan, /(?<!\\)\$/).map { Regexp.last_match.begin(0) }
    return [] if marks.size.odd?

    marks.each_slice(2).map { |open_pos, close_pos| [open_pos + 1, text[(open_pos + 1)...close_pos]] }
  end

  # `$$ ... $$`: paired only inside the paragraph around the box; an odd count
  # means a stray `$$` somewhere, so nothing is claimed.
  def self.describe_dollar_display(lines, line_no)
    first, last = LaTeXErrorCatalog.find_paragraph_bounds(lines, line_no - 1)
    marks = dollar_display_marks(lines, first, last)
    return {} if marks.size.odd?

    open_line, = marks.each_slice(2).find { |_, close_line| close_line == line_no }
    open_line ? { env: '$$', env_start: open_line } : {}
  end

  def self.dollar_display_marks(lines, first, last)
    (first..last).flat_map do |idx|
      code = lines[idx].to_s.sub(/(?<!\\)%.*$/, '')
      Array.new(code.scan(/(?<!\\)\$\$/).size, idx + 1)
    end
  end

  # Environment/bracket tags on a line, with `\\` removed first so that
  # `\\[1ex]` is not read as the display opener `\[`.
  def self.tags_of(raw_line)
    clean = raw_line.sub(/(?<!\\)%.*$/, '').gsub('\\\\', '  ')
    LaTeXErrorCatalog.parse_env_tags(clean)
  end

  def self.scan_floor(idx)
    [idx - MAX_SCAN_LINES, 0].max
  end

  # 1-based line of the \begin matching the \end on lines[idx] (its last tag).
  def self.find_begin_line(lines, idx, name)
    stack = []
    idx.downto(scan_floor(idx)) do |i|
      tags_of(lines[i].to_s).reverse_each do |type, tag|
        if type == 'end'
          stack << tag
        elsif (pos = stack.rindex(tag))
          stack.slice!(pos..-1)
          return i + 1 if stack.empty? && tag == name
        end
      end
    end
    nil
  end

  # Innermost environment still open at lines[idx]: [name, 1-based begin line].
  def self.enclosing_env(lines, idx)
    stack = []
    idx.downto(scan_floor(idx)) do |i|
      tags_of(lines[i].to_s).reverse_each do |type, tag|
        if type == 'end'
          stack << tag
        elsif (pos = stack.rindex(tag))
          stack.slice!(pos..-1)
        else
          return IGNORED_ENVS.include?(tag) ? nil : [tag, i + 1]
        end
      end
    end
    nil
  end

  def self.display_rows(lines, start, finish, env)
    splitter = RowSplitter.new(env)
    (start..finish).each { |no| splitter.feed(lines[no - 1].to_s, no) }
    rows = splitter.rows
    return {} if rows.size < 2

    widest = rows.max_by { |r| r[:size] }
    label = widest[:first] == widest[:last] ? widest[:first].to_s : "#{widest[:first]}-#{widest[:last]}"
    { rows: rows.size, widest: label }
  end
end
