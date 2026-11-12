# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostic_output.rb
#
# Ordering and printing diagnostic items: tiers, compile/LLM/JSON/VS Code records, banners, categories.
# Part of LaTeXDiagnostics (lib/leeni/diagnostics.rb), which includes it.
# ==============================================================================

module LaTeXDiagnostics
  # Ordering and printing diagnostic items: tiers, compile/LLM/JSON/VS Code records, banners, categories.
  module Output
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
      target = format_display_path(item[:companion_to] || item[:file])
      rank = item[:companion_to] ? 1 : 0
      t_rank = TIER_RANK[tier_label_for(item)] || 2
      line_num = if item[:line].is_a?(Integer) && item[:line].positive?
                   item[:line]
                 elsif item[:line_str].to_s =~ /\A(\d+)/
                   ::Regexp.last_match(1).to_i
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
        counts[f][lbl] += item[:count] || 1
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
      }.merge(box_fields(item))
    end

    BOX_HEADER_KINDS = [
      [/ in paragraph at lines /, 'paragraph'],
      [/ in alignment at lines /, 'alignment'],
      [/ detected at line /, 'detected_line']
    ].freeze
    FONT_SWITCH_PATTERN = %r{\\[A-Za-z0-9]+/[^\s/]+/[a-z]+/[a-z]+/\d+(?:\.\d+)?\s?}
    BOX_SNIPPET_MAX = 90

    # Box-specific fields for JSON and -llm output: the span end, which TeX header
    # form produced the box (a display or alignment row is reported "detected at
    # line N", running text "in paragraph at lines N--M"), and the echoed text.
    def box_fields(item)
      return {} unless item[:type].is_a?(String) && item[:type] =~ /\A(?:Overfull|Underfull)/

      header = item[:raw_text].to_s
      kind = BOX_HEADER_KINDS.find { |pattern, _| header =~ pattern }&.last || 'other'
      context = LaTeXBoxContext.describe(item[:file], item[:line], kind, item[:line_end])
      kind = 'heading' if context[:heading]
      fields = { line_end: item[:line_end], box_kind: kind, snippet: box_snippet(item[:extra_lines]) }.compact
      fields.merge(context)
    end

    def box_snippet(extra_lines)
      echo = Array(extra_lines).first.to_s
      text = echo.gsub(FONT_SWITCH_PATTERN, '').gsub('[]', '').gsub(/\s+/, ' ').strip
      return nil if text.empty?

      text.length > BOX_SNIPPET_MAX ? "#{text[0, BOX_SNIPPET_MAX]}..." : text
    end

    def normalized_line(item)
      root_line = item[:root_line] || item.dig(:catalog, :root_line)
      if root_line&.to_i&.positive?
        root_line.to_i
      elsif item[:line]&.to_i&.positive?
        item[:line].to_i
      else
        item[:line_str].to_s =~ /\A\d+\z/ ? item[:line_str].to_i : 0
      end
    end

    def normalized_col(item)
      c = item[:col] || item[:root_col] || item.dig(:catalog, :root_col)
      c&.to_i&.positive? ? c.to_i : nil
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

      col_pos = record[:col]&.to_i&.positive? ? record[:col].to_i - 1 : nil
      token_len = record[:token] && !record[:token].to_s.empty? ? record[:token].to_s.length : 1
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
      line = record[:line]&.to_i&.positive? ? record[:line].to_i : 1
      msg = LaTeXCompileFormat.format_message(record, color: false)
      cat = record[:category] || (respond_to?(:diagnostic_category, true) ? diagnostic_category(record) : nil)
      expl = cat && cat != :generic ? (DIAGNOSTIC_EXPLANATIONS[cat] || LaTeXErrorCatalog.find_by_id(cat)) : nil
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
        .flat_map { |tier, items| (items || []).map { |entry| normalize_diagnostic(entry, tier) } }
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
                 { tier_or_counts.to_s => count || 1 }
               end

      top_tier = TIER_SEVERITY_ORDER.find { |t| counts[t]&.positive? } || 'warnings'
      color = tier_color(top_tier)

      label_parts = []
      uncolored_parts = []
      TIER_SEVERITY_ORDER.each do |tier|
        cnt = counts[tier]
        next unless cnt&.positive?

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
      elsif sev.positive? && sev <= whatever_overfull_pt
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

      simple = simple_text_category(txt)
      return simple if simple
      return :font_shape if txt.include?('Some font shapes were not available') ||
                            txt =~ /Font shape .* (?:undefined|not available)/i
      return :summary_warning if txt.include?('There were multiply-defined labels') ||
                                 txt.include?('There were undefined references') ||
                                 txt.include?('Size substitutions with differences')
      return :etex_allocation if txt.include?('Extended allocation already in use')

      :generic
    end

    SIMPLE_TEXT_CATEGORIES = [
      [/unused global option/i, :unused_global_option],
      [/invalid in math mode/i, :invalid_in_math_mode],
      [/build did not converge/i, :unconverged_build],
      [/Float too large for page/i, :float_too_large],
      [/Repeated entry---|Duplicate entry key/i, :bib_repeated_entry],
      [/Missing database entr/i, :missing_bib_entry],
      [/Duplicate hyperlink destination/i, :duplicate_destination],
      [/pt too high/i, :overfull_vbox],
      [/Token not allowed in a PDF string/, :hyperref_token],
      [/float specifier changed to/i, :float_specifier]
    ].freeze

    def simple_text_category(txt)
      SIMPLE_TEXT_CATEGORIES.each { |pattern, category| return category if txt.match?(pattern) }
      nil
    end

    def alert_overfull_pt
      (@options[:alert_overfull_pt] || 24.0).to_f
    end

    def whatever_overfull_pt
      (@options[:whatever_overfull_pt] || 2.5).to_f
    end
  end
end
