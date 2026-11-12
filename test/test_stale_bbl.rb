#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'leeni_test_support'

# A .bib edit that removes a macro the old .bbl uses (the fix for an
# "Undefined control sequence" in the bibliography) must not be blocked by that
# old .bbl failing the first pass before biber can regenerate it.
class TestStaleBbl < LeeniTestBase
  MAIN = <<~TEX
    \\documentclass{article}
    \\usepackage[backend=biber]{biblatex}
    \\addbibresource{refs.bib}
    \\begin{document}
    \\cite{k}
    \\printbibliography
    \\end{document}
  TEX
  BIB = "@article{k, author={A. Author}, title={Title}, journal={J}, year=2000}\n"

  def options(extra = {})
    { engine: 'pdflatex', passes: 4, lock: false, force: true }.merge(extra)
  end

  def with_project
    Dir.mktmpdir('leeni_stale_bbl') do |dir|
      cache = File.join(dir, 'cache')
      project = File.join(dir, 'paper')
      FileUtils.mkdir_p([cache, project])
      saved = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = cache
      Dir.chdir(project) do
        File.write('main.tex', MAIN)
        File.write('refs.bib', BIB)
        capture_io { assert LatexBuilder.new('main.tex', options).run!, 'initial build failed' }
        yield LeeniBuildWorkspace.cache_dir('.')
      end
    ensure
      saved ? ENV['XDG_CACHE_HOME'] = saved : ENV.delete('XDG_CACHE_HOME')
    end
  end

  # Both copies of the .bbl use a macro nobody defines and predate the .bib.
  def poison_bbl(junk_dir)
    old = Time.now - 3600
    [File.join(junk_dir, 'main.bbl'), 'main.bbl'].each do |bbl|
      next unless File.file?(bbl)

      File.write(bbl, File.read(bbl).sub('{Title}', '{Title\\GoneMacro}'))
      File.utime(old, old, bbl)
    end
  end

  def test_stale_bbl_failing_the_first_pass_is_regenerated
    skip 'biber not installed' unless system('biber --version', out: File::NULL, err: File::NULL)
    with_project do |junk_dir|
      poison_bbl(junk_dir)
      out, err = capture_io { assert LatexBuilder.new('main.tex', options).run!, 'stale .bbl blocked the build' }
      refute_includes strip_ansi(out + err), 'GoneMacro'
      refute_includes File.read(File.join(junk_dir, 'main.bbl')), 'GoneMacro'
    end
  end

  def test_biber_error_names_the_bib_file_not_its_temporary_copy
    output = <<~LOG
      INFO - Found BibTeX data source '/home/u/paper/guarding.bib'
      ERROR - BibTeX subsystem: /tmp/biber_tmp_MwUb/66b2_2502359.utf8, line 37, syntax error: found "@article"
    LOG
    detail = LaTeXBibManager.allocate.send(:bibliography_failure_detail, output)
    assert_includes detail, 'BibTeX subsystem: guarding.bib, line 37'
    refute_includes detail, 'biber_tmp'
  end

  # biblatex sits behind a conditional that is off (a submission-version flag),
  # so the document uses BibTeX, but the .bbl next to it is the biblatex one an
  # earlier build left: it must be regenerated, not fail with a missing package.
  BIBTEX_MAIN = <<~'TEX'
    \newif\ifbiblatex
    \documentclass{article}
    \ifbiblatex\usepackage{biblatex}\fi
    \begin{document}
    \cite{k}
    \bibliographystyle{plain}
    \bibliography{refs}
    \end{document}
  TEX
  BIBLATEX_BBL = <<~'BBL'
    % $ biblatex auxiliary file $
    % $ biblatex bbl format version 3.3 $
    \begingroup
    \makeatletter
    \@ifundefined{ver@biblatex.sty}
      {\@latex@error
         {Missing 'biblatex' package}
         {The bibliography requires the 'biblatex' package.}
          \aftergroup\endinput}
      {}
    \endgroup
    \refsection{0}
    \endrefsection
  BBL

  def test_biblatex_bbl_under_bibtex_is_regenerated
    skip 'bibtex not installed' unless system('bibtex --version', out: File::NULL, err: File::NULL)
    Dir.mktmpdir('leeni_foreign_bbl') do |dir|
      with_cache(dir) do
        File.write('main.tex', BIBTEX_MAIN)
        File.write('refs.bib', BIB)
        File.write('main.bbl', BIBLATEX_BBL)
        File.utime(Time.now + 60, Time.now + 60, 'main.bbl')
        out, err = capture_io { assert LatexBuilder.new('main.tex', options).run!, 'biblatex .bbl blocked the build' }
        refute_includes strip_ansi(out + err), 'Missing'
        assert_includes File.read('main.bbl'), '\begin{thebibliography}'
      end
    end
  end

  # -c rebuilds the bibliography from the .bib files instead of seeding the
  # wiped build directory from the working-tree .bbl.
  def test_clean_build_regenerates_working_tree_bbl
    skip 'bibtex not installed' unless system('bibtex --version', out: File::NULL, err: File::NULL)
    Dir.mktmpdir('leeni_clean_bbl') do |dir|
      with_cache(dir) do
        File.write('main.tex', BIBTEX_MAIN.gsub(/^.*biblatex.*\n/, ''))
        File.write('refs.bib', BIB)
        File.write('main.bbl', "\\begin{thebibliography}{1}\n\\bibitem{k} Old \\GoneMacro Entry.\n\\end{thebibliography}\n")
        File.utime(Time.now + 60, Time.now + 60, 'main.bbl')
        capture_io { assert LatexBuilder.new('main.tex', options(clean: true)).run!, 'clean build failed' }
        refute_includes File.read('main.bbl'), 'GoneMacro'
      end
    end
  end

  # With no .bib to regenerate it, a failing .bbl is input, not cache: no
  # recovery rebuild, and the report says the .bbl is the likely culprit.
  def test_unregenerable_bbl_error_names_the_bbl
    Dir.mktmpdir('leeni_orphan_bbl') do |dir|
      with_cache(dir) do
        File.write('main.tex', BIBTEX_MAIN.gsub(/^.*biblatex.*\n/, ''))
        File.write('main.bbl', "\\begin{thebibliography}{1}\n\\bibitem{k} Old \\GoneMacro Entry.\n\\end{thebibliography}\n")
        out, err = capture_io { assert_raises(SystemExit) { LatexBuilder.new('main.tex', options).run! } }
        text = strip_ansi(out + err)
        assert_includes text, 'cannot regenerate this .bbl'
        refute_includes text, 'cleaned the build directory'
      end
    end
  end

  def with_cache(dir, &)
    cache = File.join(dir, 'cache')
    project = File.join(dir, 'paper')
    FileUtils.mkdir_p([cache, project])
    saved = ENV.fetch('XDG_CACHE_HOME', nil)
    ENV['XDG_CACHE_HOME'] = cache
    Dir.chdir(project, &)
  ensure
    saved ? ENV['XDG_CACHE_HOME'] = saved : ENV.delete('XDG_CACHE_HOME')
  end
end
