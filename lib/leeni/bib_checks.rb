# frozen_string_literal: true

# ==============================================================================
# lib/leeni/bib_checks.rb
#
# Checks on the .bib files a paper uses that the bibliography tool does not
# report, or reports without saying why: problems Bibkit's scanner finds
# (text after a field value such as a `%` "comment", which BibTeX takes as a
# syntax error and Biber silently accepts; broken entries) and unresolved
# --bib-fix alternatives. Scan results are cached in the build directory by
# file size and modification time, so a large shared collection is scanned
# once, not on every build.
# ==============================================================================

require 'json'
require 'open3'
require_relative 'bibkit_fixer'

module LatexBibChecks
  CACHE_FILE = '.bib_checks.json'
  CACHE_FORMAT = 1

  # The bibliography files the paper names: Biber's datasources from the
  # .bcf, else BibTeX's \bibdata from the .aux.
  def self.bibliography_sources(junk_dir, bfilename)
    bcf = LaTeXUtils.safe_read(File.join(junk_dir, "#{bfilename}.bcf"))
    names = bcf.scan(%r{<bcf:datasource[^>]*>([^<]+)</bcf:datasource>}).flatten
    if names.empty?
      aux = LaTeXUtils.safe_read(File.join(junk_dir, "#{bfilename}.aux"))
      names = aux.scan(/\\bibdata\{([^}]*)\}/).flatten.flat_map { |list| list.split(',') }
    end
    names.map(&:strip).reject(&:empty?).uniq
  end

  # A name as the paper gives it, found in the project (and its bib_dirs).
  def self.resolve(name, bib_dirs)
    dirs = name.start_with?('./', '../', '/') ? ['.'] : ['.'] + Array(bib_dirs)
    files = name.end_with?('.bib') ? [name] : ["#{name}.bib", name]
    dirs.product(files).map { |dir, file| File.expand_path(file, dir) }.find { |path| File.file?(path) }
  end

  # The same, falling back to the TeX search path (BIBINPUTS).
  def self.locate(name, bib_dirs)
    resolve(name, bib_dirs) || kpsewhich(name.end_with?('.bib') ? name : "#{name}.bib")
  end

  def self.kpsewhich(file)
    out, status = Open3.capture2('kpsewhich', '-format=bib', file)
    path = out.strip
    status.success? && File.file?(path) ? path : nil
  rescue SystemCallError
    nil
  end

  def self.inside_project?(path)
    File.realpath(path).start_with?("#{File.realpath('.')}/")
  end

  # [[file, key, line], ...] for every <key>_leeni_alt_N entry in the paper's
  # own bibliography files; run from the project directory.
  def self.unresolved_alternatives(junk_dir, bfilename, bib_dirs)
    paths = bibliography_sources(junk_dir, bfilename).filter_map { |name| resolve(name, bib_dirs) }
    paths.select { |path| inside_project?(path) }.uniq.flat_map do |path|
      Bibkit.alternatives_in(File.binread(path)).map { |key, line| [path, key, line] }
    end
  rescue SystemCallError
    []
  end

  # [[file, line, message], ...] for every bibliography file the paper uses.
  def self.problems(junk_dir, bfilename, bib_dirs)
    paths = bibliography_sources(junk_dir, bfilename).filter_map { |name| locate(name, bib_dirs) }.uniq
    cache_path = File.join(junk_dir, CACHE_FILE)
    cache = read_cache(cache_path)
    found = paths.flat_map { |path| cached_problems(cache, path).map { |line, message| [path, line, message] } }
    write_cache(cache_path, cache.slice(*paths))
    found
  rescue SystemCallError
    []
  end

  def self.cached_problems(cache, path)
    stat = File.stat(path)
    stamp = [stat.size, stat.mtime.to_f]
    entry = cache[path]
    return entry['problems'] if entry && entry['stamp'] == stamp

    problems = Bibkit::BibFile.load(path).problems.map { |p| [p.line, p.message] }
    cache[path] = { 'stamp' => stamp, 'problems' => problems }
    problems
  end

  def self.read_cache(path)
    data = JSON.parse(File.read(path))
    data['format'] == CACHE_FORMAT ? data['files'] : {}
  rescue StandardError
    {}
  end

  def self.write_cache(path, files)
    File.write(path, JSON.generate({ 'format' => CACHE_FORMAT, 'files' => files }))
  rescue SystemCallError
    nil
  end

  # BibTeX's "I was expecting a `,' or a `}'---line N of file F" when that
  # line has a `%`: the usual cause, which BibTeX does not name.
  def self.percent_hint(detail)
    m = detail.to_s.match(/I was expecting a `,' or a `\}'---line (\d+) of file (.+?)\.?\s*\z/)
    return '' unless m

    path = locate(m[2].strip, [])
    line = path && File.foreach(path).drop(m[1].to_i - 1).first
    line&.include?('%') ? " #{PERCENT_NOTE}" : ''
  rescue SystemCallError
    ''
  end

  PERCENT_NOTE = "'%' does not start a comment inside a .bib entry; move the note into a field or after the entry's closing brace."
end
