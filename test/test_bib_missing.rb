# frozen_string_literal: true

require_relative 'leeni_test_support'

# --bib-missing: the key set from build-directory files, the CLI contract, and
# real BibTeX/Biber builds (skipped when the tools are missing).
class TestBibMissing < LeeniTestBase
  BIB = <<~BIB
    @article{good1, author = {A. B}, title = {T}, journal = {J}, year = {2000}}
    @article{good2, author = {C. D}, title = {U}, journal = {J}, year = {2001}}
  BIB

  BIBTEX_PAPER = <<~'TEX'
    \documentclass{article}
    \begin{document}
    See \cite{good1,zeta} and \cite{good2} and \cite{alpha}.
    \bibliographystyle{plain}
    \bibliography{refs}
    \end{document}
  TEX

  BIBLATEX_PAPER = <<~'TEX'
    \documentclass{article}
    \usepackage[backend=biber]{biblatex}
    \addbibresource{refs.bib}
    \begin{document}
    See \cite{good1,zeta} and \cite{good2} and \cite{alpha}.
    \printbibliography
    \end{document}
  TEX

  def with_build_dir(files)
    Dir.mktmpdir('bib_missing') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        files.each { |name, body| File.write(File.join('junk', name), body) }
        yield legacy_builder('paper.tex')
      end
    end
  end

  def test_cited_keys_without_bbl_entries_are_missing
    files = { 'paper.aux' => "\\citation{good1,zeta}\n\\citation{alpha}\n\\citation{*}\n",
              'paper.bbl' => "\\begin{thebibliography}{1}\n\\bibitem{good1} A.\n\\end{thebibliography}\n" }
    with_build_dir(files) { |b| assert_equal %w[alpha zeta], b.missing_bib_keys }
  end

  def test_tool_reports_and_biblatex_missing_are_included
    files = { 'paper.aux' => "\\citation{good1}\n",
              'paper.bbl' => "\\entry{good1}{article}{}\n\\missing{gone}\n",
              'paper.blg' => "Warning--I didn't find a database entry for \"zeta\"\n" \
                             "WARN - I didn't find a database entry for 'beta'\n" }
    with_build_dir(files) { |b| assert_equal %w[beta gone zeta], b.missing_bib_keys }
  end

  def test_citations_from_included_aux_and_no_bbl_count
    files = { 'paper.aux' => "\\@input{chap.aux}\n", 'chap.aux' => "\\citation{inchap}\n" }
    with_build_dir(files) { |b| assert_equal %w[inchap], b.missing_bib_keys }
  end

  def test_clean_bibliography_reports_nothing
    files = { 'paper.aux' => "\\citation{good1}\n", 'paper.bbl' => "\\bibitem{good1} A.\n" }
    with_build_dir(files) { |b| assert_empty b.missing_bib_keys }
  end

  def test_clashing_options_exit_two
    [%w[-s], %w[-u], %w[--no-bib], %w[--zip], %w[--meta], %w[--bib-extract]].each do |extra|
      _out, err, status = Open3.capture3(BIN, '--bib-missing', *extra, 'paper.tex')
      assert_equal 2, status.exitstatus, "#{extra.inspect} should clash"
      assert_match(/--bib-missing cannot be combined/, err)
    end
  end

  def test_output_formats_are_overridden
    options = { bib_missing: true, llm: true, json: true, compile: true, emacs: true, trace: true }
    LatexBibMissing.validate_options!(options, 'leeni')
    refute(options.values_at(:llm, :json, :compile, :emacs, :trace).any?)
  end

  def run_paper(dir, *)
    Open3.capture3(BIN, *, 'paper.tex', chdir: dir)
  end

  def assert_lists_missing_keys(paper)
    Dir.mktmpdir('bib_missing_build') do |dir|
      File.write(File.join(dir, 'refs.bib'), BIB)
      File.write(File.join(dir, 'paper.tex'), paper)
      2.times do |run|
        out, err, status = run_paper(dir, '--bib-missing')
        assert_equal 0, status.exitstatus, "run #{run}: #{out}#{err}"
        assert_equal "alpha\nzeta\n", out, "run #{run} (second run is cached)"
      end
    end
  end

  def test_bibtex_build_prints_only_missing_keys
    skip 'bibtex not installed' unless LaTeXUtils.command_available?('bibtex')

    assert_lists_missing_keys(BIBTEX_PAPER)
  end

  def test_biber_build_prints_only_missing_keys
    skip 'biber not installed' unless LaTeXUtils.command_available?('biber')

    assert_lists_missing_keys(BIBLATEX_PAPER)
  end

  def test_latex_error_restores_regular_output
    skip 'bibtex not installed' unless LaTeXUtils.command_available?('bibtex')

    Dir.mktmpdir('bib_missing_error') do |dir|
      File.write(File.join(dir, 'refs.bib'), BIB)
      File.write(File.join(dir, 'paper.tex'), BIBTEX_PAPER.sub('See', '\undefinedmacro See'))
      out, err, status = run_paper(dir, '--bib-missing')
      assert_equal 1, status.exitstatus
      assert_match(/Undefined control sequence/, strip_ansi(out + err))
      assert_match(/Latex compilation failed/, strip_ansi(out))
    end
  end
end
