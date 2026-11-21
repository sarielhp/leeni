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

  # TeX.SE 236751: french babel's active ';' in a \caption goes into the .toc
  # write, which is unbalanced at shipout (a listing on the page): TeX stops
  # with an Emergency stop that names no error. The fault is the \caption.
  def test_unbalanced_write_is_reported_at_the_caption
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{lipsum}
      \usepackage{listings}
      \usepackage[french]{babel}
      \begin{document}
      \begin{figure}
        \caption{Foo ; bar}
      \end{figure}
      \lipsum[1-4]
      \begin{lstlisting}
      Foo 1
      Foo 2
      Foo 3
      Foo 4
      Foo 5
      Foo 6
      Foo 7
      Foo 8
      Foo 9
      \end{lstlisting}
      \end{document}
    TEX
    assert_equal 1, errors.size, errors.join
    assert_match(/\Amain\.tex:7: error: .*Unbalanced write command/, errors.first.to_s)
  end

  # TeX.SE 202217: a LuaLaTeX-only package under pdflatex fails on an
  # undefined Lua primitive (\luatexversion); the avalanche it leaves at the
  # \usepackage line is one error naming the engine, not dozens of them.
  def test_luatex_only_package_gives_one_engine_error
    skip 'lua-check-hyphen.sty not installed' if Open3.capture2('kpsewhich', 'lua-check-hyphen.sty').first.strip.empty?

    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{lua-check-hyphen}
      \begin{document}
      Foo
      \end{document}
    TEX
    assert_equal 1, errors.size, errors.join
    assert_match(/\Amain\.tex:2: error: /, errors.first.to_s)
    assert_match(/LuaTeX primitive.*-e lualatex/, errors.first.to_s)
  end

  # TeX.SE 394939: \text is undefined inside \newcommand*{\fnn}, but TeX
  # reports the \fnn call, not the definition; \textsc on the next line must
  # not be mistaken for the token.
  def test_undefined_cs_in_a_macro_is_reported_at_its_call
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \newcommand*{\fnn}[1]{\text{\texttt{#1}}}
      \newcommand*{\Ker}[1]{\textsc{ker}(\fnn{#1})}
      \begin{document}
      $\Ker{f}$
      \end{document}
    TEX
    assert_equal 1, errors.size, errors.join
    assert_match(/\Amain\.tex:2:23: error: .*undefined control sequence \\text/, errors.first.to_s)
  end

  # TeX.SE 289768: \numberwithin{ ends its line 5 with the body below, and
  # the paragraph ends at a blank line inside it. With the } after the blank
  # line the argument was closed: the blank line is the fault (760647).
  def test_blank_line_inside_a_closed_argument_is_the_fault
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{amsmath}

      \begin{document}
      \numberwithin{
      \[
      \left( \begin{array}{c}
      \textrm{$\;d\textprime\;$}\\
      \end{array} \right)

      \]
      }
      \end{document}
    TEX
    assert_match(/\Amain\.tex:10: error: .*paragraph ended before \\numberwithin.*remove the blank line/, errors.first.to_s)
  end

  # TeX.SE 289768, with the } missing: the argument is never closed, and its
  # start is the { that ends line 5.
  def test_paragraph_ended_before_an_unclosed_argument_is_at_its_brace
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{amsmath}

      \begin{document}
      \numberwithin{
      \[
      x
      \]

      Text.
      \end{document}
    TEX
    # The pre-flight brace check merges in and words it as an unclosed brace.
    assert_match(/\Amain\.tex:5:14: error: .*(?:paragraph ended before \\numberwithin|unclosed open brace)/, errors.first.to_s)
  end

  # TeX.SE 373592: \usepackage{amsfonts] leaves amsmath unloaded, and the
  # \text failures that follow are one diagnostic, not the same one twice.
  def test_same_undefined_cs_at_one_place_is_listed_once
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{amsfonts]

      \begin{document}


      \begin{equation}
      c = 1 - \frac{\text{d} P_\text{out}}{\text{d} P_\text{in}}
      \end{equation}

      \end{document}
    TEX
    texts = errors.grep(/undefined control sequence.*\\text\b/)
    assert_equal 1, texts.size, errors.join
    assert_match(/\Amain\.tex:8:15: error: .*\\text/, texts.first.to_s)
  end

  # TeX.SE 401031: dropped nullfont text in a document without pictures is
  # preamble text, not text outside the nodes of a picture.
  def test_dropped_text_hint_names_the_preamble_without_pictures
    _, errors = build(<<~'TEX')
      \documentclass[a4paper,

      11pt
      ]{article}
      \begin{document}
      x
      \end{document}
    TEX
    dropped = errors.grep(/dropped from the PDF/)
    refute_empty dropped, errors.join
    assert_match(/\Amain\.tex:3: error: .*'11pt\]article'/, dropped.first.to_s)
    assert_match(/Text typeset before any font was set up/, dropped.first.to_s)
    refute_match(/picture/, dropped.first.to_s)
  end

  # TeX.SE 78474: \z@ in the begin code of a \newenvironment is written in the
  # document body without \makeatletter, so \z is undefined there; the error
  # belongs at the \z@ in the definition, not at the \begin{document}.
  def test_zat_in_newenvironment_begin_code_is_reported_at_its_column
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \newenvironment{test}{\vspace{\z@}Hello}{World}
      \begin{document}
      \begin{test}
      x
      \end{test}
      \end{document}
    TEX
    zed = errors.grep(/undefined control sequence \\z\b/)
    refute_empty zed, errors.join
    assert_match(/\Amain\.tex:2:31: error: /, zed.first)
  end

  # TeX.SE 290592: \setmainfont naming a font the system does not have is a
  # font that cannot be loaded, with the font's name, not a missing file
  # named "or installed font".
  def test_uninstalled_main_font_is_not_loadable_with_its_name
    skip 'xelatex required' unless LaTeXUtils.command_available?('xelatex')

    _, errors = build(<<~'TEX', 'x')
      \documentclass{article}
      \usepackage{fontspec}
      \setmainfont{NoSuchFontXyz}
      \begin{document}
      Text.
      \end{document}
    TEX
    font = errors.grep(/not loadable/)
    refute_empty font, errors.join
    assert_match(/\Amain\.tex:4: error: .*NoSuchFontXyz at 10\.0pt not loadable/, font.first)
    assert_includes font.first, "Font 'NoSuchFontXyz' is not installed"
    refute(errors.any? { |e| e.include?("File 'or installed font'") }, errors.join)
  end

  # TeX.SE 325991: the ] of language=[LaTeX]TeX ends the optional argument, so
  # the value TeX keeps is [LaTeX; the hint braces it.
  def test_bracketed_language_option_hint_braces_the_value
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{listings}
      \begin{document}
      \lstinputlisting[language=[LaTeX]TeX]{myfile.tex}
      \end{document}
    TEX
    assert_equal 1, errors.size, errors.join
    assert_match(/\Amain\.tex:4: error: file ended while scanning use of \\lstKV@OptArg@@/, errors.first)
    assert_includes errors.first, "The ] of '[LaTeX]TeX' ends the optional argument early"
    assert_includes errors.first, 'brace the value ({[LaTeX]TeX})'
  end

  # TeX.SE 655907: \tl_if_gput_right:Nn does not exist, but the error names the
  # whole control sequence as written, not the \tl it starts with (which is
  # only the expl3 module prefix), and sits on the line of the definition.
  def test_undefined_expl3_command_is_named_in_full
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{xparse}

      \ExplSyntaxOn
      \NewDocumentCommand\storemydate{m}{\tl_if_gput_right:Nn \g_tmpa_tl {#1}}
      \ExplSyntaxOff

      \begin{document}
      \storemydate{x}
      \end{document}
    TEX
    command = errors.grep(/undefined control sequence/)
    refute_empty command, errors.join
    assert_match(/\Amain\.tex:5:\d+: error: .*\\tl_if_gput_right:Nn/, command.first)
    refute_match(/\\tl(?!_if_gput_right:Nn)/, command.first)
  end

  # TeX.SE 616334: siunitx has no decimalsymbol option; the error is raised at
  # the \usepackage that gives it, once, in a document xcolor and bookmark
  # also build in.
  def test_unknown_siunitx_option_is_one_error_at_its_load_line
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage[decimalsymbol=comma]{siunitx}
      \usepackage{xcolor}
      \usepackage{bookmark}
      \begin{document}
      x
      \end{document}
    TEX
    option = errors.grep(/Unknown option 'decimalsymbol'/)
    assert_equal 1, option.size, errors.join
    assert_match(/\Amain\.tex:2: error: /, option.first)
  end

  # TeX.SE 675705: a package that is LuaLaTeX-only (chickenize) fails on
  # \directlua under pdflatex; the fault is the engine, reported once at the
  # \usepackage, not at every command used in the body.
  def test_lualatex_only_package_is_one_error_at_its_load_line
    skip 'chickenize.sty required' unless system('kpsewhich', 'chickenize.sty', out: File::NULL)

    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{chickenize}

      \begin{document}
      \addtosubstitutions{a}{A}
      \substitutewords
      text
      \end{document}
    TEX
    lua = errors.grep(/\\directlua/)
    assert_equal 1, lua.size, errors.join
    assert_match(/\Amain\.tex:2: error: /, lua.first)
    assert_match(/needs LuaTeX/, lua.first)
  end

  # TeX.SE 694072: kpfonts-otf needs LuaTeX or XeTeX and refuses pdflatex at
  # its own \usepackage; that one refusal is the whole fault.
  def test_kpfonts_otf_on_pdflatex_is_one_engine_error_at_its_load_line
    skip 'kpfonts-otf.sty required' unless system('kpsewhich', 'kpfonts-otf.sty', out: File::NULL)

    _, errors = build(<<~'TEX')
      \documentclass{article}

      \usepackage{kpfonts-otf}

      \begin{document}
      Some text.\mathversion{bold}$a$
      \end{document}
    TEX
    assert_equal 1, errors.size, errors.join
    assert_match(/\Amain\.tex:3: error: .*LuaTeX or XeTeX is required/, errors.first)
    assert_match(/needs LuaTeX/, errors.first)
  end

  # TeX.SE 537582: luacode under pdfTeX stops at its \usepackage line asking
  # for LuaTeX, not with a missing control sequence in the body.
  def test_luacode_under_pdftex_asks_for_luatex_at_its_usepackage
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{luacode}
      \begin{document}
      x
      \end{document}
    TEX
    assert_equal 1, errors.size, errors.join
    assert_match(/\Amain\.tex:2: error: /, errors.first)
    assert_match(/LuaTeX is required/, errors.first)
    assert_match(/needs LuaTeX/, errors.first)
  end

  # TeX.SE 571019: \makeatletter inside a \newcommand body runs too late, so
  # the @ in \lst@AddToHook is not a letter; the error belongs at that line.
  def test_makeatletter_inside_a_macro_body_is_reported_at_the_at_command
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{listings}

      \newcommand{\testcmm}{
          \makeatletter
          \lst@AddToHook{TextStyle}{\let\lst@basicstyle=\footnotesize}
          \makeatother
      }

      \begin{document}
      \testcmm
      \end{document}
    TEX
    assert_match(/\Amain\.tex:6:\d+: error: /, errors.first.to_s)
    assert_match(/@ is not a letter here/, errors.first)
  end

  # TeX.SE 489395: a luacode body that calls an undefined global fails at run
  # time, at the line that made the call.
  def test_luacode_runtime_error_is_reported_at_its_line
    skip 'lualatex required' unless LaTeXUtils.command_available?('lualatex')

    _, errors = build(<<~'TEX', 'l')
      \documentclass{article}
      \usepackage{luacode}
      \begin{document}
      \begin{luacode}
      local a = 1
      x = nosuchfunction()
      \end{luacode}
      \end{document}
    TEX
    assert_equal 1, errors.size, errors.join
    assert_match(/\Amain\.tex:6: error: /, errors.first)
    assert_match(/Lua runtime error/, errors.first)
  end

  # TeX.SE 272310: a \newenvironment wrapping minted needs \VerbatimEnvironment
  # in its begin code; without it fancyvrb reads to the file end. One error,
  # at the \begin{pythoncode} that opened it.
  def test_minted_in_a_newenvironment_needs_verbatimenvironment
    skip 'minted.sty required' unless system('kpsewhich', 'minted.sty', out: File::NULL)

    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{minted}
      \newenvironment{pythoncode}{\begin{minted}{python}}{\end{minted}}
      \begin{document}
      \begin{pythoncode}
      x = 1
      \end{pythoncode}
      \end{document}
    TEX
    assert_equal 1, errors.size, errors.join
    assert_match(/\Amain\.tex:5: error: .*VerbatimEnvironment/, errors.first)
  end

  # TeX.SE 151317: collect* left open after its matching \end is a runaway to
  # the end of a balanced file; TeX names no line, and the fault is the last
  # line, not line 1.
  def test_runaway_to_the_end_of_a_balanced_file_is_at_its_last_line
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{xparse}
      \usepackage{collect}

      \NewDocumentEnvironment{dup}{m}
        {\begin{collect*}{#1dupcollection}{}{}{}{}}
        {\end{collect*}}
      \begin{document}
      \begin{dup}{atest}
      content...
      \end{dup}
      \end{document}
    TEX
    assert_equal 1, errors.size, errors.join
    assert_match(/\Amain\.tex:12: error: file ended while scanning/, errors.first)
  end

  # TeX.SE 276029: titlesec and titleps are incompatible; titleps repeats the
  # package error, which is one error at the \usepackage{titlesec}.
  def test_titlesec_after_titleps_is_one_repeated_error
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{titleps}
      \usepackage{titlesec}
      \begin{document}
      x
      \end{document}
    TEX
    assert_equal 1, errors.size, errors.join
    assert_match(/main\.tex:\d+: error: .*repeated \d+ times/, errors.first)
  end
end
