#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'stringio'
require_relative 'leeni_test_support'

# The cache pruner removes build directories of deleted projects and of
# projects idle for more than cache_days days, leaves fresh and locked
# entries alone, runs once a day after a build, and answers --doctor prune.
class TestCachePruner < LeeniTestBase
  NOW = Time.utc(2026, 10, 28, 12, 0, 0)
  DAY = 86_400

  def with_cache
    Dir.mktmpdir('leeni_prune') do |dir|
      saved = { 'XDG_CACHE_HOME' => ENV.fetch('XDG_CACHE_HOME', nil), 'TMPDIR' => ENV.fetch('TMPDIR', nil) }
      ENV['XDG_CACHE_HOME'] = File.join(dir, 'cache')
      ENV['TMPDIR'] = File.join(dir, 'tmp')
      FileUtils.mkdir_p([ENV.fetch('XDG_CACHE_HOME'), ENV.fetch('TMPDIR')], mode: 0o700)
      yield dir
    ensure
      saved.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
    end
  end

  # A cache entry whose newest activity lies `age_days` back. The project
  # directory exists unless `missing`.
  def entry(root, name, age_days:, missing: false, record: true)
    project = File.join(root, 'projects', name)
    FileUtils.mkdir_p(project) unless missing
    dir = File.join(LeeniCachePruner.projects_dir, "#{name}-#{format('%016x', name.sum * 7919)}")
    FileUtils.mkdir_p(dir)
    stamp = NOW - (age_days * DAY)
    File.write(File.join(dir, '.leeni_workspace'), project)
    File.write(File.join(dir, 'main.aux'), '\relax')
    if record
      LeeniProjectRecord.start!(dir, project: project, main_file: 'main.tex', engine: 'xelatex', now: stamp - 10)
      LeeniProjectRecord.finish!(dir, result: 'ok', now: stamp)
    end
    Dir.glob(File.join(dir, '{*,.*}')).select { |f| File.file?(f) }.each { |f| FileUtils.touch(f, mtime: stamp) }
    FileUtils.touch(dir, mtime: stamp)
    dir
  end

  def hold_lock(dir)
    lock_dir = File.join(Dir.tmpdir, "leeni_#{Process.uid}")
    FileUtils.mkdir_p(lock_dir, mode: 0o700)
    file = File.new(File.join(lock_dir, "#{File.basename(dir)[-16..]}_main_build.lock"), 'w')
    file.flock(File::LOCK_EX)
    file
  end

  def test_orphans_and_idle_entries_go_while_fresh_kept_and_locked_entries_stay
    with_cache do |root|
      orphan = entry(root, 'gone', age_days: 2, missing: true)
      idle = entry(root, 'old', age_days: 20)
      idle_no_record = entry(root, 'older', age_days: 40, record: false)
      kept = entry(root, 'recent', age_days: 3)
      fresh = entry(root, 'fresh', age_days: 0, missing: true)
      locked = entry(root, 'busy', age_days: 30)
      stray = File.join(LeeniCachePruner.projects_dir, 'stray')
      FileUtils.mkdir_p(stray)
      lock = hold_lock(locked)

      statuses = LeeniCachePruner.survey(days: 10, now: NOW).to_h { |e| [File.basename(e[:dir]).sub(/-\h{16}\z/, ''), e[:status]] }
      assert_equal({ 'gone' => :orphan, 'old' => :idle, 'older' => :idle, 'recent' => :kept, 'fresh' => :busy, 'busy' => :busy }, statuses)

      summary = LeeniCachePruner.run(days: 10, now: NOW)
      assert_equal [orphan, idle_no_record, idle].sort, summary[:removed].sort
      assert_equal 1, summary[:removed_orphans]
      assert_equal 2, summary[:removed_idle]
      assert_equal 0, summary[:remaining]
      [kept, fresh, locked, stray].each { |d| assert File.directory?(d), "#{d} should survive" }
      assert_match(/Removed 3 stale build directories \(1 of deleted projects, 2 idle for more than 10 days\)\./,
                   LeeniCachePruner.describe(summary))
    ensure
      lock&.close
    end
  end

  def test_zero_days_keeps_idle_projects_and_the_limit_takes_orphans_and_oldest_first
    with_cache do |root|
      orphan = entry(root, 'gone', age_days: 2, missing: true)
      entry(root, 'old', age_days: 20)
      oldest = entry(root, 'ancient', age_days: 90)

      summary = LeeniCachePruner.run(days: 0, now: NOW)
      assert_equal [orphan], summary[:removed]
      assert_equal 2, summary[:kept]

      summary = LeeniCachePruner.run(days: 10, now: NOW, limit: 1)
      assert_equal [oldest], summary[:removed]
      assert_equal 1, summary[:remaining]
      assert_includes LeeniCachePruner.describe(summary), '1 more remain'
      assert_equal 'No stale build directories.', LeeniCachePruner.describe(LeeniCachePruner.run(days: 0, now: NOW))
    end
  end

  def test_auto_runs_once_a_day_and_honours_cache_days
    with_cache do |root|
      entry(root, 'old', age_days: 20)
      assert LeeniCachePruner.due?(NOW)
      assert_nil LeeniCachePruner.auto({ cache_days: 0 }, now: NOW)[:removed].first
      refute LeeniCachePruner.due?(NOW + 3600)
      assert_nil LeeniCachePruner.auto({ cache_days: 10 }, now: NOW + 3600), 'a second run the same day must not prune'
      summary = LeeniCachePruner.auto({ cache_days: 10 }, now: NOW + DAY)
      assert_equal 1, summary[:removed].size
      assert_equal 10, LeeniCachePruner.days_from({})
      assert_equal 0, LeeniCachePruner.days_from({ cache_days: -3 })
    end
  end

  def test_doctor_reports_stale_entries_and_prunes_on_request
    with_cache do |root|
      entry(root, 'gone', age_days: 2, missing: true)
      entry(root, 'old', age_days: 20)
      entry(root, 'recent', age_days: 1)
      io = StringIO.new
      LeeniDoctor.run(true, { color: false, cache_days: 10 }, io: io)
      assert_includes io.string, 'stale: 1 of deleted projects, 1 idle for more than 10 days'

      io = StringIO.new
      assert_equal 0, LeeniDoctor.run('prune', { color: false, cache_days: 10, json: true }, io: io)
      assert_equal 2, JSON.parse(io.string)['removed'].size
      io = StringIO.new
      LeeniDoctor.run(true, { color: false, cache_days: 10 }, io: io)
      assert_includes io.string, 'no stale build directories'
      assert_includes io.string, '(1 projects,'
    end
  end
end
