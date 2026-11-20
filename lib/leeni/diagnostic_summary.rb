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

      errors = errors.reject { |error| merge_brace_fault(error, brace_errors) }
      errors.reject { |error| COMPILER_BRACE_CASCADE_IDS.include?(error[:catalog_id]) }
    end

    # The compiler error each kind of pre-flight brace error can stand for.
    BRACE_FAULT_KINDS = {
      extra_closing_brace: :extra, missing_closing_brace: :unclosed,
      file_ended_while_scanning: :unclosed, paragraph_ended_before_complete: :unclosed
    }.freeze
    SAME_LINE_BRACE_FAULTS = %i[extra_closing_brace missing_closing_brace].freeze

    # TeX and the pre-flight brace check often report one brace fault twice:
    # "Too many }'s" beside "Extra closing brace", or "Missing } inserted" /
    # "File ended while scanning" beside "Unclosed open brace". The pre-flight
    # error knows the column and the line the brace was opened on; the compiler
    # error knows the category and the hint. The brace error takes those over
    # and the compiler error is dropped (returns true).
    def merge_brace_fault(error, brace_errors)
      kind = BRACE_FAULT_KINDS[error[:catalog_id]]
      return false unless kind

      brace = brace_errors.find do |b|
        !b[:catalog_id] && brace_fault_kind(b) == kind && brace_fault_matches?(error, b)
      end
      return false unless brace

      # The token belongs to the compiler message (the macro whose argument ran
      # away); the hint already names it, and it would mark the wrong span here.
      brace[:catalog] = (error[:catalog] || {}).merge(root_line: brace[:line], root_col: brace[:col], token: nil)
      brace[:catalog_id] = error[:catalog_id]
      brace[:log_index] = error[:log_index]
      true
    end

    # A brace error that took over a compiler error goes where that error was
    # in TeX's order, ahead of the errors it caused; appended after them, the
    # root of a broken \newcommand or \begin{proof came last, after its
    # cascade. Brace errors TeX did not report keep their place at the end.
    def place_merged_brace_errors(prepared, brace_errors)
      merged, rest = brace_errors.partition { |brace| brace[:log_index] }
      queue = merged.sort_by { |brace| brace[:log_index] }
      placed = prepared.each_with_object([]) do |item, out|
        out << queue.shift while item[:log_index] && queue.any? && queue.first[:log_index] < item[:log_index]
        out << item
      end
      placed + queue + rest
    end

    def brace_fault_kind(brace)
      brace[:text].to_s.include?("Extra closing brace '}'") ? :extra : :unclosed
    end

    def brace_fault_matches?(error, brace)
      return true unless SAME_LINE_BRACE_FAULTS.include?(error[:catalog_id])

      error[:line].to_i == brace[:line].to_i && File.basename(error[:file].to_s) == File.basename(brace[:file].to_s)
    end

    # One bad word in \hyphenation (an accent macro, a babel shorthand) makes
    # TeX expand its commands inside the list: an "Improper \hyphenation" for
    # each, and Missing \begin{document}, Extra } and the like. Every later
    # error on that line is part of it and is counted in the first.
    # Dropped text that is nowhere in the source (a command's name, printed
    # while TeX recovers from another error) is a symptom of that error, not
    # text the author wrote; it is reported only when nothing else is.
    # A brace error (an unclosed table { in pgfplots) counts as something else.
    def suppress_unlocated_dropped_text(errors, brace_errors = [])
      unlocated = errors.select { |error| error[:catalog_id] == :dropped_text && error[:line].to_i <= 0 }
      unlocated.size == errors.size && brace_errors.empty? ? errors : errors - unlocated
    end

    # One # in a frame body is reported for each macro that reads it
    # (\iterate, \beamer@doifinframe); at one place it is one fault. Other
    # faults reported more than once are merged by repeated_fault_key.
    def merge_repeated_faults(errors)
      seen = {}
      errors.reject do |error|
        key = repeated_fault_key(error)
        key && seen.key?(key).tap { seen[key] = true }
      end
    end

    # A package option LaTeX does not know is reported again wherever another
    # package loads that package (tikz loading xcolor): one fault, one error.
    def repeated_fault_key(error)
      case error[:catalog_id]
      when :illegal_parameter_number then [format_display_path(error[:file]), error[:line]]
      when :unknown_package_option then error[:text].to_s[/Unknown option .*/]
      # siunitx repeats its refusal at \begin{document}.
      when :siunitx_incompatible_package then error[:text].to_s[/Package [`'][^']+' incompatible/]
      end
    end

    # A matrix & read with the wrong catcode makes pgf look for its internal
    # cell macros and typeset the cells as loose text; with the ampersand error
    # reported, those are not shown as faults of their own.
    def suppress_ampersand_cascades(errors)
      primary = errors.select { |error| error[:catalog_id] == :wrong_catcode_ampersand }
      return errors if primary.empty?

      last = primary.map { |error| error[:line].to_i }.max
      errors.reject do |error|
        next true if error[:catalog_id] == :undefined_control_sequence && error[:token].to_s.start_with?('\pgf@matrix@')

        error[:catalog_id] == :dropped_text && error[:line].to_i.between?(last - 20, last)
      end
    end

    # An error whose recovery TeX reports as more errors on the same line: an
    # improper \hyphenation, a TikZ picture whose external build failed.
    # siunitx next to units: \unit is reported as already defined there.
    SAME_LINE_CASCADE_PRIMARIES = %i[improper_hyphenation tikz_external_failed siunitx_incompatible_package].freeze

    def suppress_hyphenation_cascades(errors)
      primary = errors.find { |error| SAME_LINE_CASCADE_PRIMARIES.include?(error[:catalog_id]) }
      return errors unless primary

      place = [format_display_path(primary[:file]), primary[:line]]
      errors.reject do |error|
        next false if error.equal?(primary)

        [format_display_path(error[:file]), error[:line]] == place || external_cascade?(primary, error)
      end
    end

    # A runaway argument abandons the macro that read it, leaving its groups
    # and conditionals open: TeX notes them at \end{document}, at the line the
    # argument began on. Opened in the paragraph whose end stopped the argument,
    # they are that one fault (TeX.SE 69425).
    def suppress_runaway_group_notes(errors)
      ends = errors.select { |error| error[:catalog_id] == :paragraph_ended_before_complete }
      return errors if ends.empty?

      errors.reject do |error|
        error[:catalog_id] == :unclosed_group_at_end && ends.any? { |stop| opened_in_paragraph?(error, stop) }
      end
    end

    def opened_in_paragraph?(note, stop)
      return false unless format_display_path(note[:file]) == format_display_path(stop[:file])

      opened = note[:line].to_i
      ended = stop[:line].to_i
      return false unless opened.positive? && opened <= ended

      lines = LaTeXUtils.safe_read(stop[:file]).lines
      ((opened + 1)...ended).none? { |no| lines[no - 1].to_s.strip.empty? }
    end

    # "File ended while scanning use of \next" from the comment package: the
    # body of an excluded environment is read to the end of the file when its
    # \end is not recognised (indented, TeX.SE 77920). The \begin it is placed
    # at is that environment; the brace hint does not apply.
    def retag_verbatim_runaways(errors)
      errors.each do |error|
        next unless error[:catalog_id] == :file_ended_while_scanning

        verbatim = scan_environments(LaTeXUtils.safe_read(@filename))[:verbatim]
        next unless verbatim && verbatim[:line] == error[:line].to_i

        entry = LaTeXErrorCatalog.find_by_id(:verbatim_environment_unclosed)
        error[:catalog] = (error[:catalog] || {}).merge(
          hint: LaTeXErrorCatalog.resolve_hint(entry[:hint], "{#{verbatim[:name]}}, \\end{#{verbatim[:end]}}")
        )
      end
    end

    # fontenc without the encoding's file (T5 without vntex): LaTeX then
    # reports "Encoding scheme `T5' unknown" at the \usepackage and at every
    # later font change; all of it is the one missing file.
    def suppress_missing_encoding_cascades(errors)
      missing = errors.filter_map do |error|
        error[:catalog_id] == :file_not_found && error[:text].to_s[/[`'](\w+)enc\.def' not found/, 1]&.upcase
      end
      return errors if missing.empty?

      errors.reject do |error|
        enc = error[:text].to_s[/Encoding scheme [`'](\w+)' unknown/, 1]
        enc && missing.include?(enc.upcase)
      end
    end

    # A failed external picture leaves its environment's body unread: the
    # environment and the groups around it are reported as unclosed.
    def external_cascade?(primary, error)
      primary[:catalog_id] == :tikz_external_failed &&
        %i[mismatched_environment unclosed_group_at_end].include?(error[:catalog_id])
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

    def report_compile_mode_errors(analysis, content, io: $stderr)
      if json_mode?
        report_json_mode_errors(analysis, content, io: $stdout)
        exit 1
      end

      if llm_mode?
        report_llm_mode_errors(analysis, content, io: io)
        exit 1
      end

      io = $stdout if @options[:vscode_lw]
      displayed_errors, cascade_info = throttle_errors(analysis.errors)
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

      show_non_errors = @options[:all] || @options[:vscode_lw]
      emit_compile_diagnostics(
        errors: displayed_errors,
        alerts: show_non_errors ? analysis.alerts : [],
        warnings: show_non_errors ? analysis.warnings : [],
        whatevers: show_non_errors ? analysis.whatevers : [],
        io: io
      )
      emit_compile_cascade_notice(cascade_info, io: io) unless @options[:vscode_lw]
      exit 1
    end

    def report_llm_mode_errors(analysis, content, io: $stderr)
      log_tail = analysis.errors.empty? ? content : nil
      records = diagnostic_records(analysis, %i[errors alerts])
      presenter = LaTeXAgentPresenter.new(@options)
      presenter.render_diagnostics(**records, log_tail: log_tail, file: @filename, io: io)
    end

    # A failed pass reports its errors and, as -llm does, its alerts: a silent
    # corruption found on the way is still worth knowing while fixing the error.
    def report_json_mode_errors(analysis, content, io: $stdout)
      records = diagnostic_records(analysis, %i[errors alerts])
      alerts = tier_suppressed?(:alerts) ? [] : records[:alerts]
      errors = records[:errors].empty? ? [unclassified_failure_record] : records[:errors]
      result = LaTeXDiagnosticResult.new(
        build: json_build_report,
        success: false,
        exit_code: 1,
        pdf_path: nil,
        records: errors + alerts,
        summary: { errors: errors.size, alerts: alerts.size, warnings: 0, whatevers: 0 },
        log_tail: analysis.errors.empty? ? content.to_s.lines.last(10).join : nil
      )
      presenter = LaTeXJsonPresenter.new(@options)
      presenter.render_result(result, io: io)
    end

    # A failed pass whose log names no error leeni recognises. -llm reports it
    # as an error with the log tail; --json reported success: false with no
    # error at all, which a caller counting errors read as a clean build.
    def unclassified_failure_record
      text = 'Compilation failed with an error leeni could not classify; see log_tail'
      item = { file: @filename, line: 0, line_str: '', text: text, err_block: [text], category: :unclassified_failure,
               catalog: {}, base_color: :red, tier: 'errors', source: :leeni, synthetic: true }
      normalize_diagnostic(item, 'errors')
    end

    BIBLIOGRAPHY_FAILED_HINT = 'The bibliography tool stopped without writing a bibliography; fix what its message names'

    # A fatal bibliography run ends the build with no failed LaTeX pass to read,
    # and printed only a line of text: -cc and -llm had no file:line: error and
    # --json no JSON at all. It is reported like a failed pass instead, at the
    # line naming the database when the tool says which one it could not open.
    def report_bibliography_failure(detail)
      return unless compile_mode?

      file, line = locate_bibliography_failure(detail) || [@filename, 0]
      text = "Bibliography run failed: #{detail.empty? ? 'see the bibliography log' : detail}"
      item = { file: file, line: line, line_str: line.positive? ? line.to_s : '', text: text, err_block: [text],
               category: :bibliography_failed, catalog: { hint: BIBLIOGRAPHY_FAILED_HINT },
               base_color: :red, tier: 'errors', source: :leeni, synthetic: true }
      analysis = Leeni::DiagnosticAnalysis.new(errors: [item], alerts: [], warnings: [], whatevers: [],
                                               error_count: 1, brace_errors: [])
      report_compile_mode_errors(analysis, '', io: $stderr)
    end

    # The line naming the database BibTeX could not open, or the \bibliography
    # line when the style is what is missing.
    def locate_bibliography_failure(detail)
      match = detail.match(LaTeXBibManager::MISSING_DATABASE)
      database = (match ? match.captures.compact.first : '').to_s.sub(/[.,;:]+\z/, '')
      return locate_missing_resource_request(database) unless database.empty?
      return unless detail.match?(/no \\bibstyle command/)

      collect_source_candidates.each do |source|
        LaTeXUtils.safe_read(source).each_line.with_index(1) do |text, line_no|
          return [source, line_no] if LaTeXUtils.strip_latex_comments(text).match?(/\\bibliography\s*\{/)
        end
      end
      nil
    end

    def report_errors(loga, io: $stderr)
      LaTeXIndicator.stop(clear: true)
      raw = LaTeXUtils.safe_read(loga)
      content = LaTeXUtils.filter_subcommand_noise(raw)
      analysis = analyze_failed_log(content)
      return report_compile_mode_errors(analysis, content, io: io) if compile_mode?

      errors = analysis.errors
      fallback = errors.empty? ? content.lines.last(15) : []
      displayed_errors, cascade_info = throttle_errors(errors)
      if @options[:emacs] || @options[:all]
        render_grouped_tiers(displayed_errors, analysis.alerts, analysis.warnings, analysis.whatevers,
                             fallback_lines: fallback, io: io)
      else
        _num_warnings, _num_errors = print_diagnostics_body([], displayed_errors, fallback_lines: fallback, tier_label: 'errors', io: io)
      end
      print_cascade_notice(cascade_info, io: io) if cascade_info

      io.puts "See #{loga} for full error details." if @options[:verbose] || fallback.any? || errors.empty?
      report_error_summary(analysis, raw, io: io)
      exit 1
    end

    # Everything report_errors decides about the log of a failed pass, without
    # printing any of it: the compiler errors (cascades of a brace fault or an
    # environment mismatch dropped) followed by the pre-flight brace errors,
    # and the tiers of the warnings.
    def analyze_failed_log(content)
      compiler_errors = extract_errors(content)
      brace_errors = if compiler_errors.empty? || compiler_indicates_brace_error?(content)
                       check_source_braces
                     else
                       []
                     end
      compiler_errors.each_with_index { |error, index| error[:log_index] = index }
      compiler_errors = suppress_compiler_brace_cascades(compiler_errors, brace_errors)
      compiler_errors = suppress_environment_mismatch_cascades(compiler_errors)
      compiler_errors = suppress_hyphenation_cascades(compiler_errors)
      compiler_errors = suppress_missing_encoding_cascades(compiler_errors)
      compiler_errors = suppress_runaway_group_notes(compiler_errors)
      retag_verbatim_runaways(compiler_errors)
      compiler_errors = suppress_ampersand_cascades(compiler_errors)
      compiler_errors = merge_repeated_faults(compiler_errors)
      compiler_errors = suppress_unlocated_dropped_text(compiler_errors, brace_errors)
      errors = place_merged_brace_errors(prepare_error_items(compiler_errors), brace_errors)
      alerts, warnings, whatevers = partition_diagnostics(content, extract_warnings(content, verbose: false))
      Leeni::DiagnosticAnalysis.new(errors: errors, alerts: alerts, warnings: warnings, whatevers: whatevers,
                                    error_count: errors.size, brace_errors: brace_errors)
    end

    def report_error_summary(analysis, raw, io: $stdout)
      brace_alerts_count = analysis.brace_errors.count { |e| e[:has_alert] }
      errors_count = [analysis.errors.size, count_latex_errors(raw, 1)].max
      alerts_count = analysis.alerts.size + brace_alerts_count
      warnings_count = analysis.warnings.size
      whatevers_count = analysis.whatevers.size
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
