#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require_relative 'leeni_test_support'

# project.json in the build directory: written atomically at build start and
# end, bounded history, tolerant of damage, and kept across `l -c`.
class TestProjectRecord < LeeniTestBase
  def test_start_and_finish_accumulate_counts_and_bounded_history
    Dir.mktmpdir do |dir|
      t0 = Time.utc(2026, 10, 1, 12, 0, 0)
      7.times do |i|
        LeeniProjectRecord.start!(dir, project: '/p', main_file: 'main.tex', engine: 'xelatex', now: t0 + (i * 60))
        result = { 3 => 'failed', 5 => 'up_to_date' }.fetch(i, 'ok')
        LeeniProjectRecord.finish!(dir, result: result, passes: 2, duration: 1.234, recovered: i == 6, now: t0 + (i * 60) + 10)
      end
      r = JSON.parse(File.read(File.join(dir, 'project.json')))
      assert_equal '/p', r['project']
      assert_equal 'xelatex', r['engine']
      assert_equal t0.iso8601, r['created_at']
      assert_equal 7, r['runs']
      assert_equal 6, r['builds']
      assert_equal 1, r['failures']
      assert_equal 1, r['recoveries']
      assert_equal 5, r['history'].size
      assert_equal(%w[ok failed ok up_to_date ok], r['history'].map { |h| h['result'] })
      assert_equal 1.23, r['last_build']['duration_s']
      assert r['last_build']['recovered']
      assert_equal((t0 + 370).iso8601, r['last_success_at'])
      assert_equal t0 + 370, LeeniProjectRecord.last_activity(r)
      assert_empty Dir.glob(File.join(dir, '*.tmp')), 'temporary file left behind'
    end
  end

  def test_damaged_record_is_ignored_and_rewritten
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'project.json'), '{not json')
      assert_nil LeeniProjectRecord.read(dir)
      LeeniProjectRecord.start!(dir, project: '/p', main_file: 'a.tex', engine: 'lualatex')
      assert_equal 1, LeeniProjectRecord.read(dir)['runs']
      assert_nil LeeniProjectRecord.read(File.join(dir, 'missing'))
      assert_nil LeeniProjectRecord.last_activity({})
    end
  end

  def test_clean_directory_keeps_the_record_but_nothing_else
    Dir.mktmpdir do |dir|
      cache = File.join(dir, 'cache')
      project = File.join(dir, 'paper')
      FileUtils.mkdir_p([cache, project])
      saved = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = cache
      build_dir = LeeniBuildWorkspace.cache_dir(project)
      FileUtils.mkdir_p(build_dir)
      File.write(File.join(build_dir, 'main.aux'), '\relax')
      LeeniProjectRecord.start!(build_dir, project: project, main_file: 'main.tex', engine: 'xelatex')
      capture_io { LaTeXUtils.clean_directory(project, false) }
      assert_equal ['project.json'], Dir.children(build_dir)
      assert_equal project, LeeniProjectRecord.read(build_dir)['project']
    ensure
      saved ? ENV['XDG_CACHE_HOME'] = saved : ENV.delete('XDG_CACHE_HOME')
    end
  end
end
