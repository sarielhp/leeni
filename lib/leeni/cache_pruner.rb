# frozen_string_literal: true

# ==============================================================================
# lib/leeni/cache_pruner.rb
#
# The build cache under $XDG_CACHE_HOME/leeni/projects/ grows by one directory
# per project ever built and nothing else ever removes one. The pruner deletes
# entries whose project directory no longer exists, and entries idle for more
# than `cache_days` days (default 10; 0 keeps idle projects forever). It runs
# synchronously once a day after a build, capped so a first run on an old
# cache stays short, and on demand with `l --doctor prune`. Entries touched
# within the last hour, or whose project holds the build lock, are left alone.
# ==============================================================================

require 'fileutils'
require 'tmpdir'
require_relative 'build_workspace'
require_relative 'project_record'

module LeeniCachePruner
  DEFAULT_DAYS = 10
  RECENT_WINDOW = 3600
  DAILY_INTERVAL = 24 * 3600
  AUTO_LIMIT = 200
  ENTRY_NAME = /\A.+-\h{16}\z/
  STAMP = '.last_prune'

  module_function

  def projects_dir
    File.join(LeeniBuildWorkspace.cache_home, 'leeni', 'projects')
  end

  def stamp_file
    File.join(LeeniBuildWorkspace.cache_home, 'leeni', STAMP)
  end

  def days_from(options)
    value = options[:cache_days]
    value.nil? ? DEFAULT_DAYS : [value.to_i, 0].max
  end

  def due?(now = Time.now)
    !File.file?(stamp_file) || now - File.mtime(stamp_file) >= DAILY_INTERVAL
  rescue SystemCallError
    true
  end

  def mark_run!(now = Time.now)
    FileUtils.mkdir_p(File.dirname(stamp_file))
    FileUtils.touch(stamp_file, mtime: now)
  end

  # The daily run after a build. Returns the summary, or nil when not due.
  # The stamp is written first, so a failing prune is not retried every build.
  def auto(options, now: Time.now)
    return nil unless due?(now)

    mark_run!(now)
    run(days: days_from(options), now: now, limit: AUTO_LIMIT)
  rescue StandardError
    nil
  end

  # Every cache entry with its status: :orphan (project directory gone),
  # :idle (no activity for more than `days` days), :busy (touched within the
  # last hour or locked) or :kept.
  def survey(days:, now: Time.now)
    return [] unless File.directory?(projects_dir)

    locked = held_locks
    Dir.children(projects_dir).sort.filter_map do |name|
      dir = File.join(projects_dir, name)
      next unless name.match?(ENTRY_NAME) && File.directory?(dir)

      classify(dir, days, now, locked)
    end
  end

  def classify(dir, days, now, locked = held_locks)
    record = LeeniProjectRecord.read(dir)
    project = record&.dig('project') || workspace_project(dir)
    last = last_activity(dir, record)
    busy = locked.include?(File.basename(dir)[-16..])
    { dir: dir, project: project, last_activity: last, status: status_for(project, last, days, now, busy) }
  end

  def status_for(project, last, days, now, locked)
    return :busy if locked || now - last < RECENT_WINDOW
    return :orphan if project && !File.directory?(project)
    return :idle if days.positive? && now - last > days * 86_400

    :kept
  end

  def workspace_project(dir)
    file = File.join(dir, '.leeni_workspace')
    File.file?(file) ? File.read(file).strip : nil
  rescue SystemCallError
    nil
  end

  # The record's newest stamp, or the newest build file; a build writes
  # .leeni_workspace at its start and .build_state.json at its end.
  def last_activity(dir, record)
    stamps = [record && LeeniProjectRecord.last_activity(record)]
    ['.leeni_workspace', '.build_state.json', '.'].each do |name|
      path = File.join(dir, name)
      stamps << File.mtime(path) if File.exist?(path)
    end
    stamps.compact.max
  end

  # Project hashes whose build lock is held right now. The lock lives in
  # Dir.tmpdir/leeni_<uid>/<hash>_<main>_build.lock, and <hash> is the suffix
  # of the cache entry's name.
  def held_locks
    Dir.glob(File.join(Dir.tmpdir, "leeni_#{Process.uid}", '*_build.lock'))
       .select { |f| lock_held?(f) }.to_set { |f| File.basename(f)[0, 16] }
  end

  def lock_held?(file)
    File.open(file, File::RDONLY) do |fh|
      return true unless fh.flock(File::LOCK_EX | File::LOCK_NB)

      fh.flock(File::LOCK_UN)
      false
    end
  rescue SystemCallError
    false
  end

  # Removes orphans first, then the longest-idle projects, at most `limit`.
  def run(days:, now: Time.now, limit: nil)
    entries = survey(days: days, now: now)
    doomed = entries.select { |e| e[:status] == :orphan } +
             entries.select { |e| e[:status] == :idle }.sort_by { |e| e[:last_activity] }
    chosen = limit ? doomed.first(limit) : doomed
    removed = chosen.select { |e| remove(e[:dir]) }
    counts = entries.group_by { |e| e[:status] }.transform_values(&:size)
    { days: days, removed: removed.map { |e| e[:dir] },
      removed_orphans: removed.count { |e| e[:status] == :orphan },
      removed_idle: removed.count { |e| e[:status] == :idle },
      remaining: doomed.size - removed.size, kept: counts.fetch(:kept, 0), busy: counts.fetch(:busy, 0) }
  end

  def remove(dir)
    return false unless File.expand_path(dir).start_with?("#{File.expand_path(projects_dir)}/")

    FileUtils.rm_rf(dir)
    !File.exist?(dir)
  end

  # One line for the terminal after a build or for --doctor prune.
  def describe(summary)
    n = summary[:removed].size
    return 'No stale build directories.' if n.zero?

    parts = []
    parts << "#{summary[:removed_orphans]} of deleted projects" if summary[:removed_orphans].positive?
    parts << "#{summary[:removed_idle]} idle for more than #{summary[:days]} days" if summary[:removed_idle].positive?
    text = "Removed #{n} stale build director#{n == 1 ? 'y' : 'ies'} (#{parts.join(', ')})."
    text += " #{summary[:remaining]} more remain for later runs." if summary[:remaining].positive?
    text
  end
end
