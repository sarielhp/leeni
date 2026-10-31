#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'leeni_test_support'

class TestLeeniCLI < LeeniTestBase
  def test_version_flag
    stdout, status = Open3.capture2(BIN, '-V')
    assert status.success?, "Expected exit code 0, got: #{status.exitstatus}"
    assert_match(/^leeni \d+\.\d+\.\d+/, stdout)
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
    Dir.mktmpdir('leeni_canon_flags') do |dir|
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
          %w[-I], %w[--make-indep], %w[--index], %w[--no-index], %w[--config-save], %w[--global], %w[--local]
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
    stdout_utf8, status_utf8 = Open3.capture2({ 'TERM' => 'xterm-256color', 'LANG' => 'en_US.UTF-8', 'LC_ALL' => 'en_US.UTF-8' }, BIN,
                                              '-h', '--help-style=lines', '--color')
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
      out_u, = Open3.capture2e(BIN, '-u', 'paper.tex', chdir: dir)
      assert_includes out_u, 'xelatex'
      refute_includes out_u, 'xelatex (2)'

      # Clear junk and target
      FileUtils.rm_rf(File.join(dir, 'junk'))
      FileUtils.rm_f(File.join(dir, 'paper.pdf'))

      # Initial build with standard convergence
      Open3.capture2e(BIN, 'paper.tex', chdir: dir)

      # When targets are up to date, standard build runs 0 passes
      out_cached, = Open3.capture2e(BIN, 'paper.tex', chdir: dir)
      assert_includes out_cached, 'All targets (paper.pdf) are up-to-date.'

      # When run with -f, it forces the first pass and rebuilds
      out_force, = Open3.capture2e(BIN, '-f', 'paper.tex', chdir: dir)
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
      File.write(File.join(dir, 'refs.bib'), <<~BIB)
        @article{item, author = {Author A}, title = {Title A}, journal = {J}, year = {2020}}
      BIB

      Open3.capture2e(BIN, 'paper.tex', chdir: dir)
      txt1, = Open3.capture2e('pdftotext', File.join(dir, 'paper.pdf'), '-')
      assert_includes txt1, 'Author A'

      future_time = Time.now + 10
      File.write(File.join(dir, 'refs.bib'), <<~BIB)
        @article{item, author = {Author B}, title = {Title B}, journal = {J}, year = {2026}}
      BIB
      File.utime(future_time, future_time, File.join(dir, 'refs.bib'))

      out, = Open3.capture2e(BIN, '-f', 'paper.tex', chdir: dir)
      txt2, = Open3.capture2e('pdftotext', File.join(dir, 'paper.pdf'), '-')
      assert_includes out, 'xelatex (1)'
      assert_includes out, 'bibtex'
      assert_includes txt2, 'Author B'
    end
  end

  def test_force_on_converged_document_runs_single_pass
    Dir.mktmpdir('force_converged') do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n\\begin{document}\nHello\n\\end{document}\n")
      Open3.capture2e(BIN, 'paper.tex', chdir: dir)

      out, = Open3.capture2e(BIN, '-f', 'paper.tex', chdir: dir)
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
      tex2 = "\\documentclass{article}\n\\begin{document}\n\\cite{k1}\n\\cite{k2}\n" \
             "\\bibliographystyle{plain}\n\\bibliography{refs}\n\\end{document}\n"
      bib2 = "@article{k1, author = {Author 1}, title = {T1}, journal = {J}, year = {2020}}\n" \
             "@article{k2, author = {Author 2}, title = {T2}, journal = {J}, year = {2026}}\n"
      File.write(File.join(dir, 'paper.tex'), tex2)
      File.write(File.join(dir, 'refs.bib'), bib2)
      File.utime(future_time, future_time, File.join(dir, 'paper.tex'), File.join(dir, 'refs.bib'))

      Open3.capture2e(BIN, 'paper.tex', chdir: dir)
      txt, = Open3.capture2e('pdftotext', File.join(dir, 'paper.pdf'), '-')
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
      invalid_output, invalid_status = Open3.capture2e(BIN, '-1', 'paper.tex', chdir: dir)
      refute invalid_status.success?
      assert_includes invalid_output, 'invalid option: -1'
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

  def test_find_main_flag_with_configured_main
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.l.jsonc'), "{\"main_file\": \"document.tex\"}\n")
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
        stdout, status = Open3.capture2(BIN, '--junk-dir', 'junk', '-M', 'paper.tex')
        assert status.success?
        assert_equal "paper.pdf: extra.tex paper.tex\n\n", stdout

        stdout_long, status_long = Open3.capture2(BIN, '--junk-dir', 'junk', '--deps', 'paper.tex')
        assert status_long.success?
        assert_equal "paper.pdf: extra.tex paper.tex\n\n", stdout_long
      end
    end
  end

  def test_diagnostic_formatting_no_redundant_w
    builder = legacy_builder('sample.tex', emacs: false, color: true)
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
    emacs_builder = legacy_builder('sample.tex', emacs: true)
    emacs_formatted = emacs_builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: Token not allowed on input line 42.',
                                         :yellow)
    assert_equal 'Package hyperref Warning: Token not allowed on input line 42.', emacs_formatted
  end
end
