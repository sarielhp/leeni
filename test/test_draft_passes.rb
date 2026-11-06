#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/leeni/utils'
require_relative '../lib/leeni/builder'

# Draft passes: which passes may skip the PDF (decided before they run), and
# the guarantee that the last pass of every build is a regular one.
class TestDraftPasses < Minitest::Test
  BIBLATEX_DOC = <<~'TEX'
    \documentclass{article}
    \usepackage{biblatex}
    \addbibresource{refs.bib}
    \begin{document}
    \input{body}
    \printbibliography
    \end{document}
  TEX
  PLAIN_DOC = "\\documentclass{article}\n\\begin{document}\nx\\label{a}\\ref{a}\n\\end{document}\n"
  INDEX_DOC = "\\documentclass{article}\n\\usepackage{makeidx}\n\\makeindex\n" \
              "\\begin{document}\nx\\index{x}\n\\printindex\n\\end{document}\n"

  def in_project(tex, opts = {})
    Dir.mktmpdir('leeni_draft_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('paper.tex', tex)
        File.write('body.tex', "See \\cite{knuth}.\n")
        File.write('refs.bib', "@book{knuth, author={D. Knuth}, title={T}, year={1984}, publisher={P}}\n")
        defaults = { engine: 'lualatex', passes: 5, lock: false, bib: nil, junk_dir: 'junk', draft_passes: true }
        yield LatexBuilder.new('paper.tex', defaults.merge(opts))
      end
    end
  end

  def reason(builder, pass = 1, max = 5) = builder.send(:draft_reason, pass, max)

  def test_fresh_bibliography_drafts_the_first_pass_only
    in_project(BIBLATEX_DOC) do |b|
      assert_equal :bib, reason(b)
      assert_nil reason(b, 2), 'only the pass before the first bib run is predictable'
    end
  end

  def test_pass_budget_must_leave_room_for_the_next_pass
    in_project(BIBLATEX_DOC, passes: 1) { |b| assert_nil reason(b, 1, 1) }
  end

  def test_switches_and_modes_that_keep_every_pass_regular
    [{ draft_passes: false }, { single_pass: true }, { raw: true }, { bib: false }].each do |opts|
      in_project(BIBLATEX_DOC, opts) { |b| assert_nil reason(b), opts.inspect }
    end
  end

  def test_engines
    %w[pdflatex lualatex xelatex].each do |engine|
      in_project(BIBLATEX_DOC, engine: engine) { |b| assert_equal :bib, reason(b), engine }
    end
    in_project(BIBLATEX_DOC) do |b|
      b.instance_variable_set(:@engine_name, 'latex')
      assert_nil reason(b), 'dvi engines have no draft mode'
    end
  end

  def test_document_without_bibliography_never_drafts
    in_project(PLAIN_DOC) { |b| assert_nil reason(b) }
  end

  def test_a_commented_out_bibliography_is_not_a_bibliography
    in_project(BIBLATEX_DOC.sub('\addbibresource', '% \addbibresource')) { |b| assert_nil reason(b) }
  end

  def test_existing_bibliography_drafts_only_when_its_database_changed
    in_project(BIBLATEX_DOC) do |b|
      File.write('junk/paper.aux', "\\abx@aux@cite{0}{knuth}\n")
      File.write('junk/paper.bbl', "\\entry{knuth}{book}{}\n")
      past = Time.now - 100
      File.utime(past, past, 'refs.bib')
      assert_nil reason(b), 'an unchanged database is no reason to expect biber'
      File.utime(Time.now + 10, Time.now + 10, 'refs.bib')
      assert_equal :bib, reason(b)
    end
  end

  def test_bbl_without_entries_can_still_be_current
    in_project(PLAIN_DOC.sub('x', '\cite{none}\bibliography{refs}')) do |b|
      File.write('junk/paper.aux', "\\citation{none}\n\\bibdata{refs}\n")
      File.write('junk/paper.bbl', "\\begin{thebibliography}{}\n\\end{thebibliography}\n")
      File.utime(Time.now - 100, Time.now - 100, 'refs.bib')
      assert_nil reason(b), 'an empty bibliography that covers the citations needs no bibtex'
    end
  end

  def test_biblatex_without_an_earlier_aux_always_asks_for_biber
    in_project(BIBLATEX_DOC) do |b|
      File.write('junk/paper.bbl', "\\entry{knuth}{book}{}\n")
      File.utime(Time.now - 100, Time.now - 100, 'refs.bib')
      assert_equal :bib, reason(b)
    end
  end

  def test_missing_index_drafts_once
    in_project(INDEX_DOC, index: true) do |b|
      b.instance_variable_set(:@draft_reasons_used, [])
      assert_equal :index, reason(b)
      b.instance_variable_set(:@draft_reasons_used, [:index])
      assert_nil reason(b, 2), 'a wrong index prediction must not repeat'
    end
    in_project(INDEX_DOC, index: true) do |b|
      File.write('junk/paper.ind', "\\begin{theindex}\\end{theindex}\n")
      assert_nil reason(b)
    end
    in_project(INDEX_DOC) { |b| assert_nil reason(b), 'makeindex runs only with --index' }
  end

  def test_draft_command_and_log
    in_project(BIBLATEX_DOC, engine: 'pdflatex') do |b|
      b.send(:setup_environment)
      refute_includes b.send(:build_latex_pass_cmd), '-draftmode'
      b.instance_variable_set(:@draft_pass, true)
      assert_includes b.send(:build_latex_pass_cmd), '-draftmode'
      log = "a\npdfTeX warning: \\pdfdraftmode enabled, not changing output pdf\n" \
            "warning  (pdf backend): draftmode enabled, not changing output pdf\nb\n"
      assert_equal "a\nb\n", b.send(:strip_draft_notice, log)
    end
    in_project(BIBLATEX_DOC, engine: 'xelatex') do |b|
      b.send(:setup_environment)
      b.instance_variable_set(:@draft_pass, true)
      assert_includes b.send(:build_latex_pass_cmd), '-no-pdf'
    end
  end

  # Scripted engine: records whether each LaTeX pass was a draft.
  def script(builder, bib_wanted:, bib_fatal: false, aux_states: ['\abx@aux@cite{0}{knuth}'])
    calls = []
    aux = ''
    builder.define_singleton_method(:compute_aux_hash) { aux }
    builder.define_singleton_method(:log_pass_start) { |*_a, **_k| nil }
    builder.define_singleton_method(:log_bib_start) { |*_a, **_k| nil }
    builder.define_singleton_method(:run_latex_pass) do |_suffix|
      aux = aux_states[[calls.count { |c| c != :bib }, aux_states.size - 1].min]
      calls << (@draft_pass ? :draft : :latex)
      true
    end
    builder.define_singleton_method(:detect_bib_tool) { |_aux = nil| :biber }
    builder.define_singleton_method(:needs_bib_pass?) { |*_a| bib_wanted && calls.count(:bib).zero? }
    builder.define_singleton_method(:run_bib_pass) { |*_a| (calls << :bib) && true }
    builder.define_singleton_method(:bib_fatal?) { bib_fatal }
    builder.send(:bib_manager).define_singleton_method(:bib_stale_since_last_run?) { |*_a| false }
    calls
  end

  def test_draft_then_bib_then_regular_passes
    in_project(BIBLATEX_DOC) do |b|
      calls = script(b, bib_wanted: true)
      assert b.send(:run_convergence_loop)
      assert_equal %i[draft bib latex], calls
      assert_equal 1, b.send(:build_report)[:draft_passes]
    end
  end

  def test_draft_that_turned_out_last_gets_a_regular_pass
    in_project(BIBLATEX_DOC) do |b|
      calls = script(b, bib_wanted: false)
      assert b.send(:run_convergence_loop)
      assert_equal %i[draft latex], calls
      refute File.exist?('junk/paper.pdf'), 'the draft removed the previous PDF'
    end
  end

  def test_failed_bibliography_after_a_draft_still_writes_the_pdf
    in_project(BIBLATEX_DOC) do |b|
      calls = script(b, bib_wanted: true, bib_fatal: true)
      refute b.send(:run_convergence_loop)
      assert_equal %i[draft bib latex], calls
    end
  end

  def test_draft_removes_the_previous_pdf
    in_project(BIBLATEX_DOC) do |b|
      File.write('junk/paper.pdf', '%PDF old')
      script(b, bib_wanted: true)
      b.send(:run_convergence_loop)
      refute File.exist?('junk/paper.pdf'), 'no stale PDF may survive a draft pass'
    end
  end

  def test_no_bibliography_runs_only_regular_passes
    in_project(PLAIN_DOC) do |b|
      calls = script(b, bib_wanted: false, aux_states: ['\newlabel{a}{{1}{1}}'])
      assert b.send(:run_convergence_loop)
      assert_equal %i[latex latex], calls
      assert_nil b.send(:build_report)[:draft_passes]
    end
  end

  def test_single_pass_is_regular
    in_project(BIBLATEX_DOC, single_pass: true) do |b|
      calls = script(b, bib_wanted: true)
      assert b.send(:run_convergence_loop)
      assert_equal %i[latex], calls
    end
  end

  def test_cli_flag_and_config_key
    load File.expand_path('../leeni', __dir__) unless defined?(LatexCLI)
    parse = lambda do |cfg, argv|
      options = LatexCLI.build_default_options(cfg, 'l', [])
      LatexCLI.build_option_parser(options).parse!(argv)
      options[:draft_passes]
    end
    refute parse.call({}, [])
    assert parse.call({ 'draft_passes' => true }, [])
    refute parse.call({ 'draft_passes' => false }, [])
    refute parse.call({}, %w[--no-draft-passes])
    assert parse.call({ 'draft_passes' => false }, %w[--draft-passes])
  end
end
