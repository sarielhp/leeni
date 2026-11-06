# frozen_string_literal: true

# ==============================================================================
# lib/leeni/bib_extractor.rb
#
# Extracts cited bibliography entries and dependent @string macros from
# global or referenced .bib databases into a self-contained local .bib file.
# ==============================================================================

require 'fileutils'
require 'open3'
require_relative 'color'
require_relative 'utils'
require_relative 'bib_checks'

class LaTeXBibExtractor
  attr_reader :builder, :filename, :bfilename, :bdir, :options, :custom_outfile

  def self.extract!(builder, custom_outfile = nil)
    new(builder, custom_outfile).extract!
  end

  def initialize(builder, custom_outfile = nil)
    @builder = builder
    @filename = builder.filename
    @bfilename = builder.bfilename
    @bdir = builder.bdir
    @options = builder.options
    @custom_outfile = custom_outfile
  end

  def extract!
    Dir.chdir(File.expand_path(@bdir)) do
      do_extract
    end
  end

  # Writes the cited entries to stage_file; the caller is in the document directory.
  def extract_cited_to(stage_file)
    biblatex? ? extract_biblatex(stage_file) : extract_bibtex(stage_file)
  end

  def biblatex?
    bcf_path = File.join(junk_dir, "#{@bfilename}.bcf")
    return false unless File.file?(bcf_path) && File.size(bcf_path).positive?

    content = LaTeXUtils.safe_read(bcf_path)
    content.include?('<bcf:controlfile') || content.include?('<bcf:citekey')
  end

  private

  def junk_dir
    @builder.respond_to?(:junk_dir) ? @builder.junk_dir : 'junk'
  end

  def do_extract
    return false unless ensure_build_artifacts!

    target_name = determine_target_file
    target_abs = File.expand_path(target_name)
    return false unless validate_target_safety!(target_abs)

    FileUtils.mkdir_p(junk_dir)
    stage_file = File.join(junk_dir, "#{@bfilename}_extract_tmp.bib")
    FileUtils.rm_f(stage_file)

    success = biblatex? ? extract_biblatex(stage_file) : extract_bibtex(stage_file)
    return false unless success

    verify_and_install!(stage_file, target_name)
  end

  def ensure_build_artifacts!
    aux_path = File.join(junk_dir, "#{@bfilename}.aux")
    bcf_path = File.join(junk_dir, "#{@bfilename}.bcf")
    needs_build = @options[:force] || (!File.exist?(aux_path) && !File.exist?(bcf_path))

    return true unless needs_build

    puts "==> Compiling #{@filename} to generate bibliography tracking data..."
    @builder.run_in_current_directory!
  end

  def determine_target_file
    if @custom_outfile && !@custom_outfile.strip.empty?
      out = @custom_outfile.strip
      out += '.bib' unless out.end_with?('.bib')
      out
    else
      "#{@bfilename}.bib"
    end
  end

  def forbidden_bib_dirs
    dirs = []
    dirs.concat(Array(@options[:bib_dirs]))
    dirs.concat(LaTeXUtils::DEFAULT_BIB_DIRS)
    dirs.concat((ENV['BIBINPUTS'] || '').split(File::PATH_SEPARATOR))
    dirs.map { |d| File.expand_path(d.to_s.strip) }.reject(&:empty?).uniq
  end

  def validate_target_safety!(target_abs)
    forbidden = forbidden_bib_dirs
    forbidden.each do |fdir|
      next unless File.directory?(fdir)

      next unless File.identical?(File.dirname(target_abs), fdir) || target_abs.start_with?(fdir + File::SEPARATOR)

      warn Rainbow('==> Fatal Error: Refusing to write to global bibliography directory:').red.bright
      warn "    #{target_abs}"
      warn '    Extracted bibliography must reside in the local document directory.'
      return false
    end
    true
  end

  def extract_biblatex(stage_file)
    unless LaTeXUtils.command_available?('biber')
      warn Rainbow("==> Error: 'biber' is required for BibLaTeX bibliography extraction.").red.bright
      warn '    Please install Biber or ensure it is available in PATH.'
      return false
    end

    env = build_bibinputs_env
    bcf_base = File.join(junk_dir, @bfilename)
    cmd = ['biber', '--output-format=bibtex', '-O', stage_file, bcf_base]
    out, stat = Open3.capture2e(env, *cmd)

    unless stat.success? && File.file?(stage_file) && File.size(stage_file).positive?
      warn Rainbow('==> Error: Biber extraction failed:').red.bright
      warn out.strip unless out.strip.empty?
      return false
    end
    true
  end

  # BibTeX papers: Bibkit copies the cited entries verbatim from the paper's
  # .bib files, with their crossref/xdata parents and the @string and
  # @preamble blocks they use. The first entry of a key wins, as in BibTeX.
  def extract_bibtex(stage_file)
    files = bibtex_sources
    return false unless files

    keys = cited_keys
    collection = Bibkit::Collection.new(files.map { |path| [Bibkit::BibFile.load(path), true] })
    keys = collection.files.flat_map { |f| f.entries.map(&:key) }.uniq if keys.include?('*')
    fixer = Bibkit::Fixer.new([], collection)
    plan = fixer.plan(missing_keys: keys.reject { |k| k == '*' })
    warn Rainbow("==> Warning: no entry found for: #{plan.not_found.join(', ')}").yellow unless plan.not_found.empty?
    return extraction_failed('no cited entry found in the bibliography files') if plan.entries.empty?

    header = "% Extracted by leeni -B from #{files.map { |f| File.basename(f) }.join(', ')}"
    File.binwrite(stage_file, fixer.render('', plan, header: header))
    true
  end

  # Every \citation of the build, the .aux files of \include'd chapters too.
  def cited_keys
    aux = LaTeXUtils.glob_under(junk_dir, '**/*.aux').map { |path| LaTeXUtils.safe_read(path) }.join("\n")
    LaTeXUtils.extract_citation_keys(aux)
  end

  # The paper's \bibdata files, found as BibTeX finds them (project, then BIBINPUTS).
  def bibtex_sources
    names = LatexBibChecks.bibliography_sources(junk_dir, @bfilename)
    return extraction_failed('the paper names no bibliography file (\\bibliography{...})') if names.empty?

    paths = names.map { |name| [name, LatexBibChecks.locate(name, @options[:bib_dirs])] }
    missing = paths.select { |_, path| path.nil? }.map(&:first)
    return extraction_failed("bibliography file not found: #{missing.join(', ')}") unless missing.empty?

    paths.map(&:last).uniq
  end

  def extraction_failed(reason)
    warn Rainbow("==> Error: Bibliography extraction failed: #{reason}.").red.bright
    nil
  end

  def build_bibinputs_env
    search_dirs = [Dir.pwd]
    Array(@options[:bib_dirs]).each do |d|
      p = File.expand_path(d.to_s.strip)
      search_dirs << p if File.directory?(p)
    end
    ENV['BIBINPUTS']&.split(File::PATH_SEPARATOR)&.each do |d|
      p = File.expand_path(d.strip)
      search_dirs << p if File.directory?(p)
    end
    bibinputs_str = search_dirs.uniq.join(File::PATH_SEPARATOR) + File::PATH_SEPARATOR
    { 'BIBINPUTS' => bibinputs_str }
  end

  def verify_and_install!(stage_file, target_name)
    content = LaTeXUtils.safe_read(stage_file)
    stats = count_bib_stats(content)

    backup_existing_target!(target_name) if File.exist?(target_name)

    FileUtils.mv(stage_file, target_name)
    puts Rainbow("==> Extracted #{stats[:entries]} citations and #{stats[:strings]} @string macros to: #{target_name}").green.bright
    print_workflow_hint(target_name)
    true
  end

  def count_bib_stats(content)
    strings = content.scan(/^@string\b/i).size
    entries = content.scan(/^@(?!string\b|preamble\b|comment\b)\w+/i).size
    { entries: entries, strings: strings }
  end

  def backup_existing_target!(target_name)
    bak_file = "#{target_name}.bak"
    bak_file = "#{target_name}.#{Time.now.strftime('%Y%m%d_%H%M%S')}.bak" if File.exist?(bak_file)
    FileUtils.cp(target_name, bak_file)
    warn Rainbow("==> Notice: Existing '#{target_name}' backed up to: #{bak_file}").yellow
  end

  def print_workflow_hint(target_name)
    if biblatex?
      print_biblatex_hint(target_name)
    else
      print_bibtex_hint(target_name)
    end
  end

  def print_biblatex_hint(target_name)
    bcf_path = File.join(junk_dir, "#{@bfilename}.bcf")
    return unless File.file?(bcf_path)

    bcf_content = LaTeXUtils.safe_read(bcf_path)
    return if bcf_content.include?(">#{target_name}<")

    puts Rainbow("==> Note: Update #{@filename} to \\addbibresource{#{target_name}} to use this local file.").cyan
  end

  def print_bibtex_hint(target_name)
    aux_path = File.join(junk_dir, "#{@bfilename}.aux")
    return unless File.file?(aux_path)

    aux_content = LaTeXUtils.safe_read(aux_path)
    bibdata = aux_content.scan(/\\bibdata\{([^}]+)\}/).flatten.flat_map { |s| s.split(',') }.map(&:strip)
    target_base = File.basename(target_name, '.bib')
    return if bibdata.include?(target_base)

    puts Rainbow("==> Note: Update #{@filename} to \\bibliography{#{target_base}} to use this local file.").cyan
  end
end
