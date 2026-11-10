#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'leeni_test_support'

# XeTeX pipes its pages to xdvipdfmx. When the driver dies (typically on
# \includegraphics[page=N] past the last page of a PDF) its message reaches the
# terminal only, and XeTeX is killed by SIGPIPE mid-document, leaving cut-off
# .aux and .out files whose runaway arguments then masked the real error.
class TestPdfDriverFailure < LeeniTestBase
  OPTIONS = {
    engine: 'xelatex', score: false, emacs: true, verbose: false, werror: false,
    suppress_whatevers: true, suppress_warnings: false, suppress_alerts: false,
    alert_overfull_pt: 24.0, whatever_overfull_pt: 2.5, explain: false, passes: 3,
    lock: false
  }.freeze

  SOURCE = <<~TEX
    \\documentclass{article}
    \\usepackage{graphicx}
    \\begin{document}
    \\includegraphics{figs/vis}
    % \\includegraphics[page=3]{figs/vis}
    \\includegraphics[page=3]{figs/vis}
    \\end{document}
  TEX

  IMAGE_LOG = <<~LOG
    [24]
    xdvipdfmx:fatal: Image inclusion failed for "./figs/vis.pdf" (page=3).

    No output PDF file written.
    BIB_ENTRY: aam-agprc-21
  LOG

  # The cut-off guarding.aux of the original report: TeX closes the file at
  # EOF and blames the line of \begin{document} in the main file.
  TRUNCATED_AUX_LOG = <<~LOG
    (/cache/paper-0123/paper.aux)
    Runaway argument?
    {{7.1}{17}{Higher dimensions}{equation.
    ./paper.tex:17: File ended while scanning use of \\@newl@bel.
    <inserted text>
                    \\par
    l.17 \\begin{document}

  LOG

  def with_project(log)
    Dir.mktmpdir('leeni_driver_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('paper.tex', SOURCE)
        File.write('junk/err_xelatex_1', log)
        builder = LatexBuilder.new('paper.tex', OPTIONS)
        builder.instance_variable_set(:@junk_dir, File.expand_path('junk'))
        yield builder, 'junk/err_xelatex_1'
      end
    end
  end

  def test_image_inclusion_failure_is_an_error_at_the_requesting_line
    with_project(IMAGE_LOG) do |builder, path|
      assert_equal 1, builder.send(:count_errors_in_log, 0, path)
      errors = builder.send(:extract_errors, File.read(path))
      assert_equal([:pdf_driver_image_failed], errors.map { |e| e[:catalog_id] })
      err = errors.first
      assert_equal 6, err[:line].to_i, 'the page=3 request, not the plain one or the commented-out one'
      assert_includes err[:text], "page 3 of image 'figs/vis.pdf'"
      assert_equal 'figs/vis.pdf', err[:catalog][:token]
      assert_includes err[:catalog][:hint], "'vis.pdf'"
    end
  end

  def test_other_driver_fatals_are_errors
    log = "xdvipdfmx:fatal: Cannot proceed without .vf or \"physical\" font for PDF output...\n"
    with_project(log) do |builder, path|
      errors = builder.send(:extract_errors, File.read(path))
      assert_equal([:pdf_driver_fatal], errors.map { |e| e[:catalog_id] })
      assert_includes errors.first[:text], 'PDF driver xdvipdfmx failed: Cannot proceed without .vf'
    end
  end

  def test_runaway_in_a_cut_off_aux_is_a_cache_failure
    with_project(TRUNCATED_AUX_LOG) do |builder, path|
      failure = builder.send(:cache_failure, path)
      assert_instance_of LeeniQuarantine::CacheFailure, failure
      assert_equal 'auxiliary file cut off by an earlier run', failure.trigger
      assert_includes failure.first_error, '\\@newl@bel'
    end
  end

  def test_runaway_in_the_source_is_not_a_cache_failure
    log = "Runaway argument?\n{bold text\n./paper.tex:5: File ended while scanning use of \\textbf.\nl.5\n"
    with_project(log) do |builder, path|
      assert_nil builder.send(:cache_failure, path)
    end
  end

  def test_killed_pass_discards_only_the_generated_files_it_wrote
    with_project('') do |builder, _path|
      File.write('junk/old.toc', 'kept')
      File.utime(Time.now - 60, Time.now - 60, 'junk/old.toc')
      since = Time.now - 1
      FileUtils.mkdir_p('junk/chapters')
      %w[paper.aux paper.out chapters/one.aux paper.log].each { |name| File.write("junk/#{name}", 'cut') }

      builder.send(:discard_truncated_outputs, since)
      assert_equal %w[old.toc paper.log], Dir.children('junk').reject { |n| File.directory?("junk/#{n}") || n.start_with?('err_') }.sort
      assert_empty Dir.children('junk/chapters')
    end
  end

  def test_killed_pass_detection
    signaled = Struct.new(:exitstatus, :signaled?).new(nil, true)
    timed_out = LatexBuilder::ProcessResultStatus.new(124, false, nil, false)
    failed = LatexBuilder::ProcessResultStatus.new(1, false, nil, false)
    builder = LatexBuilder.new('paper.tex', OPTIONS)
    assert builder.send(:killed_pass?, signaled)
    assert builder.send(:killed_pass?, timed_out)
    refute builder.send(:killed_pass?, failed)
  end
end
