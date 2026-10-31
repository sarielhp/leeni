# frozen_string_literal: true

# ==============================================================================
# lib/leeni/make_indep.rb
#
# Converts a paper in place so it compiles with --no-env (-I / --make-indep).
# Files found through TEXINPUTS, TEXMFHOME and similar search paths are copied
# into styles/, the main file gets an \input@path entry for that directory,
# and the cited bibliography entries are extracted into <paper>.bib. The plan
# is first applied to a sandbox copy and verified there; only then are the
# originals of every changed file saved to old_ver_yy_mm_dd_hh_mm.zip and the
# project itself is changed.
# ==============================================================================

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative 'bib_extractor'
require_relative 'packager'

class LatexIndependizer
  STYLES_DIR = 'styles'
  COPY_EXTS = %w[.sty .cls .clo .cfg .def .fd .bbx .cbx .lbx .dbx .rtx .ldf .tex
                 .pdf .png .jpg .jpeg .eps .mps].freeze
  TEXT_EXTS = %w[.tex .sty .cls].freeze
  FONT_EXTS = %w[.tfm .vf .pfb .otf .ttf .enc .map].freeze
  SYSTEM_TREES = '$TEXMFDIST:$TEXMFLOCAL:$TEXMFSYSVAR:$TEXMFSYSCONFIG:$TEXMFVAR:$TEXMFMAIN'
  NEW_FILES_LIST = 'leeni-make-indep-new-files.txt'
  SKIP_IN_SANDBOX = %w[.git .hg .svn junk .junk].freeze

  Plan = Struct.new(:copies, :edits) do
    def empty?
      copies.empty? && edits.empty?
    end

    def paths
      (copies.keys + edits.keys).uniq.sort
    end
  end

  def initialize(builder)
    @builder = builder
    @filename = builder.filename
    @bfilename = builder.bfilename
    @options = builder.options
    @renames = {}
  end

  # styles/ must be a real directory of this project: when it is a symbolic
  # link (often to a shared styles collection), copying into it would change
  # files that other papers use. Returns the problem, or nil.
  def self.styles_dir_problem(dir)
    path = File.join(dir, STYLES_DIR)
    if File.symlink?(path)
      "#{path} is a symbolic link to #{File.readlink(path)}; --make-indep will not copy files into a shared directory. " \
        'Replace the link with a real directory (or move it aside) and run again.'
    elsif File.exist?(path) && !File.directory?(path)
      "#{path} exists but is not a directory."
    end
  end

  def run!
    Dir.chdir(File.expand_path(@builder.bdir)) do
      problem = self.class.styles_dir_problem('.')
      next convert unless problem

      warn Rainbow("[FAIL] #{problem}").red.bright
      false
    end
  end

  private

  def convert
    plan = build_plan
    return false unless plan

    if plan.empty?
      puts Rainbow("==> #{@filename} already compiles without the environment; nothing to change.").green.bright
      return true
    end
    return false unless no_linked_targets?(plan) && verify_plan(plan)
    return show_dry_run(plan) if @options[:dry_run]

    backup = write_backup(plan)
    return false unless backup

    apply_plan(plan, '.')
    report(plan, backup)
    true
  end

  # Writing through a symbolic link would change the file it points to,
  # which may be shared with other papers.
  def no_linked_targets?(plan)
    linked = plan.paths.select { |rel| File.symlink?(rel) }
    return true if linked.empty?

    warn Rainbow('[FAIL] These files are symbolic links; --make-indep will not write through them:').red.bright
    linked.each { |rel| warn "       #{rel} -> #{File.readlink(rel)}" }
    warn '       Nothing was changed.'
    false
  end

  # ---------------------------------------------------------------- planning

  def build_plan
    fls = File.join(@builder.junk_dir, "#{@bfilename}.fls")
    unless File.file?(fls)
      warn Rainbow("[FAIL] Missing #{fls}; cannot find the files the paper uses.").red.bright
      return nil
    end

    plan = Plan.new({}, {})
    inputs = fls_inputs(fls)
    warn_about_fonts(inputs)
    return nil unless plan_copies(plan, inputs)

    plan_path_rewrites(plan, inputs)
    return nil unless plan_bibliography(plan, inputs)

    plan_search_path(plan)
    plan
  end

  def fls_inputs(fls)
    paths = LaTeXUtils.safe_read(fls).each_line.filter_map do |line|
      line.start_with?('INPUT ') ? line.sub(/^INPUT\s+/, '').strip : nil
    end
    junk = File.expand_path(@builder.junk_dir) + File::SEPARATOR
    paths.uniq.reject { |path| path.empty? || File.expand_path(path).start_with?(junk) || system_file?(path) }
  end

  def system_file?(path)
    expanded = File.expand_path(path)
    system_trees.any? { |tree| expanded.start_with?(tree + File::SEPARATOR) }
  end

  # The trees kpathsea still searches once --no-env has cleared the user's
  # variables. Files under them need no copying.
  def system_trees
    @system_trees ||= begin
      env = LaTeXUtils::TEX_ENV_VARS.to_h { |var| [var, nil] }
      out, status = Open3.capture2e(env, 'kpsewhich', "--expand-var=#{SYSTEM_TREES}")
      trees = status.success? ? out.strip.split(File::PATH_SEPARATOR) : []
      trees.map { |tree| File.expand_path(tree.delete_prefix('!!')) }.reject { |tree| tree == '/' }.uniq
    rescue SystemCallError
      []
    end
  end

  def warn_about_fonts(inputs)
    fonts = inputs.select { |path| FONT_EXTS.include?(File.extname(path).downcase) }
    return if fonts.empty?

    warn Rainbow('[WARN] These font files come from a personal TeX tree and cannot be moved into styles/:').yellow
    fonts.each { |font| warn "       #{font}" }
  end

  # A file the sources name by an explicit path (../shared, /abs/fig) gets a
  # unique name in styles/ and every reference to it is rewritten. A file
  # found through a search path keeps its basename, since the sources name
  # it that way.
  def plan_copies(plan, inputs)
    candidates = inputs.select { |path| COPY_EXTS.include?(File.extname(path).downcase) && needs_copy?(path) }
    named, searched = candidates.partition { |path| named_in_sources?(path, inputs) }
    return false unless searched.all? { |path| add_copy(plan, searched_dest(path, inputs), File.expand_path(path)) }

    named.each { |path| add_named_copy(plan, path) }
    true
  end

  # A file found through a search path keeps the part of its path that the
  # sources spell out: \input{sub/x} found as ../sub/x.tex becomes
  # styles/sub/x.tex, which \input@path then finds.
  def searched_dest(path, inputs)
    File.join(STYLES_DIR, spelled_suffix(path, inputs) || File.basename(path))
  end

  def spelled_suffix(path, inputs)
    parts = path.split('/')
    suffixes = (1...(parts.size - 1)).map { |index| parts[index..] }
    suffixes.reject { |segments| segments.any? { |part| part.empty? || part.start_with?('.') } }
            .map { |segments| segments.join('/') }
            .find { |suffix| spelled?(suffix, inputs) }
  end

  def spelled?(spelling, inputs)
    text = source_text(inputs)
    [spelling, strip_ext(spelling)].any? { |form| text.match?(name_pattern(form)) }
  end

  def named_in_sources?(path, inputs)
    path.include?('/') && spelled?(path, inputs)
  end

  def strip_ext(path)
    path.delete_suffix(File.extname(path))
  end

  def name_pattern(spelling)
    /\{\s*#{Regexp.escape(spelling)}\s*\}/
  end

  def source_text(inputs)
    @source_text ||= text_sources(inputs).map { |path| LaTeXUtils.safe_read(path) }.join("\n")
  end

  def text_sources(inputs)
    ([@filename] + inputs).uniq.select { |path| TEXT_EXTS.include?(File.extname(path).downcase) && File.file?(path) }
  end

  def add_named_copy(plan, path)
    src = File.expand_path(path)
    dest = unique_dest(plan, File.basename(path), src)
    plan.copies[dest] = src unless File.file?(dest) && FileUtils.compare_file(dest, src)
    @renames[path] = dest
  end

  def unique_dest(plan, base, src)
    ext = File.extname(base)
    (1..).each do |n|
      dest = File.join(STYLES_DIR, n == 1 ? base : "#{File.basename(base, ext)}-#{n}#{ext}")
      taken = plan.copies[dest] || (File.file?(dest) ? dest : nil)
      return dest if taken.nil? || FileUtils.compare_file(taken, src)
    end
  end

  # Rewrites references in the project sources and in copied text files,
  # which may themselves name other outside files.
  def plan_path_rewrites(plan, inputs)
    rewrite_targets(plan, inputs).each do |key, path|
      content = plan.edits[key] || LaTeXUtils.safe_read(path)
      updated = rewrite_paths(content)
      next if updated == content

      plan.copies.delete(key)
      plan.edits[key] = updated
    end
  end

  def rewrite_targets(plan, inputs)
    by_source = plan.copies.to_h { |dest, src| [src, dest] }
    text_sources(inputs).filter_map do |path|
      key = project_relative(path) || by_source[File.expand_path(path)]
      key && [key, path]
    end
  end

  def rewrite_paths(content)
    @renames.each do |path, dest|
      [[path, dest], [strip_ext(path), strip_ext(dest)]].uniq.each do |from, to|
        content = content.gsub(name_pattern(from)) { "{#{to}}" }
      end
    end
    rewrite_graphicspath(content)
  end

  # \graphicspath replaces \input@path for graphics, so directories outside
  # the project are swapped for styles/, where their figures were copied.
  def rewrite_graphicspath(content)
    content.gsub(/\\graphicspath\s*\{((?:\s*\{[^{}]*\})*)\s*\}/) do |original|
      dirs = Regexp.last_match(1).scan(/\{([^{}]*)\}/).flatten
      mapped = dirs.map { |dir| outside_project?(dir) ? "#{STYLES_DIR}/" : dir }.uniq
      mapped == dirs ? original : "\\graphicspath{#{mapped.map { |dir| "{#{dir}}" }.join}}"
    end
  end

  def outside_project?(dir)
    root = File.realpath('.')
    full = File.expand_path(dir, root)
    full != root && !full.start_with?(root + File::SEPARATOR)
  end

  # Files outside the project are always copied. Inside the project, only
  # style files in subdirectories are: they were found through TEXINPUTS,
  # while figures and .tex inputs there are named by their relative path.
  def needs_copy?(path)
    rel = project_relative(path)
    return true unless rel
    return false if File.dirname(rel) == '.' || rel.start_with?("#{STYLES_DIR}/")

    !%w[.tex .pdf .png .jpg .jpeg .eps .mps].include?(File.extname(rel).downcase)
  end

  def project_relative(path)
    root = File.realpath('.')
    real = File.realpath(path)
    real.start_with?(root + File::SEPARATOR) ? real.delete_prefix(root + File::SEPARATOR) : nil
  rescue SystemCallError
    nil
  end

  def add_copy(plan, dest, src)
    previous = plan.copies[dest]
    if previous && !FileUtils.compare_file(previous, src)
      warn Rainbow("[FAIL] Two different files would both become #{dest}:").red.bright
      warn "       #{previous}\n       #{src}"
      return false
    end
    plan.copies[dest] = src unless File.file?(dest) && FileUtils.compare_file(dest, src)
    true
  end

  def plan_search_path(plan)
    return unless plan.paths.any? { |dest| dest.start_with?("#{STYLES_DIR}/") }

    content = current_content(plan, @filename)
    return if content.match?(%r{\\input@path.*\{#{STYLES_DIR}/\}})

    plan.edits[@filename] = inject_search_path(content)
  end

  def inject_search_path(content)
    definition = if content.include?('input@path')
                   "\\providecommand\\input@path{}\n\\g@addto@macro\\input@path{{#{STYLES_DIR}/}}"
                 else
                   "\\def\\input@path{{#{STYLES_DIR}/}}"
                 end
    lines = content.lines
    index = lines.find_index { |line| line =~ /^\s*\\(documentclass|RequirePackage|input)/ } || 0
    lines.insert(index, "\\makeatletter\n#{definition}\n\\makeatother\n").join
  end

  def current_content(plan, rel)
    plan.edits[rel] || LaTeXUtils.safe_read(rel)
  end

  # ------------------------------------------------------------ bibliography

  def plan_bibliography(plan, inputs)
    extractor = LaTeXBibExtractor.new(@builder)
    biblatex = extractor.biblatex?
    names = biblatex ? biber_sources : bibtex_sources
    plan_bst(plan) unless biblatex
    return true if names.empty? || names.all? { |name| local_bib?(name) }

    content = extract_bibliography(extractor)
    return false unless content

    target = "#{@bfilename}.bib"
    plan.edits[target] = content unless File.file?(target) && File.read(target) == content
    rewrite_bib_references(plan, inputs, biblatex)
  end

  def aux_text
    @aux_text ||= LaTeXUtils.safe_read(File.join(@builder.junk_dir, "#{@bfilename}.aux"))
  end

  def bibtex_sources
    aux_text.scan(/\\bibdata\{([^}]*)\}/).flatten.flat_map { |list| list.split(',') }.map(&:strip).reject(&:empty?)
  end

  def biber_sources
    bcf = LaTeXUtils.safe_read(File.join(@builder.junk_dir, "#{@bfilename}.bcf"))
    bcf.scan(%r{<bcf:datasource[^>]*>([^<]+)</bcf:datasource>}).flatten.map(&:strip)
  end

  # A source counts as local when it is a relative path that leeni finds in
  # the project without BIBINPUTS.
  def local_bib?(name)
    return false if name.start_with?('/', '~')

    dirs = ['.'] + Array(@options[:bib_dirs] || LaTeXUtils::DEFAULT_BIB_DIRS)
    stem = name.delete_suffix('.bib')
    dirs.any? { |dir| File.file?(File.join(dir, "#{stem}.bib")) }
  end

  def extract_bibliography(extractor)
    Dir.mktmpdir('leeni_indep_bib_') do |dir|
      stage = File.join(dir, "#{@bfilename}.bib")
      unless extractor.extract_cited_to(stage)
        warn Rainbow('[FAIL] Could not extract the cited bibliography entries; nothing was changed.').red.bright
        return nil
      end
      File.read(stage)
    end
  end

  def rewrite_bib_references(plan, inputs, biblatex)
    sources = ([@filename] + inputs.filter_map { |path| project_relative(path) })
              .uniq.select { |rel| File.extname(rel) == '.tex' && File.file?(rel) }
    sources.each do |rel|
      content = current_content(plan, rel)
      updated = rewrite_bib_lines(content, biblatex)
      plan.edits[rel] = updated unless updated == content
    end
    true
  end

  def rewrite_bib_lines(content, biblatex)
    seen_resource = false
    content.lines.map do |line|
      next line if line.match?(/\A\s*%/)

      line = line.gsub(/\\bibliography\{[^}]*\}/) { "\\bibliography{#{@bfilename}}" }
      next line unless biblatex && line.match?(/\\addbibresource\b/)

      replaced = seen_resource ? "% #{line.chomp} % removed by leeni --make-indep\n" : rewrite_resource(line)
      seen_resource = true
      replaced
    end.join
  end

  def rewrite_resource(line)
    line.sub(/\\addbibresource(\[[^\]]*\])?\{[^}]*\}/) { "\\addbibresource{#{@bfilename}.bib}" }
  end

  # BibTeX finds styles in the current directory, not through \input@path.
  def plan_bst(plan)
    style = aux_text[/\\bibstyle\{([^}]+)\}/, 1]&.strip
    return if style.nil? || style.include?('/') || File.file?("#{style}.bst")

    out, status = Open3.capture2e('kpsewhich', "#{style}.bst")
    path = out.strip
    return unless status.success? && File.file?(path) && !system_file?(path)

    add_copy(plan, "#{style}.bst", path)
  rescue SystemCallError
    nil
  end

  # ------------------------------------------------------- apply and verify

  def apply_plan(plan, root)
    plan.copies.each do |dest, src|
      target = File.join(root, dest)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(src, target)
    end
    plan.edits.each do |rel, content|
      target = File.join(root, rel)
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, content)
    end
  end

  def verify_plan(plan)
    puts Rainbow('==> Checking the converted paper in an isolated sandbox with --no-env...').cyan.bright
    Dir.mktmpdir('leeni_indep_') do |tmpdir|
      copy_project_to(tmpdir)
      apply_plan(plan, tmpdir)
      next true if LatexPackager.new(@builder).run_sandbox_compile(tmpdir)

      warn Rainbow('[FAIL] The converted paper did not build the same way without the environment; nothing was changed.').red.bright
      false
    end
  end

  def copy_project_to(tmpdir)
    junk = File.expand_path(@builder.junk_dir)
    Dir.children('.').each do |entry|
      next if SKIP_IN_SANDBOX.include?(entry) || File.extname(entry).casecmp?('.zip')
      next if File.expand_path(entry) == junk

      FileUtils.cp_r(entry, File.join(tmpdir, entry))
    end
    pdf = "#{@bfilename}.pdf"
    built = File.join(@builder.junk_dir, pdf)
    FileUtils.cp(built, File.join(tmpdir, pdf)) if !File.file?(pdf) && File.file?(built)
  end

  # --------------------------------------------------------------- backup

  def backup_name
    base = "old_ver_#{Time.now.strftime('%y_%m_%d_%H_%M')}"
    name = "#{base}.zip"
    counter = 2
    while File.exist?(name)
      name = "#{base}_#{counter}.zip"
      counter += 1
    end
    name
  end

  def write_backup(plan)
    unless LaTeXUtils.command_available?('zip')
      warn Rainbow("[FAIL] 'zip' is not installed, so the originals cannot be saved; nothing was changed.").red.bright
      return nil
    end

    name = backup_name
    Dir.mktmpdir('leeni_indep_backup_') do |stage|
      fill_backup_stage(plan, stage)
      out, status = Open3.capture2e('zip', '-q', '-r', File.expand_path(name), '.', chdir: stage)
      return name if status.success?

      warn Rainbow("[FAIL] Could not write #{name}: #{out}; nothing was changed.").red.bright
      nil
    end
  end

  def fill_backup_stage(plan, stage)
    existing, created = plan.paths.partition { |rel| File.file?(rel) }
    existing.each { |rel| LaTeXPackagingShared.copy_preserving_path(rel, stage) }
    File.write(File.join(stage, NEW_FILES_LIST),
               "# Files added by leeni --make-indep; delete them to undo.\n#{created.map { |rel| "#{rel}\n" }.join}")
  end

  def report(plan, backup)
    plan.copies.each_key { |dest| puts " -- Copied #{dest}" }
    plan.edits.each_key { |rel| puts " -- Wrote #{rel}" }
    puts Rainbow("==> Originals of changed files saved in #{backup}").cyan
    puts Rainbow("==> #{@filename} now compiles with --no-env.").green.bright
  end

  # --dry-run: the sandbox check has run; show the changes, make none.
  def show_dry_run(plan)
    puts Rainbow('==> Dry run: the project was not changed. -I would make these changes:').cyan.bright
    plan.copies.each { |dest, src| puts " -- copy #{src} -> #{dest}" }
    plan.edits.each { |rel, content| show_edit(rel, content) }
    true
  end

  def show_edit(rel, content)
    unless File.file?(rel)
      count = content.lines.size
      puts " -- create #{rel} (#{count} #{count == 1 ? 'line' : 'lines'})"
      return
    end

    puts " -- edit #{rel}"
    Dir.mktmpdir('leeni_indep_diff_') do |dir|
      updated = File.join(dir, File.basename(rel))
      File.write(updated, content)
      diff, = Open3.capture2e('diff', '-u', '--label', "#{rel} (now)", '--label', "#{rel} (after -I)", rel, updated)
      puts diff.lines.map { |line| "      #{line}" }.join
    end
  rescue SystemCallError
    nil
  end
end
