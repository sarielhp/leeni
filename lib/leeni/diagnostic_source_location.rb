# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostic_source_location.rb
#
# Finding the source line of an error TeX locates badly or not at all: a missing
# file, a glyph, a driver failure, a package of the distribution, an environment
# never closed, a line of a fragile frame's .vrb.
# Part of LaTeXDiagnostics (lib/leeni/diagnostics.rb), which includes it.
# ==============================================================================

module LaTeXDiagnostics
  # Finding the source line of an error TeX locates badly or not at all.
  module SourceLocation
    # TeX attributes some errors to no source position (a missing file, a glyph
    # the font lacks); the position is recovered from the source tree instead.
    def locate_error_source(classification, err_text = '')
      case classification&.[](:id)
      when :file_not_found, :include_target_missing
        locate_missing_resource_request(classification[:token])
      when :missing_character
        locate_missing_character(classification[:token])
      when :dropped_text
        locate_dropped_text(classification[:token].to_s)
      when :pdf_driver_image_failed
        locate_image_request(classification[:token], err_text[/include page (\d+) of image/, 1])
      when :pdf_driver_fatal
        locate_driver_file_request(classification[:token])
      when :file_ended_while_scanning
        locate_unclosed_environment || end_of_main_file
      end
    end

    # A [fragile] beamer frame writes its body to <job>.vrb and reads it back,
    # so TeX reports errors in the frame at a line of that build file. The
    # body is copied line for line, so the .vrb is aligned with the source by
    # the offset most of its distinctive lines agree on.
    def locate_frame_source(file, line)
      return nil unless file.to_s.end_with?('.vrb') && line.to_i.positive?

      body = LaTeXUtils.safe_read(file).lines.map { |text| text.gsub('^^I', "\t").strip } # TeX writes a tab as ^^I
      collect_source_candidates.each do |source|
        offset = frame_offset(body, LaTeXUtils.safe_read(source).lines.map(&:strip))
        return [source, line.to_i + offset] if offset
      end
      nil
    end

    def frame_offset(body, source)
      where = Hash.new { |h, k| h[k] = [] }
      source.each_with_index { |text, idx| where[text] << idx }
      distinctive = body.each_with_index.select { |text, _| text.length > 3 && where.key?(text) }
      votes = distinctive.flat_map { |text, idx| where[text].map { |at| at - idx } }.tally
      best, count = votes.max_by { |_, n| n }
      best if count && count >= 3 && count * 2 >= distinctive.size
    end

    VERBATIM_ENVIRONMENTS = %w[verbatim verbatim* Verbatim lstlisting minted comment alltt].freeze
    ENVIRONMENT_MARK = /\\(begin|end)\s*\{([^}]+)\}/

    # Environments that collect their body as an argument (beamer's frame,
    # tabularx, environ-based ones) report a missing \end only as "File ended
    # while scanning use of \beamer@collect@@body", with no line. The fault is
    # the \begin that is never closed: the first one still open when an outer
    # environment (or the document) ends, or at the end of the main file.
    def locate_unclosed_environment
      state = scan_environments(LaTeXUtils.safe_read(@filename))
      return [@filename, state[:found]] if state[:found]
      return [@filename, state[:verbatim][:line]] if state[:verbatim]

      open = state[:stack].find { |name, _| name != 'document' }
      open && [@filename, open[1]]
    end

    def scan_environments(source)
      state = { stack: [], verbatim: nil, declared: declared_verbatim_environments(source) }
      source.each_line.with_index(1) do |line, line_no|
        LaTeXUtils.strip_latex_comments(line).scan(ENVIRONMENT_MARK) do |kind, name|
          state[:found] = environment_mark(state, kind, name, line_no, line)
          return state if state[:found]
        end
      end
      state
    end

    # One \begin or \end; inside a verbatim body only its own \end counts
    # (for the comment package, only at the start of a line).
    def environment_mark(state, kind, name, line_no, line)
      if (verbatim = state[:verbatim])
        closes = kind == 'end' && name == verbatim[:end] && (!verbatim[:line_start] || line.start_with?('\\end'))
        state[:verbatim] = nil if closes
        return nil
      end
      if kind == 'begin' && (verbatim = verbatim_environment(state[:declared], name))
        state[:verbatim] = verbatim.merge(name: name, line: line_no)
        return nil
      end
      track_environment(state[:stack], kind, name, line_no)
    end

    def verbatim_environment(declared, name)
      declared[name] || (VERBATIM_ENVIRONMENTS.include?(name) && { end: name, line_start: name == 'comment' })
    end

    COMMENT_DECLARATION = /\\(?:excludecomment|specialcomment|processcomment)\s*\{([^}]+)\}/
    VERBATIM_DECLARATION = /\\(?:DefineVerbatimEnvironment|newtcblisting|newminted)\s*\{([^}]+)\}/
    LISTING_DECLARATION = /\\lstnewenvironment\s*\{([^}]+)\}\s*(?:\[[^\]]*\]\s*)*\{([^\n]*)/
    # An environment whose begin code opens a fancyvrb one (minted, Verbatim)
    # without \VerbatimEnvironment: fancyvrb then looks for \end{minted},
    # which the document never writes (TeX.SE 272310, 400111).
    WRAPPED_VERBATIM = /\\(?:(?:re)?newenvironment|(?:New|Renew)DocumentEnvironment)\s*\{([^}]+)\}(.{0,200}?)\\begin\s*\{(minted|Verbatim|BVerbatim|LVerbatim)\}/m

    # Environments the document declares that read their body verbatim. The
    # comment package ends one only at an \end at the start of a line; a
    # \lstnewenvironment whose begin code opens another environment makes
    # listings look for that one's \end (TeX.SE 77920, 135737).
    def declared_verbatim_environments(source)
      text = source.each_line.map { |line| LaTeXUtils.strip_latex_comments(line) }.join
      declared = {}
      text.scan(COMMENT_DECLARATION) { |(name)| declared[name] = { end: name, line_start: true } }
      text.scan(VERBATIM_DECLARATION) { |(name)| declared[name] = { end: name, line_start: false } }
      text.scan(WRAPPED_VERBATIM) do |name, between, inner|
        declared[name] = { end: inner, line_start: false } unless between.include?('\VerbatimEnvironment')
      end
      text.scan(LISTING_DECLARATION) do |name, code|
        declared[name] = { end: code[/\A[^}]*?\\begin\s*\{([^}]+)\}/, 1] || name, line_start: false }
      end
      declared
    end

    # A runaway that reached the end of the file with nothing left open: TeX
    # was at the end of the main file, not at its first line (TeX.SE 151317).
    def end_of_main_file
      lines = LaTeXUtils.safe_read(@filename).lines
      last = lines.rindex { |line| !line.strip.empty? }
      last && [@filename, last + 1]
    end

    # Pushes or pops one \begin/\end; returns the line of a \begin left open
    # when an \end closes an environment opened before it.
    def track_environment(stack, kind, name, line_no)
      return stack.push([name, line_no]) && nil if kind == 'begin' && !VERBATIM_ENVIRONMENTS.include?(name)
      return nil unless kind == 'end'

      match = stack.rindex { |open, _| open == name }
      return nil unless match

      unclosed = stack[match + 1]
      stack.slice!(match..)
      unclosed&.last
    end

    DISTRIBUTION_STYLE = %r{/texmf-dist/.+\.(?:sty|cls)\z}

    # A Lua error names its chunk ("[\directlua]:1:"), not a file: the TeX
    # line that ran the code is the l.N context, in the file TeX is reading.
    def locate_lua_chunk(file, err_text, file_stack)
      return nil unless file.to_s.match?(/\A\[.*\]\z/)

      tex_line = err_text[/^l\.(\d+)/, 1]
      return nil unless tex_line

      source = current_log_file(file_stack)
      chunk_line = file.to_s[/\]:(\d+)/, 1] || err_text[/\[\\directlua\]:(\d+):/, 1]
      [source, lua_source_line(source, tex_line.to_i, chunk_line.to_i) || tex_line.to_i]
    end

    LUA_CHUNK_START = /\\begin\s*\{luacode\*?\}|\\directlua\s*\{|\\luaexec\s*\{/

    # The chunk's line number counts from where the code starts: the line
    # after \begin{luacode}, the line of \directlua{. TeX's l.N is where the
    # chunk ended (TeX.SE 129183).
    def lua_source_line(source, tex_line, chunk_line)
      return nil unless chunk_line.positive?

      lines = LaTeXUtils.safe_read(source).lines
      start = (tex_line - 1).downto([tex_line - 200, 0].max).find do |idx|
        lines[idx] && LaTeXUtils.strip_latex_comments(lines[idx]).match?(LUA_CHUNK_START)
      end
      return nil unless start

      environment = lines[start].match?(/\\begin\s*\{luacode/)
      found = start + chunk_line + (environment ? 1 : 0) # start is 0-based
      found if found.between?(start + 1, tex_line)
    end

    # TeX reports an error raised while a class or package of the TeX
    # distribution is being read inside that file (babel.sty:4481), which the
    # author cannot change; the \usepackage or \documentclass that loads it,
    # with the option at fault, is the line to fix. A package loaded only by
    # another package is not found and keeps TeX's location.
    # A package the document does not load itself (hyperref loaded by a class)
    # is traced through TeX's open files to the one the document does load.
    def locate_package_load(file, file_stack = [])
      [file, *file_stack.compact.reverse].uniq.each do |path|
        found = locate_load_of(path.to_s)
        return found if found
      end
      nil
    end

    def locate_load_of(path)
      return nil unless path.match?(DISTRIBUTION_STYLE)

      command = path.end_with?('.cls') ? 'documentclass|LoadClass' : 'usepackage|RequirePackage'
      name = Regexp.escape(File.basename(path, '.*'))
      pattern = /\\(?:#{command})\s*(?:\[[^\]]*\])?\s*\{(?:[^}]*[,\s])?#{name}\s*(?:,[^}]*)?\}/
      collect_source_candidates.each do |src_file|
        LaTeXUtils.safe_read(src_file).each_line.with_index(1) do |line, line_no|
          return [src_file, line_no] if LaTeXUtils.strip_latex_comments(line).match?(pattern)
        end
      end
      nil
    end

    DRIVER_MISSING_FILE = /Could not (?:find|open) file:?\s*['`"]?([^\s'"]+)/i

    # A fatal driver message that names a file it could not find ("Image
    # inclusion failed. Could not find file: x.pdf") points at the
    # \includegraphics or \special that asked for it. A message naming no file
    # stays without a location: guessing one would mislead.
    def locate_driver_file_request(message)
      file = message.to_s[DRIVER_MISSING_FILE, 1]
      stem = File.basename(file.to_s).sub(/\.[A-Za-z0-9]+\z/, '')
      return nil if stem.empty?

      pattern = /\\(?:includegraphics\s*\*?\s*(?:\[[^\]]*\])?\s*\{|special\s*\{)[^}]*#{Regexp.escape(stem)}/
      collect_source_candidates.each do |src_file|
        LaTeXUtils.safe_read(src_file).each_line.with_index(1) do |line, line_no|
          return [src_file, line_no] if LaTeXUtils.strip_latex_comments(line).match?(pattern)
        end
      end
      nil
    end

    # The \includegraphics of the image, preferring the one that asks for the
    # failing page; the driver names the file as found, extension and all.
    def locate_image_request(path, page)
      stem = File.basename(path.to_s).sub(/\.[A-Za-z0-9]+\z/, '')
      return nil if stem.empty?

      pattern = /\\includegraphics\s*\*?\s*(?:\[(?<opts>[^\]]*)\])?\s*\{[^}]*#{Regexp.escape(stem)}(?:\.[A-Za-z0-9]+)?\s*\}/
      hits = collect_source_candidates.flat_map do |file|
        LaTeXUtils.safe_read(file).each_line.with_index(1).filter_map do |line, line_no|
          m = LaTeXUtils.strip_latex_comments(line).match(pattern)
          [file, line_no, m[:opts].to_s] if m
        end
      end
      best = hits.find { |_f, _l, opts| page && opts.match?(/\bpage\s*=\s*\{?#{page}\b/) } || hits.first
      best&.first(2)
    end

    # Inside a beamer frame TeX reports some faults at the end of the group the
    # text was read in (an \only{...}, \uncover{...}, the frame) and names
    # beamer's or pgf's internal macros. The fault is the nearest line above,
    # within the frame, holding what the error is about: a #1 that must be
    # written ##1, or the & of a matrix read with the wrong catcode.
    def locate_frame_parameter(err_text, file, line)
      probe = frame_backward_probe(err_text)
      return nil unless probe && line.to_i.positive?

      lines = LaTeXUtils.safe_read(file).lines
      return nil if probe == :param && !param_error_in_frame?(err_text, lines[line.to_i - 1])

      nearest_in_frame(lines, line.to_i - 1, probe == :param ? /(?<!#)#[1-9]/ : /(?<!\\)&/)&.then { |idx| [file, idx + 1] }
    end

    def frame_backward_probe(err_text)
      if err_text.include?('Illegal parameter number') then :param
      elsif err_text.include?('Single ampersand used with wrong catcode') then :ampersand
      end
    end

    def param_error_in_frame?(err_text, reported_line)
      reported_line.to_s.match?(/\A\s*\\end\{frame\}/) || err_text.include?('\\beamer@doifinframe')
    end

    # The index of the nearest line at or above FROM matching PATTERN, when
    # the search meets the frame's \begin{frame}; nil outside a frame.
    def nearest_in_frame(lines, from, pattern)
      found = nil
      from.downto(0) do |idx|
        text = LaTeXUtils.strip_latex_comments(lines[idx].to_s)
        found ||= idx if text.match?(pattern)
        return found if text.match?(/\\begin\{frame\}/)
      end
      nil
    end

    # A beamer frame reads its body whole before typesetting it, so TeX reports
    # an error inside it at the \end{frame}, often with no context. What the
    # error names is looked for in the frame's body instead: the \end{...}
    # that closed the wrong environment, or a _ or ^ outside math.
    def locate_frame_body(classification, err_text, file, line)
      lines = LaTeXUtils.safe_read(file).lines
      return nil unless line.to_i.positive? && lines[line.to_i - 1].to_s.match?(/\A\s*\\end\{frame\}/)

      start = (line.to_i - 2).downto(0).find { |idx| lines[idx].match?(/\\begin\{frame\}/) }
      probe = frame_body_probe(classification&.[](:id), err_text)
      return nil unless start && probe

      # Only a missing $ skips display math: there _ and ^ are no fault.
      range = (start + 1)...(line.to_i - 1)
      texts = if classification&.[](:id) == :missing_dollar
                frame_text_lines(lines, range)
              else
                range.map { |idx| [idx, frame_text(lines[idx])] }
              end
      found = texts.find { |_, text| text.match?(probe) }
      found && [file, found.first + 1]
    end

    DISPLAY_MATH = 'align|equation|gather|multline|eqnarray|flalign|alignat|displaymath|math'
    DISPLAY_BEGIN = /\\begin\{(?:#{DISPLAY_MATH})\*?\}|\\\[/
    DISPLAY_END = /\\end\{(?:#{DISPLAY_MATH})\*?\}|\\\]/

    # The text of each line outside math: display environments are skipped
    # whole (a _ inside align is no fault) and inline math is removed.
    def frame_text_lines(lines, range)
      in_math = false
      range.map do |idx|
        text = LaTeXUtils.strip_latex_comments(lines[idx])
        math_line = in_math || text.match?(DISPLAY_BEGIN)
        in_math = math_line && !text.match?(DISPLAY_END)
        [idx, math_line ? '' : frame_text(text)]
      end
    end

    def frame_body_probe(category, err_text)
      case category
      when :mismatched_environment
        name = err_text[/ended by \\end\{([^}]+)\}/, 1]
        name && /\\end\s*\{#{Regexp.escape(name)}\}/
      when :missing_dollar
        /(?<!\\)[_^]/
      when :wrong_catcode_ampersand
        /(?<!\\)&/
      end
    end

    # A line without comments and without its inline math.
    def frame_text(line)
      LaTeXUtils.strip_latex_comments(line).gsub(/(?<!\\)\$[^$]*(?<!\\)\$|\\\(.*?\\\)/, '')
    end

    # keyval names the key it does not know, not where it was given: TeX reports
    # the line where the command was read to its end, which for a beamer frame
    # is the \end{frame}. The key is looked for on that line and above it.
    def locate_key_source(classification, file, line)
      return nil unless classification&.[](:id) == :keyval_unknown_key && line.to_i.positive?

      key = /(?<![\w@])#{Regexp.escape(classification[:token].to_s)}(?![\w@])/
      lines = LaTeXUtils.safe_read(file).lines
      (line.to_i - 1).downto([line.to_i - 50, 0].max) do |idx|
        text = lines[idx] && LaTeXUtils.strip_latex_comments(lines[idx])
        next unless text&.match?(key)

        return [file, key_macro_use(lines, idx, line.to_i, text) || (idx + 1)]
      end
      nil
    end

    # The key list stored in a macro (\def\foo{scale=0.1}, used as
    # \includegraphics[\foo]): the fault is where the macro is given as the
    # options, which keyval reads unexpanded (TeX.SE 188192).
    def key_macro_use(lines, def_idx, tex_line, text)
      name = text[LaTeXErrorCatalog::KEY_MACRO_DEFINITION, 1]
      return nil unless name

      use = /\[\s*#{Regexp.escape(name)}\s*\]/
      ((def_idx + 1)...tex_line).find { |idx| lines[idx] && LaTeXUtils.strip_latex_comments(lines[idx]).match?(use) }&.+(1)
    end

    # The dropped text has lost its spaces and braces and may span lines, so it is looked
    # up in the source with whitespace removed; a run of one or two characters
    # (a stray ';' or two) falls back to its first character.
    def locate_dropped_text(text)
      return locate_short_dropped_text(text) if text.size <= 2

      probes = [text, text[0, 8]]
      collect_source_candidates.each do |file|
        joined, starts = joined_source(file)
        probes.uniq.each do |probe|
          # Not inside a command name: TeX may drop a command's name as text.
          # A number is not part of a longer one: pgfplots printing 0.00 is
          # not the 000.00 of a data row (TeX.SE 227793).
          before = probe.match?(/\A\d/) ? '(?<![\\\\\d])' : '(?<!\\\\)'
          at = !probe.empty? && joined.index(/#{before}#{Regexp.escape(probe)}/)
          return [file, starts.rindex { |offset| offset <= at } + 1] if at
        end
      end
      nil
    end

    # One or two characters match almost anywhere ('b' in \documentclass{beamer}):
    # they must stand alone, outside command names, in the document body.
    # Punctuation alone (a ; after a failed \addplot) is on half the lines of a
    # picture: it is placed only where it is the one such line.
    def locate_short_dropped_text(text)
      pattern = /(?<![[:alnum:]])#{Regexp.escape(text)}(?![[:alnum:]])/
      punctuation = !text.match?(/[[:alnum:]]/)
      collect_source_candidates.each do |file|
        found = short_text_lines(LaTeXUtils.safe_read(file).lines, pattern)
        next if found.empty?
        return nil if punctuation && found.size > 1

        return [file, found.first + 1]
      end
      nil
    end

    # Indexes of the body lines where PATTERN matches outside command names.
    def short_text_lines(lines, pattern)
      body = lines.index { |line| line.match?(/\\begin\{document\}/) }.to_i
      (body...lines.size).select do |idx|
        LaTeXUtils.strip_latex_comments(lines[idx]).gsub(/\\(?:[A-Za-z@]+|.)/, ' ').match?(pattern)
      end
    end

    def joined_source(file)
      joined = +''
      starts = LaTeXUtils.safe_read(file).each_line.map do |line|
        offset = joined.size
        joined << LaTeXUtils.strip_latex_comments(line).gsub(/[\s{}]+/, '') # braces only group
        offset
      end
      [joined, starts]
    end

    def locate_missing_character(glyph)
      return nil if glyph.to_s.empty? || glyph.to_s.start_with?('^^')

      # An invisible glyph is named by code point in the message; search for the character itself.
      glyph = [Regexp.last_match(1).hex].pack('U') if glyph =~ /\AU\+([0-9A-Fa-f]{4,6})\z/
      collect_source_candidates.each do |file|
        LaTeXUtils.safe_read(file).each_line.with_index(1) do |line, line_no|
          return [file, line_no] if LaTeXUtils.strip_latex_comments(line).include?(glyph)
        end
      end
      nil
    end

    def locate_missing_resource_request(resource)
      # epstopdf asks for x-eps-converted-to.pdf where the source names x.eps;
      # listings names a missing file name(.ext).
      stem = resource.to_s.sub(/\(\.\w+\)\z/, '').sub(/-eps-converted-to\.pdf\z/i, '').sub(/\.(?:tex|sty|cls|bib)\z/i, '')
      return nil if stem.empty?

      pattern = /
        \\(?:input|include|documentclass|LoadClass|usepackage|RequirePackage|includegraphics|bibliography|addbibresource|
          lstinputlisting|inputminted|verbatiminput)\s*
        (?:\[[^\]]*\])?\s*\{[^}]*#{Regexp.escape(stem)}[^}]*\}
      /x
      collect_source_candidates.each do |file|
        LaTeXUtils.safe_read(file).each_line.with_index(1) do |line, line_no|
          return [file, line_no] if LaTeXUtils.strip_latex_comments(line).match?(pattern)
        end
      end
      nil
    end
  end
end
