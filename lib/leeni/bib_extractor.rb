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

    success = is_biblatex? ? extract_biblatex(stage_file) : extract_bibtex(stage_file)
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

  def is_biblatex?
    bcf_path = File.join(junk_dir, "#{@bfilename}.bcf")
    return false unless File.file?(bcf_path) && File.size(bcf_path).positive?

    content = LaTeXUtils.safe_read(bcf_path)
    content.include?('<bcf:controlfile') || content.include?('<bcf:citekey')
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

      if File.identical?(File.dirname(target_abs), fdir) || target_abs.start_with?(fdir + File::SEPARATOR)
        warn Rainbow("==> Fatal Error: Refusing to write to global bibliography directory:").red.bright
        warn "    #{target_abs}"
        warn "    Extracted bibliography must reside in the local document directory."
        return false
      end
    end
    true
  end

  def extract_biblatex(stage_file)
    unless LaTeXUtils.command_available?('biber')
      warn Rainbow("==> Error: 'biber' is required for BibLaTeX bibliography extraction.").red.bright
      warn "    Please install Biber or ensure it is available in PATH."
      return false
    end

    env = build_bibinputs_env
    bcf_base = File.join(junk_dir, @bfilename)
    cmd = ['biber', '--output-format=bibtex', '-O', stage_file, bcf_base]
    out, stat = Open3.capture2e(env, *cmd)

    unless stat.success? && File.file?(stage_file) && File.size(stage_file).positive?
      warn Rainbow("==> Error: Biber extraction failed:").red.bright
      warn out.strip unless out.strip.empty?
      return false
    end
    true
  end

  def extract_bibtex(stage_file)
    unless LaTeXUtils.command_available?('bibtool')
      warn Rainbow("==> Error: 'bibtool' is required for BibTeX bibliography extraction.").red.bright
      warn "    Please install it via your package manager:"
      warn "      sudo apt install bibtool      # Debian / Ubuntu"
      warn "      brew install bibtool          # macOS"
      return false
    end

    aux_path = File.join(junk_dir, "#{@bfilename}.aux")
    unless File.file?(aux_path)
      warn Rainbow("==> Error: Auxiliary file '#{aux_path}' not found.").red.bright
      return false
    end

    env = build_bibinputs_env
    cmd = ['bibtool', '-c', '-x', aux_path, '-o', stage_file]
    out, stat = Open3.capture2e(env, *cmd)

    unless stat.success? && File.file?(stage_file) && File.size(stage_file) > 0
      warn Rainbow("==> Error: BibTool extraction failed or no citations found:").red.bright
      warn out.strip unless out.strip.empty?
      return false
    end
    true
  end

  def build_bibinputs_env
    search_dirs = [Dir.pwd]
    Array(@options[:bib_dirs]).each do |d|
      p = File.expand_path(d.to_s.strip)
      search_dirs << p if File.directory?(p)
    end
    if ENV['BIBINPUTS']
      ENV['BIBINPUTS'].split(File::PATH_SEPARATOR).each do |d|
        p = File.expand_path(d.strip)
        search_dirs << p if File.directory?(p)
      end
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
    if File.exist?(bak_file)
      bak_file = "#{target_name}.#{Time.now.strftime('%Y%m%d_%H%M%S')}.bak"
    end
    FileUtils.cp(target_name, bak_file)
    warn Rainbow("==> Notice: Existing '#{target_name}' backed up to: #{bak_file}").yellow
  end

  def print_workflow_hint(target_name)
    if is_biblatex?
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
