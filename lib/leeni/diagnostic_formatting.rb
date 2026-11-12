# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostic_formatting.rb
#
# Terminal rendering of diagnostics: links, colors, tier badges, error blocks and source snippets.
# Part of LaTeXDiagnostics (lib/leeni/diagnostics.rb), which includes it.
# ==============================================================================

module LaTeXDiagnostics
  # Terminal rendering of diagnostics: links, colors, tier badges, error blocks and source snippets.
  module Formatting
    def colorize_line_num(str, _base_color = nil)
      return str if @options[:emacs]

      Rainbow(str).cyan.bright.to_s
    end

    def link_enabled?
      @options && @options[:link] == true && !@options[:emacs]
    end

    def show_tier_badges?
      return false if @options.nil?
      return false if @options[:emacs] || compile_mode? || @options[:vscode_lw] || @options[:json]
      return false if @options[:badges] == false

      true
    end

    def format_terminal_link(file, line_str, display_str, underline: false, color: nil)
      return display_str unless link_enabled? && file && !file.to_s.empty?

      target_line = line_str.to_s[/^\d+/] || '1'
      real_file = LaTeXErrorCatalog.find_source_file(file) || file
      return display_str unless File.exist?(real_file)

      abs_path = ::URI::DEFAULT_PARSER.escape(File.expand_path(real_file.to_s))
      uri = "file://#{abs_path}##{target_line}"
      styled = display_str
      if @options[:color] != false
        styled = Rainbow(styled).send(color).bright.to_s if color && defined?(Rainbow)
        styled = "\e[4m#{styled}\e[24m" if underline
      end
      "\e]8;;#{uri}\e\\#{styled}\e]8;;\e\\"
    end

    UNDERFULL_GUIDE_URL = 'https://sarielhp.github.io/leeni/docs/guides/underfull_boxes/'

    def format_terminal_url(url, display_str, underline: false, color: nil)
      return display_str unless link_enabled? && url && !url.to_s.empty?

      styled = display_str
      if @options[:color] != false
        styled = Rainbow(styled).send(color).bright.to_s if color && defined?(Rainbow)
        styled = "\e[4m#{styled}\e[24m" if underline
      end
      "\e]8;;#{url}\e\\#{styled}\e]8;;\e\\"
    end

    OSC8_LINK_PATTERN = /(\e\]8;;[^\e]*\e\\.*?\e\]8;;\e\\)/

    def highlight_line_numbers(text, base_color, bright: false, file: nil)
      return text if @options[:emacs]
      return text if @options && @options[:color] == false

      if text.include?("\e]8;;")
        return text.split(OSC8_LINK_PATTERN).map do |segment|
          if segment.start_with?("\e]8;;")
            segment
          else
            highlight_line_numbers_segment(segment, base_color, bright: bright, file: file)
          end
        end.join
      end

      highlight_line_numbers_segment(text, base_color, bright: bright, file: file)
    end

    def highlight_line_numbers_segment(text, base_color, bright: false, file: nil)
      return '' if text.empty?

      pattern = /((?:input\s+)?lines?\s+)(\d+(?:--?\d+)?)|(\bl\.)(\d+)\b|(:)(\d+)(:)/i
      parts = []
      last_pos = 0

      num = lambda do |digits|
        styled = colorize_line_num(digits, base_color)
        file ? format_terminal_link(file, digits, styled) : styled
      end

      apply_base = lambda do |str|
        r = Rainbow(str).send(base_color)
        bright ? r.bright.to_s : r.to_s
      end

      text.scan(pattern) do
        m = Regexp.last_match
        parts << apply_base.call(text[last_pos...m.begin(0)]) if m.begin(0) > last_pos

        if m[1]
          parts << apply_base.call(m[1]) << num.call(m[2])
        elsif m[3]
          parts << apply_base.call(m[3]) << num.call(m[4])
        elsif m[5]
          parts << apply_base.call(m[5]) << num.call(m[6]) << apply_base.call(m[7])
        end
        last_pos = m.end(0)
      end

      parts << apply_base.call(text[last_pos..]) if last_pos < text.length
      parts.join
    end

    def format_emacs_diagnostic_line(line_str, message)
      return message if message =~ WARNING_LINE_PATTERN ||
                        message =~ /^(?:Overfull|Underfull)\s+\\(?:hbox|vbox)/ ||
                        message =~ /^.+:\d+:\s+/

      str = line_str.to_s
      return "LaTeX Warning: #{message.chomp('.')} on input line #{str}." unless str.empty?

      "LaTeX Warning: #{message}"
    end

    def format_diagnostic_left_side(line_str, base_color, width, bright_sep, file)
      str = line_str.to_s
      sep = Rainbow(': ').send(base_color)
      sep_str = bright_sep ? sep.bright.to_s : sep.to_s

      if str.empty?
        tag = ['bibliography', './bibliography'].include?(file) ? 'bib' : ''
        return "#{' ' * width}#{sep_str}" if tag.empty?

        padding = ' ' * [width - tag.length, 0].max
        tag_str = colorize_line_num(tag, base_color)
        return "#{padding}#{tag_str}#{sep_str}" unless link_enabled? && file && !file.to_s.empty?

        colon = bright_sep ? Rainbow(':').send(base_color).bright.to_s : Rainbow(':').send(base_color).to_s
        "#{padding}#{format_terminal_link(file, '1', "#{tag_str}#{colon}")} "
      else
        padding = ' ' * [width - str.length, 0].max
        col_num = colorize_line_num(str, base_color)
        return "#{padding}#{col_num}#{sep_str}" unless link_enabled? && file && !file.to_s.empty?

        colon = bright_sep ? Rainbow(':').send(base_color).bright.to_s : Rainbow(':').send(base_color).to_s
        "#{padding}#{format_terminal_link(file, str, "#{col_num}#{colon}")} "
      end
    end

    def diagnostic_tier_badge(tier, base_color = nil)
      return nil unless show_tier_badges?

      effective_tier = tier&.to_s
      effective_tier ||= case base_color
                         when :red then 'alerts'
                         when :cyan then 'whatevers'
                         else 'warnings'
                         end

      case effective_tier
      when 'alerts'    then '🚨 '
      when 'whatevers' then '☕ '
      when 'errors'    then '🛑 '
      else                  '❕ '
      end
    end

    def clean_diagnostic_badge_message(message)
      str = message.to_s
      cleaned = str.sub(/\A(?:Alert|Warning|Note|Whatever|Info)(?::|--)\s*/i, '').strip
      cleaned.empty? ? str : cleaned
    end

    def wrap_diagnostic_message(full_prefix, sub_indent, formatted_msg, term_width)
      return "#{full_prefix}#{formatted_msg}" if @options && @options[:no_wrap]

      lines = formatted_msg.to_s.split("\n", -1)
      return full_prefix if lines.empty?

      lines.each_with_index.map do |line, idx|
        pfx = idx.zero? ? full_prefix : sub_indent
        if line.strip.empty?
          pfx.rstrip
        else
          LaTeXUtils.wrap_single_line("#{pfx}#{line.strip}", width: term_width, prefix: pfx, indent: sub_indent)
        end
      end.join("\n")
    end

    def format_diagnostic_line(line_str, message, base_color, width: 0, bright_sep: true, file: nil, tier: nil)
      return format_emacs_diagnostic_line(line_str, message) if @options && @options[:emacs]

      left_side = format_diagnostic_left_side(line_str, base_color, width, bright_sep, file)
      badge = diagnostic_tier_badge(tier, base_color)
      clean_msg = badge ? clean_diagnostic_badge_message(message) : message

      full_prefix = badge ? "#{left_side}#{badge}" : left_side
      prefix_width = LaTeXUtils.visible_width(full_prefix)
      sub_indent = ' ' * prefix_width

      term_width = terminal_columns
      formatted_msg = highlight_line_numbers(clean_msg, base_color, file: file)
      formatted_msg = highlight_leeni_tag(formatted_msg, base_color)

      wrap_diagnostic_message(full_prefix, sub_indent, formatted_msg, term_width)
    end

    def highlight_leeni_tag(str, base_color = :red)
      return str if @options[:emacs] || @options[:color] == false
      return str unless str.include?('[leeni]')

      tag = Rainbow('[leeni]').magenta.bold.to_s
      parts = str.split('[leeni]', -1)
      return str if parts.size <= 1

      first = parts[0]
      rest = parts[1..].map do |part|
        part.empty? ? '' : Rainbow(part).send(base_color).to_s
      end
      "#{first}#{tag}#{rest.join(tag)}"
    end

    def format_error_block(err_block, line_no, width: 0, catalog: nil, repeat_count: 1, item: nil)
      cat = catalog || item&.[](:catalog)
      return format_emacs_error_block(err_block, catalog: cat) if @options[:emacs]

      indent = ' ' * (width.positive? ? width + 2 : 2)
      file_path = item&.[](:file) || @filename
      root_line = item&.[](:root_line) || cat&.[](:root_line)
      root_col = item&.[](:col) || item&.[](:root_col) || cat&.[](:root_col)

      header = format_error_header(err_block.first, file_path, line_no, root_line, root_col, width)
      lines = [header]

      active_line = root_line&.positive? ? root_line : line_no
      source_frame = format_source_frame(file_path, active_line, root_col, item, cat)
      if source_frame
        lines.concat(source_frame)
      else
        append_error_hint(lines, cat, indent)
      end
      append_error_hint(lines, { hint: cat[:note] }, indent) if cat&.[](:note)

      append_repeat_note(lines, repeat_count, line_no, indent) if repeat_count > 1

      append_verbose_error_context(lines, err_block, indent, file_path) if @options[:verbose]

      lines.join("\n")
    end

    def format_emacs_error_block(err_block, catalog: nil)
      lines = err_block.dup
      if (idx = lines.rindex { |l| l =~ /^l\.\d+/ })
        lines.insert(idx + 1, ' ')
      end
      lines << catalog[:hint] if catalog && catalog[:hint]
      lines.join("\n")
    end

    def format_error_header(first_raw_line, file_path, line_no, root_line, root_col, _width = nil)
      first_clean = first_raw_line.to_s.strip
      msg = extract_clean_error_message(first_clean)
      active_line = root_line&.positive? ? root_line : line_no
      reported_line = root_line&.positive? && root_line != line_no ? line_no : nil

      disp_file = format_display_path(file_path)
      badge = diagnostic_tier_badge('errors', :red)
      clean_msg = badge ? clean_diagnostic_badge_message(msg) : msg

      header_text = if active_line&.positive?
                      col_str = root_col ? ":#{root_col}" : ''
                      rep_str = reported_line ? " (reported on line #{reported_line})" : ''
                      "#{disp_file}:#{active_line}#{col_str}: #{badge}#{clean_msg}#{rep_str}"
                    else
                      "#{disp_file}: #{badge}#{clean_msg}"
                    end

      colored = highlight_line_numbers(header_text, :red, bright: true, file: file_path)
      highlight_leeni_tag(colored, :red)
    end

    def extract_clean_error_message(line)
      return Regexp.last_match(1).strip if line =~ /^!\s*\[leeni\]\s*(.*)/
      return Regexp.last_match(1).strip if line =~ /^.+?:\d+:\s*(.*)/
      return Regexp.last_match(1).strip if line =~ /^!\s*(.*)/

      line
    end

    def read_source_line(file_path, line_no)
      real_file = LaTeXErrorCatalog.find_source_file(file_path) || file_path
      return nil unless real_file && File.file?(real_file)

      lines = LaTeXUtils.safe_read(real_file).lines
      idx = line_no - 1
      return nil if idx.negative? || idx >= lines.size

      lines[idx].to_s.chomp
    rescue StandardError
      nil
    end

    def locate_token_column(source_line, col_no, token, catalog)
      cat_id = catalog&.[](:id)
      clean_token = token && !token.to_s.match?(/\s/) ? token.to_s : nil

      if col_no&.positive?
        col_idx = col_no - 1
        is_single_char_cat = %i[missing_dollar misplaced_alignment_tab extra_closing_brace].include?(cat_id)
        len = if !is_single_char_cat && (source_line[col_idx..] =~ /\A(\\[a-zA-Z@]+|\\[^\s])/)
                Regexp.last_match(1).length
              elsif !is_single_char_cat && clean_token
                clean_token.length
              else
                1
              end
        [col_idx, len]
      elsif clean_token && (idx = source_line.index(clean_token))
        [idx, clean_token.length]
      elsif (cat_id == :misplaced_alignment_tab && (idx = source_line.index(/(?<!\\)&/))) ||
            (cat_id == :missing_dollar && (idx = source_line.index(/(?<!\\)\$/)))
        [idx, 1]
      else
        [nil, 1]
      end
    end

    def window_source_line(source_line, col_pos)
      return [source_line, col_pos] if source_line.length <= 70

      if col_pos
        start_char = [col_pos - 25, 0].max
        prefix = start_char.positive? ? '...' : ''
        sub = source_line[start_char, 65] || ''
        suffix = start_char + 65 < source_line.length ? '...' : ''
        adj_col = col_pos - start_char + prefix.length
        ["#{prefix}#{sub}#{suffix}", adj_col]
      else
        ["#{source_line[0, 67]}...", nil]
      end
    end

    def render_source_code_line(line_no, display_line, col_pos = nil, token_len = nil)
      gutter_num = line_no.to_s.rjust(3)
      num_colored = @options && @options[:color] == false ? gutter_num : Rainbow(gutter_num).cyan
      gutter_bar = @options && @options[:color] == false ? '|' : Rainbow('|').cyan
      code_text = highlight_error_token(display_line, col_pos, token_len)
      "  #{num_colored} #{gutter_bar} #{code_text}"
    end

    def highlight_error_token(line, col_pos, token_len)
      return line if @options && @options[:color] == false
      return line unless col_pos && token_len&.positive?
      return line if col_pos.negative? || col_pos + token_len > line.length

      prefix = line[0...col_pos]
      target = line[col_pos, token_len]
      suffix = line[(col_pos + token_len)..]
      "#{prefix}#{Rainbow(target).red.bright.bold}#{suffix}"
    end

    def render_gutter_hint(gutter_num_len, catalog)
      return nil unless catalog && catalog[:hint]

      hint_colored = colorize_inline_hint(catalog[:hint]).strip
      arrow = @options && @options[:color] == false ? '▸' : Rainbow('▸').cyan.bright
      label = @options && @options[:color] == false ? 'Hint: ' : Rainbow('Hint: ').cyan
      "  #{' ' * (gutter_num_len + 2)}#{arrow} #{label}#{hint_colored}"
    end

    def render_context_snippet(file_path, target_line, context_lines, col_pos: nil, token_len: nil, catalog: nil, root_col: nil,
                               target_line_end: nil, force: false)
      return [] unless file_path && target_line&.positive? && context_lines&.positive?

      real_file = LaTeXErrorCatalog.find_source_file(file_path) || file_path
      return [] unless real_file && File.file?(real_file)

      all_raw_lines = begin
        File.readlines(real_file)
      rescue StandardError
        nil
      end
      return [] unless all_raw_lines && !all_raw_lines.empty?

      target_end = target_line_end && target_line_end.to_i >= target_line ? target_line_end.to_i : target_line
      return [] if context_range_covered?(real_file, target_line, target_end, force)

      start_line = [target_line - context_lines, 1].max
      end_line = [target_end + context_lines, all_raw_lines.size].min
      return [] if start_line > end_line

      color_enabled = @options && @options[:color] != false && !@options[:emacs]
      code_lines = fetch_snippet_code_lines(real_file, start_line, end_line, all_raw_lines, color_enabled)
      build_snippet_lines(
        code_lines, start_line, target_line, target_end, end_line,
        real_file: real_file, color_enabled: color_enabled, col_pos: col_pos,
        token_len: token_len, catalog: catalog, root_col: root_col
      )
    end

    def context_range_covered?(real_file, target_line, target_end, force)
      return false if force

      @last_context_file == real_file && @last_context_range&.cover?(target_line) && @last_context_range.cover?(target_end)
    end

    def fetch_snippet_code_lines(real_file, start_line, end_line, all_raw_lines, color_enabled)
      bat_lines = fetch_bat_snippet_lines(real_file, start_line, end_line) if color_enabled && @options && @options[:bat]
      return bat_lines if bat_lines

      raw_slice = all_raw_lines[(start_line - 1)..(end_line - 1)] || []
      raw_slice.map { |ln| LatexColor.highlight_latex(ln, color_enabled: color_enabled) }
    end

    def fetch_bat_snippet_lines(real_file, start_line, end_line)
      bat_cmd = resolve_bat_command
      return nil unless bat_cmd

      cmd = [bat_cmd, '--color=always', '--paging=never', '--style=plain', '-l', 'tex', "-r=#{start_line}:#{end_line}", real_file]
      out, _, st = begin
        Open3.capture3(*cmd)
      rescue StandardError
        nil
      end
      st&.success? && out && !out.empty? ? out.lines : nil
    end

    def resolve_bat_command
      return 'batcat' if LaTeXUtils.command_available?('batcat')
      return 'bat' if LaTeXUtils.command_available?('bat')

      nil
    end

    def format_snippet_line_gutter(cur_line, g_len, is_target, color_enabled, links_active, abs_path)
      marker = if is_target
                 color_enabled ? Rainbow('>').red.bright.to_s : '>'
               else
                 ' '
               end
      num_str = cur_line.to_s.rjust(g_len)
      link_num = if color_enabled
                   styled = is_target ? Rainbow(num_str).red.bright.to_s : Rainbow(num_str).cyan.to_s
                   links_active ? "\e]8;;file://#{abs_path}##{cur_line}\e\\#{styled}\e]8;;\e\\" : styled
                 else
                   num_str
                 end
      bar = if color_enabled
              is_target ? Rainbow('│').red.bright.to_s : Rainbow('│').cyan.to_s
            else
              '|'
            end
      "#{marker} #{link_num} #{bar}"
    end

    def append_snippet_pointer_or_hint(lines, g_len, col_pos, token_len, catalog, root_col)
      if col_pos
        pointer_line = render_pointer_line(g_len, col_pos, token_len, catalog, root_col: root_col)
        lines << pointer_line if pointer_line
      elsif (hint_line = render_gutter_hint(g_len, catalog))
        lines << hint_line
      end
    end

    def build_snippet_lines(code_lines, start_line, target_line, target_end, end_line, real_file:, color_enabled:, col_pos:, token_len:,
                            catalog:, root_col:)
      abs_path = ::URI::DEFAULT_PARSER.escape(File.expand_path(real_file.to_s))
      g_len = [end_line.to_s.length, 3].max
      links_active = color_enabled && (@options.nil? || @options[:link] != false)
      lines = []

      code_lines.each_with_index do |cline, idx|
        cur_line = start_line + idx
        is_target = cur_line.between?(target_line, target_end)
        gutter = format_snippet_line_gutter(cur_line, g_len, is_target, color_enabled, links_active, abs_path)
        lines << "#{gutter} #{cline.chomp}"
        append_snippet_pointer_or_hint(lines, g_len, col_pos, token_len, catalog, root_col) if cur_line == target_line
      end

      @last_context_file = real_file
      @last_context_range = (target_line..target_end)
      lines
    end

    def format_source_frame(file_path, line_no, col_no, item, catalog)
      return nil unless line_no&.positive?

      if @options && @options[:context_lines]&.to_i&.positive?
        token = item&.[](:token) || catalog&.[](:token)
        source_line = read_source_line(file_path, line_no)
        col_pos, token_len = source_line ? locate_token_column(source_line, col_no, token, catalog) : [nil, 1]
        return render_context_snippet(file_path, line_no, @options[:context_lines].to_i,
                                      col_pos: col_pos, token_len: token_len, catalog: catalog, root_col: col_no)
      end

      source_line = read_source_line(file_path, line_no)
      return nil unless source_line && !source_line.strip.empty?

      token = item&.[](:token) || catalog&.[](:token)
      col_pos, token_len = locate_token_column(source_line, col_no, token, catalog)
      display_line, adjusted_col = window_source_line(source_line, col_pos)

      lines = [render_source_code_line(line_no, display_line, adjusted_col, token_len)]
      g_len = [line_no.to_s.length, 3].max

      if adjusted_col
        pointer_line = render_pointer_line(g_len, adjusted_col, token_len, catalog, root_col: col_no)
        lines << pointer_line if pointer_line
      elsif (hint_line = render_gutter_hint(g_len, catalog))
        lines << hint_line
      end
      lines
    end

    def render_pointer_line(gutter_num_len, col_pos, token_len, catalog, root_col: nil)
      caret_len = [token_len || 1, 1].max
      caret = '^' * caret_len
      caret_colored = @options && @options[:color] == false ? caret : Rainbow(caret).red.bright.bold

      hint_msg = inline_hint_text(catalog, root_col)
      hint_colored = colorize_inline_hint(hint_msg)

      indent = ' ' * 2
      gutter_pad = ' ' * gutter_num_len
      gutter_bar = @options && @options[:color] == false ? '|' : Rainbow('│').cyan
      col_pad = ' ' * [col_pos, 0].max

      "#{indent}#{gutter_pad} #{gutter_bar} #{col_pad}#{caret_colored}#{hint_colored}"
    end

    def colorize_inline_hint(hint_msg)
      return '' unless hint_msg
      return " #{hint_msg}" if @options && @options[:color] == false

      if hint_msg =~ /\ADid you mean '([^']+)'(.*)\z/
        fix = Regexp.last_match(1)
        suffix = Regexp.last_match(2)
        " #{Rainbow('Did you mean ').cyan}#{Rainbow("'#{fix}'").green.bright.bold}#{Rainbow(suffix).cyan}"
      elsif hint_msg =~ /\A(Undefined (?:command|environment|setup key|color|counter)) '([^']+)'(.*)\z/
        prefix = Regexp.last_match(1)
        bad = Regexp.last_match(2)
        suffix = Regexp.last_match(3)
        " #{Rainbow("#{prefix} ").cyan}#{Rainbow("'#{bad}'").red.bright.bold}#{Rainbow(suffix).cyan}"
      else
        Rainbow(" #{hint_msg}").cyan
      end
    end

    def inline_hint_text(catalog, root_col)
      return nil unless catalog

      case catalog[:id]
      when :missing_dollar
        root_col ? "math mode opened here; insert closing '$'" : "insert closing '$'"
      else
        catalog[:hint]
      end
    end

    def append_verbose_error_context(lines, err_block, indent, file = nil)
      raw_lines = err_block[1..] || []
      return if raw_lines.empty?

      tag = @options && @options[:color] == false ? '[TeX context]' : Rainbow('[TeX context]').yellow.faint
      lines << "#{indent}#{tag}"
      raw_lines.each do |l|
        next if l.strip.empty?

        lines << "#{indent}  #{highlight_line_numbers(l, :red, file: file)}"
      end
    end

    def append_repeat_note(lines, repeat_count, line_no, indent)
      note = "Repeated #{repeat_count} times on line #{line_no}."
      note_colored = @options[:color] == false ? note : Rainbow(note).yellow
      arrow = @options[:color] == false ? '▸' : Rainbow('▸').yellow.bright
      lines << "#{indent}#{arrow} #{note_colored}"
    end

    def append_error_hint(lines, catalog, indent)
      return unless catalog && catalog[:hint]

      hint_text = "Hint: #{catalog[:hint]}"
      hint_colored = @options[:color] == false ? hint_text : Rainbow(hint_text).cyan
      arrow = @options[:color] == false ? '▸' : Rainbow('▸').cyan.bright
      lines << "#{indent}#{arrow} #{hint_colored}"
    end

    def format_diagnostic_item_text(item)
      text = item[:text].to_s
      return text unless link_enabled?

      if underfull_box?(item)
        text.sub(/\bunderfull\s+(?:\\hbox|line|box)\b/i) { |m| format_terminal_url(UNDERFULL_GUIDE_URL, m) }
            .sub(/\bunderfull\s+(?:\\vbox|page|column)\b/i) { |m| format_terminal_url(UNDERFULL_GUIDE_URL, m) }
      else
        text
      end
    end

    def render_diagnostic_item(item, width: 0)
      if item[:err_block]
        return format_error_block(item[:err_block], item[:line] || 0, width: width, catalog: item[:catalog],
                                                                      repeat_count: item[:repeat_count] || 1, item: item)
      end

      base_color = item[:base_color] || :yellow
      tier = tier_label_for(item)
      display_text = format_diagnostic_item_text(item)
      out = format_diagnostic_line(item[:line_str], display_text, base_color, width: width, file: item[:file], tier: tier)
      out += append_diagnostic_verbose_lines(item, width: width, base_color: base_color)
      out += append_diagnostic_item_context(item)
      out
    end

    def append_diagnostic_verbose_lines(item, width:, base_color:)
      return '' unless @options[:verbose] && item[:extra_lines] && !item[:extra_lines].empty?

      badge_len = show_tier_badges? ? 3 : 0
      indent = ' ' * (width.positive? ? width + 2 + badge_len : 2 + badge_len)
      formatted = item[:extra_lines].map do |el|
        @options[:emacs] ? el : "#{indent}#{highlight_line_numbers(el, base_color, file: item[:file])}"
      end
      "\n#{formatted.join("\n")}"
    end

    def append_diagnostic_item_context(item)
      return '' unless @options && @options[:context_lines].to_i.positive?

      line = item[:line].to_i
      return '' unless line.positive?

      file_path = item[:file] || @filename
      target_end = item[:line_end] || (item[:line_str].to_s =~ /\A(\d+)--(\d+)\z/ ? Regexp.last_match(2).to_i : nil)
      snippet_lines = render_context_snippet(file_path, line, @options[:context_lines].to_i, target_line_end: target_end)
      snippet_lines.empty? ? '' : "\n#{snippet_lines.join("\n")}"
    end
  end
end
