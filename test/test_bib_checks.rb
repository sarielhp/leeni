# frozen_string_literal: true

require_relative 'test_env'
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

  DUPLICATE_BIB = <<~BIB
    @article{a, author = {A. A}, title = {First Version}, journal = {J}, year = 2001}
    @article{a, author = {A. A}, title = {Second Version}, journal = {J}, year = 2001}
    @article{b, author = {B. B}, title = {Beta}, journal = {J}, year = 2002}
  BIB
  BIBTEX_TEX = "\\documentclass{article}\\begin{document}\\cite{a,b}\\bibliographystyle{plain}\\bibliography{refs}\\end{document}\n"
  BIBER_TEX = "\\documentclass{article}\\usepackage[backend=biber]{biblatex}\\addbibresource{refs.bib}\n" \
              "\\begin{document}\\cite{a,b}\\printbibliography\\end{document}\n"

  def build(tex, bib: BIB, args: [])
    Dir.mktmpdir('bib_checks_build') do |dir|
      File.write(File.join(dir, 'refs.bib'), bib)
      File.write(File.join(dir, 'p.tex'), tex)
      out, status = Open3.capture2e(BIN, '--no-color', *args, 'p.tex', chdir: dir)
      yield strip_ansi(out), status.exitstatus, dir
    end
  end

  def test_only_repeated_entries_is_recognised
    repeated = "Repeated entry---line 2 of file refs.bib\n : @article{a\n(There was 1 error message)\n"
    assert LatexBibChecks.only_repeated_entries?(repeated)
    refute LatexBibChecks.only_repeated_entries?("#{repeated}I was expecting a `,' or a `}'---line 9 of file refs.bib\n")
    refute LatexBibChecks.only_repeated_entries?('(There was 1 error message)')
  end

  # BibTeX exits with status 2 on a repeated key but writes the .bbl; the
  # build goes on and ends with an alert (it used to fail with no PDF).
  def test_bibtex_repeated_key_is_an_alert_not_a_failure
    skip 'bibtex not installed' unless LaTeXUtils.command_available?('bibtex')

    build(BIBTEX_TEX, bib: DUPLICATE_BIB) do |out, code, dir|
      assert_equal 0, code, out
      assert_match(/refs\.bib \(1 alert\).*^\s*2: \S+ Repeated entry---line 2 of file refs\.bib/m, out)
      txt, = Open3.capture2('pdftotext', File.join(dir, 'p.pdf'), '-')
      assert_includes txt, 'First version'
    end
  end

  def test_biber_duplicate_key_names_both_lines_and_links_the_file
    skip 'biber not installed' unless LaTeXUtils.command_available?('biber')

    build(BIBER_TEX, bib: DUPLICATE_BIB, args: ['--link']) do |out, code, dir|
      assert_equal 0, code, out
      assert_includes out, "Duplicate entry key 'a': Biber skips this copy and uses the one on line 1"
      assert_includes out, "\e]8;;file://#{File.realpath(dir)}/refs.bib#2\e\\2:"
    end
  end

  def test_biber_build_raises_an_alert
    skip 'biber not installed' unless LaTeXUtils.command_available?('biber')

    build(BIBER_TEX) do |out, code|
      assert_equal 0, code, out
      assert_match(/^\s*2: \S+ Bibliography file: "%DONE" after a field value: '%' does not start a/, out)
    end
  end

  def test_bibtex_failure_names_the_cause
    skip 'bibtex not installed' unless LaTeXUtils.command_available?('bibtex')

    build(BIBTEX_TEX) do |out, _code|
      assert_includes out, "I was expecting a `,' or a `}'---line 2 of file refs.bib."
      assert_includes out, "'%' does not start a comment inside a .bib entry; move the note into a field"
    end
  end
end
