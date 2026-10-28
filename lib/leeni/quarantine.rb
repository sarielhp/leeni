# frozen_string_literal: true

# ==============================================================================
# lib/leeni/quarantine.rb
#
# A build that fails inside a generated file (.aux, .toc, .bbl, ...) is the
# cache's fault, not the source's. The evidence is stored as a case under
# $XDG_CACHE_HOME/leeni/quarantine/ before the build directory is wiped, so a
# failure that only `l -c -f` cured is still debuggable afterwards.
# ==============================================================================

require 'fileutils'
require 'json'
require 'time'
require_relative 'build_workspace'
require_relative 'version'

module LeeniQuarantine
  # Raised by the pass gate when the first error of a failed pass lies in a
  # generated file; the pipeline catches it, stores a case, cleans and retries.
  class CacheFailure < StandardError
    attr_reader :trigger, :first_error, :pass_log

    def initialize(trigger, first_error, pass_log)
      @trigger = trigger
      @first_error = first_error
      @pass_log = pass_log
      super(trigger)
    end
  end

  GENERATED_EXTENSIONS = %w[
    .aux .toc .lof .lot .loa .lol .out .nav .snm .vrb .bbl .bcf .blg .idx .ind .ilg .glo .gls .thm .run.xml .fls
  ].freeze
  SKIPPED_IN_CASE = %w[.pdf .synctex.gz .xdv .dvi].freeze
  MAX_FILE_BYTES = 10 * 1024 * 1024
  MAX_CASE_BYTES = 40 * 1024 * 1024
  MAX_CASES = 10
  REPEAT_WINDOW = 7 * 24 * 3600

  module_function

  def root
    File.join(LeeniBuildWorkspace.cache_home, 'leeni', 'quarantine')
  end

  def generated_file?(path)
    name = File.basename(path.to_s).downcase
    GENERATED_EXTENSIONS.any? { |ext| name.end_with?(ext) }
  end

  # Stores one case and returns its directory. `sources` are project-relative
  # paths; `junk_dir` is copied minus PDFs, within the size caps.
  def store(project_dir:, main_file:, junk_dir:, engine:, failure:, sources: [])
    project = File.expand_path(project_dir)
    case_dir = File.join(root, case_name(project))
    FileUtils.mkdir_p(case_dir)
    budget = { left: MAX_CASE_BYTES, skipped: [] }
    copy_tree(junk_dir, File.join(case_dir, 'build'), budget)
    copy_files(project, sources, File.join(case_dir, 'sources'), budget)
    File.write(File.join(case_dir, 'manifest.json'),
               JSON.pretty_generate(manifest(project, main_file, junk_dir, engine, failure, sources, budget)))
    prune!
    case_dir
  end

  def manifest(project, main_file, junk_dir, engine, failure, sources, budget)
    {
      leeni_version: Leeni::VERSION, created_at: Time.now.iso8601, project: project, main_file: main_file,
      engine: engine, build_dir: File.expand_path(junk_dir), trigger: failure.trigger,
      first_error: failure.first_error, pass_log: File.basename(failure.pass_log.to_s),
      sources: sources, skipped_files: budget[:skipped]
    }
  end

  def case_name(project)
    base = File.basename(project).gsub(/[^a-zA-Z0-9._-]/, '_')
    "#{base}-#{Time.now.strftime('%Y%m%d-%H%M%S')}"
  end

  def copy_tree(src_dir, dest_dir, budget)
    return unless File.directory?(src_dir)

    Dir.glob('**/*', base: src_dir).sort.each do |rel|
      src = File.join(src_dir, rel)
      next unless File.file?(src)
      next if SKIPPED_IN_CASE.any? { |ext| rel.end_with?(ext) }

      copy_within_budget(src, File.join(dest_dir, rel), budget)
    end
  end

  def copy_files(base_dir, rels, dest_dir, budget)
    rels.each do |rel|
      src = File.join(base_dir, rel)
      copy_within_budget(src, File.join(dest_dir, rel), budget) if File.file?(src)
    end
  end

  def copy_within_budget(src, dest, budget)
    size = File.size(src)
    if size > MAX_FILE_BYTES || size > budget[:left]
      budget[:skipped] << src
      return
    end

    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp(src, dest, preserve: true)
    budget[:left] -= size
  end

  # Newest first, as [dir, manifest] pairs; unreadable manifests are skipped.
  def cases
    return [] unless File.directory?(root)

    Dir.children(root).sort.reverse.filter_map do |name|
      dir = File.join(root, name)
      manifest = File.join(dir, 'manifest.json')
      next unless File.file?(manifest)

      [dir, JSON.parse(File.read(manifest))]
    rescue JSON::ParserError
      nil
    end
  end

  def recent_case_for?(project_dir, now = Time.now)
    project = File.expand_path(project_dir)
    cases.any? do |_, m|
      m['project'] == project && (now - Time.iso8601(m['created_at'].to_s)) < REPEAT_WINDOW
    rescue ArgumentError
      false
    end
  end

  def prune!
    dirs = Dir.children(root).sort.reverse.map { |n| File.join(root, n) }.select { |d| File.directory?(d) }
    dirs.drop(MAX_CASES).each { |d| FileUtils.rm_rf(d) }
  end

  def clear!
    FileUtils.rm_rf(root)
  end
end
