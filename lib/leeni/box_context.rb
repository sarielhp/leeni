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
      raw_line.sub(/(?<!\\)%.*\z/, '').scan(ROW_TOKEN) { handle(Regexp.last_match(0), line_no) }
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

  # Returns {env:, env_start:, rows:, widest:} (keys present only when known).
  def self.describe(file, line, kind)
    path = LaTeXErrorCatalog.find_source_file(file)
    return {} unless path && line.to_i.positive?

    lines = LaTeXUtils.safe_read(path).lines
    kind == 'detected_line' ? describe_display(lines, line.to_i) : describe_span(lines, line.to_i)
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

  def self.describe_span(lines, line_no)
    name, start = enclosing_env(lines, line_no - 1)
    name ? { env: name, env_start: start } : {}
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
      code = lines[idx].to_s.sub(/(?<!\\)%.*\z/, '')
      Array.new(code.scan(/(?<!\\)\$\$/).size, idx + 1)
    end
  end

  # Environment/bracket tags on a line, with `\\` removed first so that
  # `\\[1ex]` is not read as the display opener `\[`.
  def self.tags_of(raw_line)
    clean = raw_line.sub(/(?<!\\)%.*\z/, '').gsub('\\\\', '  ')
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
