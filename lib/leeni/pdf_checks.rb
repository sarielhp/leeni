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

  # ---------------------------------------------------- page count and Type 3 fonts

  def self.pdf_page_count(pdf_path)
    return 1 unless LaTeXUtils.command_available?('pdfinfo') && File.file?(pdf_path)

    out, status = Open3.capture2e('pdfinfo', pdf_path)
    return 1 unless status.success?

    out =~ /Pages:\s+(\d+)/ ? Regexp.last_match(1).to_i : 1
  rescue StandardError
    1
  end

  def self.check_type3_fonts(pdf_path)
    return nil unless LaTeXUtils.command_available?('pdffonts') && File.file?(pdf_path) && File.size(pdf_path).positive?

    stdout, status = Open3.capture2e('pdffonts', pdf_path)
    return nil unless status.success? && stdout.include?('Type 3')

    names = extract_type3_font_names(stdout)
    return nil if names.empty?

    pages = find_type3_font_pages(pdf_path)
    objects = stdout.lines.grep(/\s+Type 3\s+/).filter_map { |line| line[/\s(\d+)\s+\d+\s*$/, 1] }.uniq
    { fonts: names, pages: pages, glyph_kind: classify_type3_fonts(pdf_path, objects) }
  rescue StandardError
    nil
  end

  def self.extract_type3_font_names(stdout)
    names = []
    stdout.each_line do |line|
      next if line.start_with?('name ', '---')
      next unless line =~ /\s+Type 3\s+/

      parts = line.split
      names << (parts[0] || '[none]')
    end
    names.uniq
  end

  # Only downgrade when every glyph uses known vector operators. Resource calls
  # and unfamiliar syntax remain unknown rather than being assumed scalable.
  TYPE3_VECTOR_OPERATORS = %w[d0 d1 q Q cm m l c v y h re S s f F f* B B* b b* n W W*
                              w J j M d G g RG rg K k].freeze
  TYPE3_NUMBER = /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)\z/

  def self.classify_type3_fonts(pdf_path, objects)
    return :unavailable unless LaTeXUtils.command_available?('mutool')
    return :unknown if objects.empty?

    kinds = objects.map { |object| classify_type3_object(pdf_path, object) }
    return :bitmap if kinds.include?(:bitmap)

    kinds.all?(:vector) ? :vector : :unknown
  end

  def self.classify_type3_object(pdf_path, object)
    dictionary = decoded_pdf_object(pdf_path, "#{object}/CharProcs")
    return :unknown unless dictionary

    entries = dictionary[/<<\s*(.*?)\s*>>/m, 1]
    return :unknown unless entries

    references = %r{/[^\s/<>]+\s+\d+\s+\d+\s+R}
    return :unknown unless entries.gsub(references, '').strip.empty?

    glyph_count = entries.scan(references).size
    output = decoded_pdf_object(pdf_path, "#{object}/CharProcs/*")
    return :unknown unless output && glyph_count.positive?

    streams = output.scan(/\bstream\r?\n(.*?)endstream/m).flatten
    return :unknown unless streams.size == glyph_count

    kinds = streams.map { |stream| classify_type3_glyph(stream) }
    return :bitmap if kinds.include?(:bitmap)

    kinds.all?(:vector) ? :vector : :unknown
  end

  def self.decoded_pdf_object(pdf_path, path)
    output, error, status = Open3.capture3('mutool', 'show', pdf_path, path)
    return output.b if status.success? && error.empty?

    nil # Repair warnings or failed decoding cannot establish vector glyphs.
  rescue StandardError
    nil # Inspection is optional; callers retain the alert on failure.
  end

  def self.classify_type3_glyph(stream)
    tokens = stream.gsub(/%[^\r\n]*/, '').gsub(/[\[\]]/, ' ').split
    return :bitmap if tokens.include?('BI')
    return :unknown unless tokens.include?('d0') || tokens.include?('d1')

    tokens.all? { |token| TYPE3_NUMBER.match?(token) || TYPE3_VECTOR_OPERATORS.include?(token) } ? :vector : :unknown
  end

  def self.type3_font_message(type3)
    pages = type3[:pages].empty? ? '' : " on page #{type3[:pages].join(', ')}"
    kind = type3[:glyph_kind]
    detail = { vector: 'all glyphs confirmed vector', bitmap: 'bitmap glyphs detected',
               unavailable: 'MuPDF/mutool is not installed' }.fetch(kind, 'glyph inspection inconclusive')
    message = "Type 3 fonts: #{type3[:fonts].join(', ')}#{pages} (#{detail})."
    return message if kind == :vector

    message + ' Type 3 does not necessarily mean bitmap. Install MuPDF (the package providing mutool) ' \
              'and ensure mutool is on PATH to enable automatic vector checks. ' \
              'Bitmap fonts may look pixelated; check the publisher\'s requirements. ' \
              'Regenerate affected figures with scalable fonts (for Matplotlib, set pdf.fonttype = 42); ' \
              'for LaTeX text, consider lmodern. To keep this diagnostic as a warning, ' \
              'set "alert_as_warning": ["type3_font"] in .l.jsonc or ~/.config/leeni/config.jsonc.'
  end

  def self.find_type3_font_pages(pdf_path)
    total_pages = pdf_page_count(pdf_path)
    return [] if total_pages > 100

    pages = []
    (1..total_pages).each do |p|
      out, status = Open3.capture2e('pdffonts', '-f', p.to_s, '-l', p.to_s, pdf_path)
      pages << p if status.success? && out.include?('Type 3')
    end
    pages
  rescue StandardError
    []
  end
end
