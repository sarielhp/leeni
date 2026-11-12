# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostic_summary.rb
#
# Summary line, error throttling and cascades, and the error report of a failed pass.
# Part of LaTeXDiagnostics (lib/leeni/diagnostics.rb), which includes it.
# ==============================================================================

module LaTeXDiagnostics
  # Summary line, error throttling and cascades, and the error report of a failed pass.
  module Summary
    def format_tier_count(label, count, color)
      if count.zero?
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
      suppressed << alt_label if suppressed_alerts && alerts.positive?
      suppressed << wrn_label if suppressed_warnings && warnings.positive?
      suppressed << wht_label if suppressed_whatevers && whatevers.positive?

      return '' if suppressed.empty?

      all_non_errors = [alerts.positive?, warnings.positive?, whatevers.positive?].count(true)
      if suppressed.size == all_non_errors && all_non_errors > 1
        "  #{Rainbow('(non-errors suppressed)').faint}"
      else
        "  #{Rainbow("(#{suppressed.join(', ')} suppressed)").faint}"
      end
    end

    def print_summary_line(errors, alerts, warnings, whatevers,
                           suppressed_warnings: false, suppressed_whatevers: false, suppressed_alerts: false, io: nil)
      return if @options && compile_mode?

      target_io = io || (@options && @options[:score] ? (@orig_stdout || $stdout) : $stdout)
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
        alerts: !tier_suppressed?(:alerts, explicit_suppressed: supp_alerts),
        warnings: !tier_suppressed?(:warnings, explicit_suppressed: supp_warns),
        whatevers: !tier_suppressed?(:whatevers, explicit_suppressed: supp_whats)
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

    def tier_suppressed?(tier, explicit_suppressed: false)
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

      # leeni's own findings (brace audit, promoted label errors) are never
      # cascades of a compiler error, so they are shown regardless of file.
      own, compiler = errors.partition { |e| e[:source] == :leeni }
      return [errors, nil] if compiler.size <= 1

      groups = compiler.group_by { |e| format_display_path(e[:file]) }
      first_file = primary_error_file(groups)
      file_errors = groups[first_file] || []
      companion_errors = compiler.select { |e| e[:companion_to] == first_file }
      companion_files = companion_errors.map { |ce| format_display_path(ce[:file]) }.uniq

      return [errors, nil] if groups.size <= (1 + companion_files.size) && file_errors.size <= 10

      displayed = own + file_errors.first(10) + companion_errors
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
      if cascade_info[:remaining_in_first].positive?
        msg = "▸ #{cascade_info[:remaining_in_first]} more errors in #{cascade_info[:first_file]} were truncated (likely cascades)."
        io.puts Rainbow(LaTeXUtils.wrap_text(msg, width: cols)).yellow
      end
      if cascade_info[:other_errors_count].positive?
        files_str = format_other_files_list(cascade_info[:other_files])
        msg1 = "▸ #{cascade_info[:other_errors_count]} more errors were detected across " \
               "#{cascade_info[:other_files].size} other files (#{files_str})."
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

      note_label = @options && @options[:color] == false ? 'note:' : Rainbow('note:').cyan.bright.bold.to_s
      if cascade_info[:remaining_in_first].to_i.positive?
        msg = "#{cascade_info[:remaining_in_first]} more errors in #{cascade_info[:first_file]} were truncated"
        io.puts "leeni: #{note_label} #{msg} (run with 'l -a' to display all)"
      end
      return unless cascade_info[:other_errors_count].to_i.positive?

      files_str = format_other_files_list(cascade_info[:other_files])
      msg = "#{cascade_info[:other_errors_count]} more errors detected across #{cascade_info[:other_files].size} other files (#{files_str})"
      io.puts "leeni: #{note_label} #{msg} (run with 'l -a' to display all)"
    end

    COMPILER_BRACE_ERROR_PATTERN = /(?:Runaway argument\?|File ended while scanning use of|Extra \}, or forgotten \\endgroup|Extra \\endgroup|Too many \}'s|Missing \} inserted|Paragraph ended before .* was complete|\\begin\{.*\} ended by \\end\{.*\})/i
    COMPILER_BRACE_CASCADE_IDS = %i[
      paragraph_ended_before_complete file_ended_while_scanning no_pages_of_output
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
        raw_warns = extract_warnings(content, verbose: false)
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
      alerts, = partition_diagnostics(content, extract_warnings(content, verbose: false))
      alert_records = alerts.map { |a| normalize_diagnostic(a, 'alerts') }
      presenter = LaTeXAgentPresenter.new(@options)
      presenter.render_diagnostics(errors: records, alerts: alert_records, log_tail: log_tail, file: @filename, io: io)
    end

    def report_json_mode_errors(errors, content, io: $stdout)
      records = errors.map { |e| normalize_diagnostic(e, 'errors') }
      result = LaTeXDiagnosticResult.new(
        build: json_build_report,
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
        raw_warns = extract_warnings(content, verbose: false)
        alert_items, regular_warns, whatever_items = partition_diagnostics(content, raw_warns)
        render_grouped_tiers(displayed_errors, alert_items, regular_warns, whatever_items, fallback_lines: fallback, io: io)
      else
        _num_warnings, _num_errors = print_diagnostics_body([], displayed_errors, fallback_lines: fallback, tier_label: 'errors', io: io)
      end
      print_cascade_notice(cascade_info, io: io) if cascade_info

      io.puts "See #{loga} for full error details." if @options[:verbose] || fallback.any? || errors.empty?
      report_error_summary(content, raw, brace_errors, errors.size, io: io)
      exit 1
    end

    def report_error_summary(content, raw, brace_errors, num_errors, io: $stdout)
      raw_warns = extract_warnings(content, verbose: false)
      alert_items, regular_warns, whatever_items = partition_diagnostics(content, raw_warns)

      brace_alerts_count = brace_errors.count { |e| e[:has_alert] }
      errors_count = [num_errors, count_latex_errors(raw, 1)].max
      alerts_count = alert_items.size + brace_alerts_count
      warnings_count = regular_warns.size
      whatevers_count = whatever_items.size
      suppressed = !@options[:emacs] && !@options[:all]
      print_summary_line(
        errors_count, alerts_count, warnings_count, whatevers_count,
        suppressed_alerts: suppressed && alerts_count.positive?,
        suppressed_warnings: suppressed && warnings_count.positive?,
        suppressed_whatevers: suppressed && whatevers_count.positive?,
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
  end
end
