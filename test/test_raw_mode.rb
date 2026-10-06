#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

load File.expand_path('../leeni', __dir__)

class TestRawMode < Minitest::Test
  def setup
    @bin_path = File.expand_path('../leeni', __dir__)
  end

  def test_help_includes_raw_flag
    stdout, status = Open3.capture2(@bin_path, '-h')
    assert status.success?, "Expected exit 0, got #{status.exitstatus}"
    assert_includes stdout, '-r, --raw'

    stdout_all, status_all = Open3.capture2(@bin_path, '--help-all')
    assert status_all.success?, "Expected exit 0, got #{status_all.exitstatus}"
    assert_includes stdout_all, '-r, --raw'
  end

  def test_clean_build_dumps_raw_compiler_output_short_flag
    Dir.mktmpdir('raw_clean_short') do |dir|
      tex = File.join(dir, 'clean.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Testing raw output short flag.
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '-r', 'clean.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output:\n#{out}"
      assert_match(/Transcript written on|Output written on/i, out, 'Expected raw TeX log output in stdout')
      assert_includes out, 'clean.pdf', 'Expected reference to clean.pdf in build output'
      assert File.exist?(File.join(dir, 'clean.pdf')), 'Expected clean.pdf to be generated'
    end
  end

  def test_clean_build_dumps_raw_compiler_output_long_flag
    Dir.mktmpdir('raw_clean_long') do |dir|
      tex = File.join(dir, 'clean.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Testing raw output long flag.
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--raw', 'clean.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output:\n#{out}"
      assert_match(/Transcript written on|Output written on/i, out, 'Expected raw TeX log output in stdout')
      assert_includes out, 'clean.pdf', 'Expected reference to clean.pdf in build output'
      assert File.exist?(File.join(dir, 'clean.pdf')), 'Expected clean.pdf to be generated'
    end
  end

  def test_error_build_dumps_raw_compiler_output_and_fails
    Dir.mktmpdir('raw_err') do |dir|
      tex = File.join(dir, 'bad.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\foobarunknowncommand
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--raw', 'bad.tex', chdir: dir)
      assert_equal 1, status.exitstatus, "Expected exit 1 on error. Output:\n#{out}"
      assert_includes out, 'Undefined control sequence.', 'Expected raw TeX error in output'
      assert_includes out, '\foobarunknowncommand', 'Expected faulty command in raw error output'
    end
  end

  def test_raw_mode_bypasses_cache
    Dir.mktmpdir('raw_cache') do |dir|
      tex = File.join(dir, 'cached.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Cached document.
        \\end{document}
      TEX

      # First build creates the PDF
      out1, status1 = Open3.capture2e(@bin_path, 'cached.tex', chdir: dir)
      assert_equal 0, status1.exitstatus, "Initial build failed: #{out1}"

      # Normal second build is up-to-date
      out2, status2 = Open3.capture2e(@bin_path, 'cached.tex', chdir: dir)
      assert_equal 0, status2.exitstatus
      assert_includes out2, 'up-to-date'

      # Second build with -r must re-run compiler and dump raw output
      out3, status3 = Open3.capture2e(@bin_path, '-r', 'cached.tex', chdir: dir)
      assert_equal 0, status3.exitstatus
      refute_includes out3, 'up-to-date', 'Expected -r to bypass up-to-date cache check'
      assert_match(/Transcript written on|Output written on/i, out3, 'Expected raw TeX output on -r build')
    end
  end
end
