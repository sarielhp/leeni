# frozen_string_literal: true

# ==============================================================================
# lib/leeni/bib_locator.rb
#
# Resolves citation keys and offending tokens to exact .bib file and line numbers.
# ==============================================================================

require_relative 'bibkit_collection'

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

  # Parsed .bib files, reused while a file's size and modification time stay.
  def self.bib_file(path)
    @bib_files ||= {}
    stat = File.stat(path)
    stamp = [stat.size, stat.mtime]
    cached = @bib_files[path]
    return cached.last if cached && cached.first == stamp

    @bib_files[path] = [stamp, Bibkit::BibFile.load(path)]
    @bib_files[path].last
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

  # BIBINPUTS as TeX reads it: a trailing // searches subdirectories.
  def collect_from_bibinputs
    Bibkit::Collection.expand((ENV['BIBINPUTS'] || '').split(File::PATH_SEPARATOR))
  end

  # The entry for `citekey` (matched ignoring case, as BibTeX does), and the
  # line inside it that holds `token`.
  def search_file_for_entry(bib_file, citekey, token)
    item = self.class.bib_file(bib_file).entries_like(citekey).first
    return nil unless item

    lines = item.text.dup.force_encoding('UTF-8').scrub.lines
    offset, field_text = find_field_line(lines, token)
    { file: bib_file, line: item.line + offset, entry_line: item.line, citekey: citekey, field_text: field_text,
      token: token }
  end

  # [offset from the entry's first line, that line's text].
  def find_field_line(lines, token)
    return [0, lines.first.to_s.strip] if token.to_s.empty?

    clean_token = token.to_s.strip
    index = lines.index { |line| line.include?(clean_token) }
    index ||= clean_token.scan(/[A-Za-z0-9_]{4,}/).lazy.filter_map { |seg| lines.index { |line| line.include?(seg) } }.first
    index ||= 0
    [index, lines[index].to_s.strip]
  end
end
