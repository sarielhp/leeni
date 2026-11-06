# frozen_string_literal: true

# ==============================================================================
# lib/leeni/bibkit_scanner.rb
#
# Bibkit: leeni's library for .bib files as data (see docs/bibkit.md). It
# depends on the standard library only and never prints.
#
# The scanner splits a .bib text into top-level blocks, keeping each block's
# original bytes, file and line. Text is scanned as bytes, so a file in any
# ASCII-compatible encoding is copied back exactly. A block that does not
# parse becomes a Problem and scanning resumes at the next line that starts
# with '@'; junk after a field value is recorded on the item, which is kept.
# ==============================================================================

require 'strscan'

module Bibkit
  # One field of an entry, or the single value of a @string or @preamble.
  # `value` is the raw text after '=', `macros` the @string names it uses
  # (lower-cased; BibTeX and Biber match them case-insensitively).
  Field = Struct.new(:name, :value, :macros)

  # A top-level block. kind is :entry, :string, :preamble or :comment. For a
  # @string, key is the macro name. text is the block's original bytes.
  Item = Struct.new(:kind, :type, :key, :fields, :text, :file, :line, :problems) do
    def entry? = kind == :entry

    def field(name)
      fields.find { |f| f.name&.casecmp?(name) }
    end

    def macros = fields.flat_map(&:macros).uniq

    # \commands the block uses, without the backslash.
    def commands = text.scan(/\\([A-Za-z]+)/).flatten.uniq

    def location = "#{file}:#{line}"
  end

  Problem = Struct.new(:file, :line, :message) do
    def to_s = "#{file}:#{line}: #{message}"
  end

  # Case-folded byte string used for every case-insensitive comparison.
  def self.fold(name) = name.to_s.b.downcase

  class Scanner
    class Failure < StandardError; end

    TYPE = /[A-Za-z][\w-]*/
    IDENT = /[^\s"#%'(),={}]+/
    KINDS = { 'comment' => :comment, 'string' => :string, 'preamble' => :preamble }.freeze
    RUNAWAY = /\n[ \t]*@[A-Za-z]+[ \t]*[{(]/

    # Returns [items, problems].
    def self.scan(text, file = nil)
      new(text, file).run
    end

    def initialize(text, file)
      @text = text.b
      @file = file
      @scanner = StringScanner.new(@text)
      @problems = []
    end

    def run
      items = []
      while @scanner.skip_until(/@/)
        start = @scanner.pos - 1
        item = scan_block(start)
        items << item if item
      end
      [items, @problems]
    end

    private

    def scan_block(start)
      type = @scanner.scan(TYPE)
      return nil unless type && @scanner.skip(/\s*/) && (opener = @scanner.scan(/[{(]/))

      parse_block(type, opener == '{' ? '}' : ')', start)
    rescue Failure => e
      @problems << Problem.new(@file, line_at(start), "#{e.message} in @#{type}")
      resync(start)
      nil
    end

    def parse_block(type, closer, start)
      kind = KINDS.fetch(type.downcase, :entry)
      @item_problems = []
      key, fields = send(:"parse_#{kind}", closer)
      text = @text[start...@scanner.pos]
      Item.new(kind, type, key, fields, text, @file, line_at(start), @item_problems)
    end

    # Resume at the next line starting with '@', after the failed block's '@'.
    def resync(start)
      @scanner.pos = start + 1
      @scanner.terminate unless @scanner.skip_until(/(?=^[ \t]*@)/)
    end

    def parse_comment(closer)
      skip_balanced_to(closer)
      [nil, []]
    end

    def parse_preamble(closer)
      field = Field.new(nil, *scan_value)
      expect_closer(closer)
      [nil, [field]]
    end

    def parse_string(closer)
      skip_space
      name = @scanner.scan(IDENT) or fail!('expected a macro name')
      expect('=')
      field = Field.new(name, *scan_value)
      expect_closer(closer)
      [name, [field]]
    end

    def parse_entry(closer)
      skip_space
      key = @scanner.scan(closer == '}' ? /[^,\s}]*/ : /[^,\s)]*/)
      fields = []
      loop do
        skip_space
        break if @scanner.skip(Regexp.new(Regexp.escape(closer)))

        @scanner.skip(/,/) or junk_after_value(closer)
        skip_space
        break if @scanner.skip(Regexp.new(Regexp.escape(closer)))

        fields << scan_field
      end
      [key, fields]
    end

    def scan_field
      name = @scanner.scan(IDENT) or fail!('expected a field name')
      expect('=')
      Field.new(name, *scan_value)
    end

    # Returns [raw value text, macros used].
    def scan_value
      skip_space
      start = @scanner.pos
      macros = []
      loop do
        scan_piece(macros)
        skip_space
        break unless @scanner.skip(/#/)

        skip_space
      end
      [@text[start...@scanner.pos].rstrip, macros]
    end

    def scan_piece(macros)
      case @scanner.peek(1)
      when '{' then scan_braced
      when '"' then scan_quoted
      else
        return if @scanner.skip(/\d+/)

        name = @scanner.scan(IDENT) or fail!('expected a field value')
        macros << Bibkit.fold(name)
      end
    end

    def scan_braced
      start = @scanner.pos
      depth = 0
      loop do
        @scanner.skip_until(/[{}]/) or fail!('unbalanced braces')
        depth += @scanner.matched == '{' ? 1 : -1
        break if depth.zero?
      end
      check_runaway(start)
    end

    def scan_quoted
      start = @scanner.pos
      @scanner.getch
      depth = 0
      loop do
        @scanner.skip_until(/[{}"]/) or fail!('unterminated quoted value')
        break if @scanner.matched == '"' && depth.zero?

        depth += { '{' => 1, '}' => -1 }.fetch(@scanner.matched, 0)
        fail!('unbalanced braces in a quoted value') if depth.negative?
      end
      check_runaway(start)
    end

    # A value that swallowed the start of the next entry lost its closing
    # brace or quote; BibTeX would read on, Bibkit reports it instead.
    def check_runaway(start)
      fail!('value runs into the next entry (missing closing brace or quote)') if @text[start...@scanner.pos].match?(RUNAWAY)
    end

    # Text after a field value that is neither ',' nor the closer, such as
    # `annote = {230} %DONE`: recorded, skipped, and the entry kept.
    def junk_after_value(closer)
      junk_start = @scanner.pos
      @scanner.skip(/[^,{}()"]*/)
      fail!('unexpected text in entry') if @scanner.pos == junk_start || !@scanner.check(/[,})]/)

      junk = @text[junk_start...@scanner.pos].strip
      @item_problems << Problem.new(@file, line_at(junk_start), junk_message(junk))
      @scanner.skip(/,/) unless @scanner.check(Regexp.new(Regexp.escape(closer)))
    end

    # BibTeX stops reading the entry at such text; Biber accepts it.
    def junk_message(junk)
      shown = junk[0, 40].inspect
      return "unexpected text #{shown} after a field value" unless junk.start_with?('%')

      "#{shown} after a field value: '%' does not start a comment inside a .bib entry " \
        '(BibTeX stops reading the entry here; Biber accepts it)'
    end

    def skip_balanced_to(closer)
      depth = 0
      loop do
        @scanner.skip_until(/[{}()]/) or fail!('unterminated block')
        ch = @scanner.matched
        return if ch == closer && depth.zero?

        depth += { '{' => 1, '}' => -1 }.fetch(ch, 0)
      end
    end

    def expect(char)
      skip_space
      @scanner.skip(Regexp.new(Regexp.escape(char))) or fail!("expected '#{char}'")
    end

    def expect_closer(closer)
      skip_space
      @scanner.skip(/,?\s*/)
      @scanner.skip(Regexp.new(Regexp.escape(closer))) or fail!("expected '#{closer}'")
    end

    def skip_space = @scanner.skip(/\s*/)

    def fail!(message)
      raise Failure, message
    end

    def line_at(pos)
      @line_starts ||= [0] + @text.enum_for(:scan, /\n/).map { Regexp.last_match.end(0) }
      @line_starts.bsearch_index { |s| s > pos } || @line_starts.size
    end
  end
end
