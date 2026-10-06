# frozen_string_literal: true

# ==============================================================================
# lib/leeni/bib_manager.rb
#
# Manages bibliography tool detection (Biber / BibTeX), citation extraction,
# dependency discovery, execution lifecycle, and staleness detection.
# ==============================================================================

require 'fileutils'
require 'open3'
require 'digest'

require_relative 'color'
require_relative 'utils'

class LaTeXBibManager
  attr_reader :builder, :bib_fatal
  attr_accessor :last_bib_citations, :last_bib_sources, :last_bcf_sha

  def initialize(builder)
    @builder = builder
    @bib_fatal = false
    @last_bib_citations = nil
    @last_bib_sources = nil
    @last_bcf_sha = nil
  end

  def options = @builder.options
  def junk_dir = @builder.junk_dir
  def bfilename = @builder.bfilename
  def biberr = @builder.biberr

  def bib_globs
    dirs = options[:bib_dirs] || LaTeXUtils::DEFAULT_BIB_DIRS
    ['*.bib'] + dirs.map { |d| "#{d.to_s.chomp('/')}/*.bib" }
  end

  def bib_files_on_disk
    Dir[*bib_globs].select { |f| File.file?(f) }
  end

  def bib_files_newer_than_bbl?
    fnbbl = File.join(junk_dir, "#{bfilename}.bbl")
    return false unless File.exist?(fnbbl) && File.size(fnbbl) > 0
    return false unless File.exist?(File.join(junk_dir, "#{bfilename}.aux")) || File.exist?(File.join(junk_dir, "#{bfilename}.bcf"))

    bbl_mtime = File.mtime(fnbbl)
    discover_bib_files.any? { |b| (File.mtime(b) rescue 0) > bbl_mtime }
  end

  def detect_bib_tool(aux_contents = nil)
    return nil if options[:bib] == false

    aux_contents ||= compute_aux_hash
    discard_stale_biber_control_files(aux_contents)
    return :biber if detect_biber_control_file

    return (options[:bib] == true ? :bibtex : nil) if aux_contents.empty?

    detect_bib_tool_from_aux(aux_contents)
  end

  BIBLATEX_AUX_MARKER = '\\abx@aux@'

  # junk/ persists across builds, so a .bcf left by an earlier biblatex build
  # outlives a switch to bibtex. Biblatex always writes \abx@aux@ lines to the
  # aux, so an aux that has content but none of them proves the control files
  # are stale; trusting them makes biber overwrite the bbl in biblatex format.
  def discard_stale_biber_control_files(aux_contents)
    return if aux_contents.empty? || aux_contents.include?(BIBLATEX_AUX_MARKER)

    %w[bcf run.xml].each { |ext| FileUtils.rm_f(File.join(junk_dir, "#{bfilename}.#{ext}")) }
  end

  def detect_biber_control_file
    bcf_path = File.join(junk_dir, "#{bfilename}.bcf")
    return true if File.exist?(bcf_path) && (LaTeXUtils.safe_read(bcf_path).include?('<bcf:citekey') || options[:bib] == true)

    run_xml_path = File.join(junk_dir, "#{bfilename}.run.xml")
    if File.exist?(run_xml_path)
      content = LaTeXUtils.safe_read(run_xml_path)
      return true if content =~ /biber/i && (content =~ /active="1"/ || options[:bib] == true)
    end

    false
  end

  def detect_bib_tool_from_aux(aux_contents)
    return :biber if detect_biber_aux(aux_contents)
    return :bibtex if detect_bibtex_aux(aux_contents)

    options[:bib] == true ? :bibtex : nil
  end

  def detect_biber_aux(aux_contents)
    return false unless aux_contents.include?(BIBLATEX_AUX_MARKER)

    bcf_path = File.join(junk_dir, "#{bfilename}.bcf")
    return options[:bib] == true unless File.exist?(bcf_path)

    LaTeXUtils.safe_read(bcf_path).include?('<bcf:citekey') || options[:bib] == true
  end

  def detect_bibtex_aux(aux_contents)
    has_bibdata = aux_contents =~ /\\bibdata\{/
    needs_bib = aux_contents =~ /\\citation/ || options[:bib] == true
    return false unless has_bibdata && needs_bib
    return true if options[:bib] == true

    has_bbl = LaTeXUtils.bbl_has_entries?(File.join(junk_dir, "#{bfilename}.bbl")) || LaTeXUtils.bbl_has_entries?("#{bfilename}.bbl")
    return false if has_bbl && !bib_files_exist_for_bibdata?(aux_contents)

    true
  end

  def bib_files_exist_for_bibdata?(aux_contents)
    targets = aux_contents.scan(/\\bibdata\{([^}]+)\}/).flatten.flat_map { |s| s.split(',') }.map(&:strip)
    return true if targets.empty?

    configured_dirs = options[:bib_dirs] || LaTeXUtils::DEFAULT_BIB_DIRS
    bib_dirs = (['.'] + configured_dirs + ENV['BIBINPUTS'].to_s.split(':')).reject(&:empty?)
    targets.any? do |target|
      bib_dirs.any? do |d|
        File.file?(File.join(d, "#{target}.bib")) || File.file?(File.join(d, target))
      end
    end
  end

  def run_bib_pass(tool, aux_contents = nil)
    puts '' if options[:trace] || options[:raw]
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) if options[:time]
    fnbbl = File.join(junk_dir, "#{bfilename}.bbl")
    root_bbl = "#{bfilename}.bbl"
    previous = bibliography_source(root_bbl, fnbbl)
    preserve_bibliography_backup(previous, root_bbl)
    FileUtils.rm_f(fnbbl)

    result = execute_bib_and_verify(tool, fnbbl, previous, root_bbl)
    @last_bib_citations = current_citation_keys(aux_contents)
    update_bcf_snapshot if tool == :biber

    if options[:time]
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      printf(' [%s]', Rainbow(format('%.2fs', t1 - t0)).green)
    end
    result
  end

  def update_bcf_snapshot
    bcf = File.join(junk_dir, "#{bfilename}.bcf")
    @last_bcf_sha = Digest::SHA256.file(bcf).hexdigest if File.file?(bcf)
  end

  def execute_bib_and_verify(tool, fnbbl, previous, root_bbl)
    @bib_fatal = false
    bib_out, status = invoke_bibliography_command(tool, fnbbl, previous)
    return false unless bib_out

    status_ok = status.respond_to?(:success?) ? status.success? : (status == 0)
    has_entries = LaTeXUtils.bbl_has_entries?(fnbbl)
    if LaTeXUtils.bib_fatal_error?(tool, bib_out, status_ok)
      restore_bibliography(fnbbl, previous)
      warn "\nBibliography process failed or produced no valid entries.#{bibliography_failure_detail(bib_out)} See #{biberr}."
      @bib_fatal = true
      return false
    end

    unless has_entries
      restore_bibliography(fnbbl, previous) if previous
      warn "\nBibliography process failed or produced no valid entries. See #{biberr}." if options[:verbose] || options[:trace]
      return false
    end

    @builder.update_target_file(fnbbl, root_bbl) if options[:trace] || File.exist?(root_bbl)
    true
  end

  def bibliography_failure_detail(output)
    detail = output.to_s.each_line.find do |line|
      line.match?(/I couldn't open database file|(?:ERROR|FATAL)\s+-/i)
    end
    detail ? " #{detail.strip}." : ''
  end

  def invoke_bibliography_command(tool, fnbbl, previous)
    bib_out, status = execute_bibliography(tool)
    File.write(biberr, bib_out)
    [bib_out, status]
  rescue Errno::ENOENT => e
    File.write(biberr, e.message)
    restore_bibliography(fnbbl, previous)
    warn "\nBibliography tool unavailable: #{e.message}"
    @bib_fatal = true
    nil
  end

  def bibliography_source(primary, secondary) = [primary, secondary].find { |f| LaTeXUtils.bbl_has_entries?(f) }

  def preserve_bibliography_backup(previous, root_bbl)
    return unless previous

    backup = "#{root_bbl}.bak"
    FileUtils.cp(previous, backup)
    FileUtils.cp(previous, File.join(junk_dir, File.basename(backup)))
  end

  def restore_bibliography(junk_bbl, previous)
    return FileUtils.rm_f(junk_bbl) unless previous

    backup = "#{bfilename}.bbl.bak"
    source = File.file?(backup) ? backup : previous
    FileUtils.cp(source, junk_bbl) unless source == junk_bbl
  end

  def discover_bib_files(aux_contents = nil)
    bibs = bib_files_on_disk
    bibs.concat(extract_aux_bib_files(aux_contents))
    bibs.concat(extract_bcf_bib_files)
    bibs.uniq
  end

  def extract_bcf_bib_files
    bcf_path = File.join(junk_dir, "#{bfilename}.bcf")
    return [] unless File.exist?(bcf_path)

    files = []
    LaTeXUtils.safe_read(bcf_path).scan(/<bcf:datasource[^>]*>(.*?)<\/bcf:datasource>/) { |m| collect_bib_candidates(m.first.strip, files) }
    files
  end

  def extract_aux_bib_files(aux_contents = nil)
    files = []
    sources = aux_contents ? [aux_contents] : current_aux_files.map { |aux| LaTeXUtils.safe_read(aux) }
    sources.each { |content| content.scan(/\\bibdata\{([^}]+)\}/) { |m| collect_bib_candidates(m.first, files) } }
    files
  end

  def collect_bib_candidates(bibdata_str, files)
    configured_dirs = options[:bib_dirs] || LaTeXUtils::DEFAULT_BIB_DIRS
    prefixes = [''] + configured_dirs.map { |d| "#{d.chomp('/')}/" }
    prefixes += ENV['BIBINPUTS'].to_s.split(':').reject(&:empty?).map { |d| "#{d.chomp('/')}/" }
    bibdata_str.split(',').map(&:strip).each do |name|
      stem = name.delete_suffix('.bib')
      match = prefixes.map { |pfx| "#{pfx}#{stem}.bib" }.find { |cand| File.file?(cand) }
      files << match if match
    end
  end

  def execute_bibliography(tool)
    discover_bib_files.each { |b| FileUtils.cp(b, File.join(junk_dir, '')) }
    cmd = if tool == :biber
            ['biber', '--output_safechars', '--input-directory', '.', '--output-directory', '.', bfilename]
          else
            copy_style_files_for_bibtex
            ['bibtex', bfilename]
          end
    Dir.chdir(junk_dir) { @builder.capture_pass_output(cmd) }
  end

  def copy_style_files_for_bibtex
    return unless File.directory?('styles')

    FileUtils.mkdir_p(File.join(junk_dir, 'styles'))
    Dir['styles/*'].each do |s|
      base = File.basename(s)
      FileUtils.cp_r(s, File.join(junk_dir, 'styles/')) unless base == junk_dir || base == 'junk' || base == '.junk'
    end
  end

  def compute_aux_hash
    current_aux_files.map { |f| "#{f}:#{LaTeXUtils.safe_read(f)}" }.join("\n")
  end

  AUX_MTIME_SLACK = 2

  # junk/ persists, so it also holds aux files of renamed or earlier documents
  # that are never rewritten; feeding those to bib detection can start a
  # spurious bibtex run. The current document's aux tree is the main aux plus
  # everything it \@input's, plus any aux written during this build (bibunits
  # and similar write aux files the main one does not link).
  def current_aux_files
    all = LaTeXUtils.glob_under(junk_dir, '**/*.aux')
    since = @builder.build_start_time
    return all.sort unless since

    (linked_aux_files(File.join(junk_dir, "#{bfilename}.aux")) + all.select { |f| fresh_file?(f, since) }).uniq.sort
  end

  def fresh_file?(path, since)
    (File.mtime(path) rescue Time.at(0)) >= since - AUX_MTIME_SLACK
  end

  # Containment is checked on canonical paths so a symlinked directory inside
  # junk/ cannot lead the closure to files outside it.
  def linked_aux_files(main)
    root = (File.realpath(junk_dir) rescue File.expand_path(junk_dir)) + File::SEPARATOR
    queue = [File.expand_path(main)]
    found = {}
    until queue.empty?
      file = queue.shift
      real = (File.realpath(file) rescue nil)
      next if real.nil? || found.key?(real) || !real.start_with?(root) || !File.file?(real)

      found[real] = File.join(junk_dir, file.delete_prefix(File.expand_path(junk_dir) + File::SEPARATOR))
      LaTeXUtils.safe_read(real).scan(/\\@input\{([^}]+\.aux)\}/) { |m| queue << File.expand_path(m.first, junk_dir) }
    end
    found.values
  end

  def current_citation_keys(aux_contents = nil)
    aux_str = aux_contents || compute_aux_hash
    bcf_path = File.join(junk_dir, "#{bfilename}.bcf")
    bcf = File.file?(bcf_path) ? LaTeXUtils.safe_read(bcf_path) : nil
    LaTeXUtils.extract_citation_keys(aux_str, bcf)
  end

  def bbl_coverage(fnbbl)
    return [Set.new, Set.new] unless fnbbl && File.file?(fnbbl)

    content = LaTeXUtils.safe_read(fnbbl)
    provided = content.scan(/\\bibitem(?:\[[^\]]*\])?\{([^}]+)\}/).flatten +
               content.scan(/\\entry\{([^}]+)\}/).flatten
    missing = content.scan(/\\missing\{([^}]+)\}/).flatten

    blg_path = File.join(junk_dir, "#{bfilename}.blg")
    if File.file?(blg_path)
      blg = LaTeXUtils.safe_read(blg_path)
      missing += blg.scan(/Warning--I didn't find a database entry for "([^"]+)"/).flatten
      missing += blg.scan(/WARN - I didn't find a database entry for '([^']+)'/).flatten
    end

    [provided.map(&:strip).reject(&:empty?).to_set, missing.map(&:strip).reject(&:empty?).to_set]
  end

  def bbl_satisfies_citations?(fnbbl, aux_contents = nil)
    return false unless File.file?(fnbbl) && File.size(fnbbl) > 0

    cites = current_citation_keys(aux_contents).reject { |k| k == '*' }.to_set
    return true if cites.empty?

    provided, missing = bbl_coverage(fnbbl)
    return false unless cites.subset?(provided | missing)
    return false unless (missing - cites).empty?

    true
  end

  def needs_bib_pass?(tool, loga, aux_contents = nil)
    return false if options[:bib] == false
    return true if options[:bib] == true

    fnbbl = File.join(junk_dir, "#{bfilename}.bbl")
    return true unless File.exist?(fnbbl)

    log = LaTeXUtils.safe_read(loga)
    return true if (tool == :biber && log =~ /Please \(re\)run Biber/i) || log =~ /Package natbib Warning: Citation\(s\) may have changed/i
    return true unless bbl_satisfies_citations?(fnbbl, aux_contents)

    bcf = File.join(junk_dir, "#{bfilename}.bcf")
    return true if tool == :biber && bcf_changed?(bcf)

    bbl_mtime = File.mtime(fnbbl)
    return true if discover_bib_files(aux_contents).any? { |b| bib_file_changed?(b, bbl_mtime) }

    @last_bib_citations && current_citation_keys(aux_contents) != @last_bib_citations
  end

  # True when what the last bibtex/biber run consumed no longer matches what the
  # document now asks for: uncovered citations, a changed citation set, or (biber)
  # a changed control file. Unlike needs_bib_pass? it ignores the natbib/biblatex
  # "may have changed" warnings, which appear after every successful bib run.
  def bib_stale_since_last_run?(tool, aux_contents = nil)
    fnbbl = File.join(junk_dir, "#{bfilename}.bbl")
    return true unless bbl_satisfies_citations?(fnbbl, aux_contents)
    return true if tool == :biber && bcf_changed?(File.join(junk_dir, "#{bfilename}.bcf"))

    !@last_bib_citations.nil? && current_citation_keys(aux_contents) != @last_bib_citations
  end

  def bcf_changed?(bcf_path)
    return false unless @last_bcf_sha && File.file?(bcf_path)

    Digest::SHA256.file(bcf_path).hexdigest != @last_bcf_sha
  end

  def bib_file_changed?(path, bbl_mtime)
    return true if (File.mtime(path) rescue 0) > bbl_mtime

    last_sha = @last_bib_sources&.dig(path, 'sha')
    return false unless last_sha

    current_sha = @builder.input_snapshots&.dig(path, :sha) || (Digest::SHA256.file(path).hexdigest rescue nil)
    current_sha != last_sha
  end
end
