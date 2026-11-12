# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostic_key_suggestions.rb
#
# "Did you mean" on undefined reference and citation warnings.
# Part of LaTeXDiagnostics (lib/leeni/diagnostics.rb), which includes it.
# ==============================================================================

require_relative 'key_suggester'

module LaTeXDiagnostics
  # Names the defined label or .bib key an undefined one was probably meant to be.
  module KeySuggestions
    UNDEFINED_KEY = {
      label: /(?:Hyper reference|Reference)\s+[`'"](.+?)[`'"](?:\s+on page \d+)?\s+undefined/i,
      cite: /Citation\s+[`'"](.+?)[`'"](?:\s+on page \d+)?\s+undefined/i
    }.freeze
    NEW_LABEL = /\\newlabel\{([^{}]+)\}/
    BIB_ENTRY_KEY = /^\s*@(\w+)\s*[{(]\s*([^,\s{}()]+)\s*,/
    BIB_NON_ENTRIES = %w[string comment preamble].freeze

    def suggest_undefined_keys!(warn_items)
      warn_items.each do |item|
        kind, key = undefined_key(item)
        next unless key

        suggestions = (@key_suggestions ||= {})[[kind, key]] ||= LeeniKeySuggester.suggest(key, defined_keys(kind))
        add_key_suggestion(item, suggestions) unless suggestions.empty?
      end
    end

    private

    def undefined_key(item)
      raw = (item[:raw_text] || item[:text]).to_s
      UNDEFINED_KEY.each do |kind, pattern|
        key = raw[pattern, 1]
        return [kind, key] if key && !key.strip.empty?
      end
      nil
    end

    def add_key_suggestion(item, suggestions)
      item[:text] = "#{item[:text]}; did you mean #{suggestions.map { |s| "'#{s}'" }.join(' or ')}?"
      item[:formatted] = format_diagnostic_line(item[:line_str], item[:text], item[:base_color] || :yellow, file: item[:file])
    end

    def defined_keys(kind)
      (@defined_keys ||= {})[kind] ||= kind == :label ? defined_labels : defined_bib_keys
    end

    def defined_labels
      labels = Dir[File.join(diagnostics_junk_dir, '**', '*.aux')].flat_map do |aux|
        LaTeXUtils.safe_read(aux).scan(NEW_LABEL).flatten
      end
      labels.reject { |key| internal_label_key?(key) }.uniq
    end

    def defined_bib_keys
      files = respond_to?(:bib_files_on_disk, true) ? bib_files_on_disk : Dir['*.bib']
      entries = files.flat_map { |bib| LaTeXUtils.safe_read(bib).scan(BIB_ENTRY_KEY) }
      entries.reject { |type, _| BIB_NON_ENTRIES.include?(type.downcase) }.map(&:last).uniq
    end
  end
end
