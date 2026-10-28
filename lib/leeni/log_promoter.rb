# frozen_string_literal: true

# ==============================================================================
# lib/leeni/log_promoter.rb
#
# TeX finishes some malformed runs with exit status 0 and only a note in the
# log: \end{document} inside an open group or conditional, an \include target
# that does not exist, a glyph missing from the font, or a body that typeset
# no pages at all. Each note is rewritten here into a synthetic `!` error
# block so that every downstream recogniser treats it like a compiler error.
# ==============================================================================

module LaTeXLogPromoter
  TRIGGER = /\\end occurred|^No file \S+\.tex\.|^Missing character: |^No pages of output\.|^pdfTeX warning \(ext4\): destination/
  DUPLICATE_DESTINATION = /^pdfTeX warning \(ext4\): destination with the same identifier \(name\{(.+?)\}\) has been already used, duplicate ignored/
  UNCLOSED_GROUP_NOTICE = /^\(\\end occurred inside a group at level \d+\)\s*$/
  UNCLOSED_GROUP_DETAIL = /^### (.+? group) \(level \d+\) entered at line (\d+) \((.+)\)\s*$/
  UNCLOSED_CONDITIONAL = /^\(\\end occurred when (\\\w+) on line (\d+) was incomplete\)\s*$/
  MISSING_INCLUDE = /^No file (\S+\.tex)\.\s*$/
  MISSING_CHARACTER = /^Missing character: There is no (.+?) in font (.+?)!?\s*$/
  NO_PAGES = /^No pages of output\.\s*$/

  COMPILER_ERROR = /^(?:!\s+\S|Runaway argument\?|Error:\s|.+?:\d+:\s+(?!warning\b)(?!\(see\b)\S)/i
  PENDING_BIBLIOGRAPHY = /^No file \S+\.bbl\.|\(re\)run Biber|Please run BibTeX/i

  def self.promote(text)
    return text unless text.match?(TRIGGER)

    # An empty output after a real compiler error is a consequence, not a
    # second fault, and a bibliography-only body has no pages until the
    # bibliography tool has run; the no-pages note is left alone in both cases.
    skip_no_pages = text.match?(COMPILER_ERROR) || text.match?(PENDING_BIBLIOGRAPHY)
    state = { armed: false, seen: {}, counts: missing_character_counts(text), skip_no_pages: skip_no_pages }
    text.each_line.map { |line| rewrite_line(line, state) }.join
  end

  # The `###` group listing is only promoted when it directly follows TeX's
  # own notice, so document text that merely talks about groups stays inert.
  def self.rewrite_line(line, state)
    if line.match?(UNCLOSED_GROUP_NOTICE)
      state[:armed] = true
      return ''
    end
    if state[:armed] && (m = line.match(UNCLOSED_GROUP_DETAIL))
      return error("\\end{document} reached inside an unclosed #{m[1]} opened by '#{m[3]}' on line #{m[2]}", m[2])
    end

    state[:armed] = false unless line.strip.empty? || line.start_with?('###')
    rewrite_standalone_line(line, state)
  end

  def self.rewrite_standalone_line(line, state)
    if (m = line.match(UNCLOSED_CONDITIONAL))
      error("\\end{document} reached inside an unfinished #{m[1]} conditional started on line #{m[2]}", m[2])
    elsif (m = line.match(MISSING_INCLUDE))
      error("\\include target '#{m[1]}' not found, so its contents were skipped")
    elsif (m = line.match(MISSING_CHARACTER))
      rewrite_missing_character(m[1], m[2], state)
    elsif (m = line.match(DUPLICATE_DESTINATION))
      rewrite_duplicate_destination(m[1], state)
    elsif line.match?(NO_PAGES) && !state[:skip_no_pages]
      error('No pages of output: the document body typeset nothing, so no PDF was written')
    else
      line
    end
  end

  # One error per distinct glyph and font; TeX repeats the note per occurrence.
  def self.rewrite_missing_character(glyph, font, state)
    key = [glyph, font]
    return '' if state[:seen][key]

    state[:seen][key] = true
    count = state[:counts][key]
    times = count > 1 ? " (#{count} occurrences)" : ''
    error("Missing character: there is no #{visible_glyph(glyph)} in font #{font_name(font)}, " \
          "so the glyph was dropped from the PDF#{times}")
  end

  # A zero-width or control character would vanish from the message too; name
  # it by code point instead ("U+200B (invisible character)").
  def self.visible_glyph(glyph)
    first = glyph.to_s[0]
    return glyph unless first && first != ' ' && first.match?(/\A[\p{Cf}\p{Zs}\p{Cc}\p{Mn}]\z/)

    format('U+%04X (invisible character)', first.ord)
  end

  # xetex spells the font as `[lmroman10-regular]:mapping=tex-text;`; keep the name.
  def self.font_name(font)
    font.sub(/:.*\z/, '').delete('[]"').strip
  end

  # pdfTeX's duplicate-destination note is not a LaTeX warning, so the warning
  # scanner never sees it; it becomes one (an alert downstream), once per name.
  # Links to a duplicated anchor all land on its first occurrence.
  def self.rewrite_duplicate_destination(name, state)
    key = [:destination, name]
    return '' if state[:seen][key]

    state[:seen][key] = true
    count = state[:counts][key]
    times = count > 1 ? " (#{count} occurrences)" : ''
    "LaTeX Warning: Duplicate hyperlink destination '#{name}'#{times}; every link to it lands on the first occurrence.\n\n"
  end

  def self.missing_character_counts(text)
    text.each_line.with_object(Hash.new(0)) do |line, counts|
      if (m = line.match(MISSING_CHARACTER))
        counts[[m[1], m[2]]] += 1
      elsif (m = line.match(DUPLICATE_DESTINATION))
        counts[[:destination, m[1]]] += 1
      end
    end
  end

  def self.error(what, line_no = nil)
    tail = line_no ? "\nl.#{line_no}\n" : "\n"
    "! [leeni] #{what} (TeX only notes this; leeni flags it as an error).#{tail}"
  end
end
