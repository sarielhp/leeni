# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostics.rb
#
# LaTeX compilation log diagnostic analysis, AUCTeX error extraction,
# 4-tier categorization (Errors, Alerts, Warnings, Whatevers), and scoring.
# ==============================================================================

require_relative 'error_catalog'
require_relative 'box_context'
require_relative 'compile_format'
require_relative 'bib_checks'
require_relative 'pdf_checks'
require_relative 'diagnostic_formatting'
require_relative 'diagnostic_log_parsing'
require_relative 'diagnostic_output'
require_relative 'diagnostic_alerts'
require_relative 'diagnostic_summary'
require_relative 'diagnostic_bib_messages'
require_relative 'diagnostic_key_suggestions'

module LaTeXDiagnostics
  include Formatting
  include LogParsing
  include Output
  include Alerts
  include Summary
  include BibMessages
  include KeySuggestions

  DIAGNOSTIC_EXPLANATIONS = LaTeXErrorCatalog::WARNING_EXPLANATIONS

  LOG_FILE_EXTENSIONS = %w[
    tex sty cls aux bbl bib dtx def ldf cfg clo toc lof lot png pdf jpg eps fd fontspec out idx code\.tex
  ].join('|').freeze

  LOG_FILE_PATTERN = %r{\A\((?:"([^"]+)"|((?:\.{1,2}[\\/][^\s()]+|[a-zA-Z0-9_\-./]+?\.(?:#{LOG_FILE_EXTENSIONS}))\b))}

  # One canonical recogniser for a LaTeX/package/class warning header. Five
  # near-but-not-equal variants of this used to be spelled out inline, and the
  # two that mattered most used a package-name class of [-A-Za-z0-9], which
  # excludes '.'. That made `Package pdftex.def Warning:` neither a warning
  # start nor a block boundary, so it was appended to the preceding warning's
  # text -- and when that predecessor was a Whatever, a real warning vanished
  # into a tier suppressed by default. luatex.def, xetex.def, dvips.def and
  # epstopdf-base all shared the fate.
  WARNING_LINE_PATTERN = /^(?:LaTeX|Class|Package|\*)(?:\s+[-\w.@*]+)*\s+[Ww]arning:/
  FATAL_ABORT_PATTERN = /^(?:!\s*|.+?:\d+:\s*)(?:==>\s*)?(?:Emergency stop|Fatal error occurred)/i

  # Every pattern here must be anchored. TeX echoes the offending paragraph
  # after each Overfull \hbox, so the document's own prose reaches this log
  # verbatim: an unanchored `include?('Error:')` made a paper that discusses
  # error messages fail its own successful build, and the abort happens before
  # the PDF is copied out of the build directory, so the user got no output and no
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
    return false if line =~ FATAL_ABORT_PATTERN

    line.match?(/^!\s+\S/) ||
      line.match?(/^Runaway argument\?/) ||
      line.match?(/^Error:\s/i) ||
      line.match?(/^.+?:\d+:\s+(?!warning\b)(?!\(see\b)\S/i)
  end

  def typeset_source_echo?(line)
    line.match?(%r{^\s*\\[A-Z][A-Z0-9]*/\S+\s})
  end

  def extract_error_line(err_text)
    clean = err_text.gsub(/\([a-zA-Z0-9_-]+\)\s*/, '')
    if clean =~ /:(\d+):/ || clean =~ /\bl\.(\d+)\b/ || clean =~ /(?:at|on|in)?\s*(?:input\s+)?lines?\s*(\d+)/i
      Regexp.last_match(1).to_i
    else
      0
    end
  end

  def extract_box_severity(box_line)
    if box_line =~ /(?:\(?\b|)([\d.]+)pt too (?:wide|high)\)?/i || box_line =~ /\(badness (\d+)\)/i
      Regexp.last_match(1).to_f
    else
      0.0
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
    raw_warns = extract_warnings(clean_content, verbose: @options[:verbose])
    raw_warns.concat(collect_invisible_character_warnings)
    err_items = extract_errors(clean_content)
    append_bib_diagnostics!(raw_warns, err_items) if counts[:cbib].positive?
    consolidate_missing_bib_entries!(raw_warns)
    suggest_undefined_keys!(raw_warns)

    alert_items, reg_warns, what_items = partition_diagnostics(clean_content, raw_warns)
    reg_warns = drop_empty_key_citation_warnings(alert_items, reg_warns)
    errors = count_latex_errors(new_content, 0) + counts[:biberr]
    promoted, alert_items, reg_warns = promote_error_grade_items(alert_items, reg_warns)
    err_items.concat(promoted.map { |item| alert_as_error(item) })
    errors += promoted.size
    return report_bib_missing if @options[:bib_missing] && errors.zero?

    revert_bib_missing_output! if @options[:bib_missing]
    display_analyzed_diagnostics(err_items, alert_items, reg_warns, what_items, errors)
  end

  # Duplicate labels silently rebind every \ref to the last definition, so they
  # rank with compiler errors. An alert_as_warning downgrade still wins because
  # partition_diagnostics applies it first. With --final the document is about
  # to leave the author's hands, so the ordinary drafting warnings join them.
  ERROR_GRADE_ALERTS = %i[multiply_defined_label].freeze
  FINAL_ERROR_CATEGORIES = %i[undefined_reference undefined_citation empty_citation missing_bib_entry
                              unconverged_build float_too_large].freeze

  def error_grade_alert?(item)
    category = diagnostic_category(item)
    ERROR_GRADE_ALERTS.include?(category) || (@options[:final] && FINAL_ERROR_CATEGORIES.include?(category))
  end

  def promote_error_grade_items(alert_items, reg_warns)
    promoted, alert_items = alert_items.partition { |item| error_grade_alert?(item) }
    return [promoted, alert_items, reg_warns] unless @options[:final]

    final_errors, reg_warns = reg_warns.partition { |w| FINAL_ERROR_CATEGORIES.include?(diagnostic_category(w)) }
    [promoted + final_errors, alert_items, reg_warns]
  end

  def alert_as_error(item)
    err = item.dup
    err[:tier] = 'errors'
    err[:text] = err[:text].sub(/^(?:Alert|Warning):\s*/, '')
    err[:formatted] = format_diagnostic_line(err[:line_str], err[:text], :red, file: err[:file])
    err[:err_block] ||= [err[:text]]
    err[:source] ||= :leeni
    err[:synthetic] = true
    err
  end

  def display_analyzed_diagnostics(err_items, alert_items, reg_warns, what_items, errors)
    alerts = alert_items.sum { |i| i[:count] || 1 }
    warnings = reg_warns.sum { |i| i[:count] || 1 }
    whatevers = what_items.sum { |i| i[:count] || 1 }

    if json_mode?
      errors = render_json_mode_tiers(err_items, alert_items, reg_warns, what_items, errors)
    elsif errors.positive? || alerts.positive? || warnings.positive? || whatevers.positive?
      errors = render_diagnostics_tiers(err_items, alert_items, reg_warns, what_items, errors)
    end

    summarize_and_check_werror(errors, alerts, warnings, whatevers)
  end

  def render_compile_mode_tiers(err_items, alert_items, reg_warns, what_items, errors)
    return render_json_mode_tiers(err_items, alert_items, reg_warns, what_items, errors) if json_mode?

    return render_llm_mode_tiers(err_items, alert_items, reg_warns, what_items, errors) if llm_mode?

    prepared_errors = prepare_error_items(err_items)
    displayed_errors, cascade_info = throttle_errors(prepared_errors)
    has_errors = errors.positive? || !prepared_errors.empty?
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
    has_errors = errors.positive? || !prepared_errors.empty?
    has_werrors = @options[:werror] && (alert_items.any? || reg_warns.any?)
    failed = has_errors || has_werrors

    err_records = prepared_errors.map { |e| normalize_diagnostic(e, 'errors') }
    alt_records = alert_items.map { |a| normalize_diagnostic(a, 'alerts') }
    wrn_records = reg_warns.map { |w| normalize_diagnostic(w, 'warnings') }
    wht_records = what_items.map { |wh| normalize_diagnostic(wh, 'whatevers') }

    all_records = err_records
    all_records += alt_records unless tier_suppressed?(:alerts)
    all_records += wrn_records unless tier_suppressed?(:warnings)
    all_records += wht_records unless @options[:suppress_whatevers] == true
    pdf_file = respond_to?(:delivered_pdf, true) ? delivered_pdf : "#{@bfilename}.pdf"
    result = LaTeXDiagnosticResult.new(
      build: json_build_report,
      success: !failed,
      exit_code: failed ? 1 : 0,
      pdf_path: !failed && File.exist?(pdf_file) ? pdf_file : nil,
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

    if errors.positive? || !err_items.empty?
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

  def render_grouped_tiers(error_items, alert_items, reg_warns, what_items, fallback_lines: [], io: $stdout)
    suppress_alerts = @options[:suppress_alerts] == true
    suppress_warnings = @options[:suppress_warnings] == true
    suppress_whatevers = @options[:suppress_whatevers] != false

    items_to_display = []
    error_items.each do |e|
      entry = e.dup
      entry[:tier] = 'errors'
      entry[:base_color] ||= :red
      items_to_display << entry
    end
    unless suppress_alerts
      alert_items.each do |a|
        entry = a.dup
        entry[:tier] = 'alerts'
        entry[:base_color] ||= :red
        items_to_display << entry
      end
    end
    unless suppress_warnings
      reg_warns.each do |w|
        entry = w.dup
        entry[:tier] = 'warnings'
        entry[:base_color] ||= :yellow
        items_to_display << entry
      end
    end
    unless suppress_whatevers
      what_items.each do |wh|
        entry = wh.dup
        entry[:base_color] = :cyan
        entry[:tier] = 'whatevers'
        entry[:formatted] = format_diagnostic_line(wh[:line_str], wh[:text], :cyan, file: wh[:file])
        items_to_display << entry
      end
    end

    return if items_to_display.empty? && fallback_lines.empty?

    print_diagnostics_body(items_to_display, [], fallback_lines: fallback_lines, io: io)
  end

  def print_compile_success_if_clean(errors, alerts, warnings)
    return if @options && @options[:vscode_lw]
    return unless errors.zero? && !llm_mode? && !json_mode?
    return if @options[:werror] && (alerts.positive? || warnings.positive?)

    msg = @options && @options[:color] == false ? 'Compilation succeeded.' : Rainbow('Compilation succeeded.').green.bright
    puts msg
  end

  def summarize_and_check_werror(errors, alerts, warnings, whatevers)
    suppressed_alt = (errors.positive? && !@options[:emacs] && !@options[:all]) || (@options[:suppress_alerts] == true)
    suppressed_wrn = (errors.positive? && !@options[:emacs] && !@options[:all]) || (@options[:suppress_warnings] == true)
    suppressed_wht = (errors.positive? && !@options[:emacs] && !@options[:all]) || (@options[:suppress_whatevers] != false)

    if compile_mode?
      print_compile_success_if_clean(errors, alerts, warnings)
    else
      print_summary_line(
        errors, alerts, warnings, whatevers,
        suppressed_alerts: suppressed_alt && alerts.positive?,
        suppressed_warnings: suppressed_wrn && warnings.positive?,
        suppressed_whatevers: suppressed_wht && whatevers.positive?
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

    Dir.children(dir).grep(pattern).sort_by { |f| f[pattern, 1].to_i }.map { |f| File.join(dir, f) }
  end

  def find_last_latex_log = pass_log_files.last || @pdferr

  def count_latex_errors(content, status = 0)
    errors = 0
    clean_content = LaTeXUtils.filter_subcommand_noise(content)
    clean_content.each_line do |line|
      next if line =~ FATAL_ABORT_PATTERN
      next if typeset_source_echo?(line)

      next unless line =~ /^!\s+\S+/ ||
                  line =~ /^.+:\d+:\s+(?:(?:LaTeX|Package|Class)\s+Error:|Undefined control sequence|Error:|Runaway argument\?|Missing\s|Extra\s|You can't use)/i || # rubocop:disable Layout/LineLength
                  line =~ /^.+:\d+:\s+.*error/i || line =~ /^Error:\s+/i

      errors += 1
    end
    errors = 1 if errors.zero? && status.to_i.positive?
    errors
  end

  def output_score(last_log_path = nil, status = 0)
    last_log_path ||= find_last_latex_log
    content = LaTeXUtils.safe_read(last_log_path)
    clean_content = LaTeXUtils.filter_subcommand_noise(content)
    raw_warns = extract_warnings(clean_content, verbose: false)
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
      suppressed_alerts: suppress_alerts && alerts.positive?,
      suppressed_warnings: suppress_warnings && warnings.positive?,
      suppressed_whatevers: suppress_whatevers && whatevers.positive?
    )

    # analyze_output returns early for :score, so without this `l -s -W` could
    # never fail -- the flag whose only purpose is a non-zero exit status was
    # silently disabled by the flag whose purpose is a quiet one.
    fail_on_diagnostics(errors, alerts, warnings)
  end
end
