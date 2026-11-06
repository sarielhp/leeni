# frozen_string_literal: true

require_relative 'leeni_test_support'

# Checks on the .bib files a paper uses: a `%` "comment" inside an entry is an
# alert under Biber (which accepts it) and named in BibTeX's failure message
# (which only says it expected a ',' or '}'); scan results are cached.
class TestBibChecks < LeeniTestBase
  BIB = <<~BIB
    @article{a, author = {A. A}, title = {Alpha}, journal = {J}, year = 2001,
      annote = {229} %DONE
    }
    @article{b, author = {B. B}, title = {Beta}, journal = {J}, year = 2002}
  BIB

  def test_scanner_names_the_percent_sign
    _items, problems = Bibkit::Scanner.scan(BIB)
    assert_empty problems
    item_problem = Bibkit::BibFile.new(BIB).problems.first
    assert_equal 2, item_problem.line
    assert_includes item_problem.message, "'%' does not start a comment inside a .bib entry"
  end

  def test_problems_are_cached_by_size_and_mtime
    Dir.mktmpdir('bib_checks') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('junk/paper.aux', "\\bibdata{refs}\n")
        File.write('refs.bib', BIB)
        found = LatexBibChecks.problems('junk', 'paper', [])
        assert_equal([[File.expand_path('refs.bib'), 2]], found.map { |file, line, _| [file, line] })
        assert File.file?('junk/.bib_checks.json')

        File.write('refs.bib', BIB.sub(' %DONE', ''))
        File.utime(Time.now + 5, Time.now + 5, 'refs.bib')
        assert_empty LatexBibChecks.problems('junk', 'paper', [])
      end
    end
  end

  def build(tex)
    Dir.mktmpdir('bib_checks_build') do |dir|
      File.write(File.join(dir, 'refs.bib'), BIB)
      File.write(File.join(dir, 'p.tex'), tex)
      out, status = Open3.capture2e(BIN, '--no-color', 'p.tex', chdir: dir)
      yield strip_ansi(out), status.exitstatus
    end
  end

  def test_biber_build_raises_an_alert
    skip 'biber not installed' unless LaTeXUtils.command_available?('biber')

    tex = "\\documentclass{article}\\usepackage[backend=biber]{biblatex}\\addbibresource{refs.bib}\n" \
          "\\begin{document}\\cite{a,b}\\printbibliography\\end{document}\n"
    build(tex) do |out, code|
      assert_equal 0, code, out
      assert_match(/^\s*2: \S+ Bibliography file: "%DONE" after a field value: '%' does not start a/, out)
    end
  end

  def test_bibtex_failure_names_the_cause
    skip 'bibtex not installed' unless LaTeXUtils.command_available?('bibtex')

    tex = "\\documentclass{article}\\begin{document}\\cite{a,b}\\bibliographystyle{plain}\\bibliography{refs}\\end{document}\n"
    build(tex) do |out, _code|
      assert_includes out, "I was expecting a `,' or a `}'---line 2 of file refs.bib."
      assert_includes out, "'%' does not start a comment inside a .bib entry; move the note into a field"
    end
  end
end
