#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require 'json'
require 'fileutils'
require_relative '../tools/arxiv_test_worker'

class TestArxivWorker < Minitest::Test
  def worker
    old_lang = ENV['LANG']
    old_locale = ENV['LC_ALL']
    old_encoding = Encoding.default_external
    Dir.mktmpdir('arxiv_worker_review_') do |root|
      File.write(File.join(root, 'test-config.json'), JSON.generate(main: 'paper.tex', engine: 'xelatex'))
      File.write(File.join(root, 'leeni'), '# fixture executable')
      FileUtils.mkdir_p(File.join(root, 'paper'))
      File.write(File.join(root, 'paper/paper.tex'), "\\documentclass{article}\n\\begin{document}Test\\end{document}\n")
      yield ArxivTestWorker::Runner.new(root), root
    end
  ensure
    ENV['LANG'] = old_lang
    ENV['LC_ALL'] = old_locale
    Encoding.default_external = old_encoding unless Encoding.default_external == old_encoding
  end

  def test_successful_exit_is_insufficient_for_noop_build
    worker do |runner, _|
      runner.stub(:pdf_state, ['same', 'time']) do
        runner.stub(:compile, { exit_status: 0, passes: 1 }) do
          assert_raises(ArxivTestWorker::CheckError) { runner.unchanged }
        end
      end
    end
  end

  def test_diff_check_rejects_replaced_pdf_despite_success
    worker do |runner, _|
      states = [%w[old time], %w[new time]]
      runner.stub(:pdf_state, -> { states.shift }) do
        runner.stub(:compile, { exit_status: 0, passes: 1 }) do
          assert_raises(ArxivTestWorker::CheckError) { runner.diff }
        end
      end
    end
  end

  def test_failure_probe_restores_source_and_rejects_false_success
    worker do |runner, root|
      path = File.join(root, 'paper/paper.tex')
      original = File.binread(path)
      compiler = lambda do
        content = File.binread(path)
        assert content.start_with?('\\latexItDeliberatelyUndefinedProbe') || content == original
        { exit_status: 0, passes: 1 }
      end
      capture_io { runner.stub(:compile, compiler) { runner.failure_recovery } }
      assert_equal original, File.binread(path)
      report = JSON.parse(File.read(File.join(root, 'test-worker-report.json')))
      assert_equal %w[FAIL PASS], report.fetch('checks').map { |check| check.fetch('status') }
    end
  end

  def test_dependency_probe_keeps_mtime_and_restores_source
    worker do |runner, root|
      path = File.join(root, 'paper/paper.tex')
      original = File.binread(path)
      timestamp = File.mtime(path)
      call = 0
      compiler = lambda do
        call += 1
        if call == 2
          refute_equal original, File.binread(path)
          assert_equal timestamp, File.mtime(path)
        end
        { exit_status: 0, passes: call == 3 ? 0 : 1 }
      end
      runner.stub(:pdf_state, %w[hash time]) do
        capture_io { runner.stub(:compile, compiler) { runner.change_dependency } }
      end
      assert_equal original, File.binread(path)
      assert_equal timestamp, File.mtime(path)
    end
  end

  def test_command_uses_null_stdin_and_pgroup
    worker do |runner, _root|
      spawn_args = nil
      mock_spawn = lambda do |*_args, **kwargs|
        spawn_args = kwargs
        12_345
      end
      mock_wait = lambda do |_pid, _timeout, _log|
        status = Minitest::Mock.new
        status.expect(:exitstatus, 0)
        status.expect(:termsig, nil)
        status
      end

      Process.stub(:spawn, mock_spawn) do
        runner.stub(:wait_bounded, mock_wait) do
          runner.command(['echo', 'hello'])
        end
      end

      assert_equal File::NULL, spawn_args[:in]
      assert_equal true, spawn_args[:pgroup]
    end
  end

  def test_wait_bounded_times_out_and_reaps
    worker do |runner, _root|
      reaped_pid = nil
      runner.stub(:reap, ->(pid) { reaped_pid = pid }) do
        Process.stub(:waitpid2, [nil, nil]) do
          err = assert_raises(ArxivTestWorker::CheckError) do
            runner.wait_bounded(99_999, 0.001, 'dummy.log')
          end
          assert_includes err.message, 'timed out after 0.001s'
          assert_equal 99_999, reaped_pid
        end
      end
    end
  end

  def test_check_catches_script_error
    worker do |runner, _root|
      result = nil
      capture_io do
        result = runner.check('failing_script') do
          raise LoadError, 'cannot load such file -- non_existent'
        end
      end
      refute result
      last = runner.instance_variable_get(:@report)[:checks].last
      assert_equal 'FAIL', last[:status]
      assert_includes last[:detail], 'LoadError'
    end
  end

  def test_run_recovers_from_unhandled_exception
    worker do |runner, root|
      runner.stub(:check, ->(name) { name == 'fresh_build' || name == 'environment' }) do
        runner.stub(:exercise_build, -> { raise RuntimeError, 'crash in exercise_build' }) do
          exit_code = 0
          capture_io { exit_code = runner.run }
          assert_equal 2, exit_code
          report = JSON.parse(File.read(File.join(root, 'test-worker-report.json')))
          assert_equal 'ERROR', report['status']
          assert_equal true, report['completed']
          assert_includes report['error'], 'crash in exercise_build'
        end
      end
    end
  end

  def test_read_text_scrubs_invalid_utf8
    worker do |runner, root|
      bad_path = File.join(root, 'bad_utf8.txt')
      File.binwrite(bad_path, "Hello \xFF\xFE World\n".b)
      cleaned = runner.read_text(bad_path)
      assert_equal "Hello ?? World\n", cleaned
      assert_equal Encoding::UTF_8, cleaned.encoding
    end
  end

  def test_with_original_restores_file_on_exception
    worker do |runner, root|
      path = File.join(root, 'paper/paper.tex')
      original = File.binread(path)
      assert_raises(RuntimeError) do
        runner.with_original(path) do
          File.binwrite(path, 'corrupted')
          raise RuntimeError, 'boom'
        end
      end
      assert_equal original, File.binread(path)
    end
  end

  def test_restore_all_restores_multiple_tracked_files
    worker do |runner, root|
      p1 = File.join(root, 'paper/paper.tex')
      p2 = File.join(root, 'paper/other.tex')
      File.binwrite(p2, 'original other')
      c1 = File.binread(p1)
      c2 = File.binread(p2)

      runner.instance_variable_get(:@restores)[p1] = [c1, File.stat(p1)]
      runner.instance_variable_get(:@restores)[p2] = [c2, File.stat(p2)]

      File.binwrite(p1, 'tampered 1')
      File.binwrite(p2, 'tampered 2')

      runner.restore_all
      assert_equal c1, File.binread(p1)
      assert_equal c2, File.binread(p2)
    end
  end

  def test_prepare_raises_actionable_error_when_no_latex_engine_found
    Dir.mktmpdir('arxiv_worker_no_engine_') do |root|
      File.write(File.join(root, 'test-config.json'), JSON.generate(main: 'paper.tex'))
      File.write(File.join(root, 'leeni'), '# fixture executable')
      FileUtils.mkdir_p(File.join(root, 'paper'))
      File.write(File.join(root, 'paper/paper.tex'), "\\documentclass{article}\n")
      runner = ArxivTestWorker::Runner.new(root)
      runner.stub(:executable, ->(name) { %w[pdftotext pdftoppm zip unzip].include?(name) ? '/usr/bin/' + name : nil }) do
        err = assert_raises(ArxivTestWorker::CheckError) { runner.prepare }
        assert_includes err.message, 'No LaTeX engine found on PATH'
        assert_includes err.message, 'xelatex, lualatex, pdflatex'
      end
    end
  end

  def test_prepare_fails_when_engine_or_leeni_version_probe_fails
    worker do |runner, _root|
      def runner.executable(_name); '/usr/bin/xelatex'; end
      def runner.install_engine_wrappers(_candidates); nil; end
      mock_fail = Minitest::Mock.new
      mock_fail.expect(:success?, false)
      mock_fail.expect(:exitstatus, 1)
      Open3.stub(:capture2e, ['LaTeX error', mock_fail]) do
        err = assert_raises(ArxivTestWorker::CheckError) { runner.prepare }
        assert_includes err.message, '--version failed (exit 1)'
      end
    end
  end

  def test_invalid_tex_rejects_signal_death
    worker do |runner, root|
      runner.stub(:compile, { exit_status: 137, passes: 1, log: nil }) do
        capture_io { runner.failure_recovery }
      end
      report = JSON.parse(File.read(File.join(root, 'test-worker-report.json')))
      invalid_check = report['checks'].find { |c| c['name'] == 'invalid_tex' }
      assert_equal 'FAIL', invalid_check['status']
      assert_includes invalid_check['detail'], 'Expected a clean nonzero exit; got 137'
    end
  end

  def test_invalid_tex_verifies_probe_in_log
    worker do |runner, root|
      log_path = File.join(root, 'test-logs/probe.log')
      FileUtils.mkdir_p(File.dirname(log_path))
      File.write(log_path, 'Unrelated disk failure')
      runner.stub(:compile, { exit_status: 1, passes: 1, log: log_path }) do
        capture_io { runner.failure_recovery }
      end
      report = JSON.parse(File.read(File.join(root, 'test-worker-report.json')))
      invalid_check = report['checks'].find { |c| c['name'] == 'invalid_tex' }
      assert_equal 'FAIL', invalid_check['status']
      assert_includes invalid_check['detail'], 'unrelated to the probe'
    end
  end

  def test_initialize_validates_config_and_staged_leeni
    Dir.mktmpdir('arxiv_worker_init_') do |root|
      err = assert_raises(ArxivTestWorker::CheckError) { ArxivTestWorker::Runner.new(root) }
      assert_includes err.message, 'config file not found'

      File.write(File.join(root, 'test-config.json'), JSON.generate({}))
      err = assert_raises(ArxivTestWorker::CheckError) { ArxivTestWorker::Runner.new(root) }
      assert_includes err.message, 'missing required key "main"'

      File.write(File.join(root, 'test-config.json'), JSON.generate(main: 'paper.tex'))
      err = assert_raises(ArxivTestWorker::CheckError) { ArxivTestWorker::Runner.new(root) }
      assert_includes err.message, 'leeni was not staged'
    end
  end

  def test_all_checks_recorded_as_skip_when_environment_fails
    worker do |runner, root|
      runner.stub(:prepare, -> { runner.assert(false, 'Missing pdftoppm') }) do
        exit_code = 1
        capture_io { exit_code = runner.run }
        assert_equal 1, exit_code
        report = JSON.parse(File.read(File.join(root, 'test-worker-report.json')))
        assert_equal 'FAIL', report['status']
        assert_equal true, report['completed']
        check_names = report['checks'].map { |c| c['name'] }
        assert_equal ArxivTestWorker::ALL_CHECKS, check_names
        env_check = report['checks'].find { |c| c['name'] == 'environment' }
        assert_equal 'FAIL', env_check['status']
        skips = report['checks'].reject { |c| c['name'] == 'environment' }
        assert skips.all? { |c| c['status'] == 'SKIP' }
      end
    end
  end

  def test_save_handles_system_call_error_gracefully
    worker do |runner, _root|
      File.stub(:write, ->(*_args) { raise Errno::ENOSPC, 'No space left on device' }) do
        _, err = capture_io { runner.save }
        assert_includes err, 'could not persist report: No space left on device'
      end
    end
  end
end
