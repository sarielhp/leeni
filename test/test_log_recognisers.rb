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

    items = builder.send(:extract_warnings, log, verbose: false)
    assert_equal 1, items.size, 'a Package <name>.def warning was dropped entirely'
    assert_includes items.first[:text], 'used more than once'
  end

  def test_a_real_warning_is_not_absorbed_into_a_suppressed_whatever
    log = <<~LOG
      LaTeX Font Warning: Some font shapes were not available, defaults substituted.
      Package pdftex.def Warning: Image file `fig1.png' used more than once on input line 42.
    LOG

    b = builder
    items = b.send(:extract_warnings, log, verbose: false)
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
      assert_equal 1, builder.send(:extract_warnings, log, verbose: false).size,
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

  def test_cannot_write_file_counts_as_single_error
    log = <<~LOG
      ! I can't write on file "01_min_disk/junk/page_number.txt".
      (Press Enter to retry or type a new filename)
      Please type another input file name:
      01_min_disk/min_disk.tex:15: Emergency stop.
      <to be read again>
      \\relax
      l.15 \\ChapterGen
                     {Minimum Enclosing Disk}{min_disk}{
      01_min_disk/min_disk.tex:15:  ==> Fatal error occurred, no output PDF file produced!
    LOG

    b = builder
    assert_equal 1, b.send(:count_latex_errors, log, 0)
  end

  # TeX reaches \end{document} inside a group it never closed, notes it in
  # parentheses, and exits 0 with a PDF. The source is malformed, so the note
  # is promoted to an error carrying the line TeX recorded.
  def test_end_inside_unclosed_group_is_an_error
    log = <<~LOG
      [1{/var/lib/texmf/fonts/map/pdftex/updmap/pdftex.map}] (./paper.aux) )
      (\\end occurred inside a group at level 1)

      ### simple group (level 1) entered at line 7 ({)
      ### bottom level
      Output written on junk/paper.pdf (1 page).
    LOG

    with_log(log) do |path, content|
      b = builder
      assert_equal 1, b.send(:count_errors_in_log, 0, path),
                   'an unclosed group at \\end{document} was not counted as an error'
      assert_equal 1, b.send(:count_latex_errors, content, 0)

      errors = b.send(:extract_errors, content)
      assert_equal 1, errors.size
      assert_equal 7, errors.first[:line]
      assert_equal :unclosed_group_at_end, errors.first[:catalog_id]
      assert_includes errors.first[:text], 'leeni flags it as an error'
    end
  end

  def test_end_inside_unfinished_conditional_is_an_error
    log = <<~LOG
      (./paper.aux) )
      (\\end occurred when \\ifx on line 12 was incomplete)
      (\\end occurred when \\ifnum on line 3 was incomplete)
      Output written on junk/paper.pdf (1 page).
    LOG

    with_log(log) do |path, content|
      b = builder
      assert_equal 2, b.send(:count_errors_in_log, 0, path)
      assert_equal([12, 3], b.send(:extract_errors, content).map { |e| e[:line] })
    end
  end

  # The promotion must stay inert on clean logs and on document text that
  # merely talks about groups.
  def test_group_promotion_leaves_ordinary_logs_alone
    log = <<~LOG
      []\\OT1/cmr/m/n/10 the note (\\end occurred inside a group) is discussed below.
      ### simple group (level 1) entered at line 7 ({)
      Output written on junk/paper.pdf (1 page).
    LOG

    with_log(log) do |path, _content|
      assert_equal 0, builder.send(:count_errors_in_log, 0, path)
    end
  end

  # \include of a missing file only prints "No file foo.tex." and continues;
  # the chapter is silently absent from the PDF.
  def test_missing_include_target_is_an_error
    log = <<~LOG
      No file paper.aux.
      No file chapter_missing.tex.
      No file paper.bbl.
      Output written on junk/paper.pdf (1 page).
    LOG

    with_log(log) do |path, content|
      b = builder
      assert_equal 1, b.send(:count_errors_in_log, 0, path),
                   'a missing \\include target was not counted, or the .aux/.bbl notes were'
      errors = b.send(:extract_errors, content)
      assert_equal([:include_target_missing], errors.map { |e| e[:catalog_id] })
      assert_equal 'chapter_missing.tex', errors.first[:catalog][:token]
    end
  end

  # One error per distinct glyph and font, with the repeat count folded in.
  def test_missing_characters_are_errors_folded_per_glyph
    log = <<~LOG
      Missing character: There is no 你 (U+4F60) in font [lmroman10-regular]:mapping=tex-text;!
      Missing character: There is no 你 (U+4F60) in font [lmroman10-regular]:mapping=tex-text;!
      Missing character: There is no ^^A in font cmr10!
      Output written on junk/paper.pdf (1 page).
    LOG

    with_log(log) do |path, content|
      b = builder
      assert_equal 2, b.send(:count_errors_in_log, 0, path)
      errors = b.send(:extract_errors, content)
      assert_equal(%i[missing_character missing_character], errors.map { |e| e[:catalog_id] })
      assert_includes errors[0][:text], 'in font lmroman10-regular'
      assert_includes errors[0][:text], '(2 occurrences)'
      assert_equal '你', errors[0][:catalog][:token]
      refute_includes errors[1][:text], 'occurrences'
    end
  end

  # \tracinglostchars=3: pdfTeX/XeTeX raise "! Missing character" and LuaTeX
  # adds an l.<line> context; either way the error carries the exact line.
  def test_missing_character_error_form_keeps_exact_line
    log = <<~LOG
      ! Missing character: There is no Ł ("141) in font cmmi12.
      l.162 $\\L_u$
                  . Note, that this
      ! Missing character: There is no Ł ("141) in font cmmi12.
      l.170 $\\L_v$

      Output written on paper.pdf (1 page).
    LOG

    with_log(log) do |_path, content|
      errors = builder.send(:extract_errors, content)
      assert_equal([:missing_character], errors.map { |e| e[:catalog_id] })
      assert_equal 162, errors.first[:line].to_i
      assert_includes errors.first[:text], '(2 occurrences)'
      refute_includes errors.first[:text], 'TeX only notes this'
      assert_equal 'Ł', errors.first[:catalog][:token]
    end
  end

  # leeni runs TeX with -file-line-error, so the error names an \input file.
  def test_missing_character_file_line_form_keeps_file_and_line
    log = <<~LOG
      ./chapters/intro.tex:162: Missing character: There is no Ł ("141) in font cmmi12.
      l.162 $\\L_u$

      Output written on paper.pdf (1 page).
    LOG

    with_log(log) do |_path, content|
      errors = builder.send(:extract_errors, content)
      assert_equal([:missing_character], errors.map { |e| e[:catalog_id] })
      assert_equal 162, errors.first[:line].to_i
      assert_includes errors.first[:file].to_s, 'intro.tex'
    end
  end

  def test_no_pages_of_output_is_an_error
    log = "(./paper.aux) )\nNo pages of output.\nTranscript written on paper.log.\n"

    with_log(log) do |path, content|
      b = builder
      assert_equal 1, b.send(:count_errors_in_log, 0, path)
      assert_equal([:no_pages_of_output], b.send(:extract_errors, content).map { |e| e[:catalog_id] })
    end
  end

  # An empty output is a consequence of a real compiler error, and a
  # bibliography-only body has no pages until the bibliography tool has run,
  # so neither case may raise a second, misleading error.
  def test_no_pages_of_output_is_not_promoted_when_explained
    after_error = "./paper.tex:3: Undefined control sequence.\nl.3 \\typo\nNo pages of output.\n"
    pending_bib = "No file paper.bbl.\nPackage biblatex Warning: Please (re)run Biber on the file:\nNo pages of output.\n"

    with_log(after_error) do |_path, content|
      refute_includes LaTeXUtils.filter_subcommand_noise(content), '[leeni] No pages of output'
    end
    with_log(pending_bib) do |path, content|
      assert_equal 0, builder.send(:count_errors_in_log, 0, path)
      refute_includes LaTeXUtils.filter_subcommand_noise(content), '[leeni]'
    end
  end
end
