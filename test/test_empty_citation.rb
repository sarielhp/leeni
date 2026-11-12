#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'leeni_test_support'

# An empty citation key (\cite{}[note], the note written after the command) is
# reported at its source line, in place of LaTeX's line-less "Citation `'
# undefined" and BibTeX's missing entry "".
class TestEmptyCitation < LeeniTestBase
  def scan(source)
    Dir.mktmpdir('leeni_empty_cite') do |dir|
      path = File.join(dir, 'doc.tex')
      File.write(path, source)
      LaTeXBraceChecker.check_empty_citations(path).map { |a| [a[:line], a[:text]] }
    end
  end

  def test_empty_keys_are_reported_with_their_line_and_command
    found = scan(<<~'TEX')
      As \cite{}[Matousek, Thm 2] shows.
      See \citep[p.~3]{ } and \parencite*{}.
      Fine: \cite{k}, \cite[p.~3]{k}, \nocite{*}.
      % \cite{} in a comment
      \newcommand{\mycite}{\cite{}}
    TEX
    assert_equal [1, 2, 2], found.map(&:first)
    assert_equal 'Empty \cite{}: the [...] after it is plain text; write \cite[note]{key}', found[0][1]
    assert_includes found[1][1], 'Empty \citep{}: give a key'
    assert_includes found[2][1], '\parencite[note]{key}'
  end

  MAIN = <<~'TEX'
    \documentclass{article}
    \begin{document}
    As shown \cite{}[Matousek, Thm 2] and \cite{k}.
    \bibliographystyle{plain}
    \bibliography{refs}
    \end{document}
  TEX

  def build(final: false)
    Dir.mktmpdir('leeni_empty_cite_build') do |dir|
      FileUtils.mkdir_p(%w[cache paper].map { |d| File.join(dir, d) })
      saved = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = File.join(dir, 'cache')
      Dir.chdir(File.join(dir, 'paper')) do
        File.write('main.tex', MAIN)
        File.write('refs.bib', "@book{k, author={A}, title={T}, year=2000, publisher={P}}\n")
        opts = { engine: 'pdflatex', passes: 4, lock: false, force: true, final: final }
        out, err = capture_io do
          LatexBuilder.new('main.tex', opts).run!
        rescue SystemExit
          nil
        end
        strip_ansi(out + err)
      end
    ensure
      saved ? ENV['XDG_CACHE_HOME'] = saved : ENV.delete('XDG_CACHE_HOME')
    end
  end

  def test_build_reports_the_source_line_instead_of_the_empty_citation_warnings
    skip 'bibtex not installed' unless system('bibtex --version', out: File::NULL, err: File::NULL)
    text = build
    assert_match(/^3: .*Empty \\cite\{\}: the \[\.\.\.\] after it is plain text/, text)
    refute_includes text, "Citation `'"
    refute_includes text, 'database entry for ""'
  end

  def test_final_profile_makes_it_an_error
    skip 'bibtex not installed' unless system('bibtex --version', out: File::NULL, err: File::NULL)
    assert_match(/Errors: [1-9]/, build(final: true))
  end
end
