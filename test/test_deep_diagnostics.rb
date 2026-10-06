#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require 'open3'
require 'stringio'

load File.expand_path('../leeni', __dir__)

class TestDeepDiagnostics < Minitest::Test
  def test_inverted_label_detected_when_before_caption
    Dir.mktmpdir('leeni_test_label_') do |dir|
      path = File.join(dir, 'test.tex')
      File.write(path, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\begin{figure}
          \\includegraphics{cat.png}
          \\label{fig:cat}
          \\caption{A cat}
        \\end{figure}
        \\end{document}
      TEX

      alerts = LaTeXBraceChecker.check_inverted_labels(path)
      assert_equal 1, alerts.size
      assert_equal :inverted_label, alerts.first[:alert_type]
      assert_equal 5, alerts.first[:line]
      assert_includes alerts.first[:text], 'fig:cat'
    end
  end

  def test_inverted_label_not_flagged_when_after_or_inside_caption
    Dir.mktmpdir('leeni_test_label_') do |dir|
      path = File.join(dir, 'test.tex')
      File.write(path, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\begin{figure}
          \\includegraphics{cat.png}
          \\caption{A cat}
          \\label{fig:cat}
        \\end{figure}
        \\begin{table}
          \\caption{A table\\label{tab:inside}}
          \\begin{tabular}{c} 1 \\end{tabular}
        \\end{table}
        \\end{document}
      TEX

      alerts = LaTeXBraceChecker.check_inverted_labels(path)
      assert_empty alerts
    end
  end

  def test_label_in_unnumbered_math_detected
    Dir.mktmpdir('leeni_test_label_') do |dir|
      path = File.join(dir, 'test.tex')
      File.write(path, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\begin{equation*}
          x = y + 1
          \\label{eq:unnumbered}
        \\end{equation*}
        \\end{document}
      TEX

      alerts = LaTeXBraceChecker.check_inverted_labels(path)
      assert_equal 1, alerts.size
      assert_equal :unnumbered_label, alerts.first[:alert_type]
      assert_includes alerts.first[:text], 'eq:unnumbered'
    end
  end

  def test_inverted_label_ignored_inside_verbatim_or_lstlisting
    Dir.mktmpdir('leeni_test_verbatim_label_') do |dir|
      path = File.join(dir, 'test.tex')
      File.write(path, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\begin{lstlisting}
        \\begin{figure}[h]
          \\label{fig:example}
          \\caption{An example figure.}
        \\end{figure}
        \\end{lstlisting}
        \\begin{verbatim}
        \\begin{figure}[h]
          \\label{fig:example_verb}
          \\caption{Another example.}
        \\end{figure}
        \\end{verbatim}
        \\begin{figure}[h]
          \\label{fig:real_inverted}
          \\caption{A real figure}
        \\end{figure}
        \\end{document}
      TEX

      alerts = LaTeXBraceChecker.check_inverted_labels(path)
      assert_equal 1, alerts.size
      assert_equal :inverted_label, alerts.first[:alert_type]
      assert_includes alerts.first[:text], 'fig:real_inverted'
      refute_includes alerts.first[:text], 'fig:example'
    end
  end

  def test_type3_font_detection_from_pdffonts_output
    pdffonts_clean = <<~OUT
      name                                 type              encoding         emb sub uni object ID
      ------------------------------------ ----------------- ---------------- --- --- --- ---------
      LNCPKM+LMRoman10-Regular             CID Type 0C       Identity-H       yes yes yes      4  0
    OUT

    pdffonts_with_type3 = <<~OUT
      name                                 type              encoding         emb sub uni object ID
      ------------------------------------ ----------------- ---------------- --- --- --- ---------
      LNCPKM+LMRoman10-Regular             CID Type 0C       Identity-H       yes yes yes      4  0
      [none]                               Type 3            Custom           yes no  no      12  0
    OUT

    fake_stat = Struct.new(:success?).new(true)

    Dir.mktmpdir('leeni_test_font_') do |dir|
      pdf_path = File.join(dir, 'paper.pdf')
      File.write(pdf_path, '%PDF-1.4 dummy')

      LaTeXUtils.stub(:command_available?, true) do
        Open3.stub(:capture2e, [pdffonts_clean, fake_stat]) do
          assert_nil LaTeXUtils.check_type3_fonts(pdf_path)
        end

        Open3.stub(:capture2e, [pdffonts_with_type3, fake_stat]) do
          LaTeXUtils.stub(:find_type3_font_pages, [1]) do
            res = LaTeXUtils.check_type3_fonts(pdf_path)
            refute_nil res
            assert_includes res[:fonts], '[none]'
            assert_equal [1], res[:pages]
          end
        end
      end
    end
  end

  def test_explanations_exist_for_new_alert_categories
    assert LaTeXDiagnostics::DIAGNOSTIC_EXPLANATIONS.key?(:inverted_label)
    assert LaTeXDiagnostics::DIAGNOSTIC_EXPLANATIONS.key?(:unnumbered_label)
    assert LaTeXDiagnostics::DIAGNOSTIC_EXPLANATIONS.key?(:type3_font)

    expl = LaTeXDiagnostics::DIAGNOSTIC_EXPLANATIONS[:inverted_label]
    assert_includes expl[:title], 'Inverted'
    assert_includes expl[:why], 'Section number'

    expl_font = LaTeXDiagnostics::DIAGNOSTIC_EXPLANATIONS[:type3_font]
    assert_includes expl_font[:title], 'Type 3'
    assert_includes expl_font[:fix], 'scalable'
  end

  def test_report_errors_routes_to_stderr_stream
    Dir.mktmpdir('leeni_test_stderr_') do |dir|
      log_file = File.join(dir, 'err_xelatex_1')
      File.write(log_file, <<~LOG)
        This is XeTeX, Version 3.141592653
        (./main.tex
        ! LaTeX Error: File `missing.sty` not found.
        )
      LOG

      builder = LatexBuilder.new('main.tex', {})
      out, err = capture_io do
        assert_raises(SystemExit) do
          builder.report_errors(log_file)
        end
      end

      assert_empty out
      assert_includes err, 'LaTeX Error: File `missing.sty` not found.'
      assert_includes err, 'Errors: 1'
    end
  end

  def test_report_errors_accepts_custom_io
    Dir.mktmpdir('leeni_test_custom_io_') do |dir|
      log_file = File.join(dir, 'err_xelatex_1')
      File.write(log_file, <<~LOG)
        This is XeTeX, Version 3.141592653
        (./main.tex
        ! LaTeX Error: File `missing.sty` not found.
        )
      LOG

      custom_io = StringIO.new
      builder = LatexBuilder.new('main.tex', verbose: true)
      assert_raises(SystemExit) do
        builder.report_errors(log_file, io: custom_io)
      end

      content = custom_io.string
      assert_includes content, 'LaTeX Error: File `missing.sty` not found.'
      assert_includes content, "See #{log_file} for full error details."
      assert_includes content, 'Errors: 1'
    end
  end

  def test_condense_biblatex_missing_entry_warning
    builder = LatexBuilder.new('main.tex', {})
    raw_warning = "Package biblatex Warning: The following entry could not be found\n" \
                  "(biblatex)                in the database:\n" \
                  "(biblatex)                w-nfm-74\n" \
                  "(biblatex)                Please verify the spelling and rerun\n" \
                  "(biblatex)                LaTeX afterwards."
    condensed = builder.condense_package_warning(raw_warning.lines.map(&:strip).join(' '))
    assert_equal "Package biblatex Warning: Entry 'w-nfm-74' not found in database.", condensed
  end
end
