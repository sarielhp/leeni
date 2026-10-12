#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'
require 'digest'
require 'rubygems/package'
require 'stringio'

class TestArxivRunnerReview < Minitest::Test
  RUNNER = File.expand_path('../tools/test_arxiv', __dir__)
  PAPER = "\\documentclass{article}\n\\title{Sample Paper}\n\\author{Example Author}\n" \
          "\\begin{document}\n\\maketitle\nHello.\n\\end{document}\n"

  def sample(bytes = PAPER, name = 'source.tex')
    Dir.mktmpdir('arxiv_runner_review_') do |root|
      dir = File.join(root, 'paper with spaces')
      Dir.mkdir(dir)
      File.binwrite(File.join(dir, name), bytes)
      metadata = { title: 'Sample Paper', authors: ['Example Author'], source_filename: name,
                   source_sha256: Digest::SHA256.hexdigest(bytes), id: '1510.00949v1' }
      File.write(File.join(dir, 'metadata.json'), JSON.generate(metadata))
      yield dir, root
    end
  end

  def run_tool(dir, *)
    Open3.capture2e('ruby', RUNNER, dir, *)
  end

  def failed_report(dir, output, status)
    refute status.success?, output
    assert File.file?(File.join(dir, 'FAIL')), output
    refute File.exist?(File.join(dir, 'PASS')), output
    assert File.file?(File.join(dir, 'test-report.md')), output
    JSON.parse(File.read(File.join(dir, 'test-report.json')))
  end

  def archive(entries)
    buffer = StringIO.new(''.b)
    Gem::Package::TarWriter.new(buffer) do |tar|
      entries.each { |name, data| tar.add_file_simple(name, 0o644, data.bytesize) { |f| f.write(data) } }
    end
    buffer.string
  end

  def test_checksum_failure_replaces_stale_pass_and_preserves_input
    sample do |dir, _root|
      File.write(File.join(dir, 'PASS'), 'old result')
      File.write(File.join(dir, 'source.tex'), PAPER + '% corruption')
      output, status = run_tool(dir)
      report = failed_report(dir, output, status)
      assert_match(/checksum/i, JSON.generate(report))
      assert_equal PAPER + '% corruption', File.read(File.join(dir, 'source.tex'))
    end
  end

  def test_archive_traversal_is_rejected_before_bws
    sample(archive([['../escaped.tex', PAPER]]), 'source.tar') do |dir, root|
      output, status = run_tool(dir, '--bws', File.join(root, 'missing-bws'))
      failed_report(dir, output, status)
      refute File.exist?(File.join(root, 'escaped.tex'))
      assert_match(/unsafe|traversal|member/i, File.read(File.join(dir, 'test-report.json')))
    end
  end

  def test_duplicate_normalized_archive_names_are_rejected
    sample(archive([['paper.tex', PAPER], ['./paper.tex', PAPER]]), 'source.tar') do |dir, root|
      output, status = run_tool(dir, '--bws', File.join(root, 'missing-bws'))
      report = failed_report(dir, output, status)
      assert_match(/duplicate/i, JSON.generate(report))
    end
  end

  def test_successful_launcher_without_worker_results_cannot_pass
    sample do |dir, root|
      fake = File.join(root, 'fake-bws')
      File.write(fake, "#!/usr/bin/env ruby\nexit 0\n")
      File.chmod(0o755, fake)
      source_before = Digest::SHA256.file(File.join(dir, 'source.tex')).hexdigest
      output, status = run_tool(dir, '--bws', fake)
      failed_report(dir, output, status)
      assert_equal source_before, Digest::SHA256.file(File.join(dir, 'source.tex')).hexdigest
    end
  end

  def test_report_symlink_does_not_overwrite_external_file
    sample do |dir, root|
      outside = File.join(root, 'keep-me')
      File.write(outside, 'unchanged')
      File.symlink(outside, File.join(dir, 'test-report.json'))
      File.write(File.join(dir, 'source.tex'), 'bad checksum')
      _output, status = run_tool(dir)
      refute status.success?
      assert_equal 'unchanged', File.read(outside)
    end
  end

  def test_timeout_is_reported_in_original_directory
    sample do |dir, root|
      fake = File.join(root, 'sleeping-bws')
      File.write(fake, "#!/usr/bin/env ruby\nsleep 20\n")
      File.chmod(0o755, fake)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      output, status = run_tool(dir, '--bws', fake, '--timeout', '0.2')
      report = failed_report(dir, output, status)
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 8
      assert_match(/timed out/i, JSON.generate(report))
    end
  end

  def test_plain_source_main_override_cannot_escape_staging
    sample do |dir, root|
      output, status = run_tool(dir, '--main', '../escaped.tex', '--bws', File.join(root, 'absent'))
      report = failed_report(dir, output, status)
      assert_match(/unsafe|main.*(?:invalid|member|exist)/i, JSON.generate(report))
    end
  end

  def test_normal_archive_directory_entries_are_accepted
    buffer = StringIO.new(''.b)
    Gem::Package::TarWriter.new(buffer) do |tar|
      tar.mkdir('submission', 0o755)
      tar.add_file_simple('submission/paper.tex', 0o644, PAPER.bytesize) { |f| f.write(PAPER) }
    end
    sample(buffer.string, 'source.tar') do |dir, root|
      fake = File.join(root, 'fake-bws')
      File.write(fake, "#!/usr/bin/env ruby\nputs 'REACHED_LAUNCHER'\nexit 17\n")
      File.chmod(0o755, fake)
      output, status = run_tool(dir, '--bws', fake)
      report = failed_report(dir, output, status)
      assert_includes JSON.generate(report), 'REACHED_LAUNCHER'
    end
  end

  def test_timeout_preserves_completed_check_results
    sample do |dir, root|
      fake = File.join(root, 'partial-bws')
      partial = { completed: false, status: 'RUNNING', running_check: 'fresh_build',
                  checks: [{ name: 'environment', status: 'PASS' }] }
      File.write(fake, "#!/usr/bin/env ruby\nFile.write('test-worker-report.json', #{JSON.generate(partial).dump})\nsleep 20\n")
      File.chmod(0o755, fake)
      output, status = run_tool(dir, '--bws', fake, '--timeout', '0.3')
      report = failed_report(dir, output, status)
      assert_equal 'PASS', report.fetch('checks').first.fetch('status')
      assert_match(/timed out/i, report.fetch('error'))
    end
  end
end
