# frozen_string_literal: true

# ==============================================================================
# lib/leeni/bib_locator.rb
#
# Resolves citation keys and offending tokens to exact .bib file and line numbers.
# ==============================================================================

class LaTeXBibLocator
  def self.locate(citekey, token = nil, bfilename = nil, search_dir = Dir.pwd, junk_dir: nil)
    new(bfilename, search_dir, junk_dir: junk_dir).locate(citekey, token)
  end

  def initialize(bfilename = nil, search_dir = Dir.pwd, junk_dir: nil)
    @bfilename = bfilename
    @search_dir = search_dir
    @junk_dir = junk_dir
  end

  def locate(citekey, token = nil)
    return nil if citekey.to_s.empty?

    bib_files = collect_bib_files
    bib_files.each do |bf|
      loc = search_file_for_entry(bf, citekey, token)
      return loc if loc
    end
    nil
  end

  private

  def collect_bib_files
    files = []
    files.concat(collect_from_blg) if @bfilename
    files.concat(Dir.glob(File.join(@search_dir, '{,refs/,bib/}*.bib')))
    files.concat(collect_from_bibinputs)
    files.select { |f| File.file?(f) }.uniq
  end

  def collect_from_blg
    candidates = if @junk_dir
                   [File.join(File.expand_path(@junk_dir, @search_dir), "#{@bfilename}.blg")]
                 else
                   %w[.junk junk].map { |dir| File.join(@search_dir, dir, "#{@bfilename}.blg") }
                 end
    blg_path = candidates.find { |p| File.file?(p) }
    return [] unless blg_path

    found = []
    content = LaTeXUtils.safe_read(blg_path)
    content.scan(/Found BibTeX data source \x27([^\x27]+)\x27/) do |m|
      found << m.first if File.file?(m.first)
    end
    content.scan(/Database file #\d+:\s*(.+)$/) do |m|
      p = m.first.strip
      p = "#{p}.bib" unless p.end_with?('.bib')
      resolved = File.file?(p) ? p : File.join(@search_dir, p)
      found << resolved if File.file?(resolved)
    end
    found
  end

  def collect_from_bibinputs
    paths = (ENV['BIBINPUTS'] || '').split(File::PATH_SEPARATOR).reject(&:empty?)
    paths.flat_map { |p| Dir.glob(File.join(p, '*.bib')) }
  end

  def search_file_for_entry(bib_file, citekey, token)
    lines = File.readlines(bib_file, encoding: 'UTF-8', chomp: false) rescue []
    pattern = /^@\w+\s*\{\s*#{Regexp.escape(citekey)}\s*,/i

    lines.each_with_index do |line, idx|
      next unless line =~ pattern

      entry_line = idx + 1
      field_line, field_text = find_field_line(lines, idx, token)
      return {
        file: bib_file,
        line: field_line,
        entry_line: entry_line,
        citekey: citekey,
        field_text: field_text,
        token: token
      }
    end
    nil
  end

  def find_field_line(lines, start_idx, token)
    return [start_idx + 1, lines[start_idx].strip] if token.to_s.empty?

    clean_token = token.to_s.strip
    max_idx = [start_idx + 80, lines.size - 1].min
    (start_idx..max_idx).each do |j|
      return [j + 1, lines[j].strip] if lines[j].include?(clean_token)
    end

    segments = clean_token.scan(/[A-Za-z0-9_]{4,}/)
    segments.each do |seg|
      (start_idx..max_idx).each do |j|
        return [j + 1, lines[j].strip] if lines[j].include?(seg)
      end
    end

    [start_idx + 1, lines[start_idx].strip]
  end
end
