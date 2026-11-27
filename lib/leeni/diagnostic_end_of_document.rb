# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostic_end_of_document.rb
#
# Errors TeX raised while running \end{document}: the line it names is only
# where it noticed, so the hint says so and gives the manual bisection recipe.
# Part of LaTeXDiagnostics (lib/leeni/diagnostics.rb), which includes it.
# ==============================================================================

module LaTeXDiagnostics
  # \end{document} runs \AtEndDocument code, flushes the last floats and ships
  # the last page, so an error raised by any of these lands on its line. Errors
  # whose cause TeX or leeni does place there are left alone: the paragraph
  # \end{document} closes, unclosed braces, environments and groups, and
  # errors leeni already moved (a root line, a lost float's culprit).
  module EndOfDocument
    END_DOCUMENT_LINE = /\A\s*\\end\s*\{document\}/
    END_HOOK = /\\(?:AtEndDocument|AfterEndDocument|AddToHook\s*\{enddocument[^}]*\})/
    PLACED_AT_END = %i[
      float_lost missing_dollar extra_closing_brace missing_closing_brace paragraph_ended_before_complete
      file_ended_while_scanning missing_end_document missing_begin_document mismatched_environment
      unclosed_group_at_end verbatim_environment_unclosed missing_endcsname bad_math_environment_delimiter
      missing_delimiter extra_right dropped_text missing_character font_not_loadable no_pages_of_output
      pdf_driver_fatal pdf_driver_image_failed unbalanced_write read_from_terminal engine_required
    ].freeze
    MAX_HOOK_SITES = 2

    def flag_end_of_document_errors!(items)
      items.each do |item|
        next unless noticed_at_end_of_document?(item)

        hint = [item.dig(:catalog, :hint), end_of_document_note].compact.join('; ')
        item[:catalog] = (item[:catalog] || {}).merge(hint: hint)
        item[:formatted] = format_error_block(item[:err_block], item[:line], catalog: item[:catalog], item: item)
      end
      items
    end

    private

    def noticed_at_end_of_document?(item)
      return false if PLACED_AT_END.include?(item[:catalog_id])
      return false if item[:root_line] && item[:root_line] != item[:line]
      return false unless item[:line].to_i.positive?

      path = LaTeXErrorCatalog.find_source_file(item[:file])
      # safe_read: a source with invalid UTF-8 must not crash the report.
      text = path && LaTeXUtils.safe_read(path).lines[item[:line] - 1]
      text ? LaTeXUtils.strip_latex_comments(text).match?(END_DOCUMENT_LINE) : false
    end

    def end_of_document_note
      @end_of_document_note ||= begin
        sites = end_hook_sites
        hooks = sites.empty? ? '' : " (\\AtEndDocument code from #{sites.join(', ')} runs there)"
        "TeX raised this while running \\end{document}#{hooks}, so this line is only where it noticed; " \
        'to find the cause, move \\end{document} halfway up, rebuild, and keep halving the part that ' \
        'still fails (failing right after \\begin{document} means the preamble)'
      end
    end

    # Where the document registers end-of-document code, from its local sources.
    def end_hook_sites
      end_hook_files.each_with_object([]) do |file, sites|
        LaTeXUtils.safe_read(file).each_line.with_index(1) do |line, no|
          sites << "#{file}:#{no}" if LaTeXUtils.strip_latex_comments(line).match?(END_HOOK)
          return sites if sites.size >= MAX_HOOK_SITES
        end
      end
    end

    def end_hook_files
      main = @filename.to_s
      fls = File.join(diagnostics_junk_dir.to_s, "#{File.basename(main, '.tex')}.fls")
      deps = respond_to?(:extract_fls_dependencies, true) ? extract_fls_dependencies(fls) : []
      ([main] + deps.grep(/\.(?:tex|sty|cls)\z/)).uniq.select { |f| File.file?(f) }
    end
  end
end
