# frozen_string_literal: true

# LeeniTmp (ProjectTmp from the standards template, project 'leeni'): every
# temporary file of leeni lives under <tmpdir>/<user>/leeni/, and entries older
# than 24 hours are swept when a temporary directory is made. That no other
# code creates temporary files is checked by the gate (tools/tooling.rb).

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/leeni/tmp_space'
require_relative '../lib/leeni/build_workspace'

class TestTmpSpace < Minitest::Test
  OLD = Time.now - (25 * 3600)

  # Runs the block with TMPDIR pointing at a fresh directory.
  def with_tmpdir
    Dir.mktmpdir('tmp_space_test') do |dir|
      original = ENV.fetch('TMPDIR', nil)
      ENV['TMPDIR'] = dir
      yield File.realpath(dir)
    ensure
      ENV['TMPDIR'] = original
    end
  end

  def test_directories_live_under_user_and_purpose
    with_tmpdir do |tmp|
      made = LeeniTmp.mktmpdir('zip-stage')
      assert_equal File.join(tmp, LeeniTmp.user_name, 'leeni', 'zip-stage'), File.dirname(made)
      assert_match(/\A\d{8}-\d{6}-/, File.basename(made))
      assert_equal 0o700, File.stat(File.dirname(made)).mode & 0o777

      kept = nil
      LeeniTmp.mktmpdir('report') { |d| kept = d }
      refute File.exist?(kept), 'the block form removes its directory'
    end
  end

  def test_sweep_removes_old_entries_and_keeps_fresh_and_locked_ones
    with_tmpdir do |tmp|
      old_dir = File.join(LeeniTmp.dir('zip-stage'), 'old')
      fresh_dir = File.join(LeeniTmp.dir('zip-stage'), 'fresh')
      FileUtils.mkdir_p([old_dir, fresh_dir])
      held = File.join(LeeniTmp.dir('locks'), 'held_build.lock')
      idle = File.join(LeeniTmp.dir('locks'), 'idle_build.lock')
      legacy = File.join(tmp, 'leeni_test_results_x')
      FileUtils.mkdir_p(legacy)
      [held, idle].each { |f| File.write(f, '') }
      [old_dir, held, idle, legacy].each { |p| File.utime(OLD, OLD, p) }

      File.open(held) do |lock|
        lock.flock(File::LOCK_EX)
        LeeniTmp.sweep!
      end
      refute File.exist?(old_dir)
      refute File.exist?(idle)
      refute File.exist?(legacy), 'old-style <tmpdir>/leeni_* entries are swept too'
      assert File.exist?(fresh_dir)
      assert File.exist?(held), 'a held lock is never removed'
    end
  end

  def test_user_directory_open_to_others_is_refused
    with_tmpdir do |tmp|
      hostile = File.join(tmp, LeeniTmp.user_name)
      Dir.mkdir(hostile)
      File.chmod(0o777, hostile)
      assert_raises(SystemExit) { capture_io { LeeniTmp.root } }
    end
  end

  # A project inside the temporary tree builds there too (and goes with the
  # sweep); any other project builds in $XDG_CACHE_HOME/leeni/projects/.
  def test_temporary_projects_build_in_the_temporary_tree
    with_tmpdir do |tmp|
      sandbox = LeeniTmp.mktmpdir('sandbox')
      assert_equal File.join(tmp, LeeniTmp.user_name, 'leeni', 'builds'), File.dirname(LeeniBuildWorkspace.cache_dir(sandbox))
      elsewhere = File.join(tmp, 'paper')
      Dir.mkdir(elsewhere)
      assert_equal File.join(LeeniBuildWorkspace.cache_home, 'leeni', 'projects'),
                   File.dirname(LeeniBuildWorkspace.cache_dir(elsewhere))
    end
  end

  # lib/leeni/tmp_space.rb is the standards template plus leeni's two lines;
  # tools/tmp_space.rb is the template itself. They must not drift apart.
  def test_library_copy_matches_the_tools_template
    root = File.expand_path('..', __dir__)
    library = File.read(File.join(root, 'lib', 'leeni', 'tmp_space.rb'))
    template = File.read(File.join(root, 'tools', 'tmp_space.rb'))
    assert_includes library, template.sub("# frozen_string_literal: true\n\n", '')
  end
end
