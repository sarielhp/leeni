#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require_relative 'leeni_test_support'

# A build that fails inside a generated file is the cache's fault. leeni keeps
# the evidence as a quarantine case, cleans, and rebuilds once, so the user
# never has to discover `l -c -f` by trial and error.
class TestCacheRecovery < LeeniTestBase
  def options(extra = {})
    { engine: 'xelatex', passes: 3, lock: false, bib: nil, force: true }.merge(extra)
  end

  # A project whose chapter is \include'd, so it owns a sub-.aux that can be
  # poisoned, built once in an isolated XDG cache.
  def with_built_project
    Dir.mktmpdir('leeni_recovery') do |dir|
      cache = File.join(dir, 'cache')
      project = File.join(dir, 'paper')
      FileUtils.mkdir_p([cache, project])
      saved = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = cache
      Dir.chdir(project) do
        File.write('main.tex', "\\documentclass{article}\n\\begin{document}\n\\include{chap}\n\\end{document}\n")
        File.write('chap.tex', "\\section{One}\\label{s}\nText.\n")
        capture_io { assert LatexBuilder.new('main.tex', options).run!, 'initial build failed' }
        yield LeeniBuildWorkspace.cache_dir('.')
      end
    ensure
      saved ? ENV['XDG_CACHE_HOME'] = saved : ENV.delete('XDG_CACHE_HOME')
    end
  end

  def poison(junk_dir)
    File.write(File.join(junk_dir, 'chap.aux'), "\\relax\n\\newlabel{s}{{1}{1}\n")
  end

  def test_poisoned_sub_aux_is_quarantined_cleaned_and_rebuilt
    with_built_project do |junk_dir|
      poison(junk_dir)
      out, err = capture_io { assert LatexBuilder.new('main.tex', options).run!, 'recovery build failed' }
      text = strip_ansi(out + err)
      assert_match(/error inside generated file (?:main|chap)\.aux/, text)
      assert_includes text, 'cleaned the build directory and rebuilt'
      refute_includes text, 'Second recovery'

      cases = LeeniQuarantine.cases
      assert_equal 1, cases.size
      case_dir, manifest = cases.first
      assert_equal File.expand_path('.'), manifest['project']
      assert_match(/(?:main|chap)\.aux/, manifest['trigger'])
      assert_match(/Runaway argument|File ended while scanning/, manifest['first_error'])
      assert_includes File.read(File.join(case_dir, 'build', 'chap.aux')), '\\newlabel{s}{{1}{1}'
      assert File.file?(File.join(case_dir, 'sources', 'chap.tex'))
      assert File.file?(File.join(case_dir, 'sources', 'main.tex'))
      refute File.exist?(File.join(case_dir, 'build', 'main.pdf')), 'PDFs are not part of a case'
      assert File.file?('main.pdf')
    end
  end

  def test_second_recovery_points_at_the_doctor_and_llm_mode_prints_a_note
    with_built_project do |junk_dir|
      poison(junk_dir)
      capture_io { LatexBuilder.new('main.tex', options).run! }
      poison(LeeniBuildWorkspace.cache_dir('.'))
      _out, err = capture_io { assert LatexBuilder.new('main.tex', options(compile: true, llm: true)).run! }
      assert_match(/leeni: note: Build failed with an error inside generated file (?:main|chap)\.aux/, err)
      assert_includes err, 'Second recovery for this project within a week; run l --doctor.'
      assert_equal 2, LeeniQuarantine.cases.size
    end
  end

  def test_a_real_source_error_is_not_mistaken_for_a_cache_failure
    with_built_project do |_junk_dir|
      File.write('chap.tex', "\\section{One}\\label{s}\n\\undefinedmacro\n")
      out, err = capture_io { assert_raises(SystemExit) { LatexBuilder.new('main.tex', options).run! } }
      text = strip_ansi(out + err)
      assert_includes text, 'Undefined control sequence'
      refute_includes text, 'cleaned the build directory'
      assert_empty LeeniQuarantine.cases
    end
  end

  def test_generated_file_detection_and_pruning
    assert LeeniQuarantine.generated_file?('/x/junk/chap.aux')
    assert LeeniQuarantine.generated_file?('main.run.xml')
    refute LeeniQuarantine.generated_file?('chap.tex')
    refute LeeniQuarantine.generated_file?('refs.bib')

    Dir.mktmpdir('leeni_prune') do |cache|
      saved = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = cache
      12.times { |i| FileUtils.mkdir_p(File.join(LeeniQuarantine.root, format('p-20260101-%06d', i))) }
      LeeniQuarantine.prune!
      assert_equal LeeniQuarantine::MAX_CASES, Dir.children(LeeniQuarantine.root).size
      assert Dir.exist?(File.join(LeeniQuarantine.root, 'p-20260101-000011')), 'newest case was pruned'
    ensure
      saved ? ENV['XDG_CACHE_HOME'] = saved : ENV.delete('XDG_CACHE_HOME')
    end
  end

  def test_project_record_follows_the_builds_and_counts_the_recovery
    with_built_project do |junk_dir|
      record = LeeniProjectRecord.read(junk_dir)
      assert_equal File.expand_path('.'), record['project']
      assert_equal 'ok', record['last_build']['result']
      assert_operator record['last_build']['passes'], :>=, 1
      assert_operator record['last_build']['duration_s'], :>, 0

      poison(junk_dir)
      capture_io { assert LatexBuilder.new('main.tex', options).run! }
      record = LeeniProjectRecord.read(junk_dir)
      assert_equal 1, record['recoveries']
      assert record['last_build']['recovered']

      capture_io { assert LatexBuilder.new('main.tex', options(force: false)).run! }
      record = LeeniProjectRecord.read(junk_dir)
      assert_equal 'up_to_date', record['last_build']['result']
      assert_equal 3, record['runs']
      assert_equal 2, record['builds']
    end
  end
end
