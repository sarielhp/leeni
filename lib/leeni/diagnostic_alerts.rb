# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostic_alerts.rb
#
# Alerts beyond the log: duplicate labels, final checks, fonts, and the alert/warning/whatever partition.
# Part of LaTeXDiagnostics (lib/leeni/diagnostics.rb), which includes it.
# ==============================================================================

module LaTeXDiagnostics
  # Alerts beyond the log: duplicate labels, final checks, fonts, and the alert/warning/whatever partition.
  module Alerts
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
        elsif other_locs.empty?
          msg = "Alert: label '#{label_key}' duplicate"
        else
          linked_others = other_locs.map do |ol|
            disp = "#{format_display_path(ol[:file])}:#{ol[:line]}"
            link_enabled? ? format_terminal_link(ol[:file], ol[:line].to_s, disp, underline: false, color: :cyan) : disp
          end.join(', ')
          msg = "Alert: label '#{label_key}' duplicate (also at #{linked_others})"
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
          locs << { file: file, line: idx + 1 } if stripped.include?(label_key)
        end
      end
      locs
    end

    def extract_alerts(content, warn_items = nil)
      clean_content = LaTeXUtils.filter_subcommand_noise(content)
      warn_items ||= extract_warnings(clean_content, verbose: @options[:verbose])
      threshold = alert_overfull_pt
      alert_boxes = warn_items.select { |w| promoted_warning_alert?(w, threshold) }
      alert_boxes.each do |ab|
        ab[:base_color] = :red
        ab[:tier] = 'alerts'
        ab[:text] = ab[:text].sub(/^Warning:/, 'Alert:')
        ab[:formatted] = format_diagnostic_line(ab[:line_str], ab[:text], :red, file: ab[:file])
      end
      extract_label_alerts(clean_content) + alert_boxes + collect_source_label_alerts + collect_type3_font_alerts +
        collect_page_size_alerts + collect_final_check_alerts + collect_bib_alternative_alerts +
        collect_bib_problem_alerts
    end

    # Versions --bib-fix added as <key>_leeni_alt_N stay an alert until one
    # version is kept under the real key.
    def collect_bib_alternative_alerts
      LatexBibChecks.unresolved_alternatives(junk_dir, bfilename, @options[:bib_dirs]).each_with_index.map do |(file, key, line), i|
        msg = "Unresolved --bib-fix alternative #{key}: keep one version under the key " \
              "#{key.sub(/#{Bibkit::ALT_TAG}\d+\z/o, '')} and delete the others"
        { file: file, line: line, line_str: line.to_s, text: msg, formatted: format_diagnostic_line(line.to_s, msg, :red, file: file),
          alert_type: :bib_fix_alternative, tier: 'alerts', base_color: :red, index: 60_100 + i }
      end
    end

    # Problems in the .bib files the paper uses that the tool passes over or
    # reports without a reason, such as a `%` "comment" inside an entry.
    def collect_bib_problem_alerts
      LatexBibChecks.problems(junk_dir, bfilename, @options[:bib_dirs]).each_with_index.map do |(file, line, message), i|
        msg = "Bibliography file: #{message}"
        { file: file, line: line, line_str: line.to_s, text: msg, formatted: format_diagnostic_line(line.to_s, msg, :red, file: file),
          alert_type: :bib_file_problem, tier: 'alerts', base_color: :red, index: 60_200 + i }
      end
    end

    # An A4 or landscape page inside a letter document, usually an included PDF.
    def collect_page_size_alerts
      target_pdf = resolve_target_pdf
      groups = target_pdf && LaTeXPdfChecks.page_sizes(target_pdf)
      return [] unless groups

      msg = LaTeXPdfChecks.page_size_message(groups)
      [{
        file: target_pdf, line: 0, line_str: '', text: msg, formatted: format_diagnostic_line('', msg, :red),
        alert_type: :mixed_page_sizes, tier: 'alerts', base_color: :red, index: 60_001
      }]
    end

    def collect_invisible_character_warnings
      collect_source_candidates.flat_map { |f| LaTeXBraceChecker.check_invisible_characters(f) }.each do |w|
        w[:formatted] = format_diagnostic_line(w[:line_str], w[:text], :yellow, file: w[:file])
      end
    end

    # --final only: drafting aids left in the source (\includeonly, draft, ...).
    def collect_final_check_alerts
      return [] unless @options[:final]

      collect_source_candidates.flat_map { |f| LaTeXFinalChecks.scan(f) }.each do |a|
        a[:formatted] = format_diagnostic_line(a[:line_str], a[:text], :red, file: a[:file])
      end
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

      type3 = LaTeXPdfChecks.check_type3_fonts(target_pdf)
      return [] unless type3

      msg = LaTeXPdfChecks.type3_font_message(type3)
      color = type3[:glyph_kind] == :vector ? :yellow : :red
      formatted = format_diagnostic_line('', msg, color)
      [{
        file: target_pdf,
        line: 0,
        line_str: '',
        text: msg,
        formatted: formatted,
        alert_type: :type3_font,
        tier: color == :yellow ? 'warnings' : 'alerts',
        base_color: color,
        index: 60_000
      }]
    end

    def json_build_report
      respond_to?(:build_report, true) ? build_report : nil
    end

    def resolve_target_pdf
      return delivered_pdf if @bfilename && respond_to?(:delivered_pdf, true) && File.file?(delivered_pdf)
      return "#{@bfilename}.pdf" if @bfilename && File.file?("#{@bfilename}.pdf")

      diagnostic_artifact_candidates('pdf').find { |f| File.file?(f) }
    end

    def whatever_diagnostic?(item)
      if overfull_hbox?(item)
        sev = (item[:severity] || extract_box_severity(item[:text].to_s)).to_f
        return true if sev.positive? && sev <= whatever_overfull_pt
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

      path_prefixed_package?(txt)
    end

    # A package found through \input@path (styles/ from -z --styles-inject or
    # --make-indep) is requested as `styles/foo' by the LaTeX kernel, so its own
    # \ProvidesPackage{foo} looks like a mismatch. Same name, so harmless.
    def path_prefixed_package?(txt)
      pattern = %r{requested (?:package|class) .(?:[^'`]*/)([^'`/]+)', but the (?:package|class) provides .([^'`]+)'}
      match = txt.gsub(/\s+/, ' ').match(pattern)
      match && match[1] == match[2]
    end

    def partition_diagnostics(clean_content, warn_items)
      alert_items = extract_alerts(clean_content, warn_items)
      whatevers = []
      regular_warnings = []

      threshold = alert_overfull_pt
      warn_items.each do |w|
        next if promoted_warning_alert?(w, threshold)

        if whatever_diagnostic?(w)
          whatevers << w
        else
          regular_warnings << w
        end
      end

      downgraded, alert_items = alert_items.partition { |item| alert_as_warning?(item) }
      downgraded.each { |item| downgrade_alert!(item) }
      regular_warnings.concat(downgraded)
      alert_items.each { |i| i[:tier] = 'alerts' }
      regular_warnings.each { |i| i[:tier] = 'warnings' }
      whatevers.each { |i| i[:tier] = 'whatevers' }

      [alert_items, regular_warnings, whatevers]
    end

    # Warnings leeni ranks as alerts. Boxes and floats that overflow by at least
    # the alert threshold lose content off the page; the text patterns are
    # silent faults: ignored class options and font switches, a build whose
    # cross-references never settled, and a bibliography entry BibTeX dropped.
    PROMOTED_ALERT_TEXT = /unused global option|invalid in math mode|build did not converge|Repeated entry---|Duplicate entry key|Duplicate hyperlink destination/i

    def promoted_warning_alert?(item, threshold)
      return true if (overfull_hbox?(item) || overfull_vbox?(item)) && (item[:severity] || 0.0) >= threshold
      return true if float_overflow_pt(item) >= threshold

      item[:text].to_s.match?(PROMOTED_ALERT_TEXT)
    end

    def overfull_vbox?(item)
      t = item[:type].to_s
      (t.include?('Overfull') && t.include?('vbox')) || item[:raw_text].to_s =~ /\AOverfull\s+\\vbox/i
    end

    # "Float too large for page by 341.30pt": the overflow is clipped at the page edge.
    def float_overflow_pt(item)
      item[:text].to_s[/Float too large for page by ([\d.]+)pt/i, 1].to_f
    end

    def alert_as_warning?(item)
      return true if item[:tier] == 'warnings'

      Array(@options[:alert_as_warning]).map(&:to_s).include?(diagnostic_category(item).to_s)
    end

    def downgrade_alert!(item)
      item[:tier] = 'warnings'
      item[:base_color] = :yellow
      item[:text] = item[:text].sub(/^Alert:/, 'Warning:')
      item[:formatted] = format_diagnostic_line(item[:line_str], item[:text], :yellow, file: item[:file])
    end
  end
end
