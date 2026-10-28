#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'leeni_test_support'

class TestLeeniDiagnostics < LeeniTestBase
  def test_report_errors_suppresses_warnings
    Dir.mktmpdir do |dir|
      log_file = File.join(dir, 'err_xelatex_1')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        LaTeX Warning: Reference `sec:unknown` undefined on input line 42.
        Overfull \\hbox (15.0pt too wide) in paragraph at lines 10--15
        ! LaTeX Error: File `missing.sty` not found.
        )
      LOG
      File.write(log_file, log_content)

      builder = legacy_builder('main.tex', {})
      out, err = capture_io do
        assert_raises(SystemExit) do
          builder.send(:report_errors, log_file)
        end
      end

      # Errors should be displayed on stderr
      assert_empty out
      assert_includes err, 'LaTeX Error: File `missing.sty` not found'
      # Warnings should be suppressed from the displayed body
      refute_includes err, 'Reference `sec:unknown` undefined'
      refute_includes err, 'Overfull \hbox'
      # But count is still reported in summary on stderr
      assert_includes err, 'Errors: 1'
      assert_includes err, 'Warnings: 2'
    end
  end

  def test_compilation_failure_concise_single_line_status
    builder = legacy_builder('main.tex', color: false)
    msg = builder.send(:format_compilation_failure, 1)
    assert_equal 'Latex compilation failed! (Status: 1)', msg

    crash_msg = builder.send(:format_engine_crash, 11)
    assert_equal 'Latex engine terminated by signal 11 (fatal crash)', crash_msg
  end

  def test_alerts_and_warnings_display_by_default
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        LaTeX Warning: Reference `sec:unknown` undefined on page 1.
        Overfull \\hbox (15.0pt too wide) in paragraph at lines 10--15
        Overfull \\hbox (30.0pt too wide) in paragraph at lines 20--21
        (./main.aux
        )
        )
      LOG
      File.write(log_file, log_content)

      # Default: both alerts and warnings are displayed
      builder = legacy_builder('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end

      plain = strip_ansi(out)
      assert_includes plain, '(1 alert, 2 warnings)'
      assert_includes plain, '30.00pt too wide'
      assert_includes plain, "undefined reference 'sec:unknown'"
      assert_includes plain, 'Errors: 0'
      assert_includes plain, 'Alerts: 1'
      refute_includes plain, '(❕ suppressed)'
      refute_includes plain, '(Warnings suppressed)'

      # When suppress_warnings: true, warnings are suppressed
      suppressed_builder = legacy_builder('main.tex', suppress_warnings: true)
      out_supp, = capture_io do
        Dir.chdir(dir) do
          suppressed_builder.send(:analyze_output)
        end
      end

      plain_supp = strip_ansi(out_supp)
      assert_includes plain_supp, '(1 alert)'
      refute_includes plain_supp, 'warnings)'
      assert_includes plain_supp, '30.00pt too wide'
      refute_includes plain_supp, "undefined reference 'sec:unknown'"
      assert_includes plain_supp, 'Warnings: 2'
      assert_includes plain_supp, '(❕ suppressed)'
    end
  end

  def test_overfull_hbox_alert_threshold
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        Overfull \\hbox (10.0pt too wide) in paragraph at lines 5--8
        Overfull \\hbox (35.0pt too wide) detected at line 42
        )
      LOG
      File.write(log_file, log_content)

      builder = legacy_builder('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end

      plain = strip_ansi(out)
      assert_includes plain, '(1 alert, 1 warning)'
      assert_includes plain, '35.00pt too wide'
      assert_includes plain, '10.00pt too wide'
      assert_includes plain, 'Errors: 0'
      assert_includes plain, 'Alerts: 1'
      assert_includes plain, 'Warnings: 1'
      assert_includes plain, 'Whatevers: 0'

      # Test custom threshold
      custom_builder = legacy_builder('main.tex', alert_overfull_pt: 50.0)
      out_custom, = capture_io do
        Dir.chdir(dir) do
          custom_builder.send(:analyze_output)
        end
      end

      # Under 50pt threshold, both are warnings (0 alerts)
      plain_custom = strip_ansi(out_custom)
      refute_includes plain_custom, 'alert)'
      assert_includes plain_custom, '(2 warnings)'
      assert_includes plain_custom, '35.00pt too wide'
      assert_includes plain_custom, '10.00pt too wide'
      assert_includes plain_custom, 'Errors: 0'
      assert_includes plain_custom, 'Alerts: 0'
      assert_includes plain_custom, 'Warnings: 2'
    end
  end

  def test_whatevers_classification_and_suppression
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        Overfull \\hbox (2.09996pt too wide) in paragraph at lines 20--25
        Package hyperref Warning: Token not allowed in a PDF string (PDFDocEncoding): removing `\\mathshift'
        LaTeX Warning: `!h' float specifier changed to `!ht' on input line 50.
        LaTeX Warning: There were multiply-defined labels.
        )
      LOG
      File.write(log_file, log_content)

      # By default, whatevers are suppressed
      builder = legacy_builder('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end

      plain = strip_ansi(out)
      refute_includes plain, '2.09996pt too wide'
      refute_includes plain, 'Token not allowed in a PDF string'
      assert_includes plain, '✔ No errors/alerts/warnings.'
      refute_includes plain, '(Whatevers suppressed)'

      # With all: true, whatevers are displayed
      all_builder = legacy_builder('main.tex', all: true, suppress_whatevers: false)
      out_all, = capture_io do
        Dir.chdir(dir) do
          all_builder.send(:analyze_output)
        end
      end

      plain_all = strip_ansi(out_all)
      assert_includes plain_all, '(4 whatevers)'
      assert_includes plain_all, '2.10pt too wide'
      assert_includes plain_all, 'Token not allowed in a PDF string'
      assert_includes plain_all, 'float specifier changed to'
      assert_includes plain_all, 'Whatevers: 4'
      refute_includes plain_all, '(Whatevers suppressed)'
    end
  end

  def test_boxed_explanations_with_explain_flag
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        (./main.aux
        LaTeX Warning: Label `sec:first` multiply defined.
        LaTeX Warning: Label `sec:second` multiply defined.
        )
        )
      LOG
      File.write(log_file, log_content)

      # Without explain flag: no explanation box
      builder = legacy_builder('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          assert_raises(SystemExit) { builder.send(:analyze_output) }
        end
      end
      refute_includes out, 'Diagnostic Explanation'

      # With explain: true: boxed explanation printed only on first occurrence
      expl_builder = legacy_builder('main.tex', explain: true)
      out_expl, = capture_io do
        Dir.chdir(dir) do
          assert_raises(SystemExit) { expl_builder.send(:analyze_output) }
        end
      end

      plain_expl = strip_ansi(out_expl)
      assert_includes plain_expl, 'Diagnostic Explanation: Error: Multiply-Defined Label'
      assert_includes plain_expl, 'Why: Two or more \label{...} tags share the identical key'
      assert_includes plain_expl, 'Fix: Search your .tex sources for \label{<key>}'
      assert_includes plain_expl, '┌─ Diagnostic Explanation'
      assert_includes plain_expl, '└'

      # Count occurrences of Diagnostic Explanation: must be exactly 1 despite 2 duplicate labels!
      assert_equal 1, plain_expl.scan('Diagnostic Explanation').size
    end
  end

  def test_boxed_explanation_for_underfull_line
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        Underfull \\hbox (badness 10000) in paragraph at lines 256--256
        )
      LOG
      File.write(log_file, log_content)

      builder = legacy_builder('main.tex', explain: true)
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end

      plain = strip_ansi(out)
      assert_includes plain, '256: ❕ underfull \hbox (badness 10000)'
      assert_includes plain, 'Diagnostic Explanation: Note: Underfull \hbox (Loose Line)'
      assert_includes plain, 'TeX stretched inter-word spacing excessively'
      assert_includes plain, 'Might fix: Remove trailing \\\\ before blank lines'
      assert_includes plain, 'See: https://sarielhp.github.io/leeni/docs/guides/underfull_boxes/'
    end
  end

  def test_boxed_explanation_for_underfull_vbox
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        Underfull \\vbox (badness 10000) has occurred while \\output is active []
        )
      LOG
      File.write(log_file, log_content)

      builder = legacy_builder('main.tex', explain: true)
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end

      plain = strip_ansi(out)
      assert_includes plain, 'Diagnostic Explanation: Warning: Underfull \vbox (Vertical Stretch)'
      assert_includes plain, 'TeX could not stretch vertical whitespace'
      assert_includes plain, 'Might fix: Add \\raggedbottom to preamble'
      assert_includes plain, 'See: https://sarielhp.github.io/leeni/docs/guides/underfull_boxes/'
    end
  end

  def test_underfull_box_terminal_hyperlink_when_link_enabled
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        Underfull \\hbox (badness 10000) in paragraph at lines 256--256
        )
      LOG
      File.write(log_file, log_content)

      # 1. Without link: plain text, no OSC 8 link to guide
      builder_no_link = legacy_builder('main.tex', link: false)
      out_no_link, = capture_io do
        Dir.chdir(dir) do
          builder_no_link.send(:analyze_output)
        end
      end
      refute_includes out_no_link, "\e]8;;https://sarielhp.github.io"
      assert_includes out_no_link, 'underfull \hbox (badness 10000)'

      # 2. With link: true: clean OSC 8 embedded on underfull \hbox
      builder_link = legacy_builder('main.tex', link: true)
      out_link, = capture_io do
        Dir.chdir(dir) do
          builder_link.send(:analyze_output)
        end
      end
      expected_osc8 = "\e]8;;https://sarielhp.github.io/leeni/docs/guides/underfull_boxes/\e\\underfull \\hbox\e]8;;\e\\"
      assert_includes out_link, expected_osc8
    end
  end

  def test_multiply_defined_label_pinpointing_in_diagnostics
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        (./chap1.tex
        LIT_LBL:42:\\newlabel{sec:dup}{{1}{1}}
        )
        (./chap2.tex
        LIT_LBL:88:\\newlabel{sec:dup}{{2}{1}}
        )
        (./main.aux
        LaTeX Warning: Label `sec:dup' multiply defined.
        )
        )
      LOG
      File.write(log_file, log_content)

      builder = legacy_builder('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          assert_raises(SystemExit) { builder.send(:analyze_output) }
        end
      end
      plain = strip_ansi(out)
      assert_includes plain, 'chap1.tex'
      assert_includes plain, '42:'
      assert_includes plain, "label 'sec:dup' duplicate (also at chap2.tex:88)"
      assert_includes plain, "label 'sec:dup' duplicate (also at chap1.tex:42)"
      refute_includes plain, 'main.aux'
    end
  end

  def test_custom_whatever_pt_threshold
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        Overfull \\hbox (4.0pt too wide) in paragraph at lines 10--12
        )
      LOG
      File.write(log_file, log_content)

      # Default threshold 2.5pt: 4.0pt is a Warning
      builder = legacy_builder('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end
      plain = strip_ansi(out)
      assert_includes plain, 'Warnings: 1'
      assert_includes plain, 'Whatevers: 0'

      # Custom threshold 5.0pt: 4.0pt is demoted to Whatever (suppressed)
      custom_builder = legacy_builder('main.tex', whatever_overfull_pt: 5.0)
      out_custom, = capture_io do
        Dir.chdir(dir) do
          custom_builder.send(:analyze_output)
        end
      end
      plain_custom = strip_ansi(out_custom)
      assert_includes plain_custom, '✔ No errors/alerts/warnings.'
      refute_includes plain_custom, '(Whatevers suppressed)'
    end
  end

  def test_path_hash_and_project_tmp_file
    Dir.mktmpdir do |dir1|
      Dir.mktmpdir do |dir2|
        b1 = legacy_builder(File.join(dir1, 'main.tex'), {})
        b2 = legacy_builder(File.join(dir2, 'main.tex'), {})

        refute_equal b1.send(:path_hash), b2.send(:path_hash)

        lock1 = b1.send(:project_tmp_file, 'build.lock')
        lock2 = b2.send(:project_tmp_file, 'build.lock')

        refute_equal lock1, lock2
        user = ENV['USER'] || 'user'
        refute_includes lock1, "/tmp/#{user}"
        assert_equal File.join(Dir.tmpdir, "leeni_#{Process.uid}"), File.dirname(lock1)
        assert_includes lock1, 'main_build.lock'
      end
    end
  end

  def test_with_lock_blocks_concurrent_runs
    Dir.mktmpdir do |dir|
      builder = legacy_builder(File.join(dir, 'paper.tex'), lock: true)
      executed = false

      builder.send(:with_lock) do
        executed = true
        # While locked, another process or thread attempting non-blocking lock should fail
        lock_file = builder.send(:project_tmp_file, 'build.lock')
        assert File.exist?(lock_file)

        File.open(lock_file, File::RDWR) do |f2|
          assert_equal false, f2.flock(File::LOCK_EX | File::LOCK_NB)
        end
      end

      assert executed
    end
  end

  def test_save_build_state_detects_mutation_during_build
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        tex = 'paper.tex'
        File.write(tex, "Original content\n")
        FileUtils.mkdir_p('junk')
        File.write('junk/paper.pdf', 'dummy pdf')
        File.write('paper.pdf', 'dummy pdf')

        builder = legacy_builder(tex, lock: true)
        builder.send(:snapshot_build_inputs!)

        # User modifies paper.tex during compilation
        File.write(tex, "Modified content with typo fix\n")

        builder.send(:save_build_state!)

        # Build state must be discarded because paper.tex was mutated!
        refute File.exist?('junk/.build_state.json')
        refute builder.send(:targets_up_to_date?)
      end
    end
  end

  def test_save_build_state_clean_enables_targets_up_to_date
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        tex = 'paper.tex'
        File.write(tex, "Stable content\n")
        FileUtils.mkdir_p('junk')
        File.write('junk/paper.pdf', 'dummy pdf')
        File.write('paper.pdf', 'dummy pdf')

        builder = legacy_builder(tex, lock: true)
        builder.send(:snapshot_build_inputs!)

        builder.send(:save_build_state!)

        # Build state must be saved cleanly
        assert File.exist?('junk/.build_state.json')
        assert builder.send(:targets_up_to_date?)
      end
    end
  end

  def test_count_errors_in_log_ignores_multiply_defined_warnings
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        log_file = 'junk/test.log'
        File.write(log_file, "LaTeX Warning: Label `foo' multiply defined.\n")

        builder = legacy_builder('paper.tex', {})

        # A multiply-defined label is an Alert, not a compile error, so it must
        # not push the pass-failure gate above zero. This replaces a test that
        # asserted count_errors_in_log wrote a counter file to the temp
        # directory -- a write-only side effect of a method named "count" that
        # nothing in the codebase ever read.
        assert_equal 0, builder.send(:count_errors_in_log, 0, log_file)
      end
    end
  end

  def test_brace_checker_detects_unclosed_brace_in_small_latex_example
    latex = <<~LATEX
      \\documentclass{article}
      \\begin{document}
      \\begin{equation*}
        E = \\frac{m{c^2}
      \\end{equation*}
      \\end{document}
    LATEX
    errs = LaTeXBraceChecker.new('paper.tex', latex).scan
    assert_equal 1, errs.size
    err = errs.first
    assert_equal 4, err[:line]
    assert_equal 12, err[:col]
    assert_includes err[:text], "inside environment 'equation*'"
    assert_includes err[:text], 'E = \\frac{m{c^2}'
  end

  def test_builder_check_source_braces_on_small_latex_file
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('paper.tex', <<~LATEX)
          \\documentclass{article}
          \\begin{document}
          \\begin{theorem}
            Let $X$ be { unclosed.
          \\end{theorem}
          \\end{document}
        LATEX
        builder = legacy_builder('paper.tex', {})
        errs = builder.send(:check_source_braces)
        assert_equal 1, errs.size
        err = errs.first
        assert_equal 4, err[:line]
        assert_equal 14, err[:col]
        assert_includes err[:text], "inside environment 'theorem'"
        assert_includes err[:text], '! [leeni] Unclosed open brace'
        assert_includes err[:text], 'l.4   Let $X$ be { unclosed.'
      end
    end
  end

  def test_brace_checker_detects_mismatched_bracket_alert
    snippet = "\\begin{equation*}\n  \\frac{Y_{i-1}{2].\n\\end{equation*}\n"
    errs = LaTeXBraceChecker.new('test.tex', snippet).scan
    alert_err = errs.find { |e| e[:has_alert] }
    refute_nil alert_err
    assert_equal 2, alert_err[:line]
    assert_includes alert_err[:text], "Probable mistype at line 2:18 of '}' as ']'"
    assert_includes alert_err[:text], "inside environment 'equation*'"
  end

  def test_brace_checker_ignores_bourbaki_and_half_open_intervals
    snippet = <<~LATEX
      \\begin{theorem}
        Let $x \\in [0, 1)$ and $y \\in ]0, 1]$. We have $\\mathbf{P}[ X \\in (0, 1] ] = 1$.
      \\end{theorem}
    LATEX
    errs = LaTeXBraceChecker.new('test.tex', snippet).scan
    assert_empty errs
  end

  def test_brace_checker_ignores_verbatim_blocks
    snippet = <<~LATEX
      \\begin{document}
      \\begin{verbatim}
        This is { unclosed in verbatim
      \\end{verbatim}
      Text with \\verb|{ unclosed| here.
      \\end{document}
    LATEX
    errs = LaTeXBraceChecker.new('test.tex', snippet).scan
    assert_empty errs
  end

  def test_brace_checker_detects_extra_closing_brace
    snippet = "\\begin{document}\nhello}\n\\end{document}\n"
    errs = LaTeXBraceChecker.new('test.tex', snippet).scan
    assert_equal 1, errs.size
    assert_includes errs.first[:text], "Extra closing brace '}'"
  end

  def test_compiler_environment_sets_max_print_line
    builder = legacy_builder('main.tex', {})
    env = builder.send(:pass_environment)
    assert_equal '2048', env['max_print_line']
  end

  def test_atomic_copy_replaces_target_atomically
    Dir.mktmpdir do |dir|
      src = File.join(dir, 'source.pdf')
      dst = File.join(dir, 'final.pdf')
      File.write(src, '%PDF-1.4 dummy new')
      File.write(dst, '%PDF-1.4 dummy old')

      builder = legacy_builder('main.tex', {})
      builder.send(:atomic_copy, src, dst)

      assert_equal '%PDF-1.4 dummy new', File.read(dst)
      assert_empty Dir.glob(File.join(dir, '*.tmp*'))
    end
  end

  def test_atomic_copy_failure_preserves_existing_target
    Dir.mktmpdir do |dir|
      missing_src = File.join(dir, 'missing.pdf')
      dst = File.join(dir, 'final.pdf')
      File.write(dst, '%PDF-1.4 known good')

      builder = legacy_builder('main.tex', {})
      assert_raises(Errno::ENOENT) { builder.send(:atomic_copy, missing_src, dst) }

      assert_equal '%PDF-1.4 known good', File.read(dst)
      assert_empty Dir.glob(File.join(dir, '*.tmp*'))
    end
  end

  def test_discover_bib_files_includes_aux_bibdata_and_subdirectories
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        FileUtils.mkdir_p('refs')
        File.write('refs/extra.bib', '@article{...}')
        File.write('junk/main.aux', "\\bibdata{extra}\n")

        builder = legacy_builder('main.tex', {})
        bibs = builder.send(:discover_bib_files)
        assert_includes bibs, 'refs/extra.bib'
      end
    end
  end

  def test_discover_bib_files_includes_bcf_datasources
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        FileUtils.mkdir_p('custom_bibs')
        File.write('custom_bibs/chapter.bib', '@article{...}')
        bcf = '<bcf:datasource type="file" datatype="bibtex">custom_bibs/chapter.bib</bcf:datasource>'
        File.write('junk/main.bcf', bcf)

        builder = legacy_builder('main.tex', {})
        bibs = builder.send(:discover_bib_files)
        assert_includes bibs, 'custom_bibs/chapter.bib'
      end
    end
  end

  def test_capture_pass_output_executes_and_terminates_on_timeout
    builder = legacy_builder('main.tex', timeout: 1)
    out, status = builder.send(:capture_pass_output, %w[sleep 5])
    refute status.success?
    assert_includes out, 'Compilation timed out'
  end

  def test_strip_latex_comments_parity_and_line_preservation
    raw = <<~TEX
      \\documentclass{article}
      % This is a full comment line
      Some text with \\% literal percent
      Line ending with double backslash\\\\% and a comment
      Another line % inline comment
    TEX

    stripped = LaTeXUtils.strip_latex_comments(raw)
    assert_equal raw.lines.count, stripped.lines.count
    assert_includes stripped, '\\documentclass{article}'
    assert_includes stripped, 'Some text with \\% literal percent'
    assert_includes stripped, "Line ending with double backslash\\\\\n"
    refute_includes stripped, 'This is a full comment line'
    refute_includes stripped, 'and a comment'
    refute_includes stripped, 'inline comment'
  end

  def test_format_trace_command_includes_cwd_and_overrides
    builder = legacy_builder('main.tex', trace: true)
    env = ENV.to_h.merge('TEXINPUTS' => '.:custom_styles:', 'max_print_line' => '2048')
    cmd = ['xelatex', '-output-directory=junk', 'main.tex']
    formatted = builder.send(:format_trace_command, env, cmd, '/tmp/doc')

    assert_includes formatted, 'cd /tmp/doc'
    assert_includes formatted, 'TEXINPUTS=.:custom_styles:'
    assert_includes formatted, 'max_print_line=2048'
    assert_includes formatted, 'xelatex -output-directory=junk main.tex'
  end

  def test_trace_output_during_pass_execution
    builder = legacy_builder('main.tex', trace: true, timeout: 5)
    out_capture = StringIO.new
    orig_stdout = $stdout
    begin
      $stdout = out_capture
      _out, status = builder.send(:capture_pass_output, %w[echo trace_test])
      assert status.success?
    ensure
      $stdout = orig_stdout
    end

    trace_log = out_capture.string
    assert_includes trace_log, '[trace]'
    assert_includes trace_log, 'echo trace_test'
    assert_includes trace_log, 'exit status 0'
  end

  def test_indicator_suppressed_for_fast_actions
    out, = capture_io do
      LaTeXIndicator.start('Fast action...', enabled: true, delay: 0.2)
      sleep 0.05
      LaTeXIndicator.stop(clear: true, enabled: true)
    end
    assert_empty out
  end

  def test_indicator_renders_for_slow_actions
    out, = capture_io do
      LaTeXIndicator.start('Slow action...', enabled: true, delay: 0.05)
      sleep 0.12
      LaTeXIndicator.stop(clear: true, enabled: true)
    end
    assert_includes out, 'Slow action...'
    assert_includes out, "\e[2K"
  end

  def test_sync_bbl_before_compile_trace_only
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        bbl_content = "\\begin{thebibliography}{1}\n\\bibitem{a} Test\n\\end{thebibliography}\n"
        File.write('junk/paper.bbl', bbl_content)

        # Without trace: do not contaminate root
        builder = legacy_builder('paper.tex', {})
        builder.send(:sync_bbl_before_compile)
        refute File.exist?('paper.bbl')

        # With trace: promote to root
        builder_trace = legacy_builder('paper.tex', trace: true)
        builder_trace.send(:sync_bbl_before_compile)
        assert File.exist?('paper.bbl')
        assert_equal bbl_content, File.read('paper.bbl')
      end
    end
  end

  def test_sync_bbl_to_root_promotes_bbl_when_trace_active
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        bbl_content = "\\begin{thebibliography}{1}\n\\bibitem{b} Another\n\\end{thebibliography}\n"
        File.write('junk/paper.bbl', bbl_content)

        builder = legacy_builder('paper.tex', trace: true)
        builder.send(:sync_bbl_to_root)

        assert File.exist?('paper.bbl')
        assert_equal bbl_content, File.read('paper.bbl')
      end
    end
  end

  class TestDiagnosticsHelper
    include LaTeXDiagnostics

    attr_accessor :options, :filename, :bfilename

    def initialize(filename = 'main.tex', options = {})
      @filename = filename
      @options = options
      @bfilename = File.basename(filename, '.*')
    end
  end

  def test_throttle_errors_caps_first_file_at_ten
    diag = TestDiagnosticsHelper.new('main.tex', {})
    errors = (1..15).map { |i| { file: 'ch1.tex', line: i, text: "Error #{i}" } }
    displayed, info = diag.send(:throttle_errors, errors)

    assert_equal 10, displayed.size
    refute_nil info
    assert_equal 5, info[:remaining_in_first]
    assert_empty info[:other_files]
  end

  def test_throttle_errors_stops_after_first_file
    diag = TestDiagnosticsHelper.new('main.tex', {})
    ch1_errors = (1..3).map { |i| { file: 'ch1.tex', line: i, text: "Ch1 Error #{i}" } }
    ch2_errors = (1..5).map { |i| { file: 'ch2.tex', line: i, text: "Ch2 Error #{i}" } }
    displayed, info = diag.send(:throttle_errors, ch1_errors + ch2_errors)

    assert_equal 3, displayed.size
    refute_nil info
    assert_equal 0, info[:remaining_in_first]
    assert_equal ['ch2.tex'], info[:other_files]
    assert_equal 5, info[:other_errors_count]
  end

  def test_throttle_errors_bypassed_with_all_option
    diag = TestDiagnosticsHelper.new('main.tex', all: true)
    ch1_errors = (1..15).map { |i| { file: 'ch1.tex', line: i, text: "Error #{i}" } }
    ch2_errors = (1..5).map { |i| { file: 'ch2.tex', line: i, text: "Error #{i}" } }
    displayed, info = diag.send(:throttle_errors, ch1_errors + ch2_errors)

    assert_equal 20, displayed.size
    assert_nil info
  end

  def test_print_cascade_notice_output
    diag = TestDiagnosticsHelper.new('main.tex', {})
    info = {
      first_file: 'ch1.tex',
      remaining_in_first: 4,
      other_files: %w[ch2.tex ch3.tex],
      other_errors_count: 12
    }
    io = StringIO.new
    diag.send(:print_cascade_notice, info, io: io)
    out = io.string

    assert_includes out, '4 more errors in ch1.tex were truncated'
    assert_includes out, '12 more errors were detected across 2 other files'
    assert_includes out, 'ch2.tex, ch3.tex'
    assert_includes out, "Run with 'l -a' / '--all'"

    # Truncation with ... when > 4 other files
    info_many = {
      first_file: 'ch1.tex',
      remaining_in_first: 0,
      other_files: %w[ch2.tex ch3.tex ch4.tex ch5.tex ch6.tex],
      other_errors_count: 20
    }
    io_many = StringIO.new
    diag.send(:print_cascade_notice, info_many, io: io_many)
    out_many = io_many.string
    assert_includes out_many, 'ch2.tex, ch3.tex, ch4.tex'
    assert_includes out_many, '...'
    refute_includes out_many, 'more files'
  end

  def test_primary_error_file_prefers_compiler_errors_over_synthetic_checks
    diag = TestDiagnosticsHelper.new('main.tex', {})
    groups = {
      'synthetic_ch.tex' => [{ file: 'synthetic_ch.tex', line: 10, source: :leeni, synthetic: true }],
      'compiler_ch.tex' => [{ file: 'compiler_ch.tex', line: 20, source: :compiler, synthetic: false }]
    }

    assert_equal 'compiler_ch.tex', diag.send(:primary_error_file, groups)
  end

  def test_compiler_indicates_brace_error
    diag = TestDiagnosticsHelper.new('main.tex', {})
    assert diag.send(:compiler_indicates_brace_error?, 'Runaway argument?\n{something')
    assert diag.send(:compiler_indicates_brace_error?, 'File ended while scanning use of \foo')
    assert diag.send(:compiler_indicates_brace_error?, 'Extra }, or forgotten \endgroup')
    refute diag.send(:compiler_indicates_brace_error?, 'Missing $ inserted.')
    refute diag.send(:compiler_indicates_brace_error?, 'Undefined control sequence.')
  end

  def test_error_items_have_source_and_synthetic_flags
    brace_errs = LaTeXBraceChecker.new('test.tex', "x}y\n").scan
    assert_equal 1, brace_errs.size
    assert_equal :leeni, brace_errs.first[:source]
    assert_equal true, brace_errs.first[:synthetic]

    diag = TestDiagnosticsHelper.new('main.tex', {})
    lines = ['./test.tex:10: Undefined control sequence.']
    err_item, = diag.send(:build_error_entry, lines, 0, './test.tex', [])
    assert_equal :compiler, err_item[:source]
    assert_equal false, err_item[:synthetic]
  end

  def test_print_summary_line_suppression_tag
    diag = TestDiagnosticsHelper.new('main.tex', {})

    # All non-errors suppressed
    io = StringIO.new
    diag.send(:print_summary_line, 5, 10, 15, 20, suppressed_alerts: true, suppressed_warnings: true, suppressed_whatevers: true, io: io)
    plain = strip_ansi(io.string)
    assert_includes plain, '🛑 Errors: 5, 🚨 Alerts: 10, ❕ Warnings: 15, ☕ Whatevers: 20  (non-errors suppressed)'

    # Specific tiers suppressed (with badges)
    io = StringIO.new
    diag.send(:print_summary_line, 0, 0, 3, 4, suppressed_warnings: false, suppressed_whatevers: true, io: io)
    plain = strip_ansi(io.string)
    assert_includes plain, '🛑 Errors: 0, 🚨 Alerts: 0, ❕ Warnings: 3, ☕ Whatevers: 4  (☕ suppressed)'

    # Specific tiers suppressed (without badges)
    diag_no_badges = TestDiagnosticsHelper.new('main.tex', badges: false)
    io_nb = StringIO.new
    diag_no_badges.send(:print_summary_line, 0, 0, 3, 4, suppressed_warnings: false, suppressed_whatevers: true, io: io_nb)
    plain_nb = strip_ansi(io_nb.string)
    assert_includes plain_nb, 'Errors: 0, Alerts: 0, Warnings: 3, Whatevers: 4  (Whatevers suppressed)'

    # Nothing suppressed
    io = StringIO.new
    diag.send(:print_summary_line, 0, 1, 2, 3, io: io)
    plain = strip_ansi(io.string)
    assert_includes plain, '🛑 Errors: 0, 🚨 Alerts: 1, ❕ Warnings: 2, ☕ Whatevers: 3'
    refute_includes plain, 'suppressed'
  end

  def test_print_summary_line_clean_state
    diag = TestDiagnosticsHelper.new('main.tex', {})

    # 1. Default (whatevers suppressed by default): all non-suppressed zero
    io = StringIO.new
    diag.send(:print_summary_line, 0, 0, 0, 0, io: io)
    plain = strip_ansi(io.string)
    assert_includes plain, '✔ No errors/alerts/warnings.'

    # 2. Suppressed whatevers are present (>0), but all non-suppressed are zero
    io = StringIO.new
    diag.send(:print_summary_line, 0, 0, 0, 5, io: io)
    plain = strip_ansi(io.string)
    assert_includes plain, '✔ No errors/alerts/warnings.'
    refute_includes plain, 'whatevers'

    # 3. With whatevers unsuppressed (e.g. -a / --all), all four zero
    diag_all = TestDiagnosticsHelper.new('main.tex', suppress_whatevers: false)
    io = StringIO.new
    diag_all.send(:print_summary_line, 0, 0, 0, 0, io: io)
    plain = strip_ansi(io.string)
    assert_includes plain, '✔ No errors/alerts/warnings/whatevers.'

    # 4. With warnings suppressed (-W), all non-suppressed zero
    diag_nowarn = TestDiagnosticsHelper.new('main.tex', suppress_warnings: true)
    io = StringIO.new
    diag_nowarn.send(:print_summary_line, 0, 0, 3, 0, io: io)
    plain = strip_ansi(io.string)
    assert_includes plain, '✔ No errors/alerts.'
  end

  def test_graceful_interrupt_handling
    out_err = StringIO.new
    orig_stderr = $stderr
    $stderr = out_err
    begin
      exit_status = nil
      begin
        LatexCLI.handle_interrupt(nil, Interrupt.new)
      rescue SystemExit => e
        exit_status = e.status
      end

      assert_equal 130, exit_status
      output = out_err.string
      assert_includes output, 'Build cancelled by user (Ctrl-C)'
      refute_includes output, 'Traceback'
      refute_includes output, 'from '
    ensure
      $stderr = orig_stderr
    end
  end

  def test_subcommand_interrupt_exits_with_signal_status
    Dir.mktmpdir('leeni_sigint') do |dir|
      tex = File.join(dir, 'slow.tex')
      File.write(tex, "\\documentclass{article}\n\\begin{document}\n\\loop\\iftrue\\repeat\n\\end{document}\n")
      cmd = [BIN, '-f', 'slow.tex']
      Open3.popen2e(*cmd, chdir: dir) do |_stdin, stdout_err, wait_thr|
        sleep 0.6
        begin
          Process.kill('INT', wait_thr.pid)
        rescue StandardError
          nil
        end
        output = stdout_err.read
        status = wait_thr.value
        exit_code = status.exitstatus || (status.signaled? ? 128 + status.termsig : nil)
        assert_equal 130, exit_code
        assert_includes output, 'Build cancelled by user (Ctrl-C)'
        refute_includes output, 'Traceback'
        refute_includes output, 'from /'
      end
    end
  end

  def test_group_diagnostics_by_file_with_ordered_tiers
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        (./chap1.tex
        Overfull \\hbox (10.0pt too wide) in paragraph at lines 150--152
        Overfull \\hbox (40.0pt too wide) in paragraph at lines 20--25
        Overfull \\hbox (60.0pt too wide) in paragraph at lines 80--85
        LaTeX Warning: Reference `sec:foo` undefined on page 1.
        )
        (./chap2.tex
        Overfull \\hbox (5.0pt too wide) in paragraph at lines 30--32
        )
        )
      LOG
      File.write(log_file, log_content)

      builder = legacy_builder('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end

      plain = strip_ansi(out)

      # Chap1 has 2 alerts (40pt, 60pt) and 2 warnings (10pt, ref undefined)
      assert_includes plain, '── chap1.tex (2 alerts, 2 warnings) ──'
      assert_equal 1, plain.scan(/── chap1\.tex/).size

      # Chap2 has only 1 warning (5pt)
      assert_includes plain, '── chap2.tex (1 warning) ──'
      assert_equal 1, plain.scan(/── chap2\.tex/).size

      # In chap1: alerts must come first (sorted by lines 20 then 80), then warnings (sorted by lines)
      chap1_block = plain.split('── chap2.tex').first
      alert20_pos = chap1_block.index('40.00pt too wide')
      alert80_pos = chap1_block.index('60.00pt too wide')
      warn10_pos = chap1_block.index('10.00pt too wide')
      warn_ref_pos = chap1_block.index("undefined reference 'sec:foo'")

      assert alert20_pos < alert80_pos, 'Alert on line 20 should come before alert on line 80'
      assert alert80_pos < warn_ref_pos, 'All alerts should come before warnings'
      assert warn_ref_pos < warn10_pos, 'Warnings should be sorted by line number'
    end
  end

  # Duplicate labels silently rebind every \ref, so they leave the alert tier
  # and fail the build; the PDF is still exported because the per-pass gate
  # only counts compiler errors.
  def test_duplicate_labels_are_promoted_to_errors
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'err_xelatex'), <<~LOG)
        (./main.tex
        LaTeX Warning: Reference `sec:unknown` undefined on page 1.
        (./main.aux
        LaTeX Warning: Label `sec:dup` multiply defined.
        )
        )
      LOG

      builder = legacy_builder('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) { assert_raises(SystemExit) { builder.send(:analyze_output) } }
      end
      plain = strip_ansi(out)
      assert_includes plain, '(1 error)'
      assert_includes plain, "label 'sec:dup' duplicate"
      refute_includes plain, "Alert: label 'sec:dup'"
      assert_includes plain, 'Errors: 1'
      assert_includes plain, 'Alerts: 0'
    end
  end

  # alert_as_warning is applied before the promotion, so a configured
  # downgrade keeps duplicate labels out of the error tier.
  def test_duplicate_label_downgrade_still_wins_over_promotion
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'err_xelatex'), "(./main.tex\nLaTeX Warning: Label `sec:dup` multiply defined.\n)\n")

      builder = legacy_builder('main.tex', alert_as_warning: ['multiply_defined_label'])
      out, = capture_io { Dir.chdir(dir) { builder.send(:analyze_output) } }
      plain = strip_ansi(out)
      assert_includes plain, 'Errors: 0'
      assert_includes plain, 'Warnings: 1'
    end
  end

  # A misspelled \documentclass option is ignored by LaTeX and silently leaves
  # the default layout in place, so it ranks as an alert rather than a warning.
  def test_unused_global_option_is_an_alert
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'err_xelatex'), <<~LOG)
        (./main.tex
        LaTeX Warning: Unused global option(s):
            [11p,twocolum].
        )
      LOG

      builder = legacy_builder('main.tex', {})
      out, = capture_io { Dir.chdir(dir) { builder.send(:analyze_output) } }
      plain = strip_ansi(out)
      assert_includes plain, '(1 alert)'
      assert_includes plain, 'Unused global option(s): [11p,twocolum]'
      assert_includes plain, 'Alerts: 1'
      assert_includes plain, 'Warnings: 0'
    end
  end

  # \em and the size switches inside math are only a Font Warning, yet they
  # never fix themselves and always mark a source mistake, so they are alerts.
  def test_font_switch_inside_math_is_an_alert_with_advice
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'err_xelatex'), <<~LOG)
        (./main.tex
        LaTeX Font Warning: Command \\em invalid in math mode on input line 3.
        LaTeX Font Warning: Command \\large invalid in math mode on input line 9.
        )
      LOG

      builder = legacy_builder('main.tex', {})
      out, = capture_io { Dir.chdir(dir) { builder.send(:analyze_output) } }
      plain = strip_ansi(out)
      assert_includes plain, '(2 alerts)'
      assert_includes plain, 'command \\em invalid in math mode; use \\mathit{...}'
      assert_includes plain, 'command \large invalid in math mode; wrap the whole formula'
      assert_includes plain, 'Alerts: 2'
    end
  end

  # Vertical overflow and oversized floats lose content off the page, so the
  # same point threshold that promotes horizontal boxes applies to them.
  def test_vertical_overflow_and_large_floats_are_alerts_above_threshold
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'err_xelatex'), <<~LOG)
        (./main.tex
        Overfull \\vbox (40.0pt too high) has occurred while \\output is active
        Overfull \\vbox (5.0pt too high) detected at line 12
        LaTeX Warning: Float too large for page by 341.29997pt on input line 4.
        LaTeX Warning: Float too large for page by 3.0pt on input line 9.
        )
      LOG

      builder = legacy_builder('main.tex', {})
      out, = capture_io { Dir.chdir(dir) { builder.send(:analyze_output) } }
      plain = strip_ansi(out)
      assert_includes plain, '40.00pt too high'
      assert_includes plain, 'Float too large for page by 341.30pt'
      assert_includes plain, 'Alerts: 2'
      assert_includes plain, 'Warnings: 2'
    end
  end

  # The convergence loop appends its own LaTeX-style warning when the pass
  # budget runs out; stale cross-references rank as an alert.
  def test_unconverged_build_warning_is_an_alert
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'err_xelatex'),
                 "(./main.tex\nLaTeX Warning: leeni: build did not converge; a rerun is still requested after 1 passes. " \
                 "References or page numbers may be stale (raise -n/--passes, max 20).\n)\n")

      builder = legacy_builder('main.tex', {})
      out, = capture_io { Dir.chdir(dir) { builder.send(:analyze_output) } }
      plain = strip_ansi(out)
      assert_includes plain, '(1 alert)'
      assert_includes plain, 'build did not converge'
    end
  end

  # BibTeX keeps the first of two entries sharing a key and drops the other.
  def test_repeated_bibliography_entry_is_an_alert_at_the_bib_line
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'err_xelatex'), "(./main.tex\n)\n")
      bib_log = File.join(dir, 'junk', 'bib.log')
      File.write(bib_log,
                 "Repeated entry---line 2 of file refs.bib\n : @article{k,\n :               author={B}\n" \
                 "I'm skipping whatever remains of this entry\n")

      builder = legacy_builder('main.tex', {})
      builder.instance_variable_set(:@biberr, bib_log)
      out, = capture_io { Dir.chdir(dir) { builder.send(:analyze_output) } }
      plain = strip_ansi(out)
      assert_includes plain, 'refs.bib'
      assert_includes plain, 'Repeated entry---line 2 of file refs.bib'
      assert_includes plain, 'Alerts: 1'
    end
  end

  # pdfTeX's duplicate-destination note is not a LaTeX warning; it is
  # normalised into one and ranked as an alert, once per anchor name.
  def test_duplicate_hyperlink_destinations_are_alerts_once_per_name
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'err_xelatex'), <<~LOG)
        (./main.tex
        pdfTeX warning (ext4): destination with the same identifier (name{page.1}) has been already used, duplicate ignored
        pdfTeX warning (ext4): destination with the same identifier (name{page.1}) has been already used, duplicate ignored
        pdfTeX warning (ext4): destination with the same identifier (name{dup}) has been already used, duplicate ignored
        [2]
        )
      LOG

      builder = legacy_builder('main.tex', {})
      out, = capture_io { Dir.chdir(dir) { builder.send(:analyze_output) } }
      plain = strip_ansi(out)
      assert_includes plain, '(2 alerts)'
      assert_includes plain, "Duplicate hyperlink destination 'page.1' (2 occurrences)"
      assert_includes plain, "Duplicate hyperlink destination 'dup';"
    end
  end

  def test_invisible_source_characters_are_warnings
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('main.tex', "\\documentclass{article}\n\\begin{document}\nA\u200Bword.\n\\end{document}\n")
        File.write('junk/err_xelatex', "(./main.tex\n)\n")
        builder = legacy_builder('main.tex', {})
        out, = capture_io { builder.send(:analyze_output) }
        plain = strip_ansi(out)
        assert_includes plain, '(1 warning)'
        assert_includes plain, 'invisible character (zero-width space U+200B) at column 2'
      end
    end
  end
end
