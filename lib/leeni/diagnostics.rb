# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostics.rb
#
# LaTeX compilation log diagnostic analysis, AUCTeX error extraction,
# 4-tier categorization (Errors, Alerts, Warnings, Whatevers), and scoring.
# ==============================================================================

require_relative 'error_catalog'
require_relative 'compile_format'

module LaTeXDiagnostics
  DIAGNOSTIC_EXPLANATIONS = LaTeXErrorCatalog::WARNING_EXPLANATIONS

  LOG_FILE_EXTENSIONS = %w[
    tex sty cls aux bbl bib dtx def ldf cfg clo toc lof lot png pdf jpg eps fd fontspec out idx code\.tex
  ].join('|').freeze

  LOG_FILE_PATTERN = %r{\A\((?:"([^"]+)"|((?:\.{1,2}[\\/][^\s()]+|[a-zA-Z0-9_\-./]+?\.(?:#{LOG_FILE_EXTENSIONS}))\b))}.freeze

  # One canonical recogniser for a LaTeX/package/class warning header. Five
  # near-but-not-equal variants of this used to be spelled out inline, and the
  # two that mattered most used a package-name class of [-A-Za-z0-9], which
  # excludes '.'. That made `Package pdftex.def Warning:` neither a warning
  # start nor a block boundary, so it was appended to the preceding warning's
  # text -- and when that predecessor was a Whatever, a real warning vanished
  # into a tier suppressed by default. luatex.def, xetex.def, dvips.def and
  # epstopdf-base all shared the fate.
  WARNING_LINE_PATTERN = /^(?:LaTeX|Class|Package|\*)(?:\s+[-\w.@*]+)*\s+[Ww]arning:/.freeze

  # Every pattern here must be anchored. TeX echoes the offending paragraph
  # after each Overfull \hbox, so the document's own prose reaches this log
  # verbatim: an unanchored `include?('Error:')` made a paper that discusses
  # error messages fail its own successful build, and the abort happens before
  # the PDF is copied out of junk/, so the user got no output and no
  # explanation. 'WARN - ' was dropped entirely -- that is biber's output
  # format, which never appears in a LaTeX terminal log.
  def count_errors_in_log(st, loga)
    raw = LaTeXUtils.safe_read(loga)
    content = LaTeXUtils.filter_subcommand_noise(raw)

    errcnt = content.each_line.count { |l| latex_error_line?(l) }
    errcnt + st
  end

  def latex_error_line?(line)
    return false if typeset_source_echo?(line)

    line.match?(/^!\s+\S/) ||
      line.match?(/^Runaway argument\?/) ||
      line.match?(/^Error:\s/i) ||
      line.match?(/^.+?:\d+:\s+(?!warning\b)(?!\(see\b)\S/i)
  end

  def typeset_source_echo?(line)
    line.match?(/^\s*\\[A-Z][A-Z0-9]*\/\S+\s/)
  end

  def extract_error_line(err_text)
    clean = err_text.gsub(/\([a-zA-Z0-9_\-]+\)\s*/, '')
    if clean =~ /:(\d+):/ || clean =~ /\bl\.(\d+)\b/ || clean =~ /(?:at|on|in)?\s*(?:input\s+)?lines?\s*(\d+)/i
      Regexp.last_match(1).to_i
    else
      0
    end
  end

  def extract_box_severity(box_line)
    if box_line =~ /(?:\(?\b|)([\d\.]+)pt too (?:wide|high)\)?/i || box_line =~ /\(badness (\d+)\)/i
      Regexp.last_match(1).to_f
    else
      0.0
    end
  end

  def colorize_line_num(str, _base_color = nil)
    return str if @options[:emacs]

    Rainbow(str).cyan.bright.to_s
  end

  def link_enabled?
    @options && @options[:link] == true && !@options[:emacs]
  end

  def color_enabled?
    @options.nil? || @options[:color] != false
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

  OSC8_LINK_PATTERN = /(\e\]8;;[^\e]*\e\\.*?\e\]8;;\e\\)/.freeze

  def highlight_line_numbers(text, base_color, bright: false)
    return text if @options[:emacs]
    return text if @options && @options[:color] == false

    if text.include?("\e]8;;")
      return text.split(OSC8_LINK_PATTERN).map do |segment|
        if segment.start_with?("\e]8;;")
          segment
        else
          highlight_line_numbers_segment(segment, base_color, bright: bright)
        end
      end.join
    end

    highlight_line_numbers_segment(text, base_color, bright: bright)
  end

  def highlight_line_numbers_segment(text, base_color, bright: false)
    return '' if text.empty?

    pattern = /((?:input\s+)?lines?\s+)(\d+(?:--?\d+)?)|(\bl\.)(\d+)\b|(:)(\d+)(:)/i
    parts = []
    last_pos = 0

    apply_base = lambda do |str|
      r = Rainbow(str).send(base_color)
      bright ? r.bright.to_s : r.to_s
    end

    text.scan(pattern) do
      m = Regexp.last_match
      parts << apply_base.call(text[last_pos...m.begin(0)]) if m.begin(0) > last_pos

      if m[1]
        parts << apply_base.call(m[1]) << colorize_line_num(m[2], base_color)
      elsif m[3]
        parts << apply_base.call(m[3]) << colorize_line_num(m[4], base_color)
      elsif m[5]
        parts << apply_base.call(m[5]) << colorize_line_num(m[6], base_color) << apply_base.call(m[7])
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
      tag = (file == 'bibliography' || file == './bibliography') ? 'bib' : ''
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
    formatted_msg = highlight_line_numbers(clean_msg, base_color)
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

    active_line = (root_line && root_line.positive?) ? root_line : line_no
    source_frame = format_source_frame(file_path, active_line, root_col, item, cat)
    if source_frame
      lines.concat(source_frame)
    else
      append_error_hint(lines, cat, indent)
    end

    append_repeat_note(lines, repeat_count, line_no, indent) if repeat_count > 1

    if @options[:verbose]
      append_verbose_error_context(lines, err_block, indent)
    end

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
    active_line = (root_line && root_line.positive?) ? root_line : line_no
    reported_line = (root_line && root_line.positive? && root_line != line_no) ? line_no : nil

    disp_file = format_display_path(file_path)
    badge = diagnostic_tier_badge('errors', :red)
    clean_msg = badge ? clean_diagnostic_badge_message(msg) : msg

    header_text = if active_line && active_line.positive?
                    col_str = root_col ? ":#{root_col}" : ''
                    rep_str = reported_line ? " (reported on line #{reported_line})" : ''
                    "#{disp_file}:#{active_line}#{col_str}: #{badge}#{clean_msg}#{rep_str}"
                  else
                    "#{disp_file}: #{badge}#{clean_msg}"
                  end

    colored = highlight_line_numbers(header_text, :red, bright: true)
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
    return nil if idx < 0 || idx >= lines.size

    lines[idx].to_s.chomp
  rescue StandardError
    nil
  end

  def locate_token_column(source_line, col_no, token, catalog)
    cat_id = catalog&.[](:id)
    clean_token = (token && !token.to_s.match?(/\s/)) ? token.to_s : nil

    if col_no && col_no.positive?
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
      suffix = (start_char + 65 < source_line.length) ? '...' : ''
      adj_col = col_pos - start_char + prefix.length
      ["#{prefix}#{sub}#{suffix}", adj_col]
    else
      ["#{source_line[0, 67]}...", nil]
    end
  end

  def render_source_code_line(line_no, display_line, col_pos = nil, token_len = nil)
    gutter_num = line_no.to_s.rjust(3)
    num_colored = (@options && @options[:color] == false) ? gutter_num : Rainbow(gutter_num).cyan
    gutter_bar = (@options && @options[:color] == false) ? '|' : Rainbow('|').cyan
    code_text = highlight_error_token(display_line, col_pos, token_len)
    "  #{num_colored} #{gutter_bar} #{code_text}"
  end

  def highlight_error_token(line, col_pos, token_len)
    return line if @options && @options[:color] == false
    return line unless col_pos && token_len && token_len.positive?
    return line if col_pos < 0 || col_pos + token_len > line.length

    prefix = line[0...col_pos]
    target = line[col_pos, token_len]
    suffix = line[(col_pos + token_len)..]
    "#{prefix}#{Rainbow(target).red.bright.bold}#{suffix}"
  end

  def render_gutter_hint(gutter_num_len, catalog)
    return nil unless catalog && catalog[:hint]

    hint_colored = colorize_inline_hint(catalog[:hint]).strip
    arrow = (@options && @options[:color] == false) ? '▸' : Rainbow('▸').cyan.bright
    label = (@options && @options[:color] == false) ? 'Hint: ' : Rainbow('Hint: ').cyan
    "  #{' ' * (gutter_num_len + 2)}#{arrow} #{label}#{hint_colored}"
  end

  def render_context_snippet(file_path, target_line, context_lines, col_pos: nil, token_len: nil, catalog: nil, root_col: nil, target_line_end: nil, force: false)
    return [] unless file_path && target_line && target_line.positive? && context_lines && context_lines.positive?

    real_file = LaTeXErrorCatalog.find_source_file(file_path) || file_path
    return [] unless real_file && File.file?(real_file)

    all_raw_lines = File.readlines(real_file) rescue nil
    return [] unless all_raw_lines && !all_raw_lines.empty?

    target_end = (target_line_end && target_line_end.to_i >= target_line) ? target_line_end.to_i : target_line
    return [] if context_range_covered?(real_file, target_line, target_end, force)

    start_line = [target_line - context_lines, 1].max
    end_line = [target_end + context_lines, all_raw_lines.size].min
    return [] if start_line > end_line

    color_enabled = (@options && @options[:color] != false) && !@options[:emacs]
    code_lines = fetch_snippet_code_lines(real_file, start_line, end_line, all_raw_lines, color_enabled)
    build_snippet_lines(code_lines, start_line, target_line, target_end, end_line, real_file, color_enabled, col_pos, token_len, catalog, root_col)
  end

  def context_range_covered?(real_file, target_line, target_end, force)
    return false if force

    @last_context_file == real_file && @last_context_range &&
      @last_context_range.cover?(target_line) && @last_context_range.cover?(target_end)
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
    out, _, st = Open3.capture3(*cmd) rescue nil
    (st&.success? && out && !out.empty?) ? out.lines : nil
  end

  def resolve_bat_command
    return 'batcat' if LaTeXUtils.command_available?('batcat')
    return 'bat' if LaTeXUtils.command_available?('bat')

    nil
  end

  def format_snippet_line_gutter(cur_line, g_len, is_target, color_enabled, links_active, abs_path)
    marker = is_target ? (color_enabled ? Rainbow('>').red.bright.to_s : '>') : ' '
    num_str = cur_line.to_s.rjust(g_len)
    link_num = if color_enabled
                 styled = is_target ? Rainbow(num_str).red.bright.to_s : Rainbow(num_str).cyan.to_s
                 links_active ? "\e]8;;file://#{abs_path}##{cur_line}\e\\#{styled}\e]8;;\e\\" : styled
               else
                 num_str
               end
    bar = color_enabled ? (is_target ? Rainbow('│').red.bright.to_s : Rainbow('│').cyan.to_s) : '|'
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

  def build_snippet_lines(code_lines, start_line, target_line, target_end, end_line, real_file, color_enabled, col_pos, token_len, catalog, root_col)
    abs_path = ::URI::DEFAULT_PARSER.escape(File.expand_path(real_file.to_s))
    g_len = [end_line.to_s.length, 3].max
    links_active = color_enabled && (@options.nil? || @options[:link] != false)
    lines = []

    code_lines.each_with_index do |cline, idx|
      cur_line = start_line + idx
      is_target = (cur_line >= target_line && cur_line <= target_end)
      gutter = format_snippet_line_gutter(cur_line, g_len, is_target, color_enabled, links_active, abs_path)
      lines << "#{gutter} #{cline.chomp}"
      append_snippet_pointer_or_hint(lines, g_len, col_pos, token_len, catalog, root_col) if cur_line == target_line
    end

    @last_context_file = real_file
    @last_context_range = (target_line..target_end)
    lines
  end

  def format_source_frame(file_path, line_no, col_no, item, catalog)
    return nil unless line_no && line_no.positive?

    if @options && @options[:context_lines] && @options[:context_lines].to_i > 0
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
    caret_colored = (@options && @options[:color] == false) ? caret : Rainbow(caret).red.bright.bold

    hint_msg = inline_hint_text(catalog, root_col)
    hint_colored = colorize_inline_hint(hint_msg)

    indent = ' ' * 2
    gutter_pad = ' ' * gutter_num_len
    gutter_bar = (@options && @options[:color] == false) ? '|' : Rainbow('│').cyan
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

  def append_verbose_error_context(lines, err_block, indent)
    raw_lines = err_block[1..] || []
    return if raw_lines.empty?

    tag = (@options && @options[:color] == false) ? '[TeX context]' : Rainbow('[TeX context]').yellow.faint
    lines << "#{indent}#{tag}"
    raw_lines.each do |l|
      next if l.strip.empty?

      lines << "#{indent}  #{highlight_line_numbers(l, :red)}"
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
    return format_error_block(item[:err_block], item[:line] || 0, width: width, catalog: item[:catalog], repeat_count: item[:repeat_count] || 1, item: item) if item[:err_block]

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
      @options[:emacs] ? el : "#{indent}#{highlight_line_numbers(el, base_color)}"
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

  def track_log_file(line, file_stack)
    return if line =~ WARNING_LINE_PATTERN ||
              line =~ /^(?:Overfull|Underfull)/ || line =~ /^!\s+/ ||
              line =~ /^Missing character:/

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
    return true if line.strip.empty? ||
                   line =~ WARNING_LINE_PATTERN ||
                   line =~ /^(?:Overfull|Underfull)/ || line =~ /^\[\d+\]/ ||
                   line =~ /^!\s+/ || line =~ /^.+:\d+:/ ||
                   line =~ /^Runaway argument\?/ || line =~ /^\s*\)/ ||
                   line =~ /^\s*\((?:\.[\\\/]|[a-zA-Z0-9_\-\.\/]+?\.(?:tex|sty|cls|aux|bbl|bib))/

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

    body = if box_line =~ /(?:\(|\b)([\d\.]+)pt too (wide|high)\)?/i
             pt_val = Regexp.last_match(1).to_f.round(2)
             dimension = Regexp.last_match(2)
             suffix = is_alignment ? ' (alignment)' : ''
             format('%.2fpt too %s%s', pt_val, dimension, suffix)
           elsif box_line =~ /\(badness (\d+)\)/i
             badness = Regexp.last_match(1)
             box_kind = (box_line =~ /\\(vbox)\b/i) ? '\vbox' : '\hbox'
             "underfull #{box_kind} (badness #{badness})"
           else
             clean = box_line.sub(/\s*(?:detected at line \d+|in paragraph at lines \d+(?:--\d+)?|in alignment at lines \d+(?:--\d+)?)\.?/, '')
                             .strip
             clean.empty? ? box_line : clean
           end

    prefix.empty? ? body : "#{prefix} #{body}"
  end

  def clean_diagnostic_warning(text)
    return text if @options[:emacs]

    str = text.strip
    return clean_ref_warning(str) if str =~ /LaTeX Warning: (?:Hyper reference|Reference)/i
    return clean_cite_warning(str) if str =~ /LaTeX Warning: Citation/i

    if str =~ /LaTeX Warning: Empty bibliography(?:\s+on input line \d+)?\.?/i
      return 'Warning: empty bibliography'
    end
    if str =~ /LaTeX Warning: Command\s+(.+?)\s+invalid in math mode(?:\s+on input line \d+)?\.?/i
      return "Warning: command #{Regexp.last_match(1)} invalid in math mode"
    end
    if str =~ /Missing database entry:\s*['"]([^`'"]+)['"]/i
      return "Warning: Missing database entry: '#{Regexp.last_match(1)}'"
    end
    if str =~ /^Missing database entries/i
      return "Warning: #{str}"
    end
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
      if body =~ /Float too large for page by ([\d\.]+)pt/i
        body = body.sub(/Float too large for page by ([\d\.]+)pt/i) { "Float too large for page by #{format('%.2f', Regexp.last_match(1).to_f)}pt" }
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
    if str =~ /LaTeX Warning: (?:Hyper reference|Reference)\s+[`'"](.+?)[`'"](?:\s+on page (\d+))?\s+undefined(?:\s+on input line \d+)?\.?/i
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
    clean = warn_text.gsub(/\([a-zA-Z0-9_\-]+\)\s*/, '').gsub(/line (\d+)\s+(\d+)\b/, 'line \1\2')
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
    match = (box_line =~ /lines?\s+(\d+(?:--\d+)?)/i) ? Regexp.last_match(1) : ''
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

  def parse_box_warning(lines, i, file_stack, verbose)
    l = lines[i]
    start_idx = i
    box_type = (l =~ /^(Overfull|Underfull) \\(hbox|vbox)/) ? "#{Regexp.last_match(1)} \\#{Regexp.last_match(2)}" : 'Overfull \\hbox'
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

    base_color = :yellow
    clean_text = @options[:emacs] ? box_line : clean_box_diagnostic(box_line, is_overfull ? :warning : :note)
    formatted = format_diagnostic_line(line_str, clean_text, base_color, file: file_name)
    if verbose && !extra_lines.empty?
      formatted += "\n" + extra_lines.map { |line| @options[:emacs] ? line : highlight_line_numbers(line, base_color) }.join("\n")
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

    box_groups.each { |_key, items| filtered_warnings << items.max_by { |item| item[:severity] } }
    filtered_warnings
  end

  def extract_warnings(content, verbose = false)
    raw_warnings = []
    seen_warnings = {}
    lines = content.lines
    file_stack = [@filename]
    i = 0

    while i < lines.size
      l = lines[i]
      track_log_file(l, file_stack)

      if l =~ WARNING_LINE_PATTERN
        item, i = parse_package_warning(lines, i, file_stack)
        if item
          d_key = warning_dedup_key(item)
          if !seen_warnings[d_key]
            seen_warnings[d_key] = true
            raw_warnings << item
          end
        end
      elsif l =~ /^(?:Overfull|Underfull) \\(?:hbox|vbox)/
        item, i = parse_box_warning(lines, i, file_stack, verbose)
        raw_warnings << item if item
      else
        i += 1
      end
    end

    deduplicate_box_warnings(raw_warnings)
  end

  def error_line_match(line)
    return [false, nil] if typeset_source_echo?(line)

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
      break if curr =~ /^!\s*(?:==>\s*)?(?:Emergency stop|Fatal error occurred)/i ||
               (curr =~ /^.+:\d+:\s+(?!warning\b)/i && !missing_file_location?(curr, missing_file)) ||
               curr =~ /^!\s+\S+/ || curr =~ /^Runaway argument\?/ ||
               curr =~ WARNING_LINE_PATTERN ||
               curr =~ /^(?:Overfull|Underfull) \\(?:hbox|vbox)/ ||
               curr =~ /^\s*\)/ || curr =~ /^\s*\((?:\.[\\\/]|[a-zA-Z0-9_\-\.\/]+?\.(?:tex|sty|cls|aux|bbl|bib))/

      err_block << curr
      i += 1
      break if curr =~ /^l\.\d+/
    end
    [err_block, i]
  end

  def missing_file_location?(line, missing_file)
    missing_file && line.match?(/^.+:\d+:\s+(?:Emergency stop|Fatal error occurred)/i)
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

      if line =~ /^!\s*(?:==>\s*)?(?:Emergency stop|Fatal error occurred)/i
        i += 1
        next
      end

      is_err, err_file = error_line_match(line)
      if is_err
        cur_file = err_file || current_log_file(file_stack)
        bib_key = (last_bib_entry_file == cur_file) ? last_bib_entry_key : nil
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
    if classification&.[](:id) == :file_not_found
      resource_location = locate_missing_resource_request(classification[:token])
      if resource_location
        file_name, line_no = resource_location
        classification = LaTeXErrorCatalog.classify(
          err_text, err_block, file: file_name, line: line_no, junk_dir: diagnostics_junk_dir
        )
      end
    end
    cat_id = classification ? classification[:id] : :generic
    token = (cat_id == :undefined_control_sequence && classification&.[](:token)) ? classification[:token] : (extract_argument_token(err_block) || classification&.[](:token))
    token = nil if token.to_s.match?(/\s/)
    root_l = classification ? classification[:root_line] : nil
    root_c = classification ? classification[:root_col] : nil

    item = {
      file: file_name, line: line_no, line_str: (line_no > 0 ? line_no.to_s : ''),
      root_line: root_l, root_col: root_c,
      text: err_text, err_block: err_block, base_color: :red, index: next_idx,
      catalog: classification, catalog_id: cat_id,
      source: :compiler, synthetic: false,
      bib_entry: bib_entry, token: token
    }
    item[:formatted] = format_error_block(err_block, line_no, catalog: classification, item: item)
    [item, next_idx]
  end

  def locate_missing_resource_request(resource)
    stem = resource.to_s.sub(/\.(?:tex|sty|cls|bib)\z/i, '')
    return nil if stem.empty?

    pattern = /\\(?:input|include|usepackage|RequirePackage|includegraphics|bibliography|addbibresource)\s*(?:\[[^\]]*\])?\s*\{[^}]*#{Regexp.escape(stem)}[^}]*\}/
    collect_source_candidates.each do |file|
      LaTeXUtils.safe_read(file).each_line.with_index(1) do |line, line_no|
        return [file, line_no] if line.sub(/(?<!\\)%.*\z/, '').match?(pattern)
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

    hint = token ? "Offending token '#{token}' found on this line." : "Entry typeset here when compilation failed."
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
        if @options[:emacs]
          item[:err_block] = first[:err_block] + ["  (Repeated #{group.size} times on line #{first[:line]})"]
        end
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
    items
  end

  def overfull_hbox?(item)
    t = item[:type].to_s
    txt = item[:text].to_s
    (t.include?('Overfull') && t.include?('hbox')) || txt =~ /\AOverfull\s+\\hbox/i
  end

  def underfull_box?(item)
    t = item[:type].to_s
    txt = item[:text].to_s
    raw = item[:raw_text].to_s
    (t.include?('Underfull') && (t.include?('hbox') || t.include?('vbox'))) ||
      txt =~ /\bunderfull\s+(?:line|box|\\hbox|\\vbox)/i ||
      raw =~ /\AUnderfull\s+\\(?:hbox|vbox)/i
  end

  def underfull_vbox?(item)
    t = item[:type].to_s
    txt = item[:text].to_s
    raw = item[:raw_text].to_s
    (t.include?('Underfull') && t.include?('vbox')) ||
      txt =~ /\bunderfull\s+(?:page|column|\\vbox)/i ||
      raw =~ /\AUnderfull\s+\\vbox/i
  end

  def underfull_hbox?(item)
    underfull_box?(item) && !underfull_vbox?(item)
  end

  TIER_RANK = { 'errors' => 0, 'alerts' => 1, 'warnings' => 2, 'whatevers' => 3 }.freeze

  def diagnostic_item_sort_key(item)
    idx = item[:index] || 0
    target = item[:companion_to] ? format_display_path(item[:companion_to]) : format_display_path(item[:file])
    rank = item[:companion_to] ? 1 : 0
    t_rank = TIER_RANK[tier_label_for(item)] || 2
    line_num = if item[:line].is_a?(Integer) && item[:line].positive?
                 item[:line]
               elsif item[:line_str].to_s =~ /\A(\d+)/
                 $1.to_i
               else
                 item[:line] || 0
               end
    [target, rank, t_rank, format_display_path(item[:file]), idx.negative? ? 0 : 1, line_num, idx]
  end

  def sort_diagnostic_items(warnings, errors)
    all_items = warnings + errors
    all_sorted = all_items.sort_by { |item| diagnostic_item_sort_key(item) }

    total_warn_count = warnings.sum { |w| w[:count] || 1 }
    [all_sorted, total_warn_count, errors.size]
  end

  def print_diagnostics_body(warnings, errors = [], fallback_lines: [], tier_label: nil, io: $stdout)
    @last_context_file = nil
    @last_context_range = nil
    all_sorted, num_warnings, num_errors = sort_diagnostic_items(warnings, errors)
    max_width = all_sorted.map { |item| item[:line_str].to_s.length }.max || 0

    header_counts = count_items_by_header(all_sorted, tier_label)
    current_header = nil
    all_sorted.each do |item|
      current_header = render_diagnostic_entry(item, max_width, current_header, tier_label, header_counts, io: io)
    end

    render_diagnostic_fallback(all_sorted, fallback_lines, current_header, tier_label, io: io)
    [num_warnings, num_errors]
  end

  def count_items_by_header(all_sorted, tier_label)
    counts = Hash.new { |h, k| h[k] = Hash.new(0) }
    all_sorted.each do |item|
      f = format_display_path(item[:file])
      lbl = tier_label_for(item, tier_label)
      counts[f][lbl] += (item[:count] || 1)
    end
    counts
  end

  def render_diagnostic_entry(item, max_width, current_header, tier_label = nil, header_counts = nil, io: $stdout)
    item_file = format_display_path(item[:file])
    header_key = item_file

    if header_key != current_header
      @last_context_file = nil
      @last_context_range = nil
      if @options[:emacs]
        io.puts ')' if current_header
        io.puts "(#{item_file}"
      else
        counts = header_counts ? header_counts[header_key] : { tier_label_for(item, tier_label) => 1 }
        io.puts ''
        io.puts format_file_separator(item_file, counts)
      end
      current_header = header_key
    end

    rendered = render_diagnostic_item(item, width: max_width)
    rendered = @options[:emacs] ? rendered.chomp : rendered.rstrip
    io.puts rendered unless rendered.empty?
    io.puts '' if @options[:emacs]

    explain_diagnostic_item(item, io: io) if @options[:explain] && !compile_mode?
    current_header
  end

  def compile_mode?
    @options && @options[:compile] == true
  end

  def llm_mode?
    @options && (@options[:llm] == true || @options[:agent] == true)
  end

  def json_mode?
    @options && @options[:json] == true
  end

  def normalize_diagnostic(item, tier)
    cat = item[:category] || item.dig(:catalog, :category) || (respond_to?(:diagnostic_category, true) ? diagnostic_category(item) : nil)
    {
      file: compile_display_file(item),
      line: normalized_line(item),
      col: normalized_col(item),
      tier: tier.to_s,
      category: cat,
      message: normalized_message(item),
      token: item[:token] || item.dig(:catalog, :token),
      hint: item.dig(:catalog, :hint),
      index: item[:index] || 0,
      repeat_count: item[:repeat_count] || 1
    }
  end

  def normalized_line(item)
    root_line = item[:root_line] || item.dig(:catalog, :root_line)
    if root_line && root_line.to_i.positive?
      root_line.to_i
    elsif item[:line] && item[:line].to_i.positive?
      item[:line].to_i
    else
      item[:line_str].to_s =~ /\A\d+\z/ ? item[:line_str].to_i : 0
    end
  end

  def normalized_col(item)
    c = item[:col] || item[:root_col] || item.dig(:catalog, :root_col)
    c && c.to_i.positive? ? c.to_i : nil
  end

  def normalized_message(item)
    message = if item[:err_block] && !item[:err_block].empty?
                raw_msg = item[:err_block].first.to_s.strip
                extract_clean_error_message(raw_msg)
              else
                item[:text].to_s
              end
    count = item[:repeat_count].to_i
    count > 1 ? "#{message} (repeated #{count} times)" : message
  end

  TEXTUAL_SOURCE_EXT = %w[.tex .sty .cls .bib .bbl .dtx .ltx .cfg].freeze

  def compile_display_file(item)
    raw_file = (item[:file] || @filename).to_s
    raw_file = @filename.to_s if raw_file.empty? || raw_file == '.'
    ext = File.extname(raw_file)
    if ext == '.pdf' || raw_file == './bibliography' || raw_file == 'bibliography'
      compile_relative_path(@filename)
    else
      compile_relative_path(raw_file)
    end
  end

  def compile_relative_path(path)
    init_pwd = LaTeXUtils.initial_pwd || Dir.pwd
    full_path = File.expand_path(path)
    init_prefix = "#{init_pwd}/"
    if full_path.start_with?(init_prefix)
      full_path.delete_prefix(init_prefix)
    elsif path.to_s.start_with?('./')
      path.to_s.delete_prefix('./')
    else
      format_display_path(path)
    end
  end

  def emit_compile_diagnostics(errors: [], alerts: [], warnings: [], whatevers: [], io: $stderr)
    records = collect_compile_records(errors: errors, alerts: alerts,
                                      warnings: warnings, whatevers: whatevers)
    if @options[:vscode_lw]
      emit_vscode_lw_diagnostics(records, errors: errors)
      return records.size
    end
    @last_context_file = nil
    @last_context_range = nil
    records.sort_by { |r| [r[:index] || 0, r[:file] || '', r[:line] || 0, r[:col] || 0] }
           .each do |r|
             io.puts LaTeXCompileFormat.render(r, color: @options[:color] != false, link: @options[:link] == true)
             emit_compile_record_context(r, io)
           end
    records.size
  end

  def emit_compile_record_context(record, io)
    return unless @options && @options[:context_lines].to_i.positive?
    line = record[:line].to_i
    return unless line.positive?

    col_pos = (record[:col] && record[:col].to_i.positive?) ? record[:col].to_i - 1 : nil
    token_len = (record[:token] && !record[:token].to_s.empty?) ? record[:token].to_s.length : 1
    snippet = render_context_snippet(record[:file], line, @options[:context_lines].to_i,
                                     col_pos: col_pos, token_len: token_len, root_col: record[:col])
    io.puts snippet.join("\n") unless snippet.empty?
  end

  def emit_vscode_lw_diagnostics(records, errors:)
    $stdout.puts "Fatal error occurred, no output PDF file produced!\n\n" if errors.any?
    root_base = File.basename(@filename.to_s, '.tex')
    records.sort_by { |r| [r[:index] || 0, r[:file] || '', r[:line] || 0, r[:col] || 0] }
           .each { |r| emit_single_vscode_record(r, root_base: root_base) }
  end

  def emit_single_vscode_record(record, root_base:)
    file = format_vscode_record_file(record[:file])
    line = (record[:line] && record[:line].to_i.positive?) ? record[:line].to_i : 1
    msg = LaTeXCompileFormat.format_message(record, color: false)
    cat = record[:category] || (respond_to?(:diagnostic_category, true) ? diagnostic_category(record) : nil)
    expl = (cat && cat != :generic) ? (DIAGNOSTIC_EXPLANATIONS[cat] || LaTeXErrorCatalog.find_by_id(cat)) : nil
    is_root = (File.basename(file, '.tex') == root_base)

    case record[:tier]
    when 'errors'
      emit_vscode_error(file, line, msg, expl)
    when 'whatevers'
      emit_vscode_info(file, line, msg, expl, is_root: is_root)
    else
      emit_vscode_warning(file, line, msg, expl, is_root: is_root)
    end
  end

  def format_vscode_record_file(file)
    f = file || @filename
    f.start_with?('/', './') ? f : "./#{f}"
  end

  def build_vscode_explanation_lines(expl)
    return [] unless expl

    lines = []
    lines << "❓ Why: #{expl[:why]}" if expl[:why]
    fix_label = expl[:fix_label] || 'Fix:'
    fix_label = "#{fix_label}:" unless fix_label.end_with?(':')
    lines << "🔧 #{fix_label} #{expl[:fix]}" if expl[:fix]
    lines << "👀 See: #{expl[:doc_url]}" if expl[:doc_url]
    lines
  end

  def emit_vscode_error(file, line, msg, expl)
    lines = ["#{file}:#{line}: #{msg}"] + build_vscode_explanation_lines(expl)
    $stdout.puts "#{lines.join("\n")}\n\n"
  end

  def emit_vscode_info(file, line, msg, expl, is_root:)
    lines = ["LaTeX Info: #{msg} on input line #{line}."] + build_vscode_explanation_lines(expl)
    block = lines.join("\n")
    $stdout.puts is_root ? "#{block}\n\n" : "(#{file}\n#{block}\n\n)\n\n"
  end

  def emit_vscode_warning(file, line, msg, expl, is_root:)
    lines = ["LaTeX Warning: #{msg} on input line #{line}."] + build_vscode_explanation_lines(expl)
    block = lines.join("\n")
    $stdout.puts is_root ? "#{block}\n\n" : "(#{file}\n#{block}\n\n)\n\n"
  end

  def collect_compile_records(errors:, alerts:, warnings:, whatevers:)
    { 'errors' => errors, 'alerts' => alerts,
      'warnings' => warnings, 'whatevers' => whatevers }
      .reject { |tier, _| tier_suppressed?(tier.to_sym) }
      .flat_map { |tier, items| (items || []).map { |it| normalize_diagnostic(it, tier) } }
  end

  def tier_label_for(item, tier_label = nil)
    return tier_label if tier_label
    return item[:tier] if item[:tier]
    return 'errors' if item[:err_block]
    return 'alerts' if item[:base_color] == :red
    return 'whatevers' if item[:base_color] == :cyan

    'warnings'
  end

  TIER_SEVERITY_ORDER = %w[errors alerts warnings whatevers].freeze

  def format_file_separator(item_file, tier_or_counts, count = nil)
    counts = if tier_or_counts.is_a?(Hash)
               tier_or_counts
             else
               { tier_or_counts.to_s => (count || 1) }
             end

    top_tier = TIER_SEVERITY_ORDER.find { |t| counts[t]&.positive? } || 'warnings'
    color = tier_color(top_tier)

    label_parts = []
    uncolored_parts = []
    TIER_SEVERITY_ORDER.each do |tier|
      cnt = counts[tier]
      next unless cnt && cnt.positive?

      str = format_tier_count_label(cnt, tier)
      uncolored_parts << str
      label_parts << Rainbow(str).send(tier_color(tier)).bright
    end

    uncolored_label = uncolored_parts.empty? ? '1 diagnostic' : uncolored_parts.join(', ')
    uncolored_prefix = "── #{item_file} (#{uncolored_label}) "
    cols = terminal_columns
    dash_count = [cols - uncolored_prefix.length, 3].max
    dashes = '─' * dash_count

    return "── #{item_file} (#{uncolored_label}) #{dashes}" if @options && @options[:color] == false

    lead = Rainbow('── ').send(color).bright
    disp_file = Rainbow(item_file).bold
    linked_file = format_file_banner_link(item_file, disp_file)

    sep = Rainbow(', ').send(color).bright
    inner_label = label_parts.join(sep)
    count_part = Rainbow(' (').send(color).bright + inner_label + Rainbow(') ').send(color).bright
    tail = Rainbow(dashes).send(color).bright

    "#{lead}#{linked_file}#{count_part}#{tail}"
  end

  def format_file_banner_link(file, display_str)
    return display_str unless link_enabled? && file && !file.to_s.empty?

    real_file = LaTeXErrorCatalog.find_source_file(file) || file
    return display_str unless File.exist?(real_file)

    abs_path = ::URI::DEFAULT_PARSER.escape(File.expand_path(real_file.to_s))
    uri = "file://#{abs_path}"
    "\e]8;;#{uri}\e\\#{display_str}\e]8;;\e\\"
  end

  def format_tier_count_label(count, tier_label)
    name = case tier_label.to_s
           when 'alerts' then count == 1 ? 'alert' : 'alerts'
           when 'warnings' then count == 1 ? 'warning' : 'warnings'
           when 'errors' then count == 1 ? 'error' : 'errors'
           when 'whatevers' then count == 1 ? 'whatever' : 'whatevers'
           else tier_label.to_s
           end
    "#{count} #{name}"
  end

  def tier_color(tier_label)
    case tier_label.to_s
    when 'alerts', 'errors' then :red
    when 'whatevers' then :cyan
    else :yellow
    end
  end

  def explain_diagnostic_item(item, io: $stdout)
    cat = diagnostic_category(item)
    return if !cat || cat == :generic || @explained_categories[cat]

    @explained_categories[cat] = true
    box = format_boxed_explanation(cat)
    io.puts box if box
  end

  def render_diagnostic_fallback(all_sorted, fallback_lines, current_header, tier_label = nil, io: $stdout)
    if compile_mode?
      if all_sorted.empty? && !fallback_lines.empty?
        disp = format_display_path(@filename)
        disp = "./#{disp}" if @options[:vscode_lw] && !disp.start_with?('/', './')
        io.puts 'Fatal error occurred, no output PDF file produced!' if @options[:vscode_lw]
        io.puts "#{disp}:1: error: compilation failed; see log for details"
      end
      return
    end

    if all_sorted.empty? && !fallback_lines.empty?
      render_fallback_lines(fallback_lines, tier_label, io: io)
    elsif current_header && @options[:emacs]
      io.puts ')'
    end
  end

  def render_fallback_lines(fallback_lines, tier_label = nil, io: $stdout)
    disp = format_display_path(@filename)
    if @options[:emacs]
      io.puts "(#{disp}"
    else
      lbl = tier_label || 'errors'
      io.puts ''
      io.puts format_file_separator(disp, lbl, 1)
    end
    fallback_lines.each do |l|
      next if l.strip.empty?

      io.puts @options[:emacs] ? l.strip : highlight_line_numbers(l.strip, :red, bright: true)
    end
    io.puts ')' if @options[:emacs]
  end

  def format_display_path(file)
    path = (file || @filename).to_s
    path = @filename.to_s if path.empty? || path == '.'
    cwd_prefix = "#{Dir.pwd}/"
    path = path.delete_prefix(cwd_prefix) if path.start_with?(cwd_prefix)
    path = path.delete_prefix('./') if path.start_with?('./')
    path
  end

  def terminal_columns
    LaTeXUtils.terminal_width(default: 80)
  end

  def wrap_box_field(prefix, text, inner_width)
    full_prefix = "#{prefix} "
    wrapped = LaTeXUtils.wrap_text(text, width: inner_width, prefix: full_prefix)
    wrapped.lines.map do |ln|
      pad = [inner_width - LaTeXUtils.visible_width(ln.chomp), 0].max
      "│ #{ln.chomp}#{' ' * pad} │"
    end
  end

  def format_boxed_explanation(category)
    expl = DIAGNOSTIC_EXPLANATIONS[category] || LaTeXErrorCatalog.find_by_id(category)
    return nil unless expl

    cols = terminal_columns
    inner_width = cols - 4

    top_title = "─ Diagnostic Explanation: #{expl[:title]} "
    dash_count = [cols - 2 - top_title.length, 1].max
    fix_label = expl[:fix_label] || (category.to_s.start_with?('underfull') ? 'Might fix:' : 'Fix:')
    fix_label = "#{fix_label}:" unless fix_label.end_with?(':')
    box_lines = [
      "┌#{top_title}#{'─' * dash_count}┐",
      *wrap_box_field('❓ Why:', expl[:why], inner_width),
      *wrap_box_field("🔧 #{fix_label}", expl[:fix], inner_width)
    ]
    if expl[:doc_url]
      doc_link = format_terminal_url(expl[:doc_url], expl[:doc_url], color: :blue)
      box_lines.concat(wrap_box_field('👀 See:', doc_link, inner_width))
    end
    box_lines << "└#{'─' * (cols - 2)}┘"

    render_colored_box(box_lines)
  end

  def render_colored_box(box_lines)
    return "\n#{box_lines.join("\n")}\n" if @options[:color] == false || @options[:emacs]

    colored = box_lines.map do |bl|
      if bl.start_with?('┌') || bl.start_with?('└')
        Rainbow(bl).cyan.bright
      else
        left_bar = Rainbow('│').cyan.bright
        right_bar = Rainbow('│').cyan.bright
        "#{left_bar} #{bl[2...-2]} #{right_bar}"
      end
    end
    "\n#{colored.join("\n")}\n"
  end

  def classify_overfull_category(item)
    sev = (item[:severity] || extract_box_severity(item[:text].to_s)).to_f
    if sev >= alert_overfull_pt
      :overfull_hbox_alert
    elsif sev > 0 && sev <= whatever_overfull_pt
      :overfull_hbox_whatever
    else
      :overfull_hbox_warning
    end
  end

  def reference_or_cite_category(txt)
    if txt =~ /(?:reference|Reference)\s+[`'"]/i && txt.include?('undefined')
      :undefined_reference
    elsif txt =~ /(?:citation|Citation)\s+[`'"]/i && txt.include?('undefined')
      :undefined_citation
    end
  end

  def diagnostic_category(item)
    return item[:catalog_id] if item[:catalog_id] && item[:catalog_id] != :generic
    return item[:alert_type] if item[:alert_type]

    txt = item[:text].to_s
    return :multiply_defined_label if txt.include?('multiply defined')
    return classify_overfull_category(item) if overfull_hbox?(item)
    return :underfull_vbox if underfull_vbox?(item)
    return :underfull_hbox if underfull_hbox?(item)
    ref_cat = reference_or_cite_category(txt)
    return ref_cat if ref_cat

    return :hyperref_token if txt.include?('Token not allowed in a PDF string')
    return :float_specifier if txt =~ /float specifier changed to/i
    return :font_shape if txt.include?('Some font shapes were not available') ||
                          txt =~ /Font shape .* (?:undefined|not available)/i
    return :summary_warning if txt.include?('There were multiply-defined labels') ||
                               txt.include?('There were undefined references') ||
                               txt.include?('Size substitutions with differences')
    return :etex_allocation if txt.include?('Extended allocation already in use')

    :generic
  end

  def alert_overfull_pt
    (@options[:alert_overfull_pt] || 24.0).to_f
  end

  def whatever_overfull_pt
    (@options[:whatever_overfull_pt] || 2.5).to_f
  end

  def internal_label_key?(key)
    return true if key.nil?

    key.end_with?('@cref') || key.end_with?('@vr') || key.end_with?('@xvr')
  end

  def collect_runtime_label_locations(lines)
    file_stack = [@filename]
    label_locs = Hash.new { |h, k| h[k] = [] }

    lines.each do |line|
      track_log_file(line, file_stack)
      next unless line =~ /LIT_LBL:(\d+):.*\\newlabel\s*\{([^}]+)\}/

      line_no = Regexp.last_match(1).to_i
      raw_key = Regexp.last_match(2).strip
      next if internal_label_key?(raw_key)

      label_locs[raw_key] << { file: current_log_file(file_stack), line: line_no }
    end
    label_locs
  end

  def resolve_duplicate_label_locations(label_key, label_locs)
    locs = label_key ? label_locs[label_key] : []
    return locs unless locs.empty?

    label_key ? find_source_label_definitions(label_key) : []
  end

  def build_duplicate_label_alerts(label_key, locs, base_index)
    uniq_locs = locs.uniq
    uniq_locs.each_with_index.map do |loc, idx|
      other_locs = uniq_locs.reject.with_index { |_, i| i == idx }

      if @options[:emacs]
        suffix = uniq_locs.size > 1 ? " (location #{idx + 1} of #{uniq_locs.size})" : ''
        msg = "LaTeX Warning: Label `#{label_key}' multiply defined#{suffix}"
      else
        if other_locs.empty?
          msg = "Alert: label '#{label_key}' duplicate"
        else
          linked_others = other_locs.map do |ol|
            disp = "#{format_display_path(ol[:file])}:#{ol[:line]}"
            link_enabled? ? format_terminal_link(ol[:file], ol[:line].to_s, disp, underline: false, color: :cyan) : disp
          end.join(', ')
          msg = "Alert: label '#{label_key}' duplicate (also at #{linked_others})"
        end
      end

      formatted = format_diagnostic_line(loc[:line].to_s, msg, :red, file: loc[:file])
      {
        file: loc[:file],
        line: loc[:line],
        line_str: loc[:line].to_s,
        text: msg,
        base_color: :red,
        tier: 'alerts',
        formatted: formatted,
        index: base_index + idx,
        alert_type: :multiply_defined_label
      }
    end
  end

  def build_fallback_label_alert(text, file_name, base_index)
    key = text[/Label\s+[`'"]?([^`'"\s]+)[`'"]?\s+multiply defined/i, 1]
    clean_text = if @options[:emacs]
                   text
                 elsif key
                   "Alert: label '#{key}' duplicate"
                 else
                   text.sub(/^LaTeX Warning:\s*/i, 'Alert: ')
                 end
    formatted = format_diagnostic_line('', clean_text, :red, file: file_name)
    [{
      file: file_name,
      line: 0,
      line_str: '',
      text: clean_text,
      base_color: :red,
      tier: 'alerts',
      formatted: formatted,
      index: base_index,
      alert_type: :multiply_defined_label
    }]
  end

  def extract_label_alerts(content)
    clean_content = LaTeXUtils.filter_subcommand_noise(content)
    lines = clean_content.lines
    label_locs = collect_runtime_label_locations(lines)

    alerts = []
    file_stack = [@filename]
    seen_duplicate_keys = []

    lines.each_with_index do |line, i|
      track_log_file(line, file_stack)
      next unless line.include?('multiply defined') && line.include?('LaTeX Warning')

      label_key = line[/Label\s+[`'"]?([^`'"\s]+)[`'"]?\s+multiply defined/i, 1]
      next if internal_label_key?(label_key) || (label_key && seen_duplicate_keys.include?(label_key))

      seen_duplicate_keys << label_key if label_key
      locs = resolve_duplicate_label_locations(label_key, label_locs)
      if locs.empty?
        alerts.concat(build_fallback_label_alert(line.strip, current_log_file(file_stack), i))
      else
        alerts.concat(build_duplicate_label_alerts(label_key, locs, i))
      end
    end
    alerts
  end

  def find_source_label_definitions(label_key)
    candidates = collect_source_candidates
    locs = []
    ref_pattern = /\\(?:page|auto|eq|c|C|name)?ref\*?\{[^}]*\b#{Regexp.escape(label_key)}\b[^}]*\}/

    candidates.each do |file|
      next unless File.file?(file)

      content = File.read(file, encoding: 'UTF-8', invalid: :replace, undef: :replace)
      content.lines.each_with_index do |line_text, idx|
        clean = line_text.sub(/(?<!\\)%.*$/, '')
        next unless clean.include?(label_key)

        stripped = clean.gsub(ref_pattern, '')
        if stripped.include?(label_key)
          locs << { file: file, line: idx + 1 }
        end
      end
    end
    locs
  end

  def extract_alerts(content, warn_items = nil)
    clean_content = LaTeXUtils.filter_subcommand_noise(content)
    warn_items ||= extract_warnings(clean_content, @options[:verbose])
    threshold = alert_overfull_pt
    alert_boxes = warn_items.select do |w|
      overfull_hbox?(w) && (w[:severity] || 0.0) >= threshold
    end
    alert_boxes.each do |ab|
      ab[:base_color] = :red
      ab[:tier] = 'alerts'
      ab[:text] = ab[:text].sub(/^Warning:/, 'Alert:')
      ab[:formatted] = format_diagnostic_line(ab[:line_str], ab[:text], :red, file: ab[:file])
    end
    extract_label_alerts(clean_content) + alert_boxes + collect_source_label_alerts + collect_type3_font_alerts
  end

  def collect_source_label_alerts
    candidates = collect_source_candidates
    candidates.flat_map do |f|
      raw_alerts = LaTeXBraceChecker.check_inverted_labels(f)
      raw_alerts.map do |a|
        a[:formatted] = format_diagnostic_line(a[:line_str], a[:text], :red)
        a
      end
    end
  end

  def diagnostics_junk_dir
    @junk_dir || (respond_to?(:resolve_junk_dir, true) ? resolve_junk_dir : 'junk')
  end

  def diagnostic_artifact_candidates(extension)
    primary = File.join(diagnostics_junk_dir, "#{@bfilename}.#{extension}")
    return [primary] if @junk_dir

    [primary, "junk/#{@bfilename}.#{extension}", ".junk/#{@bfilename}.#{extension}"].uniq
  end

  def collect_source_candidates
    candidates = []
    candidates << @filename if @filename && File.file?(@filename)
    fls_file = diagnostic_artifact_candidates('fls').find { |f| File.file?(f) }
    if @bfilename && fls_file && respond_to?(:extract_fls_dependencies, true)
      candidates.concat(extract_fls_dependencies(fls_file).select { |f| f.end_with?('.tex') })
    end
    candidates.concat(Dir['*.tex', '*/*.tex'].select { |f| File.file?(f) })
    patterns = (@options && @options[:exclude_source_tex]) || LaTeXUtils::DEFAULT_EXCLUDE_SOURCE_PATTERNS
    candidates.uniq.reject do |f|
      patterns.any? { |pat| File.fnmatch?(pat, f, File::FNM_CASEFOLD | File::FNM_EXTGLOB) }
    end
  end

  def collect_type3_font_alerts
    target_pdf = resolve_target_pdf
    return [] unless target_pdf

    type3 = LaTeXUtils.check_type3_fonts(target_pdf)
    return [] unless type3

    fonts_str = type3[:fonts].join(', ')
    pages_str = type3[:pages].empty? ? '' : " on page #{type3[:pages].join(', ')}"
    msg = "Type 3 (raster bitmap) font detected: #{fonts_str}#{pages_str}"
    formatted = format_diagnostic_line('', msg, :red)
    [{
      file: target_pdf,
      line: 0,
      line_str: '',
      text: msg,
      formatted: formatted,
      alert_type: :type3_font,
      base_color: :red,
      index: 60000
    }]
  end

  def resolve_target_pdf
    return "#{@bfilename}.pdf" if @bfilename && File.file?("#{@bfilename}.pdf")

    diagnostic_artifact_candidates('pdf').find { |f| File.file?(f) }
  end

  def whatever_diagnostic?(item)
    if overfull_hbox?(item)
      sev = (item[:severity] || extract_box_severity(item[:text].to_s)).to_f
      return true if sev > 0 && sev <= whatever_overfull_pt
    end

    txt = item[:text].to_s
    return true if txt.include?('Token not allowed in a PDF string') ||
                   txt =~ /float specifier changed to/i ||
                   txt.include?('There were multiply-defined labels') ||
                   txt.include?('There were undefined references') ||
                   txt.include?('Some font shapes were not available') ||
                   txt.include?('Size substitutions with differences') ||
                   txt =~ /Font shape .* (?:undefined using|tried instead|defaults substituted)/i ||
                   txt.include?('Extended allocation already in use')

    false
  end

  def partition_diagnostics(clean_content, warn_items)
    alert_items = extract_alerts(clean_content, warn_items)
    whatevers = []
    regular_warnings = []

    threshold = alert_overfull_pt
    warn_items.each do |w|
      next if overfull_hbox?(w) && ((w[:severity] || 0.0) >= threshold)

      if whatever_diagnostic?(w)
        whatevers << w
      else
        regular_warnings << w
      end
    end

    alert_items.each { |i| i[:tier] = 'alerts' }
    regular_warnings.each { |i| i[:tier] = 'warnings' }
    whatevers.each { |i| i[:tier] = 'whatevers' }

    [alert_items, regular_warnings, whatevers]
  end

  def format_tier_count(label, count, color, _suppressed = false)
    if count == 0
      Rainbow("#{label}: 0").green.bright
    else
      Rainbow("#{label}: #{count}").color(color).bright
    end
  end

  def format_suppression_tag(alerts, warnings, whatevers, suppressed_alerts, suppressed_warnings, suppressed_whatevers)
    use_badges = show_tier_badges?
    alt_label = use_badges ? '🚨' : 'Alerts'
    wrn_label = use_badges ? '❕' : 'Warnings'
    wht_label = use_badges ? '☕' : 'Whatevers'

    suppressed = []
    suppressed << alt_label if suppressed_alerts && alerts > 0
    suppressed << wrn_label if suppressed_warnings && warnings > 0
    suppressed << wht_label if suppressed_whatevers && whatevers > 0

    return '' if suppressed.empty?

    all_non_errors = [alerts > 0, warnings > 0, whatevers > 0].count(true)
    if suppressed.size == all_non_errors && all_non_errors > 1
      "  #{Rainbow('(non-errors suppressed)').faint}"
    else
      "  #{Rainbow("(#{suppressed.join(', ')} suppressed)").faint}"
    end
  end

  def print_summary_line(errors, alerts, warnings, whatevers,
                         suppressed_warnings: false, suppressed_whatevers: false, suppressed_alerts: false, io: nil)
    return if @options && compile_mode?

    target_io = io || ((@options && @options[:score]) ? (@orig_stdout || $stdout) : $stdout)
    active = active_tiers(suppressed_alerts, suppressed_warnings, suppressed_whatevers)

    target_io.puts ''
    if summary_clean?(errors, alerts, warnings, whatevers, active)
      target_io.puts format_clean_summary(active_tier_names(active))
    else
      print_nonzero_summary(target_io, errors, alerts, warnings, whatevers,
                            suppressed_alerts, suppressed_warnings, suppressed_whatevers)
    end
  end

  def active_tiers(supp_alerts, supp_warns, supp_whats)
    {
      alerts: !tier_suppressed?(:alerts, supp_alerts),
      warnings: !tier_suppressed?(:warnings, supp_warns),
      whatevers: !tier_suppressed?(:whatevers, supp_whats)
    }
  end

  def summary_clean?(errors, alerts, warnings, whatevers, active)
    errors.zero? &&
      (!active[:alerts] || alerts.zero?) &&
      (!active[:warnings] || warnings.zero?) &&
      (!active[:whatevers] || whatevers.zero?)
  end

  def active_tier_names(active)
    names = ['errors']
    names << 'alerts' if active[:alerts]
    names << 'warnings' if active[:warnings]
    names << 'whatevers' if active[:whatevers]
    names
  end

  def print_nonzero_summary(target_io, errors, alerts, warnings, whatevers, supp_alt, supp_wrn, supp_wht)
    err_label = show_tier_badges? ? '🛑 Errors' : 'Errors'
    alt_label = show_tier_badges? ? '🚨 Alerts' : 'Alerts'
    wrn_label = show_tier_badges? ? '❕ Warnings' : 'Warnings'
    wht_label = show_tier_badges? ? '☕ Whatevers' : 'Whatevers'

    err_str = format_tier_count(err_label, errors, :red)
    alert_str = format_tier_count(alt_label, alerts, :red)
    warn_str = format_tier_count(wrn_label, warnings, :yellow)
    what_str = format_tier_count(wht_label, whatevers, :cyan)
    tag = format_suppression_tag(alerts, warnings, whatevers, supp_alt, supp_wrn, supp_wht)

    target_io.puts "#{err_str}, #{alert_str}, #{warn_str}, #{what_str}#{tag}"
  end

  def format_clean_summary(active_names)
    v_symbol = Rainbow('✔').green.bright
    msg = Rainbow("No #{active_names.join('/')}.").green.bright
    "#{v_symbol} #{msg}"
  end

  def tier_suppressed?(tier, explicit_suppressed = false)
    return true if explicit_suppressed
    return false unless @options

    case tier
    when :alerts then @options[:suppress_alerts] == true
    when :warnings then @options[:suppress_warnings] == true
    when :whatevers then @options[:suppress_whatevers] != false
    else false
    end
  end

  def primary_error_file(groups)
    groups.keys.find do |f|
      groups[f].any? { |e| e[:source] != :leeni && !e[:synthetic] }
    end || groups.keys.first
  end

  def throttle_errors(errors)
    return [errors, nil] if (@options && (@options[:all] || @options[:emacs])) || errors.size <= 1

    groups = errors.group_by { |e| format_display_path(e[:file]) }
    first_file = primary_error_file(groups)
    file_errors = groups[first_file] || []
    companion_errors = errors.select { |e| e[:companion_to] == first_file }
    companion_files = companion_errors.map { |ce| format_display_path(ce[:file]) }.uniq

    return [errors, nil] if groups.size <= (1 + companion_files.size) && file_errors.size <= 10

    displayed = file_errors.first(10) + companion_errors
    other_files = groups.keys.reject { |k| k == first_file || companion_files.include?(k) }
    cascade_info = {
      first_file: first_file,
      remaining_in_first: [file_errors.size - 10, 0].max,
      other_files: other_files,
      other_errors_count: other_files.sum { |f| groups[f].size }
    }
    [displayed, cascade_info]
  end

  def format_other_files_list(other_list)
    return other_list.join(', ') if other_list.size <= 4

    "#{other_list.first(3).join(', ')}, ..."
  end

  def print_cascade_notice(cascade_info, io: $stderr)
    cols = terminal_columns
    io.puts Rainbow("\n═══════════════════════════════════════════════════════════════════════════════").yellow
    if cascade_info[:remaining_in_first] > 0
      msg = "▸ #{cascade_info[:remaining_in_first]} more errors in #{cascade_info[:first_file]} were truncated (likely cascades)."
      io.puts Rainbow(LaTeXUtils.wrap_text(msg, width: cols)).yellow
    end
    if cascade_info[:other_errors_count] > 0
      files_str = format_other_files_list(cascade_info[:other_files])
      msg1 = "▸ #{cascade_info[:other_errors_count]} more errors were detected across #{cascade_info[:other_files].size} other files (#{files_str})."
      io.puts Rainbow(LaTeXUtils.wrap_text(msg1, width: cols)).yellow
      msg2 = '  Handle above errors first to ensure these errors are not cascades.'
      io.puts Rainbow(LaTeXUtils.wrap_text(msg2, width: cols)).yellow
    end
    msg3 = "  (Run with 'l -a' / '--all' to display all errors across all files)."
    io.puts Rainbow(LaTeXUtils.wrap_text(msg3, width: cols)).yellow
    io.puts Rainbow('═══════════════════════════════════════════════════════════════════════════════').yellow
  end

  def emit_compile_cascade_notice(cascade_info, io: $stderr)
    return unless cascade_info

    note_label = (@options && @options[:color] == false) ? 'note:' : Rainbow('note:').cyan.bright.bold.to_s
    if cascade_info[:remaining_in_first].to_i > 0
      msg = "#{cascade_info[:remaining_in_first]} more errors in #{cascade_info[:first_file]} were truncated"
      io.puts "leeni: #{note_label} #{msg} (run with 'l -a' to display all)"
    end
    if cascade_info[:other_errors_count].to_i > 0
      files_str = format_other_files_list(cascade_info[:other_files])
      msg = "#{cascade_info[:other_errors_count]} more errors detected across #{cascade_info[:other_files].size} other files (#{files_str})"
      io.puts "leeni: #{note_label} #{msg} (run with 'l -a' to display all)"
    end
  end

  COMPILER_BRACE_ERROR_PATTERN = /(?:Runaway argument\?|File ended while scanning use of|Extra \}, or forgotten \\endgroup|Extra \\endgroup|Too many \}'s|Missing \} inserted|Paragraph ended before .* was complete|\\begin\{.*\} ended by \\end\{.*\})/i.freeze
  COMPILER_BRACE_CASCADE_IDS = %i[
    paragraph_ended_before_complete file_ended_while_scanning
  ].freeze

  def compiler_indicates_brace_error?(content)
    content.match?(COMPILER_BRACE_ERROR_PATTERN)
  end

  def suppress_compiler_brace_cascades(errors, brace_errors)
    return errors if brace_errors.empty?

    errors.reject { |error| COMPILER_BRACE_CASCADE_IDS.include?(error[:catalog_id]) }
  end

  def suppress_environment_mismatch_cascades(errors)
    primary = errors.find { |error| error[:catalog_id] == :mismatched_environment }
    return errors unless primary && format_display_path(primary[:file]) != format_display_path(@filename)

    errors.reject do |error|
      next false if error.equal?(primary)

      format_display_path(error[:file]) == format_display_path(@filename) &&
        error[:text].to_s.match?(/\\begin\{document\} ended by|Extra \\endgroup/i)
    end
  end

  def report_compile_mode_errors(errors, content, io: $stderr)
    if json_mode?
      report_json_mode_errors(errors, content, io: $stdout)
      exit 1
    end

    if llm_mode?
      report_llm_mode_errors(errors, content, io: io)
      exit 1
    end

    io = $stdout if @options[:vscode_lw]
    displayed_errors, cascade_info = throttle_errors(errors)
    if displayed_errors.empty?
      disp = format_display_path(@filename)
      disp = "./#{disp}" if @options[:vscode_lw] && !disp.start_with?('/', './')
      displayed_errors = [{
        file: disp,
        line: 1,
        text: 'compilation failed; see log for details',
        tier: 'errors'
      }]
    end

    alerts = []
    warns = []
    whats = []
    if @options[:all] || @options[:vscode_lw]
      raw_warns = extract_warnings(content, false)
      alerts, warns, whats = partition_diagnostics(content, raw_warns)
    end

    emit_compile_diagnostics(
      errors: displayed_errors,
      alerts: alerts,
      warnings: warns,
      whatevers: whats,
      io: io
    )
    emit_compile_cascade_notice(cascade_info, io: io) unless @options[:vscode_lw]
    exit 1
  end

  def report_llm_mode_errors(errors, content, io: $stderr)
    log_tail = errors.empty? ? content : nil
    records = errors.map { |e| normalize_diagnostic(e, 'errors') }
    presenter = LaTeXAgentPresenter.new(@options)
    presenter.render_diagnostics(errors: records, log_tail: log_tail, file: @filename, io: io)
  end

  def report_json_mode_errors(errors, content, io: $stdout)
    records = errors.map { |e| normalize_diagnostic(e, 'errors') }
    result = LaTeXDiagnosticResult.new(
      success: false,
      exit_code: 1,
      pdf_path: nil,
      records: records,
      summary: { errors: records.size, alerts: 0, warnings: 0, whatevers: 0 },
      log_tail: errors.empty? ? content.to_s.lines.last(10).join : nil
    )
    presenter = LaTeXJsonPresenter.new(@options)
    presenter.render_result(result, io: io)
  end

  def report_errors(loga, io: $stderr)
    LaTeXIndicator.stop(clear: true)
    raw = LaTeXUtils.safe_read(loga)
    content = LaTeXUtils.filter_subcommand_noise(raw)

    compiler_errors = extract_errors(content)
    brace_errors = if compiler_errors.empty? || compiler_indicates_brace_error?(content)
                     check_source_braces
                   else
                     []
                   end
    compiler_errors = suppress_compiler_brace_cascades(compiler_errors, brace_errors)
    compiler_errors = suppress_environment_mismatch_cascades(compiler_errors)
    errors = prepare_error_items(compiler_errors) + brace_errors

    return report_compile_mode_errors(errors, content, io: io) if compile_mode?

    fallback = errors.empty? ? content.lines.last(15) : []
    displayed_errors, cascade_info = throttle_errors(errors)
    if @options[:emacs] || @options[:all]
      raw_warns = extract_warnings(content, false)
      alert_items, regular_warns, whatever_items = partition_diagnostics(content, raw_warns)
      render_grouped_tiers(displayed_errors, alert_items, regular_warns, whatever_items, fallback_lines: fallback, io: io)
    else
      _num_warnings, _num_errors = print_diagnostics_body([], displayed_errors, fallback_lines: fallback, tier_label: 'errors', io: io)
    end
    print_cascade_notice(cascade_info, io: io) if cascade_info

    if @options[:verbose] || fallback.any? || errors.empty?
      io.puts "See #{loga} for full error details."
    end
    report_error_summary(content, raw, brace_errors, errors.size, io: io)
    exit 1
  end

  def report_error_summary(content, raw, brace_errors, num_errors, io: $stdout)
    raw_warns = extract_warnings(content, false)
    alert_items, regular_warns, whatever_items = partition_diagnostics(content, raw_warns)

    brace_alerts_count = brace_errors.count { |e| e[:has_alert] }
    errors_count = [num_errors, count_latex_errors(raw, 1)].max
    alerts_count = alert_items.size + brace_alerts_count
    warnings_count = regular_warns.size
    whatevers_count = whatever_items.size
    suppressed = !@options[:emacs] && !@options[:all]
    print_summary_line(
      errors_count, alerts_count, warnings_count, whatevers_count,
      suppressed_alerts: suppressed && alerts_count > 0,
      suppressed_warnings: suppressed && warnings_count > 0,
      suppressed_whatevers: suppressed && whatevers_count > 0,
      io: io
    )
  end

  def collect_diagnostic_counts(new_content)
    cnt_overfull = new_content.scan(/overfull/i).size
    cnt_underfull = new_content.scan(/underfull/i).size
    cnt_bib = count_bib_messages
    cnt_undef_cite, cnt_undef_ref, cnt_mult_def = count_reference_messages(new_content)

    cbib = cnt_bib[:warns] + cnt_bib[:errors]
    {
      overfull: cnt_overfull, underfull: cnt_underfull,
      cbib: cbib, biberr: cnt_bib[:errors],
      undef_cite: cnt_undef_cite, undef_ref: cnt_undef_ref, mult_def: cnt_mult_def,
      bib_warns: cnt_bib[:warns]
    }
  end

  # Match the tools' actual error grammar. A bare scan for /error/i counted the
  # word anywhere it appeared -- including inside a .bib path the tool prints
  # back, such as "Found BibTeX data source 'papers/error-bounds/refs.bib'".
  # One such line set counts[:biberr], and render_diagnostics_tiers then renders
  # only the errors tier, so every real alert and warning was hidden. The same
  # scan also missed bibtex's actual failure text, which never says "error".
  BIB_ERROR_PATTERN = Regexp.union(
    /^ERROR\s+-\s/i,
    /couldn't open \w+ file/i,
    /^\s*I couldn't open/i,
    /\(There (?:was|were) \d+ error message/i
  ).freeze

  BIB_WARNING_PATTERN = /^Warning--|^Repeated entry---|^WARN\s+-\s/i.freeze

  def count_bib_messages
    return { warns: 0, errors: 0 } unless @biberr && File.exist?(@biberr)

    bib_content = LaTeXUtils.safe_read(@biberr)
    warns = bib_content.each_line.count { |l| l =~ BIB_WARNING_PATTERN }
    errors = bib_content.each_line.count { |l| l =~ BIB_ERROR_PATTERN }
    { warns: warns, errors: errors }
  end

  UNDEF_CITE_PATTERN = /^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+Citation\s+[`'"]?.*?['"]?\s+.*undefined/i.freeze
  UNDEF_REF_PATTERN  = /^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+Reference\s+[`'"]?.*?['"]?\s+.*undefined/i.freeze
  MULT_DEF_PATTERN   = /^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+Label\s+[`'"]?.*?['"]?\s+multiply defined/i.freeze

  def count_reference_messages(new_content)
    content = LaTeXUtils.filter_subcommand_noise(new_content)
    undef_cite = content.scan(UNDEF_CITE_PATTERN).size
    undef_ref  = content.scan(UNDEF_REF_PATTERN).size
    mult_def   = content.scan(MULT_DEF_PATTERN).size
    [undef_cite, undef_ref, mult_def]
  end


  def append_bib_diagnostics!(warn_items, err_items)
    return unless @biberr && File.exist?(@biberr)

    LaTeXUtils.safe_read(@biberr).each_line.with_index do |bl, bidx|
      if bl =~ BIB_WARNING_PATTERN
        line_str = (bl =~ /line\s+(\d+)/i) ? Regexp.last_match(1) : ''
        formatted = format_diagnostic_line(line_str, bl.strip, :yellow)
        warn_items << { file: './bibliography', line: line_str.to_i, line_str: line_str, text: bl.strip, formatted: formatted, index: 100000 + bidx }
      elsif bl =~ BIB_ERROR_PATTERN
        formatted = @options[:emacs] ? bl.strip : highlight_line_numbers(bl.strip, :red, bright: true)
        err_items << { file: './bibliography', line: 0, text: bl.strip, formatted: formatted, index: 100000 + bidx }
      end
    end
  end

  MISSING_DB_ENTRY_PATTERNS = [
    /WARN\s+-\s+I didn't find a database entry for '([^']+)'/i,
    /Warning--I didn't find a database entry for "([^"]+)"/i,
    /Package biblatex Warning: Entry '([^']+)' not found in database/i,
    /Package biblatex Warning: The following entr(?:y|ies) could not be found in the database:\s*([^\n\r]+)/i
  ].freeze

  def consolidate_missing_bib_entries!(warn_items)
    missing_keys = []

    warn_items.reject! do |w|
      txt = w[:text].to_s
      matched = false
      MISSING_DB_ENTRY_PATTERNS.each do |pat|
        if (m = txt.match(pat))
          raw_keys = m[1].split(/[,\s]+/).map { |k| k.gsub(/['"]/, '').strip }.reject(&:empty?)
          missing_keys.concat(raw_keys)
          matched = true
          break
        end
      end
      if !matched && w[:file].to_s.end_with?('.bbl') && txt =~ /Entry '([^']+)' not found in database/i
        missing_keys << Regexp.last_match(1)
        matched = true
      end
      matched
    end

    missing_keys.uniq!
    missing_keys.sort!
    return if missing_keys.empty?

    formatted_msg = format_missing_bib_entries(missing_keys)
    warn_text = @options[:emacs] ? formatted_msg : clean_diagnostic_warning(formatted_msg)
    warn_items << {
      file: './bibliography',
      line: 0,
      line_str: 'bib',
      text: warn_text,
      raw_text: formatted_msg,
      base_color: :yellow,
      count: missing_keys.size,
      formatted: format_diagnostic_line('bib', warn_text, :yellow, file: './bibliography'),
      index: 100000
    }
  end

  def format_missing_bib_entries(keys)
    if keys.size == 1
      "Missing database entry: '#{keys.first}'"
    else
      lines = ["Missing database entries (#{keys.size}):"]
      curr = '  '
      keys.each_with_index do |k, idx|
        tok = "'#{k}'"
        tok += ',' if idx < keys.size - 1
        if curr.length + tok.length + 1 > 72 && curr.strip != ''
          lines << curr
          curr = "  #{tok}"
        else
          curr += (curr == '  ' ? tok : " #{tok}")
        end
      end
      lines << curr unless curr.strip.empty?
      lines.join("\n")
    end
  end

  def analyze_output
    pdferr = find_last_latex_log
    if @options[:score]
      output_score(pdferr, 0)
      return
    end

    new_content = LaTeXUtils.safe_read(pdferr)
    counts = collect_diagnostic_counts(new_content)
    clean_content = LaTeXUtils.filter_subcommand_noise(new_content)
    raw_warns = extract_warnings(clean_content, @options[:verbose])
    err_items = extract_errors(clean_content)
    append_bib_diagnostics!(raw_warns, err_items) if counts[:cbib] > 0
    consolidate_missing_bib_entries!(raw_warns)

    alert_items, reg_warns, what_items = partition_diagnostics(clean_content, raw_warns)
    errors = count_latex_errors(new_content, 0) + counts[:biberr]

    display_analyzed_diagnostics(err_items, alert_items, reg_warns, what_items, errors)
  end

  def display_analyzed_diagnostics(err_items, alert_items, reg_warns, what_items, errors)
    alerts = alert_items.sum { |i| i[:count] || 1 }
    warnings = reg_warns.sum { |i| i[:count] || 1 }
    whatevers = what_items.sum { |i| i[:count] || 1 }

    if json_mode?
      errors = render_json_mode_tiers(err_items, alert_items, reg_warns, what_items, errors)
    elsif errors > 0 || alerts > 0 || warnings > 0 || whatevers > 0
      errors = render_diagnostics_tiers(err_items, alert_items, reg_warns, what_items, errors)
    end

    summarize_and_check_werror(errors, alerts, warnings, whatevers)
  end

  def render_compile_mode_tiers(err_items, alert_items, reg_warns, what_items, errors)
    if json_mode?
      return render_json_mode_tiers(err_items, alert_items, reg_warns, what_items, errors)
    end

    if llm_mode?
      return render_llm_mode_tiers(err_items, alert_items, reg_warns, what_items, errors)
    end

    prepared_errors = prepare_error_items(err_items)
    displayed_errors, cascade_info = throttle_errors(prepared_errors)
    has_errors = errors > 0 || !prepared_errors.empty?
    show_non_errors = @options[:all] || !has_errors || @options[:vscode_lw]

    out_io = @options[:vscode_lw] ? $stdout : $stderr
    emit_compile_diagnostics(
      errors: displayed_errors,
      alerts: show_non_errors ? alert_items : [],
      warnings: show_non_errors ? reg_warns : [],
      whatevers: show_non_errors ? what_items : [],
      io: out_io
    )
    emit_compile_cascade_notice(cascade_info, io: out_io) unless @options[:vscode_lw]
    [prepared_errors.size, errors].max
  end

  def render_llm_mode_tiers(err_items, alert_items, reg_warns, what_items, errors)
    prepared_errors = prepare_error_items(err_items)
    err_records = prepared_errors.map { |e| normalize_diagnostic(e, 'errors') }
    alt_records = alert_items.map { |a| normalize_diagnostic(a, 'alerts') }
    wrn_records = reg_warns.map { |w| normalize_diagnostic(w, 'warnings') }
    wht_records = what_items.map { |wh| normalize_diagnostic(wh, 'whatevers') }

    presenter = LaTeXAgentPresenter.new(@options)
    presenter.render_diagnostics(
      errors: err_records,
      alerts: alt_records,
      warnings: wrn_records,
      whatevers: wht_records,
      file: @filename,
      io: $stderr
    )
    [prepared_errors.size, errors].max
  end

  def render_json_mode_tiers(err_items, alert_items, reg_warns, what_items, errors)
    prepared_errors = prepare_error_items(err_items)
    has_errors = errors > 0 || !prepared_errors.empty?
    has_werrors = @options[:werror] && (alert_items.any? || reg_warns.any?)
    failed = has_errors || has_werrors

    err_records = prepared_errors.map { |e| normalize_diagnostic(e, 'errors') }
    alt_records = alert_items.map { |a| normalize_diagnostic(a, 'alerts') }
    wrn_records = reg_warns.map { |w| normalize_diagnostic(w, 'warnings') }
    wht_records = what_items.map { |wh| normalize_diagnostic(wh, 'whatevers') }

    all_records = err_records + alt_records + wrn_records + wht_records
    pdf_file = "#{@bfilename}.pdf"
    result = LaTeXDiagnosticResult.new(
      success: !failed,
      exit_code: failed ? 1 : 0,
      pdf_path: (!failed && File.exist?(pdf_file)) ? pdf_file : nil,
      records: all_records,
      summary: {
        errors: err_records.size,
        alerts: alt_records.size,
        warnings: wrn_records.size,
        whatevers: wht_records.size
      }
    )
    presenter = LaTeXJsonPresenter.new(@options)
    presenter.render_result(result, io: $stdout)
    [prepared_errors.size, errors].max
  end

  def render_diagnostics_tiers(err_items, alert_items, reg_warns, what_items, errors)
    return render_compile_mode_tiers(err_items, alert_items, reg_warns, what_items, errors) if compile_mode?

    if errors > 0 || !err_items.empty?
      prepared_errors = prepare_error_items(err_items)
      displayed_errors, cascade_info = throttle_errors(prepared_errors)
      if @options[:emacs] || @options[:all]
        render_grouped_tiers(displayed_errors, alert_items, reg_warns, what_items, io: $stdout)
      else
        _num_warnings, _num_errors = print_diagnostics_body([], displayed_errors, tier_label: 'errors')
      end
      print_cascade_notice(cascade_info, io: $stdout) if cascade_info
      [prepared_errors.size, errors].max
    else
      render_grouped_tiers([], alert_items, reg_warns, what_items, io: $stdout)
      errors
    end
  end

  def render_non_error_tiers(alert_items, reg_warns, what_items, io: $stdout)
    render_grouped_tiers([], alert_items, reg_warns, what_items, io: io)
  end

  def render_grouped_tiers(error_items, alert_items, reg_warns, what_items, fallback_lines: [], io: $stdout)
    suppress_alerts = @options[:suppress_alerts] == true
    suppress_warnings = @options[:suppress_warnings] == true
    suppress_whatevers = @options[:suppress_whatevers] != false

    items_to_display = []
    error_items.each { |e| (it = e.dup)[:tier] = 'errors'; it[:base_color] ||= :red; items_to_display << it }
    unless suppress_alerts
      alert_items.each { |a| (it = a.dup)[:tier] = 'alerts'; it[:base_color] ||= :red; items_to_display << it }
    end
    unless suppress_warnings
      reg_warns.each { |w| (it = w.dup)[:tier] = 'warnings'; w[:base_color] ||= :yellow; items_to_display << it }
    end
    unless suppress_whatevers
      what_items.each do |wh|
        it = wh.dup
        it[:base_color] = :cyan
        it[:tier] = 'whatevers'
        it[:formatted] = format_diagnostic_line(wh[:line_str], wh[:text], :cyan, file: wh[:file])
        items_to_display << it
      end
    end

    return if items_to_display.empty? && fallback_lines.empty?

    print_diagnostics_body(items_to_display, [], fallback_lines: fallback_lines, io: io)
  end

  def print_compile_success_if_clean(errors, alerts, warnings)
    return if @options && @options[:vscode_lw]
    return unless errors.zero? && !llm_mode? && !json_mode?
    return if @options[:werror] && (alerts.positive? || warnings.positive?)

    msg = (@options && @options[:color] == false) ? 'Compilation succeeded.' : Rainbow('Compilation succeeded.').green.bright
    puts msg
  end

  def summarize_and_check_werror(errors, alerts, warnings, whatevers)
    suppressed_alt = (errors > 0 && !@options[:emacs] && !@options[:all]) || (@options[:suppress_alerts] == true)
    suppressed_wrn = (errors > 0 && !@options[:emacs] && !@options[:all]) || (@options[:suppress_warnings] == true)
    suppressed_wht = (errors > 0 && !@options[:emacs] && !@options[:all]) || (@options[:suppress_whatevers] != false)

    if compile_mode?
      print_compile_success_if_clean(errors, alerts, warnings)
    else
      print_summary_line(
        errors, alerts, warnings, whatevers,
        suppressed_alerts: suppressed_alt && alerts > 0,
        suppressed_warnings: suppressed_wrn && warnings > 0,
        suppressed_whatevers: suppressed_wht && whatevers > 0
      )
    end

    fail_on_diagnostics(errors, alerts, warnings)
  end

  # The exit status has to agree with the summary line the user just read.
  # summarize_and_check_werror printed `errors` and then ignored it, so a run
  # that reported "Errors: 2" still exited 0 -- and -W only ever looked at
  # alerts and warnings, so even that flag could not make an error fatal.
  def fail_on_diagnostics(errors, alerts, warnings)
    if errors.positive?
      puts Rainbow("\n#{errors} error(s) reported; exiting with a non-zero status.").red.bright unless compile_mode?
      exit 1
    end
    return unless @options[:werror] && (alerts.positive? || warnings.positive?)

    if compile_mode?
      warn 'leeni: error: warnings being treated as errors (--werror)' unless json_mode?
    else
      puts Rainbow("\n[Werror] Warnings treated as fatal errors.").red.bright
    end
    exit 1
  end

  # Per-pass logs are err_<engine>_<N>; N is unbounded (up to MAX_PASSES), so
  # they are discovered rather than enumerated.
  def pass_log_files
    dir = File.dirname(@pdferr)
    base = File.basename(@pdferr)
    pattern = /\A#{Regexp.escape(base)}_(\d+)\z/
    return [] unless File.directory?(dir)

    Dir.children(dir).select { |f| f.match?(pattern) }.sort_by { |f| f[pattern, 1].to_i }.map { |f| File.join(dir, f) }
  end

  def find_last_latex_log = pass_log_files.last || @pdferr

  def count_latex_errors(content, status = 0)
    errors = 0
    clean_content = LaTeXUtils.filter_subcommand_noise(content)
    clean_content.each_line do |line|
      next if line =~ /^!\s*(?:==>\s*)?(?:Emergency stop|Fatal error occurred)/i
      next if typeset_source_echo?(line)

      if line =~ /^!\s+\S+/ ||
         line =~ /^.+:\d+:\s+(?:(?:LaTeX|Package|Class)\s+Error:|Undefined control sequence|Error:|Runaway argument\?|Missing\s|Extra\s|You can't use)/i ||
         line =~ /^.+:\d+:\s+.*error/i || line =~ /^Error:\s+/i
        errors += 1
      end
    end
    errors = 1 if errors == 0 && status.to_i > 0
    errors
  end

  def count_latex_warnings(content)
    warnings = 0
    content.each_line do |line|
      next if line.include?('multiply defined') && line.include?('LaTeX Warning')

      if line =~ WARNING_LINE_PATTERN ||
         line =~ /^.+:\d+:\s+warning:/i || line =~ /^Warning:\s+/i ||
         line =~ /^(?:Overfull|Underfull) \\(?:hbox|vbox)/
        warnings += 1
      end
    end
    warnings
  end

  def output_score(last_log_path = nil, status = 0)
    last_log_path ||= find_last_latex_log
    content = LaTeXUtils.safe_read(last_log_path)
    clean_content = LaTeXUtils.filter_subcommand_noise(content)
    raw_warns = extract_warnings(clean_content, false)
    alert_items, regular_warns, whatever_items = partition_diagnostics(clean_content, raw_warns)

    errors = count_latex_errors(content, status)
    alerts = alert_items.size
    warnings = regular_warns.size
    whatevers = whatever_items.size
    suppress_alerts = @options[:suppress_alerts] == true
    suppress_warnings = @options[:suppress_warnings] == true
    suppress_whatevers = @options[:suppress_whatevers] != false

    print_summary_line(
      errors, alerts, warnings, whatevers,
      suppressed_alerts: suppress_alerts && alerts > 0,
      suppressed_warnings: suppress_warnings && warnings > 0,
      suppressed_whatevers: suppress_whatevers && whatevers > 0
    )

    # analyze_output returns early for :score, so without this `l -s -W` could
    # never fail -- the flag whose only purpose is a non-zero exit status was
    # silently disabled by the flag whose purpose is a quiet one.
    fail_on_diagnostics(errors, alerts, warnings)
  end
end
