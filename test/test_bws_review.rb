#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'

class TestBwsReview < Minitest::Test
  BIN = File.expand_path('../tools/bws_run', __dir__)

  def with_source
    Dir.mktmpdir('bws-review-') do |root|
      source = File.join(root, 'source')
      FileUtils.mkdir_p(source)
      File.write(File.join(source, 'paper.tex'), '\\documentclass{article}')
      yield root, source, File.join(root, 'output')
    end
  end

  def prepare(source, output)
    Open3.capture2e('ruby', BIN, source, '--output', output, '--prepare-only')
  end

  def test_copy_omits_git_worktrees_and_source_bws_settings
    with_source do |_root, source, output|
      %w[.git junk .bws nested].each { |name| FileUtils.mkdir_p(File.join(source, name)) }
      File.write(File.join(source, '.git/config'), 'private')
      File.write(File.join(source, 'nested/.git'), 'gitdir: /real/repository')
      File.write(File.join(source, 'junk/state'), 'stale')
      File.write(File.join(source, '.bws/config.jsonc'), '{"binds_rw":["/home"]}')
      File.write(File.join(source, '.bws.jsonc'), '{"binds_rw":["/"]}')
      text, status = prepare(source, output)
      assert status.success?, text
      assert_equal '\\documentclass{article}', File.read(File.join(output, 'paper.tex'))
      %w[.git nested/.git junk .bws.jsonc].each do |name|
        refute File.exist?(File.join(output, name)), name
      end
      config = JSON.parse(File.read(File.join(output, '.bws/config.jsonc')))
      refute_includes config.fetch('binds_rw', []), '/home'
      assert File.file?(File.join(source, '.git/config'))
    end
  end

  def test_prepare_stages_revtex4_compatibility_tree
    with_source do |_root, source, output|
      text, status = prepare(source, output)
      assert status.success?, text
      assert File.file?(File.join(output, '.leeni_bws_bin/vendor/revtex4/tex/latex/revtex4/revtex4.cls'))
    end
  end

  def test_existing_output_is_not_overwritten
    with_source do |_root, source, output|
      FileUtils.mkdir_p(output)
      File.write(File.join(output, 'marker'), 'keep')
      text, status = prepare(source, output)
      refute status.success?, text
      assert_equal ['marker'], Dir.children(output)
    end
  end

  def test_output_inside_source_is_rejected
    with_source do |_root, source, _output|
      text, status = prepare(source, File.join(source, 'recursive'))
      refute status.success?, text
      refute File.exist?(File.join(source, 'recursive'))
    end
  end

  def test_symlink_cannot_import_outside_source
    with_source do |root, source, output|
      secret = File.join(root, 'secret')
      File.write(secret, 'do not copy')
      File.symlink(secret, File.join(source, 'leak'))
      text, status = prepare(source, output)
      refute status.success?, text
      refute File.exist?(File.join(output, 'leak'))
      assert_equal 'do not copy', File.read(secret)
    end
  end

  def test_help_and_unknown_option_are_concise
    text, status = Open3.capture2e('ruby', BIN, '--help')
    assert status.success?, text
    assert_includes text, '--prepare-only'
    with_source do |_root, source, _output|
      text, status = Open3.capture2e('ruby', BIN, source, '--nonexistent')
      refute status.success?, text
      refute_includes text, "in `<main>'"
    end
  end

  def fake_bws(root)
    path = File.join(root, 'fake-bws')
    File.write(path, "#!/usr/bin/ruby\nexec(*ARGV.drop(ARGV.index('--') + 1))\n")
    File.chmod(0o755, path)
    path
  end

  def test_command_arguments_status_logging_and_environment
    with_source do |root, source, output|
      code = 'abort "leaked environment" if ENV.key?("BWS_TEST_SECRET"); puts ARGV.inspect; exit 7'
      text, status = Open3.capture2e({ 'BWS_TEST_SECRET' => 'must not pass' }, 'ruby', BIN,
                                     source, '--output', output, '--bws', fake_bws(root), '--',
                                     '/usr/bin/ruby', '-e', code, '--', '--timeout', 'argument with spaces')
      assert_equal 7, status.exitstatus, text
      assert_includes text, 'argument with spaces'
      assert_includes text, '--timeout'
      assert_includes File.read(File.join(output, 'bws-run.log')), 'argument with spaces'
      isolated_home = File.join(output, '.bws-home')
      assert_equal({}, JSON.parse(File.read(File.join(isolated_home, '.config/bws/config.jsonc'))))
      config = JSON.parse(File.read(File.join(output, '.bws/config.jsonc')))
      assert_equal File.join(output, '.sandbox-config'), config.dig('env', 'XDG_CONFIG_HOME')
    end
  end

  def test_timeout_kills_a_command_that_ignores_term
    with_source do |root, source, output|
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      code = 'trap("TERM") {}; File.write("child.pid", Process.pid.to_s); sleep 30'
      text, status = Open3.capture2e('ruby', BIN, source, '--output', output,
                                     '--bws', fake_bws(root), '--timeout', '0.3', '--', '/usr/bin/ruby', '-e', code)
      assert_equal 124, status.exitstatus, text
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, :<, 6
      pid = Integer(File.read(File.join(output, 'child.pid')))
      assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
      assert_includes File.read(File.join(output, 'bws-run.log')), 'timed out'
    end
  end

  def test_timeout_must_be_positive
    with_source do |_root, source, output|
      ['0', '-1'].each do |value|
        text, status = Open3.capture2e('ruby', BIN, source, '--output', output,
                                       '--prepare-only', '--timeout', value)
        refute status.success?, text
        assert_includes text, '--timeout must be'
        refute File.exist?(output)
      end
    end
  end

  def test_symlink_alias_cannot_put_output_inside_source
    with_source do |root, source, _output|
      alternate = File.join(root, 'alias')
      File.symlink(source, alternate)
      text, status = prepare(source, File.join(alternate, 'recursive'))
      refute status.success?, text
      refute File.exist?(File.join(source, 'recursive'))
    end
  end

  def test_default_temporary_output_cannot_recurse_into_source
    ['/', '/tmp'].each do |source|
      text, status = Open3.capture2e('ruby', BIN, source, '--prepare-only')
      refute status.success?, text
      assert_includes text, 'bws_run:'
    end
  end
end
