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

  # Builds TEX fresh; returns [success, error lines of -llm]. ENGINE is the
  # one-letter engine code of -e ('p' pdflatex, 'l' lualatex).
  def build(tex, engine = 'p')
    Dir.mktmpdir('leeni_texse_it') do |dir|
      File.write(File.join(dir, 'main.tex'), tex)
      out, status = Open3.capture2e(LEENI, '--no-lock', '-e', engine, '--junk-dir', 'junk', '-llm', 'main.tex',
                                    chdir: dir)
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

  # TeX.SE 654633: a missing encoding file (T5 without vntex) makes every later
  # "Encoding scheme unknown" from the same fault; one error, with a hint.
  def test_missing_font_encoding_is_one_error_with_an_install_hint
    ok, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage[XQ9]{fontenc}
      \begin{document}
      Text \textbf{bold}.
      \end{document}
    TEX
    refute ok
    assert_equal 1, errors.size
    assert_match(/main\.tex:2: error: .*xq9enc\.def.*Font encoding 'XQ9' is not installed/, errors.first.to_s)
  end

  # TeX.SE 749679: memoize's Perl extraction without a PDF module; TeX reports
  # it from main.mmz.log, leeni places it at the \usepackage with a hint.
  def test_memoize_without_perl_pdf_module_gets_a_hint
    ok, errors = build(<<~'TEX')
      \documentclass{article}
      \PackageError{memoize (perl-based extraction)}{No suitable Perl module for PDF processing was found, options are PDF::API2, PDF::Builder}{Have you followed the instructions is section 1.1 of the manual?}
      \begin{document}
      Text.
      \end{document}
    TEX
    refute ok
    assert_match(/main\.tex:2: error: .*No suitable Perl module.*PDF::API2.*extract=python/, errors.first.to_s)
  end

  # TeX.SE 37700: units and siunitx both define \unit. siunitx reports the
  # clash, then "Command '\unit' already defined", then repeats itself at
  # \begin{document}; one error, at the \usepackage{siunitx}, with a hint.
  def test_siunitx_with_units_is_one_error_with_a_hint
    ok, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{units}
      \usepackage{siunitx}
      \begin{document}
      \unit{m}
      \end{document}
    TEX
    refute ok
    assert_equal 1, errors.size
    assert_match(/main\.tex:3: error: .*Package 'units' incompatible.*remove \\usepackage\{units\}/, errors.first.to_s)
  end

  # TeX.SE 227793: a pgfplots boxplot over all-zero data on a log axis prints
  # "0.00" with no font. It starts with a digit, so it was placed inside a
  # longer number of a data row (000.00) instead of being left unlocated.
  def test_number_inside_a_longer_number_is_not_dropped_text
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{pgfplots}
      \usetikzlibrary{pgfplots.statistics}
      \pgfplotsset{compat=1.9}
      \begin{document}
      \begin{tikzpicture}
      \begin{axis}[boxplot/draw direction=y, ymode=log]
      \addplot+[boxplot] table[row sep=\\,y index=0] {
      000.00\\
      000.00\\
      };
      \end{axis}
      \end{tikzpicture}
      \end{document}
    TEX
    assert(errors.none? { |e| e.include?('dropped') }, errors.join)
    assert_match(/\Amain\.tex:11: error: missing number, treated as zero/, errors.first.to_s)
  end

  # TeX.SE 142458: an \addplot table { never closed before the next \addplot.
  # The unclosed brace is already reported; the dropped '^^M' it leaves behind
  # is unlocated and was reported beside it as a second error.
  def test_unlocated_dropped_text_is_not_reported_beside_a_brace_error
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{pgfplots}
      \begin{document}
      \begin{tikzpicture}
      \begin{axis}
      \addplot table {
      1 2
      \addplot table {
      3 4
      };
      \end{axis}
      \end{tikzpicture}
      \end{document}
    TEX
    assert_equal 1, errors.size
    assert_match(/\Amain\.tex:6:16: error: unclosed open brace/, errors.first.to_s)
  end

  # TeX.SE 83773: xltxtra under pdflatex stops with "XeTeX is required to
  # compile this document" and an Emergency stop in xltxtra.sty; the error
  # is reported at the \usepackage line that loaded it.
  def test_engine_required_package_is_reported_at_its_usepackage
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{xltxtra}
      \begin{document}
      Hi
      \end{document}
    TEX
    assert_equal 1, errors.size
    assert_match(/\Amain\.tex:2: error: .*XeTeX is required to compile this document/, errors.first.to_s)
  end

  # TeX.SE 148271: \openin of a missing file then \readline: TeX only gives
  # the Emergency stop "cannot \read from terminal in nonstop modes". One
  # error at the \readline line, and no spurious "unclosed open brace".
  def test_read_from_unopened_stream_is_reported_once
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \newread\reader
      \openin\reader=no_such_list.txt
      \readline\reader to \data
      \begin{document}
      Hello
      \end{document}
    TEX
    assert_equal 1, errors.size
    assert_match(/\Amain\.tex:4: error: .*\\read from a stream that is not open/, errors.first.to_s)
    assert(errors.none? { |e| e.include?('unclosed open brace') }, errors.join)
  end

  # TeX.SE 135737: \lstnewenvironment whose begin code opens center; the
  # body is read verbatim until \end{center}, so the environment never ends
  # and TeX only says "no legal \end found". Reported at its \begin.
  def test_verbatim_environment_opened_by_lstnewenvironment
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{listings}
      \lstnewenvironment{codetext}[1]{\begin{center}#1}{\end{center}}
      \begin{document}
      \begin{codetext}{cap}
      Some code.
      \end{codetext}
      \end{document}
    TEX
    assert_equal 1, errors.size
    assert_match(/\Amain\.tex:5: error: .*ended inside environment \{codetext\}/, errors.first.to_s)
    assert_match(/\\lstnewenvironment\{codetext\}/, errors.first.to_s)
  end

  # TeX.SE 77920: the comment package's \excludecomment makes an indented
  # \end{wrapfigure} end "the file" for \next. Reported at the \begin.
  def test_comment_environment_end_needs_no_indentation
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{comment}
      \excludecomment{wrapfigure}
      \begin{document}
      X.

      \begin{wrapfigure}{r}{0.5\textwidth}
      inside
          \end{wrapfigure}
      \end{document}
    TEX
    assert_equal 1, errors.size
    assert_match(/\Amain\.tex:7: error: .*scanning use of \\next/, errors.first.to_s)
    assert_match(/\\end\{wrapfigure\} alone at the start of a line/, errors.first.to_s)
  end

  # TeX.SE 22943: a missing file in \lstinputlisting is reported by listings
  # without a line; the error belongs at the \lstinputlisting line.
  def test_lstinputlisting_missing_file_is_reported_at_its_line
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{listings}
      \begin{document}
      Text before.

      \lstinputlisting{no_such_file.txt}

      \end{document}
    TEX
    assert_match(/\Amain\.tex:6: error: .*not found/, errors.first.to_s)
  end

  # TeX.SE 188192: keyval does not expand the \foo that holds the options,
  # so 'scale=0.1' is read as one key. The error belongs at the
  # \includegraphics line, not at the \def.
  def test_keyval_error_is_reported_at_the_command_not_the_def
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{graphicx}
      \begin{document}
      \def\foo{scale=0.1}
      \includegraphics[\foo]{fig1}
      \end{document}
    TEX
    assert_match(/\Amain\.tex:5:.*error: .*keyval Error/, errors.first.to_s)
    assert_match(/'scale=0\.1' was read as one key/, errors.first.to_s)
  end

  # TeX.SE 69425: \lstinline with a bracketed language inside a \newcommand
  # breaks at the paragraph end; the groups and \ifx it leaves open are
  # folded into that one error.
  def test_listing_options_in_newcommand_give_one_error
    _, errors = build(<<~'TEX')
      \documentclass{scrreprt}
      \usepackage{listings}
      \newcommand{\lstcs}[1]{\lstinline[language=[Sharp]C,breaklines=false]#1}

      \begin{document}

      This is \lstcs{CSharpCode()}.

      \end{document}
    TEX
    assert_equal 1, errors.size
    assert_match(/\Amain\.tex:7: error: .*paragraph ended before .*\\lstKV@OptArg@@ was complete/, errors.first.to_s)
  end

  # TeX.SE 129183: a Lua syntax error in a luacode* environment is reported
  # at the line of the chunk, not at \end{luacode*}.
  def test_lua_error_in_luacode_is_reported_at_the_chunk_line
    skip 'lualatex required' unless LaTeXUtils.command_available?('lualatex')

    _, errors = build(<<~'TEX', 'l')
      \documentclass{article}
      \usepackage{luacode}
      \begin{document}
      \begin{luacode*}
      for i=-1,5,1.0 do
        tex.print(..i "&" ..-i^2 + 5*i - 8 "\\hline")
      end
      \end{luacode*}
      \end{document}
    TEX
    assert_match(/\Amain\.tex:6: error: .*unexpected symbol/, errors.first.to_s)
  end
end
