#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'leeni_test_support'

# The .bbl is judged stale by the content of the files the bibliography run
# read (from its .blg), not by modification times.
class TestBblProvenance < LeeniTestBase
  P = LeeniBblProvenance

  def test_biber_log_gives_every_data_source_but_remote_ones
    Dir.mktmpdir('leeni_prov') do |dir|
      blg = File.join(dir, 'main.blg')
      File.write(blg, <<~LOG)
        [60] Biber.pm:421> INFO - Reading '#{dir}/main.bcf'
        [138] bibtex.pm:1519> INFO - Found BibTeX data source '/papers/refs.bib'
        [139] biblatexml.pm:200> INFO - Found biblatexml data source 'extra.bltxml'
        [140] bibtex.pm:1519> INFO - Found BibTeX data source 'https://example.org/x.bib'
      LOG
      assert_equal ['/papers/refs.bib', File.join(dir, 'extra.bltxml')], P.logged_inputs(:biber, blg, dir, {})
    end
  end

  def test_bibtex_log_names_are_resolved_like_bibtex_does
    Dir.mktmpdir('leeni_prov') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'sub'))
      File.write(File.join(dir, 'sub', 'refs.bib'), "@misc{k}\n")
      blg = File.join(dir, 'main.blg')
      File.write(blg, <<~LOG)
        The top-level auxiliary file: main.aux
        A level-1 auxiliary file: ch.aux
        The style file: plain.bst
        Database file #1: sub/refs.bib
        Database file #2: nowhere.bib
      LOG
      inputs = P.logged_inputs(:bibtex, blg, dir, {})
      assert_equal File.join(dir, 'sub', 'refs.bib'), inputs.last
      assert_match(%r{/plain\.bst\z}, inputs.first) if system('kpsewhich plain.bst', out: File::NULL)
      refute(inputs.any? { |p| p.end_with?('nowhere.bib', '.aux') })
    end
  end

  def test_staleness_follows_content_not_timestamps
    Dir.mktmpdir('leeni_prov') do |dir|
      bib = File.join(dir, 'refs.bib')
      bbl = File.join(dir, 'main.bbl')
      File.write(bib, "@misc{k}\n")
      File.write(bbl, "\\begin{thebibliography}{1}\\bibitem{k}x\\end{thebibliography}\n")
      assert_nil P.stale_verdict(dir, bbl), 'no record yet'

      P.record(dir, bbl, [bib])
      refute P.stale_verdict(dir, bbl)
      future = Time.now + 60
      File.utime(future, future, bib)
      refute P.stale_verdict(dir, bbl), 'a touch is not a change'

      File.write(bib, "@misc{k, title={T}}\n")
      File.utime(Time.now - 3600, Time.now - 3600, bib)
      assert P.stale_verdict(dir, bbl), 'an older timestamp hides no edit'

      FileUtils.rm_f(bib)
      assert P.stale_verdict(dir, bbl), 'a vanished input is a change'

      File.write(bbl, "something else\n")
      assert_nil P.stale_verdict(dir, bbl), 'a .bbl from elsewhere has no record'
    end
  end

  def test_empty_input_list_leaves_no_record
    Dir.mktmpdir('leeni_prov') do |dir|
      bbl = File.join(dir, 'main.bbl')
      File.write(bbl, "x\n")
      P.record(dir, bbl, [])
      refute File.exist?(File.join(dir, P::RECORD))
      assert_nil P.stale_verdict(dir, bbl)
    end
  end

  # A project-local .bst is now an input: editing it reruns BibTeX, while
  # touching the .bib without changing it does not.
  def test_bst_edit_reruns_bibtex_and_a_touch_does_not
    skip 'bibtex not installed' unless system('kpsewhich plain.bst', out: File::NULL)
    with_bibtex_project do |junk_dir|
      assert File.file?(File.join(junk_dir, P::RECORD)), 'first bib run left no record'

      future = Time.now + 60
      File.utime(future, future, 'refs.bib')
      refute_includes build_output, 'bibtex'

      File.write('mine.bst', "#{File.read('mine.bst')}\n% edited\n")
      assert_includes build_output, 'bibtex'
    end
  end

  # The record covers only the databases it lists: switching \bibliography to
  # another file reruns BibTeX even though every recorded input is unchanged.
  def test_a_newly_named_database_is_not_covered_by_the_record
    skip 'bibtex not installed' unless system('kpsewhich plain.bst', out: File::NULL)
    with_bibtex_project do |_junk_dir|
      File.write('other.bib', File.read('refs.bib'))
      File.write('main.tex', File.read('main.tex').sub('\bibliography{refs}', '\bibliography{other}'))
      assert_includes build_output, 'bibtex'
    end
  end

  private

  def options = { engine: 'pdflatex', passes: 4, lock: false, force: true }

  def build_output
    out, err = capture_io { assert LatexBuilder.new('main.tex', options).run! }
    strip_ansi(out + err)
  end

  def with_bibtex_project
    Dir.mktmpdir('leeni_prov_build') do |dir|
      cache = File.join(dir, 'cache')
      project = File.join(dir, 'paper')
      FileUtils.mkdir_p([cache, project])
      saved = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = cache
      Dir.chdir(project) do
        FileUtils.cp(`kpsewhich plain.bst`.strip, 'mine.bst')
        File.write('refs.bib', "@article{k, author={A. Author}, title={Title}, journal={J}, year=2000}\n")
        File.write('main.tex', "\\documentclass{article}\n\\begin{document}\n\\cite{k}\n" \
                               "\\bibliographystyle{mine}\n\\bibliography{refs}\n\\end{document}\n")
        assert_includes build_output, 'bibtex'
        yield LeeniBuildWorkspace.cache_dir('.')
      end
    ensure
      saved ? ENV['XDG_CACHE_HOME'] = saved : ENV.delete('XDG_CACHE_HOME')
    end
  end
end
