# frozen_string_literal: true

# ==============================================================================
# lib/leeni/pdf_checks.rb
#
# Checks on the produced PDF that no log line reports. Page geometry comes
# from poppler's pdfinfo; a mixed set of page sizes (an A4 or landscape page
# in a letter document, usually an included PDF) is a common submission
# rejection that TeX never mentions.
# ==============================================================================

require 'open3'
require_relative 'utils'

module LaTeXPdfChecks
  PAGE_SIZE_LINE = /^Page\s+(\d+)\s+size:\s+([\d.]+) x ([\d.]+) pts(?: \(([^)]+)\))?/
  MAX_LISTED_PAGES = 6

  # Returns nil when every page has the same size, otherwise the size groups
  # as [[label, [pages...]], ...] with the dominant size first.
  def self.page_sizes(pdf_path)
    return nil unless pdf_path && File.file?(pdf_path) && LaTeXUtils.command_available?('pdfinfo')

    out, status = Open3.capture2e('pdfinfo', '-f', '1', '-l', '100000', pdf_path)
    return nil unless status.success?

    mixed_page_sizes(out)
  rescue StandardError
    nil
  end

  def self.mixed_page_sizes(pdfinfo_text)
    groups = Hash.new { |h, k| h[k] = [] }
    pdfinfo_text.each_line do |line|
      m = line.match(PAGE_SIZE_LINE)
      next unless m

      groups[size_label(m)] << m[1].to_i
    end
    return nil if groups.size <= 1

    groups.sort_by { |_, pages| -pages.size }
  end

  def self.size_label(match)
    dims = "#{match[2].to_f.round} x #{match[3].to_f.round} pt"
    match[4] ? "#{match[4]} (#{dims})" : dims
  end

  def self.page_size_message(groups)
    (main_label, main_pages), *odd = groups
    details = odd.map do |label, pages|
      "#{label} on #{plural(pages.size, 'page')} #{compact_pages(pages)}"
    end
    "Mixed page sizes: #{main_pages.size} #{plural(main_pages.size, 'page')} #{main_label}, but #{details.join('; ')}"
  end

  def self.plural(count, noun)
    count == 1 ? noun : "#{noun}s"
  end

  def self.compact_pages(pages)
    listed = pages.first(MAX_LISTED_PAGES).join(', ')
    pages.size > MAX_LISTED_PAGES ? "#{listed}, ... (#{pages.size} pages)" : listed
  end
end
