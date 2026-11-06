# frozen_string_literal: true

require_relative 'leeni_test_support'

# --bib-fix end to end: real BibTeX and Biber builds against a bibliography
# collection reached through BIBINPUTS (skipped when the tools are missing).
class TestBibFix < LeeniTestBase
  STRINGS = <<~BIB
    @string{DCG = "Discrete Comput. Geom."}
    @preamble{"\\providecommand{\\CNFX}[1]{(#1)}"}
  BIB
  ENTRIES = <<~BIB
    @article{fresh, author = {F. Fay}, title = {Fresh Paper}, note = {\\CNFX{conf}}, journal = DCG, year = 2001}
    @book{clash, author = {C. Cee}, title = {First Title}, publisher = {P}, year = 2002}
  BIB
  OTHER = "@book{clash, author = {C. Cee}, title = {Second Title}, publisher = {P}, year = 2002}\n"
  LOCAL = "@article{known, author = {K. Kay}, title = {Already Local}, journal = DCG, year = 2000}\n"

  BIBTEX_PAPER = <<~'TEX'
    \documentclass{article}
    \begin{document}
    See \cite{known,fresh,clash}.
    \bibliographystyle{plain}
    \bibliography{paper}
    \end{document}
  TEX

  BIBLATEX_PAPER = <<~'TEX'
    \documentclass{article}
    \usepackage[backend=biber]{biblatex}
    \addbibresource{paper.bib}
    \begin{document}
    See \cite{known,fresh,clash}.
    \printbibliography
    \end{document}
  TEX

  # Yields the paper directory and the environment pointing BIBINPUTS at a
  # collection outside it.
  def with_paper(tex, local: LOCAL)
    Dir.mktmpdir('bib_fix') do |root|
      lib = File.join(root, 'lib')
      dir = File.join(root, 'paper')
      FileUtils.mkdir_p([lib, dir])
      { 'strings.bib' => STRINGS, 'entries.bib' => ENTRIES, 'other.bib' => OTHER }.each do |name, text|
        File.write(File.join(lib, name), text)
      end
      File.write(File.join(dir, 'paper.tex'), tex)
      File.write(File.join(dir, 'paper.bib'), local) if local
      yield dir, { 'BIBINPUTS' => "#{lib}:" }
    end
  end

  def leeni(env, dir, *)
    out, status = Open3.capture2e(env, BIN, '--no-color', *, 'paper.tex', chdir: dir)
    [strip_ansi(out), status.exitstatus]
  end

  def assert_fixes(tex)
    with_paper(tex) do |dir, env|
      out, code = leeni(env, dir, '--bib-fix')
      assert_equal 0, code, out
      assert_includes out, '2 entries: clash, fresh'
      assert_includes out, '1 @string: DCG'
      fixed = File.read(File.join(dir, 'paper.bib'))
      assert_operator fixed.index('@string{DCG'), :<, fixed.index('@article{known'), 'macros go first'
      assert_includes fixed, '@book{clash_leeni_alt_2, author = {C. Cee}, title = {Second Title}'
      assert_equal LOCAL, File.read(File.join(dir, 'paper.bib.bak'))
      txt, = Open3.capture2('pdftotext', File.join(dir, 'paper.pdf'), '-')
      assert_includes txt, 'Discrete Comput. Geom.'
      assert_includes txt, '(conf)'

      out, = leeni(env, dir, '-f')
      line = fixed.lines.index { |l| l.include?('clash_leeni_alt_2') } + 1
      assert_match(/paper\.bib \(1 alert\).*^\s*#{line}: \S+ Unresolved --bib-fix alternative clash_leeni_alt_2/m, out)
    end
  end

  def test_bibtex_paper_is_fixed
    skip 'bibtex not installed' unless LaTeXUtils.command_available?('bibtex')

    assert_fixes(BIBTEX_PAPER)
  end

  def test_biber_paper_is_fixed
    skip 'biber not installed' unless LaTeXUtils.command_available?('biber')

    assert_fixes(BIBLATEX_PAPER)
  end

  def test_dry_run_changes_nothing
    skip 'bibtex not installed' unless LaTeXUtils.command_available?('bibtex')

    with_paper(BIBTEX_PAPER) do |dir, env|
      out, code = leeni(env, dir, '--bib-fix', '--dry-run')
      assert_equal 0, code, out
      assert_includes out, '(dry run)'
      assert_equal LOCAL, File.read(File.join(dir, 'paper.bib'))
      refute File.exist?(File.join(dir, 'paper.bib.bak'))
    end
  end

  def test_bibliography_outside_the_project_is_refused
    skip 'bibtex not installed' unless LaTeXUtils.command_available?('bibtex')

    with_paper(BIBTEX_PAPER.sub('\bibliography{paper}', '\bibliography{strings,entries}'), local: nil) do |dir, env|
      out, code = leeni(env, dir, '--bib-fix')
      assert_equal 1, code
      assert_includes out, 'Not a file of this project: strings, entries'
    end
  end

  def test_option_clashes_are_refused
    Dir.mktmpdir('bib_fix_cli') do |dir|
      out, status = Open3.capture2e(BIN, '--bib-fix', '--bib-missing', 'paper.tex', chdir: dir)
      assert_equal 2, status.exitstatus
      assert_includes out, '--bib-fix cannot be combined with --bib-missing'
    end
  end
end
