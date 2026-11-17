# frozen_string_literal: true

# ==============================================================================
# lib/leeni/gitignore_check.rb
#
# --gitignore-init on a paper that built: adds the standard LaTeX ignore rules
# to .gitignore (PDFs under figs/ directories stay tracked), then checks that
# git ignores no project file the paper needs: the build's inputs from the
# recorder file and the paper's own .bib files. Such a file would be missing
# from a fresh clone. Files git already tracks are not affected by ignore
# rules, so only untracked ones are reported.
# ==============================================================================

require 'open3'

class LeeniGitignore
  COPY_DEPTH = 4

  def initialize(builder)
    @builder = builder
    @bfilename = builder.bfilename
    @options = builder.options
  end

  # Runs in the paper's directory; false when a needed file is ignored.
  def run!
    Dir.chdir(File.expand_path(@builder.bdir)) do
      LaTeXConfig.init_gitignore!('.')
      check_needed_files
    end
  end

  private

  def check_needed_files
    unless inside_git_work_tree?
      puts Rainbow('==> Not inside a git repository; skipped the check for ignored files the paper uses.').yellow
      return true
    end

    ignored = ignored_files(needed_files)
    return report_clean if ignored.empty?

    report_ignored(ignored)
    false
  end

  def inside_git_work_tree?
    out, status = Open3.capture2e('git', 'rev-parse', '--is-inside-work-tree')
    status.success? && out.strip == 'true'
  rescue SystemCallError
    false
  end

  def needed_files
    (recorded_inputs + local_bibs).uniq.sort
  end

  def recorded_inputs
    fls = File.join(@builder.junk_dir, "#{@bfilename}.fls")
    LaTeXUtils.safe_read(fls).each_line.flat_map do |line|
      path = line.start_with?('INPUT ') ? line.delete_prefix('INPUT ').strip : ''
      next [] if path.empty? || LaTeXUtils.system_tex_file?(path) || File.expand_path(path).start_with?(junk_prefix)

      inside = project_relative(path)
      inside ? [inside] : project_copies(path)
    end
  end

  # A file read from outside the project (through TEXINPUTS) may have a copy
  # in the project, made by -I, that a build without the environment uses
  # instead: the same trailing path in the project or under styles/.
  def project_copies(path)
    parts = File.expand_path(path).split('/').reject(&:empty?)
    tails = (1..[parts.size - 1, COPY_DEPTH].min).map { |count| parts.last(count).join('/') }
    tails.flat_map { |tail| [tail, File.join(LatexIndependizer::STYLES_DIR, tail)] }.filter_map { |rel| project_relative(rel) }
  end

  def local_bibs
    bib_dirs = @options[:bib_dirs] || LaTeXUtils::DEFAULT_BIB_DIRS
    LatexBibChecks.bibliography_sources(@builder.junk_dir, @bfilename).filter_map do |name|
      path = LatexBibChecks.resolve(name, bib_dirs)
      path && project_relative(path)
    end
  end

  # A file of the project, outside the build directory; nil otherwise.
  def project_relative(path)
    return nil unless File.file?(path)

    root = File.realpath('.') + File::SEPARATOR
    real = File.realpath(path)
    return nil unless real.start_with?(root) && !real.start_with?(junk_prefix)

    real.delete_prefix(root)
  rescue SystemCallError
    nil
  end

  def junk_prefix
    @junk_prefix ||= begin
      junk = File.expand_path(@builder.junk_dir)
      (File.directory?(junk) ? File.realpath(junk) : junk) + File::SEPARATOR
    end
  end

  # { path => "source:line:pattern" } for each file an ignore rule matches.
  def ignored_files(paths)
    return {} if paths.empty?

    out, = Open3.capture2('git', 'check-ignore', '--verbose', '--non-matching', '--stdin', stdin_data: paths.join("\n"))
    out.each_line.with_object({}) do |line, found|
      rule, path = line.chomp.split("\t", 2)
      found[path] = rule unless rule.nil? || path.nil? || rule == '::' || rule.split(':', 3)[2].start_with?('!')
    end
  rescue SystemCallError
    {}
  end

  def report_clean
    puts Rainbow('==> Git ignores none of the project files the paper uses.').green.bright
    true
  end

  def report_ignored(ignored)
    warn Rainbow('[FAIL] Git ignores these files the paper uses; a fresh clone would not have them:').red.bright
    width = ignored.keys.map(&:length).max
    ignored.each { |path, rule| warn "       #{path.ljust(width)}  (#{rule})" }
    warn '       Track them with git add -f, or add an exception (!path) after the rule that ignores them;'
    warn '       an exception cannot bring back a file inside an ignored directory (a rule ending in /).'
  end
end
