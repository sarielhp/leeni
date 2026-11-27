#!/usr/bin/env ruby
# frozen_string_literal: true

# Expected diagnostics for the error corpus (docs/errors/<case>/expected.json)
# and for clean documents (test/corpus/clean/<case>/main.tex).
#
# Each error case pins the engine and lists, by hand-reviewed judgement, the
# diagnostics leeni should report: file, line, column (when known), tier and
# category. Message text is deliberately not compared. A case leeni does not
# yet get right carries a `known_issue` and the `current` output instead; the
# test then pins `current`, so any change shows up, and fails once the output
# matches `diagnostics` so the expectation is promoted rather than forgotten.
#
# The -llm run must name the same locations as --json: both formats are read
# by tools that jump to the line, so they may not disagree.
require_relative 'test_env'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'json'

class TestErrorCorpus < Minitest::Test
  # The tier runner already runs test files in parallel; a few threads here keep
  # the corpus from oversubscribing the machine and starving timing tests.
  Minitest.parallel_executor = Minitest::Parallel::Executor.new(4)
  parallelize_me!

  ROOT = File.expand_path('..', __dir__)
  BIN = File.join(ROOT, 'leeni')
  ERROR_CASES = Dir.glob(File.join(ROOT, 'docs', 'errors', '*', 'expected.json')).map { |p| File.dirname(p) }.sort.freeze
  FIXED_CASES = Dir.glob(File.join(ROOT, 'docs', 'errors', '*', 'fixed.tex')).map { |p| File.dirname(p) }.sort.freeze
  CLEAN_CASES = Dir.glob(File.join(ROOT, 'test', 'corpus', 'clean', '*', 'main.tex')).map { |p| File.dirname(p) }.sort.freeze
  ENGINE_FLAGS = { 'xelatex' => 'x', 'lualatex' => 'l', 'pdflatex' => 'p' }.freeze
  LLM_LOCATION = /\A(?<file>[^\s:]+):(?<line>\d+)(?::\d+)?: error: /

  def test_corpus_is_present
    assert_operator ERROR_CASES.size, :>=, 60, 'docs/errors cases without expected.json are not tested'
    missing = Dir.glob(File.join(ROOT, 'docs', 'errors', '*', 'example.tex')).map { |p| File.dirname(p) } - ERROR_CASES
    assert_empty missing.map { |dir| File.basename(dir) }, 'error cases without expected.json'
    refute_empty CLEAN_CASES
  end

  ERROR_CASES.each do |dir|
    define_method("test_error_#{File.basename(dir)}") { check_error_case(dir) }
  end

  FIXED_CASES.each do |dir|
    define_method("test_fixed_#{File.basename(dir)}") { check_fixed_case(dir) }
  end

  CLEAN_CASES.each do |dir|
    define_method("test_clean_#{File.basename(dir)}") { check_clean_case(dir) }
  end

  private

  def check_error_case(dir)
    spec = JSON.parse(File.read(File.join(dir, 'expected.json')))
    data, llm = in_copy(dir) { |work| [run_json(work, 'example.tex', spec['engine']), run_llm(work, 'example.tex', spec['engine'])] }
    actual = data.fetch('diagnostics').map { |d| comparable(d) }
    assert_equal_locations(data, llm)
    return assert_equal(spec['diagnostics'], actual, "#{File.basename(dir)}: diagnostics") unless spec['known_issue']

    check_known_issue(dir, spec, actual)
  end

  def check_known_issue(dir, spec, actual)
    name = File.basename(dir)
    refute_equal spec['diagnostics'], actual,
                 "#{name}: the known issue is fixed; make the output the expectation and drop known_issue/current"
    assert_equal spec['current'], actual, "#{name}: output changed under a known issue (#{spec['known_issue']})"
    skip "#{name}: known issue: #{spec['known_issue']}"
  end

  # A case with fixed.tex shows the repair, which must build clean.
  def check_fixed_case(dir)
    engine = JSON.parse(File.read(File.join(dir, 'expected.json')))['engine']
    data = in_copy(dir) { |work| run_json(work, 'fixed.tex', engine) }
    assert_clean(data, "#{File.basename(dir)}/fixed.tex")
  end

  def check_clean_case(dir)
    data = in_copy(dir) { |work| run_json(work, 'main.tex', 'xelatex') }
    assert_clean(data, File.basename(dir))
  end

  def assert_clean(data, name)
    reported = data.fetch('diagnostics').reject { |d| d['tier'] == 'whatevers' }
    assert data['success'], "#{name}: clean document failed to build"
    assert_empty reported.map { |d| "#{d['tier']} #{d['file']}:#{d['line']} #{d['category']}: #{d['message']}" },
                 "#{name}: clean document reported diagnostics"
  end

  def in_copy(dir)
    Dir.mktmpdir('corpus') do |tmp|
      work = File.join(tmp, File.basename(dir))
      FileUtils.cp_r(dir, work)
      yield work
    end
  end

  def run_json(work, main, engine)
    out, err, = Open3.capture3(BIN, '--no-lock', '--json', '-e', ENGINE_FLAGS.fetch(engine), main, chdir: work)
    JSON.parse(out)
  rescue JSON::ParserError
    flunk "#{work}: --json output is not JSON: #{out[0, 300]} #{err[0, 300]}"
  end

  def run_llm(work, main, engine)
    out, = Open3.capture2e(BIN, '--no-lock', '-llm', '-e', ENGINE_FLAGS.fetch(engine), main, chdir: work)
    out
  end

  # -llm prints the errors in the same order as --json, possibly truncated with a
  # note; a line-less diagnostic (line 0 in JSON) is printed at line 1 so
  # editors can open the file.
  def assert_equal_locations(data, llm)
    errors = data.fetch('diagnostics').select { |d| d['tier'] == 'errors' }
    json_locs = errors.map { |d| [File.basename(d['file'].to_s), [d['line'].to_i, 1].max] }
    llm_locs = llm.each_line.filter_map do |line|
      m = LLM_LOCATION.match(line)
      m && [File.basename(m[:file]), m[:line].to_i]
    end
    assert_match(/errors? in \S+ truncated/, llm, "-llm dropped errors without saying so:\n#{llm}") if llm_locs.size < json_locs.size
    assert_equal json_locs.first(llm_locs.size), llm_locs, "-llm and --json disagree on error locations:\n#{llm}"
  end

  def comparable(diag)
    file = diag['file'].to_s
    file = "<texmf>/#{File.basename(file)}" if file.start_with?('/')
    out = { 'file' => file, 'line' => diag['line'] }
    out['col'] = diag['col'] if diag['col']
    out.merge('tier' => diag['tier'], 'category' => diag['category'])
  end
end
