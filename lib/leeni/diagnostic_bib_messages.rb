# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostic_bib_messages.rb
#
# Bibliography tool messages: counts, duplicate keys, missing entries and fix hints.
# Part of LaTeXDiagnostics (lib/leeni/diagnostics.rb), which includes it.
# ==============================================================================

module LaTeXDiagnostics
  # Bibliography tool messages: counts, duplicate keys, missing entries and fix hints.
  module BibMessages
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

    BIB_WARNING_PATTERN = /^Warning--|^Repeated entry---|^WARN\s+-\s/i
    BIBTEX_ERROR_SUMMARY = /\(There (?:was|were) \d+ error message/i

    # BibTeX's "(There was 1 error message)" is no error when every error it
    # counted is a repeated entry, which leeni reports as an alert.
    def bib_error_lines(content)
      lines = content.each_line.grep(BIB_ERROR_PATTERN)
      LatexBibChecks.only_repeated_entries?(content) ? lines.grep_v(BIBTEX_ERROR_SUMMARY) : lines
    end

    def count_bib_messages
      return { warns: 0, errors: 0 } unless @biberr && File.exist?(@biberr)

      bib_content = LaTeXUtils.safe_read(@biberr)
      warns = bib_content.each_line.count { |l| l =~ BIB_WARNING_PATTERN }
      errors = bib_error_lines(bib_content).size
      { warns: warns, errors: errors }
    end

    UNDEF_CITE_PATTERN = /^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+Citation\s+[`'"]?.*?['"]?\s+.*undefined/i
    UNDEF_REF_PATTERN  = /^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+Reference\s+[`'"]?.*?['"]?\s+.*undefined/i
    MULT_DEF_PATTERN   = /^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+Label\s+[`'"]?.*?['"]?\s+multiply defined/i

    def count_reference_messages(new_content)
      content = LaTeXUtils.filter_subcommand_noise(new_content)
      undef_cite = content.scan(UNDEF_CITE_PATTERN).size
      undef_ref  = content.scan(UNDEF_REF_PATTERN).size
      mult_def   = content.scan(MULT_DEF_PATTERN).size
      [undef_cite, undef_ref, mult_def]
    end

    def append_bib_diagnostics!(warn_items, err_items)
      return unless @biberr && File.exist?(@biberr)

      content = LaTeXUtils.safe_read(@biberr)
      errors = bib_error_lines(content)
      content.each_line.with_index do |bl, bidx|
        if (dup = biber_duplicate_item(bl, 100_000 + bidx))
          warn_items << dup
        elsif bl =~ BIB_WARNING_PATTERN
          line_str = bl =~ /line\s+(\d+)/i ? Regexp.last_match(1) : ''
          bib_file = bl[/of file (\S+?)\.?\s*$/i, 1] || './bibliography'
          formatted = format_diagnostic_line(line_str, bl.strip, :yellow, file: bib_file)
          warn_items << { file: bib_file, line: line_str.to_i, line_str: line_str, text: bl.strip, formatted: formatted,
                          index: 100_000 + bidx }
        elsif errors.include?(bl)
          formatted = @options[:emacs] ? bl.strip : highlight_line_numbers(bl.strip, :red, bright: true)
          err_items << { file: './bibliography', line: 0, text: bl.strip, formatted: formatted, index: 100_000 + bidx }
        end
      end
    end

    BIBER_DUPLICATE = /Duplicate entry key: '([^']+)' in file '([^']+)'/

    # Biber names the file by absolute path and neither line. Bibkit finds the
    # copy it kept and the one it skipped; the file is shown relative to the
    # project when inside it, and the line links to the real location.
    def biber_duplicate_item(text, index)
      m = text.match(BIBER_DUPLICATE)
      return nil unless m

      key, path = m.captures
      lines = File.file?(path) ? Bibkit::BibFile.load(path).entries_for(key).map(&:line) : []
      line_str = lines[1].to_s
      msg = "Duplicate entry key '#{key}'#{": Biber skips this copy and uses the one on line #{lines[0]}" if lines.size > 1}"
      file = display_bib_path(path)
      { file: file, line: lines[1].to_i, line_str: line_str, text: msg,
        formatted: format_diagnostic_line(line_str, msg, :yellow, file: file), index: index }
    rescue SystemCallError
      nil
    end

    def display_bib_path(path)
      root = "#{File.realpath('.')}/"
      real = File.realpath(path)
      real.start_with?(root) ? real.delete_prefix(root) : path
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
          next unless (m = txt.match(pat))

          raw_keys = m[1].split(/[,\s]+/).map { |k| k.gsub(/['"]/, '').strip }.reject(&:empty?)
          missing_keys.concat(raw_keys)
          matched = true
          break
        end
        if !matched && w[:file].to_s.end_with?('.bbl') && txt =~ /Entry '([^']+)' not found in database/i
          missing_keys << Regexp.last_match(1)
          matched = true
        end
        matched
      end

      missing_keys.uniq!
      missing_keys.sort!
      return add_bib_fix_note!(warn_items) if missing_keys.empty?

      formatted_msg = format_missing_bib_entries(missing_keys) + bib_fix_hint(missing_keys)
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
        index: 100_000
      }
    end

    # One line when --bib-fix can add some of the missing keys from the
    # bibliography collection; nothing otherwise.
    def bib_fix_hint(missing_keys)
      found = LatexBibChecks.fixable_keys(missing_keys, junk_dir, bfilename, @options)
      return '' if found.empty?

      subject = if found.size < missing_keys.size then "#{found.size} of them #{found.size == 1 ? 'is' : 'are'}"
                elsif found.size == 1 then 'It is'
                else 'All are'
                end
      "\n  #{subject} in BIBINPUTS; l --bib-fix adds #{found.size == 1 ? 'it' : 'them'} to the paper's .bib file."
    end

    UNDEFINED_CITATION = /Citation\s+[`'"](.+?)[`'"](?:\s+on page \d+)?\s+undefined/i

    # When the bibliography tool did not run this time (nothing it reads
    # changed), LaTeX's undefined-citation warnings are the only sign of a
    # missing entry; the --bib-fix hint then is a line of its own. Worded so it
    # is not taken for one more citation warning.
    def add_bib_fix_note!(warn_items)
      keys = warn_items.filter_map { |w| (w[:raw_text] || w[:text]).to_s[UNDEFINED_CITATION, 1] }.uniq.sort
      found = keys.empty? ? [] : LatexBibChecks.fixable_keys(keys, junk_dir, bfilename, @options).to_a.sort
      return if found.empty?

      text = "Warning: l --bib-fix can add #{found.size == 1 ? 'the entry' : "#{found.size} entries"} " \
             "#{found.map { |k| "'#{k}'" }.join(', ')} from BIBINPUTS to the paper's .bib file"
      warn_items << { file: './bibliography', line: 0, line_str: 'bib', text: text, raw_text: text, base_color: :yellow,
                      formatted: format_diagnostic_line('bib', text, :yellow, file: './bibliography'), index: 100_001 }
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
  end
end
