#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'json'

class TestJsonMode < Minitest::Test
  def setup
    @bin_path = File.expand_path('../leeni', __dir__)
  end

  def test_clean_build_in_json_mode
    Dir.mktmpdir('json_clean') do |dir|
      tex = File.join(dir, 'clean.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Clean JSON output test.
        \\end{document}
      TEX

      out, err, status = Open3.capture3(@bin_path, '--json', 'clean.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. stderr: #{err}, stdout: #{out}"
      assert_empty err.strip, "Expected empty stderr in --json mode, got: #{err}"

      data = JSON.parse(out.strip)
      assert_equal true, data['success']
      assert_equal 0, data['exit_code']
      assert_equal 'clean.pdf', data['pdf_path']
      assert File.exist?(File.join(dir, data['pdf_path'])), "PDF file #{data['pdf_path']} should exist"
      assert_equal 0, data['summary']['errors']
      assert_empty data['diagnostics']

      # Second run (cache up-to-date) must also produce valid JSON
      out2, err2, status2 = Open3.capture3(@bin_path, '--json', 'clean.tex', chdir: dir)
      assert_equal 0, status2.exitstatus, "Expected exit 0 on cached build. stderr: #{err2}, stdout: #{out2}"
      assert_empty err2.strip, "Expected empty stderr on cached build, got: #{err2}"

      data2 = JSON.parse(out2.strip)
      assert_equal true, data2['success']
      assert_equal 0, data2['exit_code']
      assert_equal 'clean.pdf', data2['pdf_path']
      assert_empty data2['diagnostics']
    end
  end

  def test_error_build_in_json_mode
    Dir.mktmpdir('json_err') do |dir|
      tex = File.join(dir, 'bad.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\undefinedcommandjson
        \\end{document}
      TEX

      out, err, status = Open3.capture3(@bin_path, '--json', 'bad.tex', chdir: dir)
      assert_equal 1, status.exitstatus, "Expected exit 1 on error. stderr: #{err}, stdout: #{out}"

      data = JSON.parse(out.strip)
      assert_equal false, data['success']
      assert_equal 1, data['exit_code']
      assert_nil data['pdf_path']
      assert_operator data['summary']['errors'], :>, 0
      refute_empty data['diagnostics']

      first_diag = data['diagnostics'].first
      assert_equal 'bad.tex', first_diag['file']
      assert_operator first_diag['line'], :>, 0
      assert_equal 'errors', first_diag['tier']
      assert_includes first_diag['message'].downcase, 'undefined control sequence'
    end
  end

  def test_warnings_in_json_mode
    Dir.mktmpdir('json_warn') do |dir|
      tex = File.join(dir, 'cites.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Missing citation \\cite{unknownKey}.
        \\end{document}
      TEX

      out, err, status = Open3.capture3(@bin_path, '--json', 'cites.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0 for warnings. stderr: #{err}, stdout: #{out}"

      data = JSON.parse(out.strip)
      assert_equal true, data['success']
      assert_equal 0, data['exit_code']
      total_warnings = data['summary']['warnings'] + data['summary']['alerts']
      assert_operator total_warnings, :>, 0
      refute_empty data['diagnostics']

      cite_diag = data['diagnostics'].find { |d| d['message'].include?('unknownKey') }
      refute_nil cite_diag, "Expected citation diagnostic in JSON payload: #{data['diagnostics']}"
      assert_equal 'cites.tex', cite_diag['file']
    end
  end

  def test_werror_in_json_mode
    Dir.mktmpdir('json_werror') do |dir|
      tex = File.join(dir, 'cites.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Missing citation \\cite{unknownKey}.
        \\end{document}
      TEX

      out, err, status = Open3.capture3(@bin_path, '--json', '--werror', 'cites.tex', chdir: dir)
      assert_equal 1, status.exitstatus, "Expected exit 1 with --werror. stderr: #{err}, stdout: #{out}"

      data = JSON.parse(out.strip)
      assert_equal false, data['success']
      assert_equal 1, data['exit_code']
    end
  end
end
