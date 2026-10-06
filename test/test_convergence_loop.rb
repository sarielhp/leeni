#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/leeni/utils'
require_relative '../lib/leeni/builder'
load File.expand_path('../leeni', __dir__)

# Drives run_convergence_loop with a scripted engine: each LaTeX pass "writes"
# the next aux state and the calls made are recorded, so pass accounting can be
# asserted without running TeX.
class TestConvergenceLoop < Minitest::Test
  def in_project(opts = {})
    Dir.mktmpdir('leeni_loop_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('paper.tex', "\\documentclass{article}\n\\begin{document}\nx\n\\end{document}\n")
        yield LatexBuilder.new('paper.tex', { engine: 'xelatex', passes: 3, lock: false, bib: nil }.merge(opts))
      end
    end
  end

  # aux_states[i] is the aux content after LaTeX pass i+1; `initial` is what a
  # previous build left in junk/. bib_stale answers bib_stale_since_last_run?.
  def script(builder, aux_states:, initial: '', bib_stale: [], bib_tool: :bibtex)
    calls = []
    aux = initial
    passes = 0
    builder.define_singleton_method(:compute_aux_hash) { aux }
    builder.define_singleton_method(:log_pass_start) { |*_a, **_k| nil }
    builder.define_singleton_method(:log_bib_start) { |*_a, **_k| nil }
    builder.define_singleton_method(:run_latex_pass) do |_suffix|
      aux = aux_states[[passes, aux_states.size - 1].min]
      passes += 1
      calls << :latex
      true
    end
    builder.define_singleton_method(:detect_bib_tool) { |_aux = nil| bib_tool }
    builder.define_singleton_method(:needs_bib_pass?) { |*_a| calls.count(:bib).zero? }
    builder.define_singleton_method(:run_bib_pass) { |*_a| (calls << :bib) && true }
    builder.send(:bib_manager).define_singleton_method(:bib_stale_since_last_run?) { |*_a| bib_stale.shift || false }
    calls
  end

  def test_single_pass_cap_never_runs_bib_or_a_second_latex_pass
    in_project(passes: 1) do |builder|
      calls = script(builder, aux_states: ['\citation{a}'])
      assert builder.send(:run_convergence_loop)
      assert_equal %i[latex], calls
      refute builder.instance_variable_get(:@cacheable_build), 'a skipped bibliography must not be cached'
    end
  end

  def test_pass_after_bib_is_compared_with_the_aux_the_previous_pass_wrote
    in_project(passes: 2) do |builder|
      calls = script(builder, initial: '\old', aux_states: ['\abx@aux@cite{a}'])
      assert builder.send(:run_convergence_loop)
      assert_equal %i[latex bib latex], calls
      assert builder.instance_variable_get(:@cacheable_build), 'converged at pass 2 but treated as unconverged'
    end
  end

  def test_second_bib_run_when_the_first_is_out_of_date
    in_project(passes: 5) do |builder|
      calls = script(builder, aux_states: %w[a b c c c], bib_stale: [true])
      assert builder.send(:run_convergence_loop)
      assert_equal %i[latex bib latex bib latex latex], calls
    end
  end

  def test_bib_runs_are_capped_and_an_unsatisfied_bibliography_is_not_cached
    in_project(passes: 6) do |builder|
      calls = script(builder, aux_states: %w[a b c d e f], bib_stale: [true] * 20)
      assert builder.send(:run_convergence_loop)
      assert_equal 2, calls.count(:bib)
      refute builder.instance_variable_get(:@cacheable_build)
    end
  end

  def test_stale_bcf_from_an_earlier_biblatex_build_does_not_select_biber
    in_project do |builder|
      File.write('junk/paper.bcf', '<bcf:citekey order="1">a</bcf:citekey>')
      File.write('junk/paper.run.xml', '<requests><external package="biber" active="1"/></requests>')
      aux = "\\relax\n\\citation{a}\n\\bibdata{refs}\n"
      assert_equal :bibtex, builder.detect_bib_tool(aux)
      refute File.exist?('junk/paper.bcf'), 'stale control file should be discarded'
    end
  end

  def test_current_bcf_still_selects_biber
    in_project do |builder|
      File.write('junk/paper.bcf', '<bcf:citekey order="1">a</bcf:citekey>')
      assert_equal :biber, builder.detect_bib_tool("\\relax\n\\abx@aux@cite{0}{a}\n")
    end
  end

  def test_biblatex_bbl_is_discarded_when_no_source_uses_biblatex
    in_project do |builder|
      File.write('refs.bib', "@book{a, title={T}}\n")
      File.write('junk/paper.bbl', "% $ biblatex bbl format version 3.3 $\n")
      FileUtils.cp('junk/paper.bbl', 'paper.bbl')
      File.write('junk/paper.bcf', '<bcf:citekey>a</bcf:citekey>')
      builder.send(:discard_stale_bib_format_files)
      assert_empty Dir['paper.bbl', 'junk/paper.bbl', 'junk/paper.bcf']
    end
  end

  def test_biblatex_bbl_is_kept_when_a_source_uses_biblatex
    in_project do |builder|
      File.write('paper.tex', "\\usepackage{biblatex}\n")
      File.write('junk/paper.bbl', "% $ biblatex bbl format version 3.3 $\n")
      builder.send(:discard_stale_bib_format_files)
      assert File.file?('junk/paper.bbl')
    end
  end

  def test_bibtex_bbl_is_discarded_when_the_document_now_uses_biblatex
    in_project do |builder|
      File.write('paper.tex', "\\usepackage[backend=biber]{biblatex}\n")
      File.write('refs.bib', "@book{a, title={T}}\n")
      File.write('junk/paper.bbl', "\\begin{thebibliography}{1}\n\\end{thebibliography}\n")
      builder.send(:discard_stale_bib_format_files)
      refute File.exist?('junk/paper.bbl')
    end
  end

  def test_commented_out_biblatex_does_not_count_as_use
    in_project do |builder|
      File.write('paper.tex', "% \\usepackage{biblatex}\n")
      File.write('refs.bib', "@book{a, title={T}}\n")
      File.write('junk/paper.bbl', "\\begin{thebibliography}{1}\n\\end{thebibliography}\n")
      builder.send(:discard_stale_bib_format_files)
      assert File.exist?('junk/paper.bbl')
    end
  end

  def test_biblatex_aux_is_discarded_when_no_source_uses_biblatex
    in_project do |builder|
      File.write('junk/paper.aux', "\\relax\n\\abx@aux@cite{0}{a}\n")
      builder.instance_variable_set(:@build_start_time, Time.now)
      builder.send(:discard_stale_bib_format_files)
      refute File.exist?('junk/paper.aux')
    end
  end

  def last_pass_log(builder, pass)
    File.read("#{builder.instance_variable_get(:@pdferr)}_#{pass}")
  end

  def test_default_pass_cap_allows_more_than_three_passes
    assert_operator LaTeXUtils::DEFAULT_PASSES, :>=, 5
    in_project(passes: LaTeXUtils::DEFAULT_PASSES) do |builder|
      calls = script(builder, aux_states: %w[a b c d d])
      assert builder.send(:run_convergence_loop)
      assert_equal 5, calls.count(:latex)
      assert builder.instance_variable_get(:@cacheable_build)
    end
  end

  def test_running_out_of_passes_warns_and_disables_the_cache
    in_project(passes: 3) do |builder|
      calls = script(builder, aux_states: %w[a b c d e])
      FileUtils.mkdir_p('junk')
      builder.send(:run_convergence_loop)
      assert_equal 3, calls.count(:latex)
      refute builder.instance_variable_get(:@cacheable_build)
      assert_match(/LaTeX Warning: leeni: build did not converge; a rerun is still requested after 3 passes/, last_pass_log(builder, 3))
    end
  end

  def test_cycling_aux_state_stops_early_with_a_warning
    in_project(passes: 8) do |builder|
      calls = script(builder, aux_states: %w[a b a b a b a b])
      builder.send(:run_convergence_loop)
      assert_operator calls.count(:latex), :<, 8
      refute builder.instance_variable_get(:@cacheable_build)
      assert_match(/keep cycling/, last_pass_log(builder, calls.count(:latex)))
    end
  end

  def test_unchanged_aux_is_not_mistaken_for_a_cycle
    in_project(passes: 8) do |builder|
      script(builder, aux_states: %w[a a a])
      assert builder.send(:run_convergence_loop)
      assert builder.instance_variable_get(:@cacheable_build)
    end
  end

  def test_last_pass_log_is_numeric_not_lexicographic_and_cleanup_removes_all
    in_project do |builder|
      base = builder.instance_variable_get(:@pdferr)
      FileUtils.mkdir_p(File.dirname(base))
      %i[@log @loga @biberr].each { |v| builder.instance_variable_set(v, "junk/#{v.to_s.delete('@')}.txt") }
      [1, 2, 9, 10].each { |n| File.write("#{base}_#{n}", "pass #{n}") }
      assert_equal "#{base}_10", builder.send(:find_last_latex_log)
      builder.send(:clean_pass_logs)
      assert_empty builder.send(:pass_log_files)
      assert_equal base, builder.send(:find_last_latex_log)
    end
  end

  def test_toc_only_change_requests_another_pass
    in_project(passes: 5) do |builder|
      toc = %w[one two two]
      builder.define_singleton_method(:compute_aux_hash) { 'stable' }
      builder.define_singleton_method(:log_pass_start) { |*_a, **_k| nil }
      calls = []
      builder.define_singleton_method(:run_latex_pass) { |_s| File.write('junk/paper.toc', toc[calls.size]) && (calls << :latex) && true }
      builder.define_singleton_method(:detect_bib_tool) { |_a = nil| nil }
      builder.send(:run_convergence_loop)
      assert_equal 3, calls.size
    end
  end

  def test_rerun_phrase_in_echoed_source_context_is_ignored
    in_project do |builder|
      refute builder.send(:latex_rerun_requested?, "! Undefined control sequence.\nl.12 Please rerun LaTeX before printing\n")
      assert builder.send(:latex_rerun_requested?, "LaTeX Warning: Label(s) may have changed. Rerun to get cross-references right.\n")
    end
  end

  FakeStatus = Struct.new(:ok) do
    def success? = ok
  end

  def test_failed_makeindex_is_reported_retried_and_uncacheable
    in_project(index: true) do |builder|
      File.write('junk/paper.idx', '\\indexentry{a}{1}')
      builder.instance_variable_set(:@cacheable_build, true)
      builder.define_singleton_method(:capture_pass_output) { |_c| ['! bad', FakeStatus.new(false)] }
      _out, err = capture_io { refute builder.send(:run_index_pass) }
      assert_match(/makeindex failed/, err)
      assert builder.send(:needs_index_pass?), 'a failed run must be retried'
      refute builder.instance_variable_get(:@cacheable_build)
      capture_io { builder.send(:run_index_pass) }
      refute builder.send(:needs_index_pass?), 'retries are bounded'
    end
  end

  def test_successful_makeindex_is_not_repeated_for_the_same_idx
    in_project(index: true) do |builder|
      File.write('junk/paper.idx', '\\indexentry{a}{1}')
      File.write('junk/paper.ind', 'x')
      builder.define_singleton_method(:capture_pass_output) { |_c| ['', FakeStatus.new(true)] }
      assert builder.send(:run_index_pass)
      refute builder.send(:needs_index_pass?)
    end
  end

  def aux_names(builder) = builder.send(:bib_manager).current_aux_files.map { |f| File.basename(f) }.sort

  def test_aux_discovery_ignores_old_aux_of_other_documents
    in_project do |builder|
      File.write('junk/paper.aux', "\\relax\n\\@input{ch1.aux}\n")
      File.write('junk/ch1.aux', "\\relax\n\\@input{sub/ch2.aux}\n")
      FileUtils.mkdir_p('junk/sub')
      File.write('junk/sub/ch2.aux', "\\relax\n")
      %w[junk/ch1.aux junk/sub/ch2.aux].each { |f| File.utime(Time.now - 3600, Time.now - 3600, f) }
      File.write('junk/oldpaper.aux', "\\citation{x}\n\\bibdata{refs}\n")
      File.utime(Time.now - 3600, Time.now - 3600, 'junk/oldpaper.aux')
      builder.instance_variable_set(:@build_start_time, Time.now)
      assert_equal %w[ch1.aux ch2.aux paper.aux], aux_names(builder)
      refute_includes builder.compute_aux_hash, 'oldpaper'
    end
  end

  def test_aux_discovery_keeps_unlinked_aux_written_during_this_build
    in_project do |builder|
      File.write('junk/paper.aux', "\\relax\n")
      builder.instance_variable_set(:@build_start_time, Time.now - 10)
      File.write('junk/bu1.aux', "\\relax\n")
      assert_equal %w[bu1.aux paper.aux], aux_names(builder)
    end
  end

  def test_aux_input_cannot_escape_the_junk_directory
    in_project do |builder|
      File.write('outside.aux', "secret\n")
      File.write('junk/paper.aux', "\\@input{../outside.aux}\n")
      builder.instance_variable_set(:@build_start_time, Time.now)
      assert_equal %w[paper.aux], aux_names(builder)
    end
  end

  def test_aux_input_cannot_escape_junk_through_a_symlinked_directory
    in_project do |builder|
      FileUtils.mkdir_p('elsewhere')
      File.write('elsewhere/chapter.aux', "\\citation{x}\n")
      File.symlink(File.expand_path('elsewhere'), 'junk/shared')
      File.write('junk/paper.aux', "\\@input{shared/chapter.aux}\n")
      builder.instance_variable_set(:@build_start_time, Time.now)
      assert_equal %w[paper.aux], aux_names(builder)
    end
  end

  def test_junk_dir_name_with_glob_characters_does_not_touch_a_lookalike_directory
    Dir.mktmpdir('leeni_glob_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p(%w[build1 build[1]])
        File.write('paper.tex', "\\begin{document}x\\end{document}\n")
        File.write('build1/other.aux', "\\abx@aux@cite{0}{a}\n")
        File.write('build1/x.toc', 'toc')
        builder = LatexBuilder.new('paper.tex', { engine: 'xelatex', passes: 3, lock: false, junk_dir: 'build[1]' })
        builder.instance_variable_set(:@build_start_time, Time.now)
        builder.send(:discard_stale_bib_format_files)
        assert File.exist?('build1/other.aux'), 'a lookalike directory was cleaned'
        assert_empty LaTeXUtils.glob_under('build[1]', '**/*.toc')
        File.write('build[1]/a.toc', 'x')
        assert_equal ['build[1]/a.toc'], LaTeXUtils.glob_under('build[1]', '**/*.toc')
      end
    end
  end

  def test_other_documents_biblatex_aux_in_shared_junk_is_kept
    in_project do |builder|
      File.write('junk/paper.aux', "\\relax\n")
      File.write('junk/thesis.aux', "\\abx@aux@cite{0}{a}\n")
      File.utime(Time.now - 3600, Time.now - 3600, 'junk/thesis.aux')
      builder.instance_variable_set(:@build_start_time, Time.now)
      builder.send(:discard_stale_bib_format_files)
      assert File.exist?('junk/thesis.aux')
    end
  end

  def test_supplied_bbl_without_a_bib_database_is_never_discarded
    in_project do |builder|
      File.write('paper.bbl', "% $ biblatex bbl format version 3.3 $\n")
      builder.send(:discard_stale_bib_format_files)
      assert File.exist?('paper.bbl')
    end
  end

  def test_bbl_kept_when_biblatex_is_loaded_by_a_class_file
    in_project do |builder|
      File.write('refs.bib', "@book{a, title={T}}\n")
      File.write('mythesis.cls', "\\RequirePackage[backend=biber]{biblatex}\n")
      File.write('paper.bbl', "% $ biblatex bbl format version 3.3 $\n")
      builder.send(:discard_stale_bib_format_files)
      assert File.exist?('paper.bbl')
    end
  end

  def test_no_bib_option_disables_bbl_discard
    in_project(bib: false) do |builder|
      File.write('refs.bib', "@book{a, title={T}}\n")
      File.write('paper.bbl', "% $ biblatex bbl format version 3.3 $\n")
      builder.send(:discard_stale_bib_format_files)
      assert File.exist?('paper.bbl')
    end
  end

  def test_index_run_between_aux_transitions_is_not_a_cycle
    in_project(passes: 6, index: true) do |builder|
      calls = script(builder, initial: 'A', aux_states: %w[B A A A], bib_tool: nil)
      builder.define_singleton_method(:needs_index_pass?) { calls.count(:index).zero? }
      builder.define_singleton_method(:run_index_pass) { (calls << :index) && true }
      builder.define_singleton_method(:log_index_start) { |*_a, **_k| nil }
      assert builder.send(:run_convergence_loop)
      assert_equal %i[latex index latex latex], calls
      assert builder.instance_variable_get(:@cacheable_build)
    end
  end

  def test_failed_makeindex_is_retried_within_the_loop
    in_project(passes: 4, index: true) do |builder|
      calls = script(builder, aux_states: %w[a a a], bib_tool: nil)
      results = [false, true]
      builder.define_singleton_method(:needs_index_pass?) { calls.count(:index) < 2 }
      builder.define_singleton_method(:run_index_pass) { (calls << :index) && results.shift }
      builder.define_singleton_method(:log_index_start) { |*_a, **_k| nil }
      builder.send(:run_convergence_loop)
      assert_equal 2, calls.count(:index)
      assert_operator calls.count(:latex), :>=, 2, 'a successful retry should be followed by another pass'
    end
  end

  def test_bibliography_stale_at_a_stable_exit_below_the_cap_is_not_cached
    in_project(passes: 8) do |builder|
      calls = script(builder, aux_states: %w[a a a a a a], bib_stale: [true] * 20)
      assert builder.send(:run_convergence_loop)
      assert_operator calls.count(:latex), :<, 8, 'the run must end by stability, not by the cap'
      refute builder.instance_variable_get(:@cacheable_build), 'exit-time bib check is not effective'
    end
  end
end
