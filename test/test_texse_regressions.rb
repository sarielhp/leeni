#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'open3'

require_relative '../lib/leeni/utils'
require_relative '../lib/leeni/error_catalog'
load File.expand_path('../leeni', __dir__)

# Real pdflatex builds of faults found in TeX Stack Exchange documents whose
# diagnostics leeni got wrong.
class TestTexseRegressions < Minitest::Test
  LEENI = File.expand_path('../leeni', __dir__)

  def setup
    skip 'pdflatex required' unless LaTeXUtils.command_available?('pdflatex')
  end

  # Builds TEX fresh; returns [success, error lines of -llm].
  def build(tex)
    Dir.mktmpdir('leeni_texse_it') do |dir|
      File.write(File.join(dir, 'main.tex'), tex)
      out, status = Open3.capture2e(LEENI, '--no-lock', '-e', 'p', '--junk-dir', 'junk', '-llm', 'main.tex', chdir: dir)
      [status.success?, out.lines.grep(/: error: /)]
    end
  end

  # TeX.SE 360474: a node drawn only once the .aux holds data (there, a
  # balloon over a listing) is unknown in the first pass and found in the
  # second, as when TeX is run twice by hand.
  def test_node_that_needs_the_aux_is_resolved_by_the_next_pass
    ok, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{tikz}
      \begin{document}
      \section{A}\label{sec}
      \makeatletter\@ifundefined{r@sec}{}{\tikz \node (n) {a};}\makeatother
      \tikz \draw (n) -- (0,1);
      \end{document}
    TEX
    assert ok, errors.join
    assert_empty errors
  end

  def test_unknown_node_is_still_an_error_after_the_extra_pass
    ok, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{tikz}
      \begin{document}
      \tikz \draw (nowhere) -- (0,1);
      \end{document}
    TEX
    refute ok
    assert_match(/main\.tex:4: error: .*No shape named `nowhere'/, errors.first.to_s)
  end

  # TeX.SE 491706: one dropped character is placed where it stands alone in
  # the body, not inside \documentclass{beamer} (here \usepackage{bm}).
  def test_one_dropped_character_is_found_in_the_body
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{bm}
      \usepackage{tikz}
      \begin{document}
      \begin{tikzpicture}
      \node {a}; b
      \end{tikzpicture}
      \end{document}
    TEX
    dropped = errors.grep(/dropped from the PDF: 'b'/)
    refute_empty dropped, errors.join
    assert_match(/\Amain\.tex:6: /, dropped.first)
  end

  # TeX.SE 754837: "File ended while scanning use of ..." has no line, and TeX
  # shows the runaway text as tokens across source lines, without a brace the
  # source has.
  def test_runaway_start_matches_tokens_across_lines_when_the_file_ended
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'p.tex')
      File.write(path, "\\begin{axis}\n  \\addplot {x^2+4};\n\\end{axis}\n\\end{center}\n}\n\\end{overlayarea}\n")
      shown = '; \\end {axis} \\end {center}  \\end {overlayarea} \\ETC.'
      assert_equal [2, nil], LaTeXErrorCatalog.runaway_start(path, 0, shown)
    end
  end

  # TeX.SE 367913: with main.aux already there, LuaTeX prints the Lua error on
  # the line of the files it opened, which were read as its file name.
  def test_lua_error_after_opened_files_gets_a_line_of_its_own
    builder = LatexBuilder.new('main.tex', junk_dir: 'junk')
    log = "(./main.aux)[\\directlua]:1: unexpected symbol near '\\'.\nl.6 \\directlua{print(\"hello\")}\n"
    assert_equal "(./main.aux)\n[\\directlua]:1: unexpected symbol near '\\'.\nl.6 \\directlua{print(\"hello\")}\n",
                 builder.send(:join_error_continuations, log)
  end

  # TeX.SE 30012: a blank line inside align* is the fault, at the line TeX
  # reports, not the line where the environment's body began.
  def test_blank_line_in_align_is_reported_where_it_is
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{amsmath}
      \begin{document}
      \begin{align*}
      a & = b + c \\

      \end{align*}
      \end{document}
    TEX
    assert_match(/\Amain\.tex:6: error: paragraph ended before \\align\* was complete/, errors.first.to_s)
  end

  # TeX.SE 140531: dropped punctuation is placed only where it is the one
  # standalone occurrence in the body; a ; after a failed \addplot was put on
  # the first line of the picture ending in ;.
  def test_dropped_punctuation_is_placed_only_when_unambiguous
    picture = "\\begin{tikzpicture}\n\\draw (0,0) -- (1,1);\n\\node {a}; !\n\\end{tikzpicture}\n"
    _, errors = build("\\documentclass{article}\n\\usepackage{tikz}\n\\begin{document}\n#{picture}\\end{document}\n")
    assert_match(/\Amain\.tex:6: error: .*dropped from the PDF: '!'/, errors.first.to_s)
    _, errors = build("\\documentclass{article}\n\\usepackage{tikz}\n\\begin{document}\nWow !\n\n#{picture}\\end{document}\n")
    refute_match(/\Amain\.tex:4: /, errors.first.to_s, 'two lines hold a standalone !')
  end

  # TeX.SE 351795: \draw in a \caption is undefined although tikz is loaded
  # (\protect\tikz does not protect it); "check \usepackage" sent users astray.
  def test_undefined_tikz_path_command_explains_the_picture_scope
    hint = LaTeXErrorCatalog.suggest_command('\\draw')
    assert_includes hint, 'exists only inside a tikzpicture'
    assert_includes hint, '\\protect\\draw'
  end

  # TeX.SE 554070: an \addplot table without its closing ; runs to the end of
  # the file; TeX shows the runaway text with \par for each blank line.
  def test_addplot_without_semicolon_is_placed_after_the_plot
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{pgfplots}
      \begin{document}
      \begin{tikzpicture}
      \begin{axis}
      \addplot table {
      x y
      1 2
      }

      \end{axis}
      \end{tikzpicture}
      \end{document}
    TEX
    assert_match(/\Amain\.tex:11: error: file ended while scanning .*\\addplot was never ended: it must end with ;/, errors.first.to_s)
  end
end
