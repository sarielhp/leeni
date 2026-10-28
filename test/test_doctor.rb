#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'stringio'
require_relative 'leeni_test_support'

# `l --doctor` reports tools, cache and quarantined builds, shows one case,
# and clears the quarantine.
class TestDoctor < LeeniTestBase
  def with_cache
    Dir.mktmpdir('leeni_doctor') do |cache|
      saved = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = cache
      yield cache
    ensure
      saved ? ENV['XDG_CACHE_HOME'] = saved : ENV.delete('XDG_CACHE_HOME')
    end
  end

  def store_case(project)
    junk = File.join(project, 'junk')
    FileUtils.mkdir_p(junk)
    File.write(File.join(junk, 'chap.aux'), "\\newlabel{s}{{1}{1}\n")
    File.write(File.join(junk, 'err_xelatex_1'), "(./chap.aux\n! File ended while scanning use of \\@newl@bel.\n<inserted text>\nl.2 \n")
    File.write(File.join(project, 'main.tex'), "\\documentclass{article}\n")
    failure = LeeniQuarantine::CacheFailure.new('error inside generated file chap.aux', 'Runaway argument?', 'err_xelatex_1')
    LeeniQuarantine.store(project_dir: project, main_file: 'main.tex', junk_dir: junk, engine: 'xelatex',
                          failure: failure, sources: ['main.tex'])
  end

  def run_doctor(target, options = {})
    io = StringIO.new
    status = LeeniDoctor.run(target, { color: false }.merge(options), io: io)
    [status, io.string]
  end

  def test_overview_lists_tools_cache_and_quarantined_cases
    with_cache do |cache|
      project = File.join(cache, 'paper')
      case_dir = store_case(project)
      status, out = run_doctor(true)
      assert_equal 0, status
      assert_includes out, 'Engines:'
      assert_includes out, 'xelatex'
      assert_includes out, "Cache:    #{File.join(cache, 'leeni')}"
      assert_includes out, 'Quarantine: 1 case'
      assert_includes out, File.basename(case_dir)
      assert_includes out, 'trigger: error inside generated file chap.aux'

      status, json = run_doctor(true, json: true)
      assert_equal 0, status
      data = JSON.parse(json)
      assert_equal 1, data['quarantine'].size
      assert_equal File.expand_path(project), data['quarantine'].first['project']
      assert data['engines'].key?('xelatex')
    end
  end

  def test_empty_quarantine_is_a_single_line
    with_cache do
      _status, out = run_doctor(true)
      assert_includes out, 'Quarantine: no quarantined builds.'
    end
  end

  def test_show_one_case_prints_manifest_and_error_block
    with_cache do |cache|
      case_dir = store_case(File.join(cache, 'paper'))
      status, out = run_doctor(File.basename(case_dir))
      assert_equal 0, status
      assert_includes out, '"trigger": "error inside generated file chap.aux"'
      assert_includes out, "Case directory: #{case_dir}"
      assert_includes out, '! File ended while scanning use of \\@newl@bel.'
      assert_includes out, 'l.2'

      status, out = run_doctor('no-such-case')
      assert_equal 1, status
      assert_includes out, 'No quarantined build named no-such-case.'
    end
  end

  def test_clear_removes_every_case
    with_cache do |cache|
      store_case(File.join(cache, 'paper'))
      status, out = run_doctor('clear')
      assert_equal 0, status
      assert_includes out, 'Removed 1 quarantined build.'
      assert_empty LeeniQuarantine.cases
    end
  end
end
