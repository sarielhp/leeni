#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require_relative 'leeni_test_support'

# Build-runtime behaviour of the builder: locking, build state, brace checks,
# atomic copies, bibliography discovery, pass capture and trace, the progress
# indicator, .bbl synchronisation and interrupt handling.
class TestLeeniBuildRuntime < LeeniTestBase
  def test_path_hash_and_project_tmp_file
    Dir.mktmpdir do |dir1|
      Dir.mktmpdir do |dir2|
        b1 = legacy_builder(File.join(dir1, 'main.tex'), {})
        b2 = legacy_builder(File.join(dir2, 'main.tex'), {})

        refute_equal b1.send(:path_hash), b2.send(:path_hash)

        lock1 = b1.send(:project_tmp_file, 'build.lock')
        lock2 = b2.send(:project_tmp_file, 'build.lock')

        refute_equal lock1, lock2
        assert_equal File.join(Dir.tmpdir, LeeniTmp.user_name, 'leeni', 'locks'), File.dirname(lock1)
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
    formatted = builder.send(:format_trace_command, env, cmd, '/tmp/doc') # tmp-exempt: a string

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
        wait_for_child_process(wait_thr.pid)
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

  # The interrupt must reach leeni once it runs the engine, not while Ruby
  # still loads it (a fixed sleep lost that race on a loaded machine).
  def wait_for_child_process(pid, limit: 60)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + limit
    until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      children, = Open3.capture2('pgrep', '-P', pid.to_s)
      return sleep(0.2) unless children.strip.empty?

      sleep 0.05
    end
    flunk "leeni (pid #{pid}) started no engine within #{limit}s"
  end
end
