#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class TestLatexItCLI < Minitest::Test
  # Several tests flip the process-global Rainbow.enabled; without this the value
  # leaks into whichever test file runs next and makes results order-dependent.
  def setup
    @saved_rainbow_enabled = Rainbow.enabled
  end

  def teardown
    Rainbow.enabled = @saved_rainbow_enabled
  end

  BIN = File.expand_path('../latex_it', __dir__)
  load BIN

  def strip_ansi(str)
    str.to_s.gsub(/\e\[[0-9;]*m/, '')
  end

  def test_version_flag
    stdout, status = Open3.capture2(BIN, '-V')
    assert status.success?, "Expected exit code 0, got: #{status.exitstatus}"
    assert_match(/^l \d+\.\d+\.\d+/, stdout)
  end

  def test_help_flag
    stdout, status = Open3.capture2(BIN, '-h')
    assert status.success?, "Expected exit code 0, got: #{status.exitstatus}"
    assert stdout.lines.count <= 25, "Expected -h to be strictly <= 25 lines, got #{stdout.lines.count}"
    assert_includes stdout, 'Usage: l [options]'
    assert_includes stdout, 'Common Options:'
    assert_includes stdout, '-e, --engine ENGINE'
    assert_includes stdout, '-u, --single-pass'
    assert_includes stdout, '-f, --force'
    assert_includes stdout, '-c, --clean'
    assert_includes stdout, '-x, --explain'
    assert_includes stdout, '-E, --examples'
    assert_includes stdout, '--help-all'
    assert_includes stdout, '-h, --help'

    # Verify options demoted to -H are not in condensed help
    refute_includes stdout, '-m, --main'
    refute_includes stdout, '--update-if-changed'
    refute_includes stdout, '-z, --zip'
    refute_includes stdout, '-t, --verify'
    refute_includes stdout, '-W, --werror'
    refute_includes stdout, '--arxiv'

    # Verify shortcuts and no-ops are not present in condensed help output
    refute_includes stdout, '--lua'
    refute_includes stdout, '--xe'
    refute_includes stdout, '--pdflatex'
    refute_includes stdout, '--fast'
    refute_includes stdout, '--pdf'

    # Verify redundant aliases are not present in help output
    refute_includes stdout, '--one-pass'
    refute_includes stdout, '--quick'
    refute_includes stdout, '--find-main'
    refute_includes stdout, '--file'
    refute_includes stdout, '--lualatex'
    refute_includes stdout, '--xelatex'
    refute_includes stdout, '--update-on-diff'
    refute_includes stdout, '--diff'
    refute_includes stdout, '--test'
    refute_includes stdout, '--env-free'
    refute_includes stdout, '--envfree'
  end

  def test_help_all_flag
    stdout, status = Open3.capture2(BIN, '--help-all')
    assert status.success?, "Expected exit code 0, got: #{status.exitstatus}"
    assert_includes stdout, 'Compilation Options:'
    assert_includes stdout, 'arXiv Preparation Options:'
    assert_includes stdout, 'General Options:'
    assert_includes stdout, '-e, --engine ENGINE'
    assert_includes stdout, '-x, --explain'
    assert_includes stdout, '--deps'
    assert_includes stdout, '--no-env'
    assert_includes stdout, '--alert-hbox'
    assert_includes stdout, '--whatever-pt'
    assert_includes stdout, '--arxiv'
    assert_includes stdout, '--update-if-changed'

    # Verify shortcuts and no-ops are not present in full help either
    refute_includes stdout, '--lua'
    refute_includes stdout, '--xe'
    refute_includes stdout, '--pdflatex'
    refute_includes stdout, '--fast'
    refute_includes stdout, '--pdf'

    # Verify removed aliases are not present
    refute_includes stdout, '--one-pass'
    refute_includes stdout, '--quick'
    refute_includes stdout, '--find-main'
    refute_includes stdout, '--file'
    refute_includes stdout, '--lualatex'
    refute_includes stdout, '--xelatex'
    refute_includes stdout, '--update-on-diff'
    refute_includes stdout, '--diff'
    refute_includes stdout, '--test'
    refute_includes stdout, '--env-free'
    refute_includes stdout, '--envfree'
  end

  def test_examples_flag
    stdout, status = Open3.capture2(BIN, '-E')
    assert status.success?, "Expected exit code 0, got: #{status.exitstatus}"
    assert_includes stdout, 'Detailed Examples & Common Workflows:'
    assert_includes stdout, 'l -f'
    assert_includes stdout, 'l -u'
    assert_includes stdout, 'l -z'
    assert_includes stdout, 'l --arxiv'

    stdout_long, status_long = Open3.capture2(BIN, '--examples')
    assert status_long.success?
    assert_equal stdout, stdout_long

    stdout_both, status_both = Open3.capture2(BIN, '-h', '-E')
    assert status_both.success?
    assert_includes stdout_both, 'Common Options:'
    assert_includes stdout_both, 'Detailed Examples & Common Workflows:'

    stdout_all_both, status_all_both = Open3.capture2(BIN, '--help-all', '-E')
    assert status_all_both.success?
    assert_includes stdout_all_both, 'Compilation Options:'
    assert_includes stdout_all_both, 'Detailed Examples & Common Workflows:'
  end

  def test_canonical_cli_flags_and_anti_alias
    Dir.mktmpdir('latex_it_canon_flags') do |dir|
      Dir.chdir(dir) do
        canonical_flags = [
          %w[-u], %w[--single-pass], %w[-f], %w[--force], %w[-m], %w[--main],
          %w[-x], %w[--explain], %w[--update-if-changed], %w[-t], %w[--verify],
          %w[--no-env], %w[-W], %w[--werror], ['-e', 'xelatex'], ['-e', 'l'], ['-e', 'p'],
          %w[--engine=xelatex], %w[--engine=lualatex], %w[--engine=pdflatex],
          %w[--help-style=lines], %w[-r], %w[--raw], %w[-cc], %w[--compile],
          %w[-llm], %w[--llm], %w[--agent], %w[--json],
          %w[--config-show], %w[--theme-list],
          %w[--styles-inject], %w[--no-styles-inject],
          %w[-I], %w[--index], %w[--no-index], %w[--config-save], %w[--global], %w[--local]
        ]
        opts = LatexCLI.build_default_options({}, 'l', [])
        sample_parser = LatexCLI.build_option_parser(opts)
        refute_nil sample_parser.top.search(:long, 'vscode-init')
        refute_nil sample_parser.top.search(:long, 'config-init')
        refute_nil sample_parser.top.search(:long, 'gitignore-init')

        canonical_flags.each do |flag_args|
          argv = flag_args.dup
          LatexCLI.normalize_argv!(argv)
          parser = LatexCLI.build_option_parser(LatexCLI.build_default_options({}, 'l', []))
          capture_io { parser.order!(argv) }
        end

        removed_aliases = %w[
          --one-pass --quick --find-main --file --lualatex --xelatex --update-on-diff
          --test --env-free --envfree --pdf --lua --xe --pdflatex --fast --cc
          --extract-bib --help-lines --no-help-lines --links --no-links
          --init-config --show-config --init-vscode --list-themes
          --inject-styles --no-inject-styles -i
        ]
        removed_aliases.each do |alias_flag|
          argv = [alias_flag]
          LatexCLI.normalize_argv!(argv)
          opts = LatexCLI.build_default_options({}, 'l', [])
          parser = LatexCLI.build_option_parser(opts)
          assert_raises(OptionParser::ParseError, "Removed alias #{alias_flag} should be rejected") do
            parser.order!(argv)
          end
        end
      end
    end
  end

  def test_help_colorization
    stdout_color, status_color = Open3.capture2(BIN, '-h', '--color')
    assert status_color.success?
    assert_match(/(?:\e\[[0-9;]+m)+Usage:/, stdout_color)
    assert_match(/(?:\e\[[0-9;]+m)+-f\e\[0m/, stdout_color)
    assert_match(/(?:\e\[[0-9;]+m)+-e\e\[0m, (?:\e\[[0-9;]+m)+--engine\e\[0m (?:\e\[[0-9;]+m)+ENGINE\e\[0m/, stdout_color)

    stdout_nocolor, status_nocolor = Open3.capture2(BIN, '-h', '--no-color')
    assert status_nocolor.success?
    refute_includes stdout_nocolor, "\e["

    stdout_all_color, status_all_color = Open3.capture2(BIN, '-H', '--color')
    assert status_all_color.success?
    assert_match(/(?:\e\[[0-9;]+m)+Pass Control & Compilation:\e\[0m/, stdout_all_color)
    assert_match(/(?:\e\[[0-9;]+m)+-e\e\[0m, (?:\e\[[0-9;]+m)+--engine\e\[0m (?:\e\[[0-9;]+m)+ENGINE\e\[0m/, stdout_all_color)
  end

  def test_help_lines_style
    # In dumb terminal (test runner default), dividers use '-'
    stdout_lines, status_lines = Open3.capture2({ 'TERM' => 'dumb', 'LANG' => 'C', 'LC_ALL' => 'C' }, BIN, '-h', '--help-style=lines')
    assert status_lines.success?
    assert_includes stdout_lines, '----------------------------------------------------------------------------'

    # In UTF-8 terminal with color, dividers use '─' with faint styling
    stdout_utf8, status_utf8 = Open3.capture2({ 'TERM' => 'xterm-256color', 'LANG' => 'en_US.UTF-8', 'LC_ALL' => 'en_US.UTF-8' }, BIN, '-h', '--help-style=lines', '--color')
    assert status_utf8.success?
    assert_includes stdout_utf8, '────────────────────────────────────────────────────────────────────────────'
    assert_match(/\e\[2m/, stdout_utf8)

    # In plain style, no divider lines appear
    stdout_plain, status_plain = Open3.capture2(BIN, '-h', '--help-style=plain')
    assert status_plain.success?
    refute_includes stdout_plain, '----------------------------------------------------------------------------'
    refute_includes stdout_plain, '────────────────────────────────────────────────────────────────────────────'
  end

  def test_difference_between_u_and_1_passes
    Dir.mktmpdir do |dir|
      tex = File.join(dir, 'paper.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Section \\ref{sec:intro}
        \\section{Intro}\\label{sec:intro}
        \\end{document}
      TEX
      # Run with -u: forces single pass only and stops (1 pass)
      out_u, _ = Open3.capture2e(BIN, '-u', 'paper.tex', chdir: dir)
      assert_includes out_u, 'xelatex'
      refute_includes out_u, 'xelatex (2)'

      # Clear junk and target
      FileUtils.rm_rf(File.join(dir, 'junk'))
      FileUtils.rm_f(File.join(dir, 'paper.pdf'))

      # Initial build with standard convergence
      Open3.capture2e(BIN, 'paper.tex', chdir: dir)

      # When targets are up to date, standard build runs 0 passes
      out_cached, _ = Open3.capture2e(BIN, 'paper.tex', chdir: dir)
      assert_includes out_cached, 'All targets (paper.pdf) are up-to-date.'

      # When run with -f, it forces the first pass and rebuilds
      out_force, _ = Open3.capture2e(BIN, '-f', 'paper.tex', chdir: dir)
      assert_includes out_force, 'xelatex (1)'
      refute_includes out_force, 'All targets (paper.pdf) are up-to-date.'
    end
  end

  def test_force_with_bibtex_change_and_convergence
    Dir.mktmpdir('force_bibtex') do |dir|
      File.write(File.join(dir, 'paper.tex'), <<~'TEX')
        \documentclass{article}
        \begin{document}
        Testing: \cite{item}.
        \bibliographystyle{plain}
        \bibliography{refs}
        \end{document}
      TEX
      File.write(File.join(dir, 'refs.bib'), <<~'BIB')
        @article{item, author = {Author A}, title = {Title A}, journal = {J}, year = {2020}}
      BIB

      Open3.capture2e(BIN, 'paper.tex', chdir: dir)
      txt1, _ = Open3.capture2e('pdftotext', File.join(dir, 'paper.pdf'), '-')
      assert_includes txt1, 'Author A'

      future_time = Time.now + 10
      File.write(File.join(dir, 'refs.bib'), <<~'BIB')
        @article{item, author = {Author B}, title = {Title B}, journal = {J}, year = {2026}}
      BIB
      File.utime(future_time, future_time, File.join(dir, 'refs.bib'))

      out, _ = Open3.capture2e(BIN, '-f', 'paper.tex', chdir: dir)
      txt2, _ = Open3.capture2e('pdftotext', File.join(dir, 'paper.pdf'), '-')
      assert_includes out, 'xelatex (1)'
      assert_includes out, 'bibtex'
      assert_includes txt2, 'Author B'
    end
  end

  def test_force_on_converged_document_runs_single_pass
    Dir.mktmpdir('force_converged') do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n\\begin{document}\nHello\n\\end{document}\n")
      Open3.capture2e(BIN, 'paper.tex', chdir: dir)

      out, _ = Open3.capture2e(BIN, '-f', 'paper.tex', chdir: dir)
      assert_includes out, 'xelatex (1)'
      refute_includes out, 'xelatex (2)'
    end
  end

  def test_simultaneous_tex_and_bib_change
    Dir.mktmpdir('simultaneous_change') do |dir|
      tex1 = "\\documentclass{article}\n\\begin{document}\n\\cite{k1}\n\\bibliographystyle{plain}\n\\bibliography{refs}\n\\end{document}\n"
      bib1 = "@article{k1, author = {Author 1}, title = {T1}, journal = {J}, year = {2020}}\n"
      File.write(File.join(dir, 'paper.tex'), tex1)
      File.write(File.join(dir, 'refs.bib'), bib1)

      Open3.capture2e(BIN, 'paper.tex', chdir: dir)

      future_time = Time.now + 10
      tex2 = "\\documentclass{article}\n\\begin{document}\n\\cite{k1}\n\\cite{k2}\n\\bibliographystyle{plain}\n\\bibliography{refs}\n\\end{document}\n"
      bib2 = "@article{k1, author = {Author 1}, title = {T1}, journal = {J}, year = {2020}}\n@article{k2, author = {Author 2}, title = {T2}, journal = {J}, year = {2026}}\n"
      File.write(File.join(dir, 'paper.tex'), tex2)
      File.write(File.join(dir, 'refs.bib'), bib2)
      File.utime(future_time, future_time, File.join(dir, 'paper.tex'), File.join(dir, 'refs.bib'))

      Open3.capture2e(BIN, 'paper.tex', chdir: dir)
      txt, _ = Open3.capture2e('pdftotext', File.join(dir, 'paper.pdf'), '-')
      assert_includes txt, 'Author 2'
      refute_includes txt, '[?]'
    end
  end

  def test_force_option_is_f_and_minus_one_rejected
    Dir.mktmpdir('force_option_test') do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n\\begin{document}\nHello\n\\end{document}\n")
      Open3.capture2e(BIN, 'paper.tex', chdir: dir)

      # -f forces a rebuild
      out_f, status_f = Open3.capture2e(BIN, '-f', 'paper.tex', chdir: dir)
      assert status_f.success?
      assert_includes out_f, 'xelatex (1)'

      # -1 must now be rejected as an invalid option
      out_1, status_1 = Open3.capture2e(BIN, '-1', 'paper.tex', chdir: dir)
      refute status_1.success?
      assert_includes out_1, 'invalid option: -1'
    end
  end

  def test_find_main_file_ignores_commented_documentclass
    Dir.mktmpdir('commented_documentclass') do |dir|
      File.write(File.join(dir, 'main.tex'), "\\documentclass{article}\n\\begin{document}\nReal doc\n\\end{document}\n")
      File.write(File.join(dir, 'notes.tex'), "% \\documentclass{article}\n% \\begin{document}\nJust notes\n")

      found = LaTeXUtils.find_main_latex_file(dir)
      assert_equal 'main.tex', found
    end
  end

  def test_pdflatex_is_supported_engine
    assert_equal 'pdflatex', LaTeXUtils.normalize_engine('pdflatex')
    assert_equal 'pdflatex', LaTeXUtils.normalize_engine('pdftex')
    assert_equal 'pdflatex', LaTeXUtils.normalize_engine('p')
    assert_equal 'lualatex', LaTeXUtils.normalize_engine('l')
    assert_equal 'xelatex', LaTeXUtils.normalize_engine('x')
  end

  def test_inputenc_source_selects_pdflatex
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, "\\documentclass{article}\n\\usepackage[latin9]{inputenc}\n")
      assert_equal 'pdflatex', LaTeXUtils.detect_engine_from_file(path)
    end
  end

  def test_inputenc_detection_handles_requirepackage
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, "\\documentclass{article}\n\\RequirePackage { inputenc }\n")
      assert_equal 'pdflatex', LaTeXUtils.detect_engine_from_file(path)
    end
  end

  def test_explicit_magic_comment_overrides_inputenc_fallback
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, "%!TEX TS-program = xelatex\n\\usepackage[utf8]{inputenc}\n")
      assert_equal 'xelatex', LaTeXUtils.detect_engine_from_file(path)
    end
  end

  def test_incompatible_explicit_engine_falls_back_to_pdflatex
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, "\\documentclass{article}\n\\usepackage[latin9]{inputenc}\n")
      assert_equal 'pdflatex', LaTeXUtils.compatible_engine('xelatex', path)
      assert_equal 'pdflatex', LaTeXUtils.compatible_engine('lualatex', path)
      assert_equal 'pdflatex', LaTeXUtils.compatible_engine('pdflatex', path)
    end
  end

  def test_eps_graphics_require_pdflatex
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, <<~TEX)
        \\usepackage{graphicx}
        \\includegraphics[width=.5\\linewidth]{figures/result.eps}
        \\epsfig{file=old.eps,width=2cm}
      TEX
      assert_equal ['EPS graphics'], LaTeXUtils.source_pdflatex_reasons(path)
      assert LaTeXUtils.source_requires_pdflatex?(path)
      assert_equal 'pdflatex', LaTeXUtils.compatible_engine('xelatex', path)
      assert_equal 'pdflatex', LaTeXUtils.compatible_engine('lualatex', path)
    end
  end

  def test_commented_eps_reference_does_not_trigger_detection
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, "% \\includegraphics{commented.eps}\n% \\epsfig{file=commented.eps}\n")
      assert_empty LaTeXUtils.source_pdflatex_reasons(path)
    end
  end

  def test_pdflatex_symlink_personality_selects_engine
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        pdflatex personality
        \\end{document}
      TEX
      launcher = File.join(dir, 'lp')
      File.symlink(BIN, launcher)

      Dir.chdir(dir) do
        stdout, stderr, status = Open3.capture3(launcher, 'paper.tex')
        assert status.success?, "pdflatex personality failed: #{stdout}\n#{stderr}"
        assert File.file?(File.join(dir, 'paper.pdf'))
        assert_includes stdout, 'pdflatex'
      end
    end
  end

  def test_find_main_flag_with_mainfile
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.mainfile'), "document.tex\n")
      File.write(File.join(dir, 'other.tex'), "\\begin{document}\\end{document}\n")

      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-m')
        assert status.success?
        assert_equal "document.tex\n\n", stdout
      end
    end
  end

  def test_find_main_flag_directory_name_heuristic
    Dir.mktmpdir('my_paper') do |dir|
      dir_name = File.basename(dir)
      File.write(File.join(dir, "#{dir_name}.tex"), "\\begin{document}\\end{document}\n")
      File.write(File.join(dir, 'random.tex'), "content\n")

      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-m')
        assert status.success?
        assert_equal "#{dir_name}.tex\n\n", stdout
      end
    end
  end

  def test_clean_only_flag
    Dir.mktmpdir do |dir|
      # Create mock junk files
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'temp.aux'), 'temp')
      File.write(File.join(dir, 'test.aux'), 'aux')
      File.write(File.join(dir, 'test.log'), 'log')

      Dir.chdir(dir) do
        _stdout, status = Open3.capture2(BIN, '-C')
        assert status.success?
        refute File.exist?(File.join(dir, 'junk'))
        refute File.exist?(File.join(dir, 'test.aux'))
        refute File.exist?(File.join(dir, 'test.log'))
      end
    end
  end

  def test_deps_flag_cli
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\begin{document}\\end{document}\n")
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      state = {
        'target' => 'paper.pdf',
        'sources' => { 'paper.tex' => {}, 'extra.tex' => {} }
      }
      File.write(File.join(dir, 'junk', '.build_state.json'), JSON.generate(state))

      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-M', 'paper.tex')
        assert status.success?
        assert_equal "paper.pdf: extra.tex paper.tex\n\n", stdout

        stdout_long, status_long = Open3.capture2(BIN, '--deps', 'paper.tex')
        assert status_long.success?
        assert_equal "paper.pdf: extra.tex paper.tex\n\n", stdout_long
      end
    end
  end

  def test_diagnostic_formatting_no_redundant_w
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)
    formatted = builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: Token not allowed on input line 42.', :yellow)
    refute_includes formatted, 'W:'
    assert_includes formatted, Rainbow('42').cyan.bright.to_s
    assert_includes formatted, Rainbow(': ').yellow.bright.to_s

    # In plain/monochrome mode, verify plain 42: prefix with badge
    Rainbow.enabled = false
    mono_formatted = builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: Token not allowed on input line 42.', :yellow)
    refute_includes mono_formatted, 'W:'
    assert_equal '42: ❕ Package hyperref Warning: Token not allowed on input line 42.', mono_formatted

    # In emacs mode, verify line prefixes are completely suppressed
    emacs_builder = LatexBuilder.new('sample.tex', emacs: true)
    emacs_formatted = emacs_builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: Token not allowed on input line 42.', :yellow)
    assert_equal 'Package hyperref Warning: Token not allowed on input line 42.', emacs_formatted
  end

  def test_diagnostic_formatting_empty_line_str
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)
    formatted = builder.send(:format_diagnostic_line, '', 'LaTeX Warning: Label(s) may have changed.', :yellow)
    refute_includes formatted, 'W:'
    assert_includes formatted, Rainbow(': ').yellow.bright.to_s

    Rainbow.enabled = false
    mono_formatted = builder.send(:format_diagnostic_line, '', 'LaTeX Warning: Label(s) may have changed.', :yellow)
    assert_equal ': ❕ LaTeX Warning: Label(s) may have changed.', mono_formatted

    emacs_builder = LatexBuilder.new('sample.tex', emacs: true)
    emacs_formatted = emacs_builder.send(:format_diagnostic_line, '', 'LaTeX Warning: Label(s) may have changed.', :yellow)
    assert_equal 'LaTeX Warning: Label(s) may have changed.', emacs_formatted
  end

  def test_line_number_colorization_left_and_inside
    Rainbow.enabled = true
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)

    formatted = builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: on input line 42.', :yellow)
    cyan_bright_42 = Rainbow('42').cyan.bright.to_s
    assert_includes formatted, cyan_bright_42

    # Verify both left side and message interior have the highlighted number
    occurrences = formatted.scan(cyan_bright_42).size
    assert_equal 2, occurrences, 'Expected 42 to be highlighted in cyan.bright both on left side and inside message'
  end

  def test_error_line_number_colorization
    Rainbow.enabled = true
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)

    err_lines = ['./sample.tex:42: Undefined control sequence.', 'l.42 \\badcommand']
    formatted = builder.send(:format_error_block, err_lines, 42)
    cyan_bright_42 = Rainbow('42').cyan.bright.to_s
    assert_includes formatted, cyan_bright_42
  end

  def test_did_you_mean_rust_style_colorization
    Rainbow.enabled = true
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)

    catalog = { id: :undefined_control_sequence, hint: "Did you mean '\\alpha'?" }
    pointer = builder.send(:render_pointer_line, 3, 5, 5, catalog)

    assert_includes pointer, Rainbow("Did you mean ").cyan.to_s
    assert_includes pointer, Rainbow("'\\alpha'").green.bright.bold.to_s
    assert_includes pointer, Rainbow('^^^^^').red.bright.bold.to_s
  end

  def test_left_width_alignment
    Rainbow.enabled = false
    builder = LatexBuilder.new('sample.tex', emacs: false, color: false)

    # Testing formatting with width = 10 (as in 1071--1075)
    f_range = builder.send(:format_diagnostic_line, '1071--1075', 'Overfull \\hbox ...', :magenta, width: 10)
    f_short = builder.send(:format_diagnostic_line, '448', 'Overfull \\hbox ...', :magenta, width: 10)
    f_empty = builder.send(:format_diagnostic_line, '', 'Warning without line', :yellow, width: 10)

    assert_match(/^1071--1075: ❕ Overfull/, f_range)
    assert_match(/^       448: ❕ Overfull/, f_short)
    assert_match(/^          : ❕ Warning/, f_empty)

    # Check colon positions: all must align at index 10 (11th character)
    assert_equal 10, f_range.index(':')
    assert_equal 10, f_short.index(':')
    assert_equal 10, f_empty.index(':')
  end

  def test_extract_fls_dependencies
    Dir.mktmpdir do |dir|
      fls_content = <<~FLS
        PWD #{dir}
        INPUT /usr/share/texmf/base.cls
        INPUT #{dir}/main.tex
        INPUT #{dir}/sections/intro.tex
        INPUT #{dir}/junk/main.aux
        OUTPUT #{dir}/junk/main.pdf
      FLS

      FileUtils.mkdir_p(File.join(dir, 'junk'))
      FileUtils.mkdir_p(File.join(dir, 'sections'))
      File.write(File.join(dir, 'main.tex'), 'test')
      File.write(File.join(dir, 'sections', 'intro.tex'), 'intro')
      fls_path = File.join(dir, 'junk', 'main.fls')
      File.write(fls_path, fls_content)

      builder = LatexBuilder.new('main.tex', {})
      Dir.chdir(dir) do
        deps = builder.send(:extract_fls_dependencies, fls_path)
        assert_includes deps, 'main.tex'
        assert_includes deps, 'sections/intro.tex'
        refute_includes deps, 'junk/main.aux'
        refute deps.any? { |d| d.include?('/usr/share') }
      end
    end
  end

  def test_aux_has_cross_references
    builder = LatexBuilder.new('main.tex', {})
    refute builder.send(:aux_has_cross_references?, "\\relax\n\\@abspage@last{1}\n")
    assert builder.send(:aux_has_cross_references?, "\\newlabel{sec:one}{{1}{1}}\n")
    assert builder.send(:aux_has_cross_references?, "\\citation{knuth1984}\n")
    assert builder.send(:aux_has_cross_references?, "\\@writefile{toc}{\\contentsline {section}}\n")
  end

  def test_targets_up_to_date_logic
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), 'content')
      File.write(File.join(dir, 'paper.pdf'), 'mock pdf')
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      builder = LatexBuilder.new('paper.tex', {})

      sha = Digest::SHA256.file(File.join(dir, 'paper.tex')).hexdigest
      mtime = File.mtime(File.join(dir, 'paper.tex')).to_i
      state = {
        'target' => 'paper.pdf',
        'engine' => 'xelatex',
        'signature' => builder.send(:build_signature),
        'sources' => { 'paper.tex' => { 'mtime' => mtime, 'sha' => sha } }
      }
      File.write(File.join(dir, 'junk', '.build_state.json'), JSON.generate(state))

      Dir.chdir(dir) do
        assert builder.send(:targets_up_to_date?), 'Expected build to be up to date'

        # Test force (-u / --force) forces rebuild
        force_builder = LatexBuilder.new('paper.tex', force: true)
        refute force_builder.send(:targets_up_to_date?)

        # Test single_pass (-1 / --single-pass) forces rebuild
        single_builder = LatexBuilder.new('paper.tex', single_pass: true)
        refute single_builder.send(:targets_up_to_date?)

        # Test clean forces rebuild
        clean_builder = LatexBuilder.new('paper.tex', clean: true)
        refute clean_builder.send(:targets_up_to_date?)

        # Test modified source triggers rebuild
        sleep 0.05
        File.write(File.join(dir, 'paper.tex'), 'modified content')
        refute builder.send(:targets_up_to_date?), 'Expected modified file to trigger rebuild'
      end
    end
  end

  def test_werror_forces_rebuild
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), 'content')
      File.write(File.join(dir, 'paper.pdf'), 'mock pdf')
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      sha = Digest::SHA256.file(File.join(dir, 'paper.tex')).hexdigest
      mtime = File.mtime(File.join(dir, 'paper.tex')).to_i
      state = {
        'target' => 'paper.pdf',
        'sources' => { 'paper.tex' => { 'mtime' => mtime, 'sha' => sha } }
      }
      File.write(File.join(dir, 'junk', '.build_state.json'), JSON.generate(state))

      builder = LatexBuilder.new('paper.tex', werror: true)
      Dir.chdir(dir) do
        refute builder.send(:targets_up_to_date?), 'Expected werror to force rebuild'
      end
    end
  end

  def test_export_dependencies
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), 'content')
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      state = {
        'target' => 'paper.pdf',
        'sources' => { 'paper.tex' => {}, 'figures/fig1.pdf' => {} }
      }
      File.write(File.join(dir, 'junk', '.build_state.json'), JSON.generate(state))

      builder = LatexBuilder.new('paper.tex', deps: true)
      Dir.chdir(dir) do
        out, = capture_io { builder.send(:export_dependencies) }
        assert_equal "paper.pdf: figures/fig1.pdf paper.tex\n", out
      end
    end
  end

  def test_multi_file_diagnostics
    log_content = <<~LOG
      This is XeTeX, Version 3.141592653-2.6-0.999996
      (./main.tex
      (./chapters/ch1.tex
      LaTeX Warning: Reference `sec:unknown' on page 1 undefined on input line 42.
      )
      (./chapters/ch2.tex
      Overfull \\hbox (15.0pt too wide) in paragraph at lines 10--15
      )
      ! LaTeX Error: File `missing.sty' not found.
      )
    LOG

    builder = LatexBuilder.new('main.tex', {})
    warnings = builder.send(:extract_warnings, log_content)
    errors = builder.send(:extract_errors, log_content)

    ch1_warn = warnings.find { |w| w[:text].include?('sec:unknown') }
    assert ch1_warn
    assert_equal './chapters/ch1.tex', ch1_warn[:file]
    assert_equal 42, ch1_warn[:line]

    ch2_warn = warnings.find { |w| w[:type].to_s.include?('Overfull') || w[:text].include?('too wide') }
    assert ch2_warn
    assert_equal './chapters/ch2.tex', ch2_warn[:file]
    assert_equal 10, ch2_warn[:line]

    assert_equal 1, errors.size
    assert_equal './main.tex', errors.first[:file]

    out, = capture_io { builder.send(:print_diagnostics_body, warnings, errors) }
    plain = strip_ansi(out)
    assert_includes plain, '── chapters/ch1.tex (1 warning) ──'
    assert_includes plain, '── chapters/ch2.tex (1 warning) ──'
    assert_includes plain, '── main.tex (1 error) ──'
    refute_match(/^\(/, plain)
    refute_match(/^\)/, plain)
    refute_includes plain, './'

    builder_emacs = LatexBuilder.new('main.tex', emacs: true)
    out_emacs, = capture_io { builder_emacs.send(:print_diagnostics_body, warnings, errors) }
    assert_includes out_emacs, "(chapters/ch1.tex\n"
    assert_includes out_emacs, "(chapters/ch2.tex\n"
    assert_includes out_emacs, "(main.tex\n"
    assert_match(/^\)/, out_emacs)
    refute_includes out_emacs, './'
  end

  def test_extract_errors_handles_generic_file_line_error
    log_content = <<~LOG
      ./talagrand.tex:294: Misplaced alignment tab character &.
      l.294         &
                     s \\in \\CHSetY{\\pnt}{\\SetA_\\OldOm}
      ./talagrand.tex:298: Misplaced alignment tab character &.
      l.298         &
    LOG

    builder = LatexBuilder.new('talagrand.tex', {})
    errors = builder.send(:extract_errors, log_content)
    assert_equal 2, errors.size
    assert_equal './talagrand.tex', errors[0][:file]
    assert_equal 294, errors[0][:line]
    assert_includes errors[0][:text], 'Misplaced alignment tab character &'
    assert_equal 298, errors[1][:line]
  end

  def test_diagnostics_correctly_attributes_file_with_inline_package_parens
    log_content = <<~LOG
      (./main.tex (./styles/prefix.tex)
      (/usr/share/texlive/texmf-dist/tex/latex/microtype/mt-NewComputerModern.cfg)
      (junk/main.aux)
      File: foo.cfg (AT)
      Overfull \\hbox (30.0pt too wide) in paragraph at lines 140--143
      (../fragment/def.tex)
      Overfull \\hbox (15.0pt too wide) detected at line 249
      )
    LOG

    builder = LatexBuilder.new('main.tex', {})
    warnings = builder.send(:extract_warnings, log_content)
    assert_equal 2, warnings.size
    assert_equal './main.tex', warnings[0][:file]
    assert_equal "140\u{2026}", warnings[0][:line_str]
    assert_equal 140, warnings[0][:line]
    assert_equal 143, warnings[0][:line_end]
    assert_equal './main.tex', warnings[1][:file]
    assert_equal '249', warnings[1][:line_str]
  end

  def test_werror_aborts_on_warnings
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_content = <<~LOG
        LaTeX Warning: Reference `sec:foo' on page 1 undefined on input line 10.
      LOG
      File.write(File.join(dir, 'junk', 'err_xelatex'), log_content)

      builder = LatexBuilder.new('paper.tex', werror: true)
      Dir.chdir(dir) do
        assert_raises(SystemExit) do
          capture_io { builder.send(:analyze_output) }
        end
      end
    end
  end

  def test_parse_jsonc_with_comments_and_trailing_commas
    jsonc = <<~JSONC
      {
        // Line comment
        "engine": "lualatex",
        /* Block
           comment */
        "url": "https://example.com/test",
        "zip": {
          "inject_styles": true,
          "include": ["foo.txt", "bar.csv",], // trailing comma in array
        }, // trailing comma in hash
      }
    JSONC

    parsed = LaTeXConfig.parse_jsonc(jsonc)
    assert_equal 'lualatex', parsed['engine']
    assert_equal 'https://example.com/test', parsed['url']
    assert_equal true, parsed.dig('zip', 'inject_styles')
    assert_equal %w[foo.txt bar.csv], parsed.dig('zip', 'include')
  end

  def test_parse_jsonc_error_resilience
    assert_equal({}, LaTeXConfig.parse_jsonc(nil))
    assert_equal({}, LaTeXConfig.parse_jsonc('   '))
    _out, err = capture_io do
      assert_equal({}, LaTeXConfig.parse_jsonc('{ invalid json: }}'))
    end
    assert_includes err, 'Warning: Could not parse JSONC config'
  end

  def test_load_merged_config
    Dir.mktmpdir do |dir|
      local_jsonc = <<~JSONC
        {
          "engine": "lualatex",
          "zip": {
            "inject_styles": true
          }
        }
      JSONC
      File.write(File.join(dir, '.l.jsonc'), local_jsonc)

      cfg = LaTeXConfig.load_merged_config(dir)
      assert_equal 'lualatex', cfg['engine']
      assert_equal true, cfg.dig('zip', 'inject_styles')
      assert_equal false, cfg['fast']
    end
  end

  def test_init_config_cli
    Dir.mktmpdir do |dir|
      stdout, status = Open3.capture2(BIN, '--config-init', chdir: dir)
      assert status.success?
      assert_includes stdout, 'Created local configuration file: ./.l.jsonc'
      target = File.join(dir, '.l.jsonc')
      assert File.file?(target)
      content = File.read(target)
      assert_includes content, 'latex_it Global Configuration File'
      assert_includes content, '"engine": "xelatex"'
    end
  end

  def test_bbl_without_bib_lifecycle
    Dir.mktmpdir do |dir|
      bbl_content = <<~BBL
        \\begin{thebibliography}{1}
        \\bibitem{ref1} Author. Title. 2026.
        \\end{thebibliography}
      BBL
      File.write(File.join(dir, 'paper.bbl'), bbl_content)
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'paper.aux'), "\\bibdata{refs}\n\\citation{ref1}\n")

      builder = LatexBuilder.new('paper.tex', {})
      Dir.chdir(dir) do
        # 1. paper_cleanup should seed bbl into junk/
        builder.send(:paper_cleanup)
        assert File.file?('junk/paper.bbl')
        assert_equal bbl_content, File.read('junk/paper.bbl')

        # 2. detect_bib_tool should skip bibtex because valid bbl exists and no .bib is present
        assert_nil builder.send(:detect_bib_tool)
      end
    end
  end

  def test_figure_discovery_and_zip_creation
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'figs'))
      FileUtils.mkdir_p(File.join(dir, 'junk'))

      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n\\begin{document}Hello\\end{document}\n")
      File.write(File.join(dir, 'paper.pdf'), 'PDF-DUMMY')
      File.write(File.join(dir, 'paper.bbl'), "\\begin{thebibliography}{1}\n\\bibitem{a} A\n\\end{thebibliography}\n")
      File.write(File.join(dir, 'paper.bib'), "@article{a, title={A}}\n")
      File.write(File.join(dir, 'figs', 'diagram.pdf'), 'PDF-FIG')
      File.write(File.join(dir, 'figs', 'diagram.fig'), 'FIG-SOURCE')
      File.write(File.join(dir, 'figs', 'diagram.ipe'), 'IPE-SOURCE')
      File.write(File.join(dir, 'figs', 'standard.isy'), 'ISY-STYLESHEET')
      File.write(File.join(dir, 'figs', 'diagram.bak'), 'JUNK-BAK')
      File.write(File.join(dir, 'extra.txt'), 'EXTRA-CONTENT')

      fls_content = <<~FLS
        INPUT /usr/share/texlive/texmf-dist/tex/latex/base/article.cls
        INPUT ./figs/diagram.pdf
        INPUT ./paper.tex
      FLS
      File.write(File.join(dir, 'junk', 'paper.fls'), fls_content)

      builder = LatexBuilder.new('paper.tex', extra_files: ['extra.txt'])
      packager = LatexPackager.new(builder)

      Dir.chdir(dir) do
        packager.package!
        assert File.file?('paper.zip')

        entries, = Open3.capture2('unzip', '-l', 'paper.zip')
        assert_includes entries, 'paper.tex'
        assert_includes entries, 'paper.pdf'
        assert_includes entries, 'paper.bbl'
        assert_includes entries, 'paper.bib'
        assert_includes entries, 'figs/diagram.pdf'
        assert_includes entries, 'figs/diagram.fig'
        assert_includes entries, 'figs/diagram.ipe'
        assert_includes entries, 'figs/standard.isy'
        assert_includes entries, 'extra.txt'
        refute_includes entries, 'diagram.bak'
      end
    end
  end

  def test_inject_styles_mode
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'paper.tex'), "%!TEX TS-program = xelatex\n\\documentclass{article}\n\\usepackage{mystyle}\n\\begin{document}X\\end{document}\n")
      File.write(File.join(dir, 'paper.pdf'), 'PDF-DUMMY')
      File.write(File.join(dir, 'mystyle.sty'), "\\ProvidesPackage{mystyle}\n")

      fls_content = <<~FLS
        INPUT ./mystyle.sty
        INPUT ./paper.tex
      FLS
      File.write(File.join(dir, 'junk', 'paper.fls'), fls_content)

      builder = LatexBuilder.new('paper.tex', inject_styles: true)
      packager = LatexPackager.new(builder)

      Dir.chdir(dir) do
        packager.package!
        assert File.file?('paper.zip')

        Dir.mktmpdir do |unzip_dir|
          Open3.capture2('unzip', '-q', File.join(dir, 'paper.zip'), '-d', unzip_dir)
          assert File.file?(File.join(unzip_dir, 'styles', 'mystyle.sty'))

          tex_content = File.read(File.join(unzip_dir, 'paper.tex'))
          assert_includes tex_content, "\\def\\input@path{{styles/}{./}}"
          # Verify magic comments remain at the top
          assert tex_content.start_with?("%!TEX TS-program = xelatex\n")
        end
      end
    end
  end

  def test_packager_zip_flat_mode
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      FileUtils.mkdir_p(File.join(dir, 'sections'))
      FileUtils.mkdir_p(File.join(dir, 'figs'))

      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n% author notes\n\\input{sections/intro.tex}\n\\begin{document}\nHello\n\\end{document}\n")
      File.write(File.join(dir, 'sections', 'intro.tex'), "% section comment\n\\section{Intro}\nIntro text here\n")
      File.write(File.join(dir, 'paper.pdf'), 'PDF-DUMMY')
      File.write(File.join(dir, 'paper.bbl'), "\\begin{thebibliography}{1}\n\\bibitem{x}Ref\n\\end{thebibliography}\n")
      File.write(File.join(dir, 'figs', 'plot.pdf'), 'PLOT-DUMMY')

      fls_content = <<~FLS
        INPUT /usr/share/texlive/texmf-dist/tex/latex/base/article.cls
        INPUT ./paper.tex
        INPUT ./sections/intro.tex
        INPUT ./figs/plot.pdf
      FLS
      File.write(File.join(dir, 'junk', 'paper.fls'), fls_content)

      builder = LatexBuilder.new('paper.tex', zip_flat: true)
      packager = LatexPackager.new(builder)

      Dir.chdir(dir) do
        packager.package!
        assert File.file?('paper.zip')

        entries, = Open3.capture2('unzip', '-l', 'paper.zip')
        assert_includes entries, 'paper.tex'
        assert_includes entries, 'paper.pdf'
        assert_includes entries, 'paper.bbl'
        assert_includes entries, 'figs/plot.pdf'
        refute_includes entries, 'sections/intro.tex'

        Dir.mktmpdir do |unzip_dir|
          Open3.capture2('unzip', '-q', File.join(dir, 'paper.zip'), '-d', unzip_dir)
          tex_content = File.read(File.join(unzip_dir, 'paper.tex'))
          assert_includes tex_content, 'Intro text here'
          assert_includes tex_content, '% author notes'
          assert_includes tex_content, '% section comment'
          refute_includes tex_content, '\\input{sections/intro.tex}'
        end
      end
    end
  end

  def test_cli_zip_flat_flag_parsing
    options = LatexCLI.build_default_options({}, 'l', [])
    parser = LatexCLI.build_option_parser(options)

    parser.parse(['-Z'])
    assert_equal true, options[:zip]
    assert_equal true, options[:zip_flat]

    options2 = LatexCLI.build_default_options({}, 'l', [])
    parser2 = LatexCLI.build_option_parser(options2)

    parser2.parse(['--zip-flat'])
    assert_equal true, options2[:zip]
    assert_equal true, options2[:zip_flat]
  end

  def test_cli_zip_with_separator
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n\\begin{document}Hi\\end{document}\n")
      File.write(File.join(dir, 'notes.txt'), "Important notes\n")
      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-z', 'paper.tex', '--', 'notes.txt')
        assert status.success?, "l -z failed: #{stdout}"
        assert File.file?('paper.zip')

        entries, = Open3.capture2('unzip', '-l', 'paper.zip')
        assert_includes entries, 'paper.tex'
        assert_includes entries, 'notes.txt'
      end
    end
  end

  def test_cli_zip_and_verify
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n\\begin{document}Verify me\\end{document}\n")
      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-z', '-t', 'paper.tex')
        assert status.success?, "l -z -t failed: #{stdout}"
        assert File.file?('paper.zip')
        assert_includes stdout, 'Created portable zip: paper.zip'
        assert_includes stdout, 'Verifying archive portability in isolated sandbox'
        assert_includes stdout, '[VERIFIED]'
        assert_includes stdout, 'Text layout exact match confirmed'
      end
    end
  end

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

      builder = LatexBuilder.new('main.tex', {})
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
    builder = LatexBuilder.new('main.tex', color: false)
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
        (./main.aux
        LaTeX Warning: Label `sec:dup` multiply defined.
        )
        )
      LOG
      File.write(log_file, log_content)

      # Default: both alerts and warnings are displayed
      builder = LatexBuilder.new('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end

      plain = strip_ansi(out)
      assert_includes plain, '(1 alert)'
      assert_includes plain, '(2 warnings)'
      assert_includes plain, "label 'sec:dup' duplicate"
      assert_includes plain, "undefined reference 'sec:unknown'"
      assert_includes plain, 'Errors: 0'
      assert_includes plain, 'Alerts: 1'
      refute_includes plain, '(❕ suppressed)'
      refute_includes plain, '(Warnings suppressed)'

      # When suppress_warnings: true, warnings are suppressed
      suppressed_builder = LatexBuilder.new('main.tex', suppress_warnings: true)
      out_supp, = capture_io do
        Dir.chdir(dir) do
          suppressed_builder.send(:analyze_output)
        end
      end

      plain_supp = strip_ansi(out_supp)
      assert_includes plain_supp, '(1 alert)'
      refute_includes plain_supp, 'warnings)'
      assert_includes plain_supp, "label 'sec:dup' duplicate"
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

      builder = LatexBuilder.new('main.tex', {})
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
      custom_builder = LatexBuilder.new('main.tex', alert_overfull_pt: 50.0)
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
      builder = LatexBuilder.new('main.tex', {})
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
      all_builder = LatexBuilder.new('main.tex', all: true, suppress_whatevers: false)
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
      builder = LatexBuilder.new('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end
      refute_includes out, 'Diagnostic Explanation'

      # With explain: true: boxed explanation printed only on first occurrence
      expl_builder = LatexBuilder.new('main.tex', explain: true)
      out_expl, = capture_io do
        Dir.chdir(dir) do
          expl_builder.send(:analyze_output)
        end
      end

      plain_expl = strip_ansi(out_expl)
      assert_includes plain_expl, 'Diagnostic Explanation: Alert: Multiply-Defined Label'
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

      builder = LatexBuilder.new('main.tex', explain: true)
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
      assert_includes plain, 'See: https://sarielhp.github.io/latex_it/docs/guides/underfull_boxes/'
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

      builder = LatexBuilder.new('main.tex', explain: true)
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end

      plain = strip_ansi(out)
      assert_includes plain, 'Diagnostic Explanation: Warning: Underfull \vbox (Vertical Stretch)'
      assert_includes plain, 'TeX could not stretch vertical whitespace'
      assert_includes plain, 'Might fix: Add \\raggedbottom to preamble'
      assert_includes plain, 'See: https://sarielhp.github.io/latex_it/docs/guides/underfull_boxes/'
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
      builder_no_link = LatexBuilder.new('main.tex', link: false)
      out_no_link, = capture_io do
        Dir.chdir(dir) do
          builder_no_link.send(:analyze_output)
        end
      end
      refute_includes out_no_link, "\e]8;;https://sarielhp.github.io"
      assert_includes out_no_link, 'underfull \hbox (badness 10000)'

      # 2. With link: true: clean OSC 8 embedded on underfull \hbox
      builder_link = LatexBuilder.new('main.tex', link: true)
      out_link, = capture_io do
        Dir.chdir(dir) do
          builder_link.send(:analyze_output)
        end
      end
      expected_osc8 = "\e]8;;https://sarielhp.github.io/latex_it/docs/guides/underfull_boxes/\e\\underfull \\hbox\e]8;;\e\\"
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

      builder = LatexBuilder.new('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
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
      builder = LatexBuilder.new('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end
      plain = strip_ansi(out)
      assert_includes plain, 'Warnings: 1'
      assert_includes plain, 'Whatevers: 0'

      # Custom threshold 5.0pt: 4.0pt is demoted to Whatever (suppressed)
      custom_builder = LatexBuilder.new('main.tex', whatever_overfull_pt: 5.0)
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
        b1 = LatexBuilder.new(File.join(dir1, 'main.tex'), {})
        b2 = LatexBuilder.new(File.join(dir2, 'main.tex'), {})

        refute_equal b1.send(:path_hash), b2.send(:path_hash)

        lock1 = b1.send(:project_tmp_file, 'build.lock')
        lock2 = b2.send(:project_tmp_file, 'build.lock')

        refute_equal lock1, lock2
        user = ENV['USER'] || 'user'
        refute_includes lock1, "/tmp/#{user}"
        assert_equal File.join(Dir.tmpdir, "latex_it_#{Process.uid}"), File.dirname(lock1)
        assert_includes lock1, 'main_build.lock'
      end
    end
  end

  def test_with_lock_blocks_concurrent_runs
    Dir.mktmpdir do |dir|
      builder = LatexBuilder.new(File.join(dir, 'paper.tex'), lock: true)
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

        builder = LatexBuilder.new(tex, lock: true)
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

        builder = LatexBuilder.new(tex, lock: true)
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

        builder = LatexBuilder.new('paper.tex', {})

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
        builder = LatexBuilder.new('paper.tex', {})
        errs = builder.send(:check_source_braces)
        assert_equal 1, errs.size
        err = errs.first
        assert_equal 4, err[:line]
        assert_equal 14, err[:col]
        assert_includes err[:text], "inside environment 'theorem'"
        assert_includes err[:text], '! [latex_it] Unclosed open brace'
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
    builder = LatexBuilder.new('main.tex', {})
    env = builder.send(:pass_environment)
    assert_equal '2048', env['max_print_line']
  end

  def test_atomic_copy_replaces_target_atomically
    Dir.mktmpdir do |dir|
      src = File.join(dir, 'source.pdf')
      dst = File.join(dir, 'final.pdf')
      File.write(src, '%PDF-1.4 dummy new')
      File.write(dst, '%PDF-1.4 dummy old')

      builder = LatexBuilder.new('main.tex', {})
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

      builder = LatexBuilder.new('main.tex', {})
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

        builder = LatexBuilder.new('main.tex', {})
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

        builder = LatexBuilder.new('main.tex', {})
        bibs = builder.send(:discover_bib_files)
        assert_includes bibs, 'custom_bibs/chapter.bib'
      end
    end
  end

  def test_capture_pass_output_executes_and_terminates_on_timeout
    builder = LatexBuilder.new('main.tex', timeout: 1)
    out, status = builder.send(:capture_pass_output, ['sleep', '5'])
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
    builder = LatexBuilder.new('main.tex', trace: true)
    env = ENV.to_h.merge('TEXINPUTS' => '.:custom_styles:', 'max_print_line' => '2048')
    cmd = ['xelatex', '-output-directory=junk', 'main.tex']
    formatted = builder.send(:format_trace_command, env, cmd, '/tmp/doc')

    assert_includes formatted, 'cd /tmp/doc'
    assert_includes formatted, 'TEXINPUTS=.:custom_styles:'
    assert_includes formatted, 'max_print_line=2048'
    assert_includes formatted, 'xelatex -output-directory=junk main.tex'
  end

  def test_trace_output_during_pass_execution
    builder = LatexBuilder.new('main.tex', trace: true, timeout: 5)
    out_capture = StringIO.new
    orig_stdout = $stdout
    begin
      $stdout = out_capture
      _out, status = builder.send(:capture_pass_output, ['echo', 'trace_test'])
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
        builder = LatexBuilder.new('paper.tex', {})
        builder.send(:sync_bbl_before_compile)
        refute File.exist?('paper.bbl')

        # With trace: promote to root
        builder_trace = LatexBuilder.new('paper.tex', trace: true)
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

        builder = LatexBuilder.new('paper.tex', trace: true)
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
      'synthetic_ch.tex' => [{ file: 'synthetic_ch.tex', line: 10, source: :latex_it, synthetic: true }],
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
    assert_equal :latex_it, brace_errs.first[:source]
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

  def test_subcommand_interrupt_signal_exits_130
    Dir.mktmpdir('latex_it_sigint') do |dir|
      tex = File.join(dir, 'slow.tex')
      File.write(tex, "\\documentclass{article}\n\\begin{document}\n\\loop\\iftrue\\repeat\n\\end{document}\n")
      cmd = [BIN, '-f', 'slow.tex']
      Open3.popen2e(*cmd, chdir: dir) do |_stdin, stdout_err, wait_thr|
        sleep 0.25
        Process.kill('INT', wait_thr.pid) rescue nil
        output = stdout_err.read
        status = wait_thr.value
        assert_equal 130, status.exitstatus
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

      builder = LatexBuilder.new('main.tex', {})
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
end
