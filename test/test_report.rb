#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'
require 'stringio'
require_relative 'leeni_test_support'

# `l --report` bundles diagnostics, build logs and environment into a zip under
# the cache; sources only with `full`; nothing is sent in -llm mode.
class TestReport < LeeniTestBase
  def with_project
    Dir.mktmpdir('leeni_report') do |dir|
      cache = File.join(dir, 'cache')
      project = File.join(dir, 'paper')
      FileUtils.mkdir_p([cache, project])
      saved = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = cache
      Dir.chdir(project) do
        File.write('main.tex', "\\documentclass{article}\n\\begin{document}\n\\input{body}\nSee \\ref{nowhere}.\n\\end{document}\n")
        File.write('body.tex', "Body text.\n")
        yield
      end
    ensure
      saved ? ENV['XDG_CACHE_HOME'] = saved : ENV.delete('XDG_CACHE_HOME')
    end
  end

  def zip_entries(zip)
    out, = Open3.capture2e('unzip', '-Z1', zip)
    out.lines.map(&:strip)
  end

  def run_report(level, extra = {})
    io = StringIO.new
    status = LeeniReport.run('main.tex', { report: level, engine: 'xelatex', compile: true, llm: true }.merge(extra), io: io)
    [status, io.string]
  end

  def test_basic_report_has_diagnostics_logs_and_manifest_but_no_sources
    with_project do
      status, out = run_report('basic')
      assert_equal 0, status
      zip = out[/leeni: note: report written: (\S+\.zip)/, 1]
      refute_nil zip, out
      assert File.file?(zip)
      assert_includes zip, File.join('leeni', 'reports')

      entries = zip_entries(zip)
      assert_includes entries, 'manifest.json'
      assert_includes entries, 'diagnostics.json'
      assert_includes entries, 'diagnostics.txt'
      assert(entries.any? { |e| e.start_with?('build/err_') }, "pass logs missing: #{entries}")
      assert(entries.any? { |e| e == 'build/main.log' }, "main.log missing: #{entries}")
      refute(entries.any? { |e| e.start_with?('sources/') }, 'basic report must not carry sources')

      Dir.mktmpdir do |x|
        Open3.capture2e('unzip', '-q', zip, '-d', x)
        manifest = JSON.parse(File.read(File.join(x, 'manifest.json')))
        assert_equal 'basic', manifest['level']
        assert_equal 'xelatex', manifest['engine']
        assert_equal Leeni::VERSION, manifest['leeni_version']
        diagnostics = JSON.parse(File.read(File.join(x, 'diagnostics.json')))
        assert(diagnostics['diagnostics'].any? { |d| d['message'].include?('nowhere') }, 'diagnostics.json lacks the undefined reference')
        assert_includes File.read(File.join(x, 'diagnostics.txt')), 'nowhere'
      end
    end
  end

  def test_full_report_adds_project_sources_from_the_recorder
    with_project do
      _status, out = run_report('full')
      zip = out[/report written: (\S+\.zip)/, 1]
      entries = zip_entries(zip)
      assert_includes entries, 'sources/main.tex'
      assert_includes entries, 'sources/body.tex'
    end
  end

  def test_json_mode_prints_the_bundle_path_and_unknown_level_is_rejected
    with_project do
      status, out = run_report('basic', compile: false, llm: false, json: true)
      assert_equal 0, status
      assert_equal 'basic', JSON.parse(out)['level']

      _, err = capture_io { assert_equal 2, LeeniReport.run('main.tex', { report: 'everything', compile: true }, io: StringIO.new) }
      assert_includes err, "takes 'basic' or 'full'"
    end
  end

  def test_a_document_after_report_is_a_target_not_a_level
    options = LatexCLI.build_default_options({}, 'l', [])
    argv = %w[--report main.tex]
    LatexCLI.build_option_parser(options).parse!(argv)
    LatexCLI.reclaim_report_target!(options, argv)
    assert_equal ['main.tex'], argv
    assert_equal 'basic', options[:report]

    options = LatexCLI.build_default_options({}, 'l', [])
    argv = %w[--report=full main.tex]
    LatexCLI.build_option_parser(options).parse!(argv)
    LatexCLI.reclaim_report_target!(options, argv)
    assert_equal ['main.tex'], argv
    assert_equal 'full', options[:report]
  end
end
