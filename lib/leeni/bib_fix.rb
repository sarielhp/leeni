# frozen_string_literal: true

# ==============================================================================
# lib/leeni/bib_fix.rb
#
# --bib-fix: builds the paper, then adds what its local .bib file lacks from
# the bibliography collection (bib_fix_sources, then BIBINPUTS): missing
# entries with their crossref/xdata parents, undefined @string macros and the
# @preamble blocks they need. Conflicting candidates are added as marked
# alternatives that every build reports until resolved. The .bib logic lives
# in Bibkit (docs/bibkit.md); this file is the build and CLI side.
# ==============================================================================

require 'fileutils'
require_relative 'bib_checks'

class LatexBibFix
  UNDEFINED_MACRO = [/Warning--string name "([^"]+)" is undefined/, /undefined macro "([^"]+)"/].freeze

  def self.validate_options!(options, prog_name)
    return unless options[:bib_fix]

    clashing = { zip: '--zip', arxiv: '--arxiv', bib_extract: '--bib-extract', bib_missing: '--bib-missing',
                 meta_only: '--meta', make_indep: '--make-indep', sandbox: '--sandbox', single_pass: '--single-pass' }
               .select { |key, _| options[key] }.values
    clashing << '--no-bib' if options[:bib] == false
    return if clashing.empty?

    warn "#{prog_name}: error: --bib-fix cannot be combined with #{clashing.join(', ')}"
    exit 2
  end

  def initialize(target, options)
    @target = target
    @options = options
  end

  # True when, after the fix, no cited key is missing.
  def run!
    builder = LatexBuilder.new(@target, @options)
    return false unless builder.run!

    plan_and_apply(builder) && rebuild_and_report
  end

  private

  def plan_and_apply(builder)
    Dir.chdir(File.expand_path(builder.bdir)) do
      @bfilename = builder.bfilename
      files = local_bibliography(builder)
      return false unless files

      @target_file = target_file(files)
      apply(plan_for(builder, files))
    end
  end

  # Every bibliography file must be a file of the project: --bib-fix edits it.
  def local_bibliography(builder)
    names = bibliography_sources(builder)
    return fail_with('The paper uses no bibliography file.') if names.empty?

    paths = names.map { |name| [name, resolve(name)] }
    outside = paths.reject { |_, path| path && inside_project?(path) }.map(&:first)
    return paths.map(&:last) if outside.empty?

    fail_with("Not a file of this project: #{outside.join(', ')}. " \
              'Run l -I to give the paper its own .bib file, then l --bib-fix.')
  end

  def bibliography_sources(builder) = LatexBibChecks.bibliography_sources(builder.junk_dir, @bfilename)
  def resolve(name) = LatexBibChecks.resolve(name, @options[:bib_dirs])
  def inside_project?(path) = LatexBibChecks.inside_project?(path)

  def target_file(files)
    files.find { |path| File.basename(path) == "#{@bfilename}.bib" } || files.first
  end

  def plan_for(builder, files)
    @local = files.map { |path| Bibkit::BibFile.load(path) }
    collection = Bibkit::Collection.build(preferred: Array(@options[:bib_fix_sources]),
                                          search_path: ENV.fetch('BIBINPUTS', nil), exclude: ['.'])
    @fixer = Bibkit::Fixer.new(@local, collection)
    @fixer.plan(missing_keys: builder.missing_bib_keys, undefined_macros: undefined_macros(builder))
  end

  def undefined_macros(builder)
    blg = LaTeXUtils.safe_read(File.join(builder.junk_dir, "#{@bfilename}.blg"))
    UNDEFINED_MACRO.flat_map { |re| blg.scan(re).flatten }.uniq
  end

  def apply(plan)
    report(plan)
    @unresolved = plan.not_found.any? || plan.case_hints.any?
    return true if plan.empty? || @options[:dry_run]

    text = File.binread(@target_file)
    FileUtils.cp(@target_file, "#{@target_file}.bak")
    tmp = "#{@target_file}.leeni-tmp"
    File.binwrite(tmp, @fixer.render(text, plan))
    File.rename(tmp, @target_file)
    puts Rainbow("==> Updated #{@target_file} (previous version: #{@target_file}.bak)").green.bright
    @changed = true
  end

  def report(plan)
    return puts(Rainbow('==> Nothing to fix: no cited key or @string macro is missing.').green) if nothing_missing?(plan)

    puts Rainbow("==> --bib-fix#{' (dry run)' if @options[:dry_run]}: #{@target_file}").cyan.bright
    added_lines(plan).each { |line| puts "    #{Rainbow('+').green} #{line}" }
    problem_lines(plan).each { |line| puts "    #{Rainbow('!').red} #{line}" }
  end

  def nothing_missing?(plan)
    plan.empty? && plan.not_found.empty? && plan.case_hints.empty? && plan.unknown_macros.empty?
  end

  def added_lines(plan)
    lines = []
    lines << "#{count(plan.entries.size, 'entry', 'entries')}: #{plan.entries.map(&:key).join(', ')}" if plan.entries.any?
    lines << "#{count(plan.strings.size, '@string')}: #{plan.strings.map(&:key).join(', ')}" if plan.strings.any?
    lines << count(plan.preambles.size, '@preamble') if plan.preambles.any?
    lines
  end

  def problem_lines(plan)
    lines = plan.conflicts.map do |a|
      "#{a.key}: #{count(a.alternatives.size, 'differing version')} added as #{a.key}#{Bibkit::ALT_TAG}N; keep one and delete the rest"
    end
    lines << "not found anywhere: #{plan.not_found.join(', ')}" if plan.not_found.any?
    plan.case_hints.each { |key, found| lines << "#{key}: not found; differs only in case from #{found.join(', ')}" }
    lines << "@string not found anywhere: #{plan.unknown_macros.join(', ')}" if plan.unknown_macros.any?
    lines
  end

  def count(number, singular, plural = "#{singular}s")
    "#{number} #{number == 1 ? singular : plural}"
  end

  def rebuild_and_report
    return !@unresolved unless @changed

    builder = LatexBuilder.new(@target, @options)
    return false unless builder.run!

    missing = Dir.chdir(File.expand_path(builder.bdir)) { builder.missing_bib_keys }
    return true if missing.empty?

    puts Rainbow("==> Still missing: #{missing.join(', ')}").yellow
    false
  end

  def fail_with(message)
    warn Rainbow("[FAIL] #{message}").red.bright
    nil
  end
end
