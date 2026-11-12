# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostic_log_parsing.rb
#
# Reading the engine log: file tracking, warning and error extraction, bibliography companions.
# Part of LaTeXDiagnostics (lib/leeni/diagnostics.rb), which includes it.
# ==============================================================================

module LaTeXDiagnostics
  # Reading the engine log: file tracking, warning and error extraction, bibliography companions.
  module LogParsing
    # Where TeX says a box problem happened; the message keeps only the problem.
    BOX_LOCATION_SUFFIX = /\s*(?:detected at line \d+|in paragraph at lines \d+(?:--\d+)?|in alignment at lines \d+(?:--\d+)?)\.?/
    UNDEFINED_REFERENCE_WARNING =
      /LaTeX Warning: (?:Hyper reference|Reference)\s+[`'"](.+?)[`'"](?:\s+on page (\d+))?\s+undefined(?:\s+on input line \d+)?\.?/i

    def track_log_file(line, file_stack)
      return if line =~ WARNING_LINE_PATTERN ||
                line =~ /^(?:Overfull|Underfull)/ || line =~ /^!\s+/ ||
                line =~ /^Missing character:/ || line =~ /^(?:LIT_LBL|BIB_ENTRY):/

      pos = 0
      len = line.length
      while pos < len
        ch = line[pos]
        if ch == '('
          sub = line[pos..]
          if (m = sub.match(LOG_FILE_PATTERN))
            file_stack.push(m[1] || m[2])
            pos += m[0].length
          else
            file_stack.push(nil)
            pos += 1
          end
        elsif ch == ')'
          file_stack.pop unless file_stack.empty?
          pos += 1
        else
          pos += 1
        end
      end
    end

    def current_log_file(file_stack)
      file_stack.reverse_each.find { |f| !f.nil? } || @filename
    end

    def diagnostic_boundary_line?(line)
      return true if line.strip.empty? || line =~ /^(?:BIB_ENTRY|LIT_LBL):/ ||
                     line =~ WARNING_LINE_PATTERN ||
                     line =~ /^(?:Overfull|Underfull)/ || line =~ /^\[\d+\]/ ||
                     line =~ /^!\s+/ || line =~ /^.+:\d+:/ ||
                     line =~ /^Runaway argument\?/ || line =~ /^\s*\)/ ||
                     line =~ %r{^\s*\((?:\.[\\/]|[a-zA-Z0-9_\-./]+?\.(?:tex|sty|cls|aux|bbl|bib))}

      false
    end

    def clean_box_diagnostic(box_line, prefix_type = :warning)
      prefix = case prefix_type
               when :alert then 'Alert:'
               when :note then 'Note:'
               when :none then ''
               else 'Warning:'
               end

      is_alignment = box_line.include?('in alignment')

      body = if box_line =~ /(?:\(|\b)([\d.]+)pt too (wide|high)\)?/i
               pt_val = Regexp.last_match(1).to_f.round(2)
               dimension = Regexp.last_match(2)
               suffix = is_alignment ? ' (alignment)' : ''
               format('%<value>.2fpt too %<dimension>s%<suffix>s', value: pt_val, dimension: dimension, suffix: suffix)
             elsif box_line =~ /\(badness (\d+)\)/i
               badness = Regexp.last_match(1)
               box_kind = box_line =~ /\\(vbox)\b/i ? '\vbox' : '\hbox'
               "underfull #{box_kind} (badness #{badness})"
             else
               clean = box_line.sub(BOX_LOCATION_SUFFIX, '').strip
               clean.empty? ? box_line : clean
             end

      prefix.empty? ? body : "#{prefix} #{body}"
    end

    def clean_diagnostic_warning(text)
      return text if @options[:emacs]

      str = text.strip
      return clean_ref_warning(str) if str =~ /LaTeX Warning: (?:Hyper reference|Reference)/i
      return clean_cite_warning(str) if str =~ /LaTeX Warning: Citation/i

      return 'Warning: empty bibliography' if str =~ /LaTeX Warning: Empty bibliography(?:\s+on input line \d+)?\.?/i

      if str =~ /LaTeX(?: Font)? Warning: Command\s+(.+?)\s+invalid in math mode(?:\s+on input line \d+)?\.?/i
        command = Regexp.last_match(1)
        return "Warning: command #{command} invalid in math mode; #{LaTeXErrorCatalog.math_mode_advice(command)}"
      end
      if str =~ /Missing database entry:\s*['"]([^`'"]+)['"]/i
        return "Warning: Missing database entry: '#{Regexp.last_match(1)}'#{Regexp.last_match.post_match.rstrip}"
      end
      return "Warning: #{str}" if str =~ /^Missing database entries/i

      if str =~ /^(?:\*?\s*(?:Package|Class))\s+([-\w.@*]+)\s+[Ww]arning:\s*(.+)$/m
        pkg = Regexp.last_match(1)
        body = Regexp.last_match(2).gsub(/\(#{Regexp.escape(pkg)}\)/, ' ').gsub(/\s+/, ' ').strip
        body = strip_input_line_noise(body)
        return "Warning: [#{pkg}] #{body}"
      end
      if str =~ /^LaTeX Font Warning:\s*(.+)$/im
        body = Regexp.last_match(1)
        body = body.gsub(/not available\s*\(Font\)\s*/i, 'not available, ')
        body = body.gsub(/\(Font\)/i, ' ')
        body = strip_input_line_noise(body)
        return "Warning: [font] #{body}"
      end
      if str =~ /^LaTeX Warning:\s*(.+)$/i
        body = Regexp.last_match(1).gsub(/\s+/, ' ').strip
        if body =~ /Float too large for page by ([\d.]+)pt/i
          body = body.sub(/Float too large for page by ([\d.]+)pt/i) do
            "Float too large for page by #{format('%.2f', Regexp.last_match(1).to_f)}pt"
          end
        end
        body = strip_input_line_noise(body)
        return "Warning: #{body}"
      end

      str
    end

    def strip_input_line_noise(body)
      body = body.sub(/(?:,\s*)?on input line \d+(?:,\s*|\s+(?=[a-zA-Z]))/i, ' ')
      body = body.sub(/(?:,\s*)?on input line \d+\.?$/i, '')
      body.gsub(/\s+/, ' ').strip
    end

    def clean_ref_warning(str)
      if str =~ UNDEFINED_REFERENCE_WARNING
        key = Regexp.last_match(1)
        pg = Regexp.last_match(2)
        return pg ? "Warning: undefined reference '#{key}' (page #{pg})" : "Warning: undefined reference '#{key}'"
      end
      str
    end

    def clean_cite_warning(str)
      if str =~ /LaTeX Warning: Citation\s+[`'"](.+?)[`'"](?:\s+on page (\d+))?\s+undefined(?:\s+on input line \d+)?\.?/i
        key = Regexp.last_match(1)
        pg = Regexp.last_match(2)
        return pg ? "Warning: undefined citation '#{key}' (page #{pg})" : "Warning: undefined citation '#{key}'"
      end
      str
    end

    def warning_dedup_key(item)
      raw = item[:raw_text] || item[:text]
      if raw =~ /(?:Hyper reference|Reference)\s+[`'"](.+?)[`'"](?:\s+on page \d+)?\s+undefined/i
        [:undef_ref, item[:file], item[:line], Regexp.last_match(1)]
      else
        item[:text]
      end
    end

    def parse_package_warning(lines, i, file_stack)
      l = lines[i]
      return [nil, i + 1] if l.include?('multiply defined')

      warn_block = [l.strip]
      start_idx = i
      i += 1
      while i < lines.size && !diagnostic_boundary_line?(lines[i])
        warn_block << lines[i].strip
        i += 1
      end

      raw_warn_text = condense_package_warning(warn_block.join(' '))
      file_name, line_no, line_str = extract_warning_location(raw_warn_text, file_stack)
      warn_text = clean_diagnostic_warning(raw_warn_text)

      formatted = format_diagnostic_line(line_str, warn_text, :yellow, file: file_name)
      item = {
        type: :warn, file: file_name, line: line_no, line_str: line_str,
        text: warn_text, raw_text: raw_warn_text, base_color: :yellow, formatted: formatted, index: start_idx
      }
      [item, i]
    end

    def condense_package_warning(text)
      if text =~ /Package biblatex Warning: The following entr(?:y|ies) could not be found/i
        sub = text[/(?:in the database:)\s*(.*?)\s*(?:Please verify the spelling|$)/i, 1]
        if sub
          keys = sub.gsub(/\(biblatex\)/i, '').strip.gsub(/\s+/, ' ')
          return "Package biblatex Warning: Entry '#{keys}' not found in database."
        end
      end
      text
    end

    def extract_warning_location(warn_text, file_stack)
      clean = warn_text.gsub(/\([a-zA-Z0-9_-]+\)\s*/, '').gsub(/line (\d+)\s+(\d+)\b/, 'line \1\2')
      file_name = current_log_file(file_stack)
      line_no = 0
      line_str = ''

      if clean =~ /^([^\s:]+):(\d+):/
        file_name = Regexp.last_match(1)
        line_no = Regexp.last_match(2).to_i
        line_str = Regexp.last_match(2)
      elsif clean =~ /(?:at|on|in)?\s*(?:input\s+)?lines?\s*(\d+)/i || clean =~ /:(\d+):/
        line_no = Regexp.last_match(1).to_i
        line_str = Regexp.last_match(1)
      end
      [file_name, line_no, line_str]
    end

    def parse_box_line_span(box_line)
      match = box_line =~ /lines?\s+(\d+(?:--\d+)?)/i ? Regexp.last_match(1) : ''
      if match =~ /\A(\d+)--(\d+)\z/
        start_l = Regexp.last_match(1).to_i
        end_l = Regexp.last_match(2).to_i
        line_end = end_l > start_l ? end_l : nil
        line_str = line_end ? "#{start_l}\u{2026}" : start_l.to_s
        [start_l, line_str, line_end]
      else
        start_l = match[/^\d+/].to_i
        [start_l, start_l.positive? ? start_l.to_s : '', nil]
      end
    end

    # An overfull box while typesetting a bibliography entry reports the line of
    # the \\printbibliography call, not the entry. BIB_ENTRY markers name the entry,
    # so point the box at its position in the .bib file instead.
    def locate_bib_box(bib_key)
      return nil unless bib_key

      LaTeXBibLocator.locate(bib_key, nil, @bfilename, Dir.pwd, junk_dir: diagnostics_junk_dir)
    end

    def parse_box_warning(lines, i, file_stack, verbose, bib_key: nil)
      l = lines[i]
      start_idx = i
      box_type = l =~ /^(Overfull|Underfull) \\(hbox|vbox)/ ? "#{Regexp.last_match(1)} \\#{Regexp.last_match(2)}" : 'Overfull \\hbox'
      box_line = l.strip
      is_overfull = box_line.start_with?('Overfull')
      i += 1
      extra_lines = []
      while i < lines.size && !diagnostic_boundary_line?(lines[i]) && lines[i] !~ /^l\.\d+/
        extra_lines << lines[i].strip
        i += 1
      end

      line_no, line_str, line_end = parse_box_line_span(box_line)
      file_name = current_log_file(file_stack)
      severity = extract_box_severity(box_line)
      if (loc = locate_bib_box(bib_key))
        file_name = loc[:file]
        line_no = loc[:line]
        line_str = line_no.to_s
        line_end = nil
      end

      base_color = :yellow
      clean_text = if @options[:emacs]
                     box_line
                   else
                     clean_box_diagnostic(box_line, is_overfull ? :warning : :note)
                   end
      clean_text = "#{clean_text} [bib entry #{bib_key}]" if bib_key
      formatted = format_diagnostic_line(line_str, clean_text, base_color, file: file_name)
      if verbose && !extra_lines.empty?
        extra = extra_lines.map do |line|
          @options[:emacs] ? line : highlight_line_numbers(line, base_color, file: file_name)
        end
        formatted += "\n#{extra.join("\n")}"
      end

      item = {
        type: box_type, file: file_name, line: line_no, line_str: line_str, line_end: line_end,
        text: clean_text, raw_text: box_line, base_color: base_color, extra_lines: extra_lines,
        severity: severity, formatted: formatted, index: start_idx
      }
      [item, i]
    end

    def deduplicate_box_warnings(raw_warnings)
      filtered_warnings = []
      box_groups = {}
      raw_warnings.each do |w|
        if w[:type].is_a?(String) && w[:type] =~ /^(Overfull|Underfull)/ && !w[:line_str].empty?
          key = [w[:file], w[:type], w[:line_str]]
          box_groups[key] ||= []
          box_groups[key] << w
        else
          filtered_warnings << w
        end
      end

      box_groups.each_value { |items| filtered_warnings << items.max_by { |item| item[:severity] } }
      filtered_warnings
    end

    def extract_warnings(content, verbose: false)
      raw_warnings = []
      seen_warnings = {}
      lines = content.lines
      file_stack = [@filename]
      bib_key = nil
      bib_file = nil
      i = 0

      while i < lines.size
        l = lines[i]
        track_log_file(l, file_stack)

        if l =~ /^BIB_ENTRY:\s*(\S+)/
          bib_key = Regexp.last_match(1)
          bib_file = current_log_file(file_stack)
          i += 1
          next
        end
        bib_key = nil if bib_key && current_log_file(file_stack) != bib_file

        if l =~ WARNING_LINE_PATTERN
          item, i = parse_package_warning(lines, i, file_stack)
          if item
            d_key = warning_dedup_key(item)
            unless seen_warnings[d_key]
              seen_warnings[d_key] = true
              raw_warnings << item
            end
          end
        elsif l =~ /^(?:Overfull|Underfull) \\(?:hbox|vbox)/
          item, i = parse_box_warning(lines, i, file_stack, verbose, bib_key: bib_key)
          raw_warnings << item if item
        else
          i += 1
        end
      end

      deduplicate_box_warnings(raw_warnings)
    end

    def error_line_match(line)
      return [false, nil] if typeset_source_echo?(line)
      return [false, nil] if line =~ FATAL_ABORT_PATTERN

      if line =~ /^(.+?):(\d+):\s+(?!warning\b)(?!\(see\b)\S+/i
        [true, Regexp.last_match(1)]
      elsif line =~ /^!\s+\S+/ || line =~ /^Runaway argument\?/ || line =~ /^Error:\s+/i
        [true, nil]
      else
        [false, nil]
      end
    end

    def collect_error_block(lines, start_idx)
      err_block = [lines[start_idx]]
      missing_file = lines[start_idx].match?(/File `?[^']+'? not found/i)
      block_limit = missing_file ? 14 : 6
      i = start_idx + 1
      while i < lines.size && err_block.size < block_limit
        curr = lines[i]
        break if curr =~ FATAL_ABORT_PATTERN ||
                 (curr =~ /^.+:\d+:\s+(?!warning\b)/i && !missing_file_location?(curr, missing_file)) ||
                 curr =~ /^!\s+\S+/ || curr =~ /^Runaway argument\?/ ||
                 curr =~ WARNING_LINE_PATTERN ||
                 curr =~ /^(?:Overfull|Underfull) \\(?:hbox|vbox)/ ||
                 curr =~ /^\s*\)/ || curr =~ %r{^\s*\((?:\.[\\/]|[a-zA-Z0-9_\-./]+?\.(?:tex|sty|cls|aux|bbl|bib))}

        err_block << curr
        i += 1
        break if curr =~ /^l\.\d+/
      end
      [err_block, i]
    end

    def missing_file_location?(line, missing_file)
      missing_file && line.match?(FATAL_ABORT_PATTERN)
    end

    def extract_argument_token(err_block)
      arg_lines = []
      in_arg = false
      err_block.each do |line|
        if line =~ /^<argument>\s*(.*)/
          in_arg = true
          arg_lines << Regexp.last_match(1)
        elsif in_arg
          break if line =~ /^l\.\d+/ || line =~ /^<\w+>/

          arg_lines << line
        end
      end
      return nil if arg_lines.empty?

      token = arg_lines.join.gsub(/\s+/, '').gsub(/[{}\\]/, '')
      token.empty? ? nil : token
    end

    def extract_errors(content)
      errors = []
      clean_content = LaTeXUtils.filter_subcommand_noise(content)
      lines = clean_content.lines
      file_stack = [@filename]
      last_bib_entry_key = nil
      last_bib_entry_file = nil
      i = 0

      while i < lines.size
        line = lines[i]
        track_log_file(line, file_stack)

        if line =~ /^BIB_ENTRY:\s*(\S+)/
          last_bib_entry_key = Regexp.last_match(1)
          last_bib_entry_file = current_log_file(file_stack)
          i += 1
          next
        end

        if line =~ FATAL_ABORT_PATTERN
          i += 1
          next
        end

        is_err, err_file = error_line_match(line)
        if is_err
          cur_file = err_file || current_log_file(file_stack)
          bib_key = last_bib_entry_file == cur_file ? last_bib_entry_key : nil
          err_item, i = build_error_entry(lines, i, err_file, file_stack, bib_entry: bib_key)
          errors << err_item
        else
          i += 1
        end
      end
      errors
    end

    def build_error_entry(lines, idx, err_file, file_stack = [], bib_entry: nil)
      err_block, next_idx = collect_error_block(lines, idx)
      err_block = err_block.map(&:rstrip).reject(&:empty?)
      err_text = err_block.join("\n")
      line_no = extract_error_line(err_text)
      file_name = err_file || current_log_file(file_stack)
      classification = LaTeXErrorCatalog.classify(
        err_text, err_block, file: file_name, line: line_no, junk_dir: diagnostics_junk_dir
      )
      source_location = locate_error_source(classification, err_text)
      if source_location
        file_name, line_no = source_location
        classification = LaTeXErrorCatalog.classify(
          err_text, err_block, file: file_name, line: line_no, junk_dir: diagnostics_junk_dir
        )
      end
      cat_id = classification ? classification[:id] : :generic
      token = if cat_id == :undefined_control_sequence && classification&.[](:token)
                classification[:token]
              else
                extract_argument_token(err_block) || classification&.[](:token)
              end
      token = nil if token.to_s.match?(/\s/)
      root_l = classification ? classification[:root_line] : nil
      root_c = classification ? classification[:root_col] : nil

      item = {
        file: file_name, line: line_no, line_str: (line_no.positive? ? line_no.to_s : ''),
        root_line: root_l, root_col: root_c,
        text: err_text, err_block: err_block, base_color: :red, index: next_idx,
        catalog: classification, catalog_id: cat_id,
        source: :compiler, synthetic: false,
        bib_entry: bib_entry, token: token
      }
      item[:formatted] = format_error_block(err_block, line_no, catalog: classification, item: item)
      [item, next_idx]
    end

    # TeX attributes some errors to no source position (a missing file, a glyph
    # the font lacks); the position is recovered from the source tree instead.
    def locate_error_source(classification, err_text = '')
      case classification&.[](:id)
      when :file_not_found, :include_target_missing
        locate_missing_resource_request(classification[:token])
      when :missing_character
        locate_missing_character(classification[:token])
      when :pdf_driver_image_failed
        locate_image_request(classification[:token], err_text[/include page (\d+) of image/, 1])
      end
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
      stem = resource.to_s.sub(/\.(?:tex|sty|cls|bib)\z/i, '')
      return nil if stem.empty?

      pattern = /
        \\(?:input|include|usepackage|RequirePackage|includegraphics|bibliography|addbibresource)\s*
        (?:\[[^\]]*\])?\s*\{[^}]*#{Regexp.escape(stem)}[^}]*\}
      /x
      collect_source_candidates.each do |file|
        LaTeXUtils.safe_read(file).each_line.with_index(1) do |line, line_no|
          return [file, line_no] if LaTeXUtils.strip_latex_comments(line).match?(pattern)
        end
      end
      nil
    end

    def generate_bib_companions(errors)
      companions = []
      seen = {}

      errors.each do |err|
        next unless err[:bib_entry] && !err[:synthetic]

        is_bib_cmd = err[:text] =~ /\\(?:ChapterEnd|printbibliography|bibliography|putbib|bibitem)\b/ ||
                     err[:file].to_s.end_with?('.bbl')
        next unless is_bib_cmd || err[:token]

        loc = LaTeXBibLocator.locate(err[:bib_entry], err[:token], @bfilename, Dir.pwd,
                                     junk_dir: diagnostics_junk_dir)
        next unless loc

        loc_key = [loc[:file], loc[:line]]
        next if seen[loc_key]

        seen[loc_key] = true
        companions << build_bib_companion_item(err, loc)
      end
      filter_redundant_bib_companions(companions)
    end

    def filter_redundant_bib_companions(companions)
      grouped = companions.group_by { |c| [c[:file], c[:citekey]] }
      result = []
      grouped.each_value do |entry_comps|
        has_token = entry_comps.any? { |c| c[:token] }
        entry_comps.each do |c|
          result << c unless has_token && c[:token].nil?
        end
      end
      result
    end

    def build_bib_companion_item(parent_err, loc)
      file_name = loc[:file]
      line_no = loc[:line]
      citekey = loc[:citekey]
      token = loc[:token]
      field_text = loc[:field_text]

      display_file = format_display_path(file_name)
      first_line = "#{display_file}:#{line_no}: [leeni] Bibliography error in entry '#{citekey}'"
      lines = [first_line]
      lines << (field_text ? "l.#{line_no} #{field_text}" : "l.#{line_no}")

      hint = token ? "Offending token '#{token}' found on this line." : 'Entry typeset here when compilation failed.'
      item = {
        file: file_name,
        line: line_no,
        line_str: line_no.to_s,
        text: lines.join("\n"),
        err_block: lines,
        base_color: :red,
        index: (parent_err[:index] || 0) + 1,
        catalog: { hint: hint },
        source: :leeni,
        synthetic: true,
        companion_to: format_display_path(parent_err[:file]),
        citekey: citekey,
        token: token
      }
      item[:formatted] = format_error_block(lines, line_no, catalog: { hint: hint }, item: item)
      item
    end

    def decluster_errors(errors)
      return errors if errors.size <= 1

      grouped = errors.group_by do |e|
        sig = e[:text].to_s.gsub(/\s+/, ' ').strip
        [format_display_path(e[:file]), e[:line] || 0, sig]
      end

      clustered = []
      grouped.each_value do |group|
        first = group.first
        if group.size > 1
          item = first.dup
          item[:repeat_count] = group.size
          item[:formatted] = format_error_block(
            first[:err_block], first[:line] || 0,
            catalog: first[:catalog], repeat_count: group.size,
            item: first
          )
          item[:err_block] = first[:err_block] + ["  (Repeated #{group.size} times on line #{first[:line]})"] if @options[:emacs]
          clustered << item
        else
          clustered << first
        end
      end
      clustered
    end

    def prepare_error_items(raw_items)
      bib_companions = generate_bib_companions(raw_items)
      items = decluster_errors(raw_items) + bib_companions
      items.each { |i| i[:tier] = 'errors' }
      flag_unregenerable_bbl(items.first) if respond_to?(:flag_unregenerable_bbl, true)
      items
    end
  end
end
