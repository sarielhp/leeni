#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

load File.expand_path('../leeni', __dir__)

# The engine's terminal log is the only evidence the tool has about a build.
# These tests pin the three recognisers that read it: the gate that decides a
# pass failed, the pattern that finds a warning, and the bibliography scanner.
class TestLogRecognisers < Minitest::Test
  OPTIONS = {
    engine: 'xelatex', score: false, emacs: true, verbose: false, werror: false,
    suppress_whatevers: true, suppress_warnings: false, suppress_alerts: false,
    alert_overfull_pt: 24.0, whatever_overfull_pt: 2.5, explain: false, passes: 3,
    lock: false
  }.freeze

  def builder(biberr = nil)
    b = LatexBuilder.new('paper.tex', OPTIONS)
    b.instance_variable_set(:@biberr, biberr)
    b
  end

  def with_log(content)
    Dir.mktmpdir('leeni_log_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('junk/err_xelatex_1', content)
        yield 'junk/err_xelatex_1', content
      end
    end
  end

  # TeX echoes the offending paragraph after every Overfull \hbox, so document
  # text reaches the log verbatim. An unanchored substring scan counted it.
  def test_document_text_containing_error_does_not_fail_the_build
    log = <<~LOG
      Overfull \\hbox (7.0pt too wide) in paragraph at lines 21--22
      []\\OT1/cmr/m/n/10 the tool prints Error: no such file when the path is wrong,
      Output written on junk/paper.pdf (1 page).
    LOG

    with_log(log) do |path, content|
      b = builder
      assert_equal 0, b.send(:count_errors_in_log, 0, path),
                   'a document containing the literal "Error:" failed its own successful build'
      assert_equal 0, b.send(:count_latex_errors, content, 0)
    end
  end

  def test_document_text_naming_tex_diagnostics_does_not_fail_the_build
    log = <<~LOG
      Overfull \\hbox (9.0pt too wide) in paragraph at lines 8--9
      []\\OT1/cmr/m/n/10 an Undefined control sequence is what TeX re-ports here,
      Overfull \\hbox (3.0pt too wide) in paragraph at lines 12--13
      []\\OT1/cmr/m/n/10 a Runaway argument? is the other com-mon shape,
    LOG

    with_log(log) do |path, _content|
      assert_equal 0, builder.send(:count_errors_in_log, 0, path)
    end
  end

  def test_document_text_containing_citation_words_not_counted_as_reference_warnings
    echoed_prose_log = <<~LOG
      Overfull \\hbox (7.0pt too wide) in paragraph at lines 21--22
      []\\OT1/cmr/m/n/10 when a citation key is undefined, LaTeX reports it without a reference on this page.
      Overfull \\hbox (5.0pt too wide) in paragraph at lines 25--26
      []\\OT1/cmr/m/n/10 an unnumbered label multiply defined in this context is invalid.
    LOG

    counts = builder.send(:count_reference_messages, echoed_prose_log)
    assert_equal [0, 0, 0], counts,
                 'echoed document text talking about undefined citations/references was counted as real warnings'

    real_warnings_log = <<~LOG
      LaTeX Warning: Citation `foo' on page 1 undefined on input line 5.
      Package natbib Warning: Citation `bar' on page 2 undefined on input line 8.
      LaTeX Warning: Reference `sec:intro' on page 3 undefined on input line 12.
      LaTeX Warning: Label `eq:one' multiply defined.
    LOG

    real_counts = builder.send(:count_reference_messages, real_warnings_log)
    assert_equal [2, 1, 1], real_counts,
                 'authentic citation, reference, and label warnings were not counted correctly'
  end

  def test_real_errors_are_still_counted
    file_line = "./paper.tex:12: LaTeX Error: Environment foo undefined.\nl.12 \\begin{foo}\n"
    bang = "! Undefined control sequence.\nl.5 \\badmacro\n"

    with_log(file_line) do |path, content|
      assert_operator builder.send(:count_errors_in_log, 0, path), :>, 0,
                      'a real file-line-error was not counted'
      assert_operator builder.send(:count_latex_errors, content, 0), :>, 0
    end

    with_log(bang) do |path, _content|
      assert_operator builder.send(:count_errors_in_log, 0, path), :>, 0,
                      'a real "!" error was not counted'
    end
  end

  def test_nonzero_engine_status_always_counts
    with_log("Output written on junk/paper.pdf (1 page).\n") do |path, _content|
      assert_operator builder.send(:count_errors_in_log, 1, path), :>, 0,
                      'a non-zero engine exit status must always count as a failure'
    end
  end

  # The package-name class excluded '.', so pdftex.def / luatex.def / xetex.def
  # warnings were neither a warning start nor a block boundary.
  def test_package_names_containing_a_dot_are_recognised
    log = "Package pdftex.def Warning: Image file `fig1.png' used more than once on input line 42.\n"

    items = builder.send(:extract_warnings, log, false)
    assert_equal 1, items.size, 'a Package <name>.def warning was dropped entirely'
    assert_includes items.first[:text], 'used more than once'
  end

  def test_a_real_warning_is_not_absorbed_into_a_suppressed_whatever
    log = <<~LOG
      LaTeX Font Warning: Some font shapes were not available, defaults substituted.
      Package pdftex.def Warning: Image file `fig1.png' used more than once on input line 42.
    LOG

    b = builder
    items = b.send(:extract_warnings, log, false)
    _alerts, regular, whatevers = b.send(:partition_diagnostics, log, items)

    assert_equal 2, items.size, 'the second warning was glued onto the first'
    assert_equal 1, regular.size, 'the real warning was not reported in the Warnings tier'
    assert_includes regular.first[:text], 'used more than once'
    assert_equal 1, whatevers.size
    refute_includes whatevers.first[:text], 'used more than once',
                    'a real warning was absorbed into a Whatever and suppressed by default'
  end

  def test_underscored_and_starred_package_names_are_recognised
    %w[epstopdf-base fontspec l3backend].each do |pkg|
      log = "Package #{pkg} Warning: something happened on input line 3.\n"
      assert_equal 1, builder.send(:extract_warnings, log, false).size,
                   "a warning from package #{pkg} was dropped"
    end
  end

  def bib_builder(content)
    Dir.mktmpdir('leeni_bib_test') do |dir|
      path = File.join(dir, 'err_bib')
      File.write(path, content)
      yield builder(path)
    end
  end

  # A substring scan for /error/i counted the word wherever it appeared,
  # including inside a path that the tool itself prints back.
  def test_benign_bibliography_output_is_not_an_error
    benign = <<~BIB
      INFO - This is Biber 2.19
      INFO - Found BibTeX data source '/home/me/papers/error-bounds/refs.bib'
      INFO - Overriding locale 'C' with 'en_US.UTF-8'
    BIB

    bib_builder(benign) do |b|
      assert_equal 0, b.send(:count_bib_messages)[:errors],
                   'a .bib path containing the word "error" was counted as a compile error'
    end
  end

  def test_real_bibliography_errors_are_counted
    {
      "ERROR - Cannot find 'refs.bib'!\n" => 'biber ERROR line',
      "I couldn't open database file refs.bib\n" => 'bibtex missing database',
      "(There were 2 error messages)\n" => 'bibtex error summary'
    }.each do |content, label|
      bib_builder(content) do |b|
        assert_operator b.send(:count_bib_messages)[:errors], :>, 0,
                        "#{label} was not counted as an error"
      end
    end
  end

  def test_bibliography_warnings_are_still_counted
    bib_builder("Warning--I didn't find a database entry for \"smith\"\n") do |b|
      assert_operator b.send(:count_bib_messages)[:warns], :>, 0
    end
  end

  def test_benign_bibliography_output_does_not_suppress_other_tiers
    benign = "INFO - Found BibTeX data source 'papers/error-bounds/refs.bib'\n"

    bib_builder(benign) do |b|
      warn_items = []
      err_items = []
      b.send(:append_bib_diagnostics!, warn_items, err_items)
      assert_empty err_items,
                   'a benign INFO line was promoted to an error item, which hides every other tier'
    end
  end

  def test_reported_errors_produce_a_nonzero_exit
    b = builder
    out, = capture_io do
      assert_raises(SystemExit, 'a run reporting errors exited 0') do
        b.send(:summarize_and_check_werror, 2, 0, 0, 0)
      end
    end
    assert_match(/Errors: 2/, out)
  end

  def test_clean_run_does_not_exit
    b = builder
    capture_io { b.send(:summarize_and_check_werror, 0, 0, 1, 0) }
  end

  def test_werror_fails_on_warnings
    b = LatexBuilder.new('paper.tex', OPTIONS.merge(werror: true))
    capture_io do
      assert_raises(SystemExit) { b.send(:summarize_and_check_werror, 0, 0, 1, 0) }
    end
  end

  def test_score_mode_still_honours_werror
    with_log("Overfull \\hbox (30.0pt too wide) in paragraph at lines 3--4\n") do |path, _c|
      b = LatexBuilder.new('paper.tex', OPTIONS.merge(werror: true, score: true))
      b.instance_variable_set(:@biberr, nil)
      capture_io do
        assert_raises(SystemExit, 'l -s -W could not fail on warnings') do
          b.send(:output_score, path, 0)
        end
      end
    end
  end

  def test_undefined_control_sequence_names_the_last_macro_on_the_line
    {
      ['! Undefined control sequence.', 'l.5 \\textbf{Hello} \\badmacro'] => '\\badmacro',
      ['! Undefined control sequence.', 'l.9 \\item Foo \\barbaz'] => '\\barbaz',
      ['! Undefined control sequence.', 'l.3 \\alone'] => '\\alone'
    }.each do |block, expected|
      token = LaTeXErrorCatalog::UNDEFINED_CS_EXTRACTOR.call(nil, block)
      assert_equal expected, token,
                   "named the wrong macro for #{block.last.inspect}"
    end
  end

  def test_recently_read_still_wins
    block = ['! Undefined control sequence.', '<recently read> \\reallyit', 'l.5 \\textbf{x} \\other']
    assert_equal '\\reallyit', LaTeXErrorCatalog::UNDEFINED_CS_EXTRACTOR.call(nil, block)
  end

  def test_consolidate_missing_bib_entries_deduplicates_biber_and_bbl
    b = builder
    warn_items = [
      { file: './bibliography', line: 0, text: "WARN - I didn't find a database entry for 'c-dmr-01' (section 0)" },
      { file: 'junk/book.bbl', line: 0, text: "Package biblatex Warning: Entry 'c-dmr-01' not found in database." }
    ]

    b.send(:consolidate_missing_bib_entries!, warn_items)
    assert_equal 1, warn_items.size
    assert_equal './bibliography', warn_items.first[:file]
    assert_equal 1, warn_items.first[:count]
    assert_includes warn_items.first[:text], "Missing database entry: 'c-dmr-01'"
  end

  def test_consolidate_missing_bib_entries_groups_multiple_keys_cleanly
    b = builder
    keys = %w[h-a6q-61 h-a6f-61 fr-etbs-75 fr-a4s-75 c-dmr-01]
    warn_items = keys.map do |k|
      { file: './bibliography', line: 0, text: "WARN - I didn't find a database entry for '#{k}' (section 0)" }
    end
    # Also add duplicate biblatex .bbl warnings
    warn_items += keys.map do |k|
      { file: 'junk/book.bbl', line: 0, text: "Package biblatex Warning: Entry '#{k}' not found in database." }
    end

    b.send(:consolidate_missing_bib_entries!, warn_items)
    assert_equal 1, warn_items.size
    item = warn_items.first
    assert_equal './bibliography', item[:file]
    assert_equal 5, item[:count]
    assert_includes item[:text], 'Missing database entries (5):'
    refute_includes item[:text], 'WARN - '
    refute_includes item[:text], 'Package biblatex Warning'
    keys.each { |k| assert_includes item[:text], "'#{k}'" }
  end
end
