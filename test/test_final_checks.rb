#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'leeni_test_support'

# The --final profile: drafting aids left in the source are alerts, the
# everyday reference warnings become errors, and the packaging paths switch
# the profile on by themselves.
class TestFinalChecks < LeeniTestBase
  DRAFTY = <<~TEX
    \\documentclass[11pt,draft]{article}
    \\usepackage[disable]{todonotes}
    \\usepackage{showkeys,amsmath}
    \\usepackage[draft]{graphicx}
    % \\includeonly{chap1}  commented out, must not count
    \\includeonly{chap1,chap2}
    \\usepackage{lineno}
    \\begin{document}
    \\linenumbers
    Text.
    \\end{document}
  TEX

  def test_scan_reports_each_draft_leftover_once_with_its_line
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'main.tex')
      File.write(path, DRAFTY)
      alerts = LaTeXFinalChecks.scan(path)
      by_line = alerts.to_h { |a| [a[:line], a[:text]] }

      assert_equal [1, 3, 4, 6, 9], by_line.keys.sort, "unexpected alert lines: #{by_line.inspect}"
      assert_includes by_line[1], 'documentclass option draft'
      assert_includes by_line[3], 'package showkeys'
      assert_includes by_line[4], 'graphicx option draft'
      assert_includes by_line[6], '\\includeonly'
      assert_includes by_line[9], '\\linenumbers'
      assert(alerts.all? { |a| a[:alert_type] == :draft_leftover })
    end
  end

  def test_todonotes_with_disable_and_plain_lineno_load_are_not_leftovers
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'main.tex')
      File.write(path,
                 "\\documentclass{article}\n\\usepackage[disable]{todonotes}\n\\usepackage{lineno}\n\\begin{document}x\\end{document}\n")
      assert_empty LaTeXFinalChecks.scan(path)
      File.write(path, "\\documentclass{article}\n\\usepackage{todonotes}\n\\begin{document}x\\end{document}\n")
      assert_equal 1, LaTeXFinalChecks.scan(path).size
    end
  end

  def test_final_profile_turns_reference_warnings_into_errors_and_draft_leftovers_into_alerts
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('main.tex', "\\documentclass[draft]{article}\n\\begin{document}\nSee \\ref{x}.\n\\end{document}\n")
        log = <<~LOG
          (./main.tex
          LaTeX Warning: Reference `x' on page 1 undefined on input line 3.
          LaTeX Warning: Citation `k' on page 1 undefined on input line 3.
          Overfull \\hbox (3.0pt too wide) in paragraph at lines 3--3
          )
        LOG
        File.write('junk/err_xelatex', log)

        relaxed = legacy_builder('main.tex', {})
        out, = capture_io { relaxed.send(:analyze_output) }
        plain = strip_ansi(out)
        assert_includes plain, 'Errors: 0'
        refute_includes plain, 'Draft leftover'

        final = legacy_builder('main.tex', final: true)
        out, = capture_io { assert_raises(SystemExit) { final.send(:analyze_output) } }
        plain = strip_ansi(out)
        assert_includes plain, "undefined reference 'x'"
        assert_includes plain, "undefined citation 'k'"
        assert_includes plain, 'Errors: 2'
        assert_includes plain, 'Alerts: 1'
        assert_includes plain, 'Warnings: 1'
      end
    end
  end

  def test_final_profile_shows_draft_leftovers_as_alerts
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('main.tex', "\\documentclass[draft]{article}\n\\includeonly{a}\n\\begin{document}\nx\n\\end{document}\n")
        File.write('junk/err_xelatex', "(./main.tex\n)\n")

        final = legacy_builder('main.tex', final: true)
        out, = capture_io { final.send(:analyze_output) }
        plain = strip_ansi(out)
        assert_includes plain, '(2 alerts)'
        assert_includes plain, 'main.tex:1:'
        assert_includes plain, 'documentclass option draft'
        assert_includes plain, '\\includeonly restricts the build'
      end
    end
  end

  def test_packaging_paths_imply_the_final_profile
    assert LatexCLI.arxiv_build_options(engine: 'xelatex')[:final]
    assert_equal true, LatexCLI.arxiv_build_options(final: false)[:final]
  end
end
