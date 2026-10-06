# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/flattener.rb
#
# Recursive LaTeX document flattener. Inlines \\input and \\include directives,
# strips comments, and cleans machine-specific styles.
# ==============================================================================

module LaTeXFlattener
  # Two guards on the \verb alternative. `(?![a-zA-Z])` stops macros that merely
  # begin with "verb" -- \verbatiminput, \verbdef, \verbatimfont -- from being
  # read as \verb with the next letter as the delimiter. `[^\n]*?` keeps the
  # span on one line, which is what TeX requires anyway; with the /m flag and an
  # unbounded `.*?` a bogus match ran to the next occurrence of that letter,
  # often many lines later, and everything inside was passed through untouched:
  # \input directives there were never inlined and their files never staged.
  LITERAL_TEX = /\\begin\{(verbatim\*?|Verbatim|BVerbatim|LVerbatim|lstlisting|minted)\}.*?\\end\{\1\}|\\verb\*?(?![a-zA-Z])([^\s])[^\n]*?\2/m.freeze

  def self.transform_tex(content)
    output = +''
    offset = 0
    content.to_enum(:scan, LITERAL_TEX).each do
      literal = Regexp.last_match
      output << yield(content[offset...literal.begin(0)])
      output << literal[0]
      offset = literal.end(0)
    end
    output << yield(content[offset..])
  end

  def self.flatten(main_tex, base_dir = '.', strip_patterns = nil, strip_comments: true)
    inlined = inline_file(main_tex, base_dir, [])
    cleaned = clean_host_specific(inlined, strip_patterns)
    strip_comments ? strip_comments(cleaned) : cleaned
  end

  def self.within_tree?(candidate, base_expanded, real_base)
    expanded = File.expand_path(candidate)
    return false unless expanded == base_expanded || expanded.start_with?(base_expanded + File::SEPARATOR)

    real_cand = begin
      File.realpath(candidate)
    rescue StandardError
      nil
    end
    return false unless real_cand

    real_cand == real_base || real_cand.start_with?(real_base + File::SEPARATOR)
  end

  def self.inline_file(filepath, base_dir, stack)
    base_expanded = File.expand_path(base_dir)
    real_base = begin
      File.realpath(base_expanded)
    rescue StandardError
      base_expanded
    end

    real_path = File.expand_path(filepath, base_dir)
    return '' unless File.file?(real_path) && within_tree?(real_path, base_expanded, real_base)

    if stack.include?(real_path)
      chain = (stack + [real_path]).map { |path| File.basename(path) }.join(' -> ')
      raise "Cyclic LaTeX input detected: #{chain}"
    end

    stack << real_path
    entered = true
    content = LaTeXUtils.safe_read(real_path)
    file_dir = File.dirname(real_path)

    transform_tex(content) do |chunk|
      chunk.lines.map { |line| inline_line(line, base_expanded, real_base, file_dir, stack) }.join
    end
  ensure
    stack.pop if entered
  end

  def self.inline_line(line, base_expanded, real_base, file_dir, stack)
    comment_idx = inline_comment_index(line)
    code_part = comment_idx ? line[0...comment_idx] : line
    comment_part = comment_idx ? line[comment_idx..] : ''

    return line unless code_part =~ /\\(?:input|include)\{([^}]+)\}/

    has_newline = code_part.end_with?("\n")
    had_only_directives = code_part.gsub(/\\(?:input|include)\{[^}]+\}/, '').strip.empty?

    inlined_code = code_part.gsub(/\\(?:input|include)\{([^}]+)\}/) do |match|
      target = Regexp.last_match(1).strip
      target += '.tex' unless target.end_with?('.tex')
      candidate = File.expand_path(target, file_dir)
      if File.file?(candidate) && within_tree?(candidate, base_expanded, real_base)
        inline_file(candidate, base_expanded, stack)
      else
        match
      end
    end

    if had_only_directives && comment_part.empty? && inlined_code.end_with?("\n")
      inlined_code = inlined_code.chomp if has_newline && inlined_code.end_with?("\n\n")
      inlined_code += "\n" unless inlined_code.end_with?("\n")
    end

    inlined_code + comment_part
  end

  CONDITIONAL_MACRO = '\IfFileExists'

  # Strips \IfFileExists conditionals whose tested filename names a machine the
  # document should not depend on. This used to be two gsubs matching argument
  # groups with \{[^}]*\}, which cannot span a nested brace -- and the second
  # argument of this idiom almost always contains one (\input{...},
  # \usepackage{...}). The three-argument alternative therefore never matched,
  # the two-argument one fired, and a *prefix* of the construct was deleted,
  # leaving stray braces in the .tex that ships inside the arXiv package. The
  # scan below reads balanced groups instead, and removes a conditional only
  # when it can account for the whole of it.
  def self.clean_host_specific(content, patterns = nil)
    tokens = patterns || LaTeXUtils::DEFAULT_STRIP_HOST_PATTERNS
    return content if tokens.empty?

    re = Regexp.union(tokens.map { |t| Regexp.escape(t) })
    transform_tex(content) { |chunk| strip_host_conditionals(chunk, re) }
  end

  def self.strip_host_conditionals(chunk, re)
    output = +''
    pos = 0
    while (idx = chunk.index(CONDITIONAL_MACRO, pos))
      output << chunk[pos...idx]
      stop = host_conditional_end(chunk, idx, re)
      if stop
        pos = stop
      else
        output << CONDITIONAL_MACRO
        pos = idx + CONDITIONAL_MACRO.length
      end
    end
    output << chunk[pos..]
  end

  # Returns the index just past a \IfFileExists whose first argument matches
  # `re`, or nil when it does not match or the construct is malformed. A
  # malformed conditional is left in place: emitting half of it is strictly
  # worse than emitting all of it.
  def self.host_conditional_end(chunk, idx, re)
    cursor = idx + CONDITIONAL_MACRO.length
    groups = []
    3.times do
      cursor = skip_blanks(chunk, cursor)
      break unless chunk[cursor] == '{'

      inner, cursor = balanced_group(chunk, cursor)
      return nil unless inner

      groups << inner
    end
    return nil if groups.size < 2

    groups.first.match?(re) ? cursor : nil
  end

  def self.skip_blanks(text, index)
    index += 1 while index < text.length && text[index].match?(/[ \t\r\n]/)
    index
  end

  # Reads the balanced group beginning at `start` (which must be '{').
  # Returns [contents, index_after_closing_brace], or [nil, start] if unclosed.
  def self.balanced_group(text, start)
    depth = 0
    i = start
    while i < text.length
      case text[i]
      when '\\' then i += 1
      when '{' then depth += 1
      when '}'
        depth -= 1
        return [text[(start + 1)...i], i + 1] if depth.zero?
      end
      i += 1
    end
    [nil, start]
  end

  def self.strip_comments(content)
    transform_tex(content) { |chunk| strip_comment_chunk(chunk) }
  end

  def self.strip_comment_chunk(content)
    output = +''
    content.each_line do |raw_line|
      line = raw_line.chomp
      if line =~ /^%!TEX\s+TS-program/i
        output << line << "\n"
        next
      end

      comment_idx = inline_comment_index(line)
      clean_line = comment_idx ? line[0...comment_idx] : line
      next if clean_line.nil?

      output << clean_line
      output << '%' if comment_idx
      output << "\n" if raw_line.end_with?("\n")
    end

    output
  end

  def self.strip_inline_comment(line)
    idx = inline_comment_index(line)
    idx ? line[0...idx] : line
  end

  def self.preceding_backslash_count(line, idx)
    count = 0
    k = idx - 1
    while k >= 0 && line[k] == '\\'
      count += 1
      k -= 1
    end
    count
  end

  URL_MACROS = %w[\\url{ \\nolinkurl{ \\path{ \\href{].freeze

  def self.matching_url_macro(line, idx)
    return nil unless preceding_backslash_count(line, idx).even?

    URL_MACROS.find { |m| line[idx, m.length] == m }
  end

  def self.inline_comment_index(line)
    url_depth = 0
    i = 0
    len = line.length
    while i < len
      c = line[i]
      if c == '\\' && (macro = matching_url_macro(line, i))
        url_depth += 1
        i += macro.length
        next
      end
      if url_depth > 0
        if c == '{'
          url_depth += 1
        elsif c == '}'
          url_depth -= 1
        end
      elsif c == '%'
        return i if preceding_backslash_count(line, i).even?
      end
      i += 1
    end
    nil
  end
end
