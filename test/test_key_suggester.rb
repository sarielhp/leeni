#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'leeni_test_support'

# "Did you mean" for undefined keys: a wrong category prefix or separator is
# a cheaper mistake than a misspelt name.
class TestKeySuggester < LeeniTestBase
  S = LeeniKeySuggester
  LABELS = %w[thm:main_result lem:packing sec:intro eq:1 fig:a].freeze

  def test_wrong_prefix_or_separator_finds_the_label
    assert_equal ['thm:main_result'], S.suggest('lem:main_result', LABELS)
    assert_equal ['thm:main_result'], S.suggest('thm-main-result', LABELS)
    assert_equal ['thm:main_result'], S.suggest('lem_main-result', LABELS)
    assert_equal ['thm:main_result'], S.suggest('main_result', LABELS), 'a missing prefix'
  end

  def test_typos_in_the_name
    assert_equal ['lem:packing'], S.suggest('lem:pakcing', LABELS), 'a swap is one edit'
    assert_equal ['lem:packing'], S.suggest('lem:pacing', LABELS)
    assert_empty S.suggest('sec:intro2x', LABELS), 'two edits in a short name is another name'
    assert_empty S.suggest('eq:2', LABELS), 'short names allow no edit'
    assert_equal ['eq:1'], S.suggest('eqn:1', LABELS), 'but their prefix may differ'
  end

  def test_the_prefix_costs_less_than_an_edit_of_the_name
    assert_equal ['thm:packing'], S.suggest('lem:packing', %w[thm:packing lem:packings])
    assert_equal ['lem:packing'], S.suggest('lem:pakcing', %w[thm:pakcing_x lem:packing]),
                 'a wrong prefix plus an edit loses to the edit alone'
  end

  def test_ties_are_all_named_and_capped
    assert_equal %w[claim:x_y cor:x_y lem:x_y], S.suggest('prop:x_y', %w[thm:x_y lem:x_y cor:x_y claim:x_y])
    assert_empty S.suggest('zzz', LABELS)
    assert_empty S.suggest('thm:main_result', LABELS), 'a defined key suggests nothing'
  end

  def test_case_and_citation_keys
    assert_equal ['HarPeled11'], S.suggest('harpeled11', %w[HarPeled11 knuth84])
    assert_equal ['knuth84'], S.suggest('knuht84', %w[HarPeled11 knuth84])
  end

  MAIN = <<~'TEX'
    \documentclass{article}
    \newtheorem{theorem}{Theorem}
    \begin{document}
    \begin{theorem}\label{thm:main_result}A.\end{theorem}
    See \ref{lem:main_result} and \cite{knuht84}.
    \bibliographystyle{plain}
    \bibliography{refs}
    \end{document}
  TEX

  def test_build_output_suggests_the_defined_keys
    skip 'bibtex not installed' unless system('bibtex --version', out: File::NULL, err: File::NULL)
    Dir.mktmpdir('leeni_key_suggest') do |dir|
      FileUtils.mkdir_p(%w[cache paper].map { |d| File.join(dir, d) })
      saved = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = File.join(dir, 'cache')
      Dir.chdir(File.join(dir, 'paper')) do
        File.write('main.tex', MAIN)
        File.write('refs.bib', "@book{knuth84, author={D. Knuth}, title={T}, year=1984, publisher={P}}\n@string{knuth = \"x\"}\n")
        out, err = capture_io { LatexBuilder.new('main.tex', engine: 'pdflatex', passes: 4, lock: false, force: true).run! }
        text = strip_ansi(out + err).gsub(/\s+/, ' ')
        assert_includes text, "undefined reference 'lem:main_result' (page 1); did you mean 'thm:main_result'?"
        assert_includes text, "undefined citation 'knuht84' (page 1); did you mean 'knuth84'?"
      end
    ensure
      saved ? ENV['XDG_CACHE_HOME'] = saved : ENV.delete('XDG_CACHE_HOME')
    end
  end
end
