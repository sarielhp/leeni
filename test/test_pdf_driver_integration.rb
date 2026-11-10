#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/leeni/build_workspace'

# Real xelatex runs of \includegraphics[page=3] on a one-page PDF. In a short
# document xdvipdfmx fails after XeTeX finished; in a long one XeTeX is still
# writing pages when the driver dies and is killed by SIGPIPE, which used to
# leave a cut-off .aux whose runaway arguments buried the real error.
class TestPdfDriverIntegration < Minitest::Test
  BIN = File.expand_path('../leeni', __dir__)
  HEAD = <<~'TEX'
    \documentclass{article}
    \usepackage{graphicx,hyperref}
    \begin{document}
    \tableofcontents
  TEX

  def setup
    @image, = Open3.capture2('kpsewhich', 'example-image.pdf')
    @image = @image.strip
    skip 'mwe example-image.pdf not installed' if @image.empty?
  end

  # The bad image follows `before` sections, so the .aux written up to it is
  # past XeTeX's first output buffer when the driver dies, as in the report.
  def with_paper(before, after)
    Dir.mktmpdir('leeni_driver') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'figs'))
      FileUtils.cp(@image, File.join(dir, 'figs', 'one_page.pdf'))
      File.write(File.join(dir, 'main.tex'), paper(before, after))
      yield dir
    end
  end

  def paper(before, after)
    @bad_line = HEAD.lines.size + before + 1
    "#{HEAD}#{sections(1..before)}\\includegraphics[page=3]{figs/one_page}\n" \
      "#{sections((before + 1)..(before + after))}\\end{document}\n"
  end

  def sections(range)
    range.map do |i|
      "\\section{Part #{i} $x^2$}\\label{s#{i}} See \\ref{s#{i - 1}}. #{'Lorem ipsum dolor sit amet. ' * 60}\n"
    end.join
  end

  def leeni(dir)
    out, status = Open3.capture2e(BIN, '-llm', 'main.tex', chdir: dir)
    refute status.success?, "the build must fail:\n#{out}"
    out
  end

  def assert_driver_error_only(out)
    assert_includes out, "main.tex:#{@bad_line}: error: PDF driver could not include page 3 of image " \
                         "'figs/one_page.pdf'"
    refute_match(/runaway argument|file ended while scanning|unclassified/i, out)
  end

  def test_short_document_reports_the_driver_error_at_its_line
    with_paper(1, 1) { |dir| assert_driver_error_only(leeni(dir)) }
  end

  def test_engine_killed_by_sigpipe_leaves_no_cut_off_aux_behind
    with_paper(300, 1500) do |dir|
      out = leeni(dir)
      assert_includes out, 'terminated by signal 13', 'the document is too short to outlive the driver'
      assert_driver_error_only(out)
      build_dir = Dir.chdir(dir) { LeeniBuildWorkspace.cache_dir('.') }
      refute File.exist?(File.join(build_dir, 'main.aux')), 'the cut-off .aux was kept'
      assert_driver_error_only(leeni(dir))
    end
  end

  # A cut-off .aux already in the cache (from a leeni without this fix, or a
  # crash) is a cache failure: cleaned and rebuilt, the real error reported.
  def test_cut_off_aux_from_an_earlier_run_is_recovered
    with_paper(1, 1) do |dir|
      leeni(dir)
      build_dir = Dir.chdir(dir) { LeeniBuildWorkspace.cache_dir('.') }
      File.write(File.join(build_dir, 'main.aux'), "\\relax\n\\newlabel{s1}{{1}{1}{Part 1}{section.")
      out = leeni(dir)
      assert_driver_error_only(out)
      assert_includes out, 'auxiliary file cut off by an earlier run'
    end
  end
end
