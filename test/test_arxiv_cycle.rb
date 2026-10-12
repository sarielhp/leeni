#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class TestArxivTestCycle < Minitest::Test
  RUNNER = File.expand_path('../tools/arxiv_test_cycle', __dir__)

  def script(root, name, body)
    path = File.join(root, name)
    File.write(path, "#!/usr/bin/env ruby\n#{body}\n")
    File.chmod(0o755, path)
    path
  end

  def run_cycle(root, downloader:, tester:)
    output = File.join(root, 'samples')
    Open3.capture2e('ruby', RUNNER, '--output', output, '--downloader', downloader, '--tester', tester)
  end

  def downloader_body
    <<~RUBY
      destination = File.join(ARGV.fetch(ARGV.index('--output') + 1), '2401.00001v1')
      Dir.mkdir(destination)
      File.write(File.join(destination, 'metadata.json'), '{}')
    RUBY
  end

  def tester_body(status)
    <<~RUBY
      sample = ARGV.fetch(0)
      File.write(File.join(sample, 'test-report.json'), #{JSON.generate({ 'status' => status, 'checks' => [{ 'name' => 'fresh_build', 'status' => status, 'detail' => 'compiler failed' }] }).dump})
      puts '#{status}: test-report.md'
      exit #{status == 'PASS' ? 0 : 1}
    RUBY
  end

  def test_pass_reports_no_bugs_and_uses_new_directory
    Dir.mktmpdir('arxiv-cycle-') do |root|
      downloader = script(root, 'downloader.rb', downloader_body)
      tester = script(root, 'tester.rb', tester_body('PASS'))
      output, status = run_cycle(root, downloader: downloader, tester: tester)
      assert status.success?, output
      assert_includes output, 'NO BUGS FOUND'
      assert_includes output, '2401.00001v1'
    end
  end

  def test_failed_test_reports_failed_checks_and_nonzero_status
    Dir.mktmpdir('arxiv-cycle-') do |root|
      downloader = script(root, 'downloader.rb', downloader_body)
      tester = script(root, 'tester.rb', tester_body('FAIL'))
      output, status = run_cycle(root, downloader: downloader, tester: tester)
      refute status.success?, output
      assert_includes output, 'POTENTIAL BUGS FOUND'
      assert_includes output, 'fresh_build: compiler failed'
    end
  end

  def test_successful_download_without_new_paper_is_an_error
    Dir.mktmpdir('arxiv-cycle-') do |root|
      downloader = script(root, 'downloader.rb', 'exit 0')
      tester = script(root, 'tester.rb', 'raise "tester should not run"')
      output, status = run_cycle(root, downloader: downloader, tester: tester)
      refute status.success?, output
      assert_includes output, 'did not create a new paper directory'
    end
  end
end
