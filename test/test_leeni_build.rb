#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'leeni_test_support'

class TestLeeniBuild < LeeniTestBase
  def test_diagnostic_formatting_empty_line_str
    builder = legacy_builder('sample.tex', emacs: false, color: true)
    formatted = builder.send(:format_diagnostic_line, '', 'LaTeX Warning: Label(s) may have changed.', :yellow)
    refute_includes formatted, 'W:'
    assert_includes formatted, Rainbow(': ').yellow.bright.to_s

    Rainbow.enabled = false
    mono_formatted = builder.send(:format_diagnostic_line, '', 'LaTeX Warning: Label(s) may have changed.', :yellow)
    assert_equal ': ❕ LaTeX Warning: Label(s) may have changed.', mono_formatted

    emacs_builder = legacy_builder('sample.tex', emacs: true)
    emacs_formatted = emacs_builder.send(:format_diagnostic_line, '', 'LaTeX Warning: Label(s) may have changed.', :yellow)
    assert_equal 'LaTeX Warning: Label(s) may have changed.', emacs_formatted
  end

  def test_line_number_colorization_left_and_inside
    Rainbow.enabled = true
    builder = legacy_builder('sample.tex', emacs: false, color: true)

    formatted = builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: on input line 42.', :yellow)
    cyan_bright_line = Rainbow('42').cyan.bright.to_s
    assert_includes formatted, cyan_bright_line

    # Verify both left side and message interior have the highlighted number
    occurrences = formatted.scan(cyan_bright_line).size
    assert_equal 2, occurrences, 'Expected 42 to be highlighted in cyan.bright both on left side and inside message'
  end

  def test_error_line_number_colorization
    Rainbow.enabled = true
    builder = legacy_builder('sample.tex', emacs: false, color: true)

    err_lines = ['./sample.tex:42: Undefined control sequence.', 'l.42 \\badcommand']
    formatted = builder.send(:format_error_block, err_lines, 42)
    cyan_bright_line = Rainbow('42').cyan.bright.to_s
    assert_includes formatted, cyan_bright_line
  end

  def test_did_you_mean_rust_style_colorization
    Rainbow.enabled = true
    builder = legacy_builder('sample.tex', emacs: false, color: true)

    catalog = { id: :undefined_control_sequence, hint: "Did you mean '\\alpha'?" }
    pointer = builder.send(:render_pointer_line, 3, 5, 5, catalog)

    assert_includes pointer, Rainbow('Did you mean ').cyan.to_s
    assert_includes pointer, Rainbow("'\\alpha'").green.bright.bold.to_s
    assert_includes pointer, Rainbow('^^^^^').red.bright.bold.to_s
  end

  def test_left_width_alignment
    Rainbow.enabled = false
    builder = legacy_builder('sample.tex', emacs: false, color: false)

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

      builder = legacy_builder('main.tex', {})
      Dir.chdir(dir) do
        deps = builder.send(:extract_fls_dependencies, fls_path)
        assert_includes deps, 'main.tex'
        assert_includes deps, 'sections/intro.tex'
        refute_includes deps, 'junk/main.aux'
        refute(deps.any? { |d| d.include?('/usr/share') })
      end
    end
  end

  def test_aux_has_cross_references
    builder = legacy_builder('main.tex', {})
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
      builder = legacy_builder('paper.tex', {})

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
        force_builder = legacy_builder('paper.tex', force: true)
        refute force_builder.send(:targets_up_to_date?)

        # Test single_pass (-1 / --single-pass) forces rebuild
        single_builder = legacy_builder('paper.tex', single_pass: true)
        refute single_builder.send(:targets_up_to_date?)

        # Test clean forces rebuild
        clean_builder = legacy_builder('paper.tex', clean: true)
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

      builder = legacy_builder('paper.tex', werror: true)
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

      builder = legacy_builder('paper.tex', deps: true)
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

    builder = legacy_builder('main.tex', {})
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

    builder_emacs = legacy_builder('main.tex', emacs: true)
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

    builder = legacy_builder('talagrand.tex', {})
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

    builder = legacy_builder('main.tex', {})
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

      builder = legacy_builder('paper.tex', werror: true)
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
      assert_includes content, 'leeni Global Configuration File'
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

      builder = legacy_builder('paper.tex', {})
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

      builder = legacy_builder('paper.tex', extra_files: ['extra.txt'])
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
      File.write(File.join(dir, 'paper.tex'),
                 "%!TEX TS-program = xelatex\n\\documentclass{article}\n\\usepackage{mystyle}\n\\begin{document}X\\end{document}\n")
      File.write(File.join(dir, 'paper.pdf'), 'PDF-DUMMY')
      File.write(File.join(dir, 'mystyle.sty'), "\\ProvidesPackage{mystyle}\n")

      fls_content = <<~FLS
        INPUT ./mystyle.sty
        INPUT ./paper.tex
      FLS
      File.write(File.join(dir, 'junk', 'paper.fls'), fls_content)

      builder = legacy_builder('paper.tex', inject_styles: true)
      packager = LatexPackager.new(builder)

      Dir.chdir(dir) do
        packager.package!
        assert File.file?('paper.zip')

        Dir.mktmpdir do |unzip_dir|
          Open3.capture2('unzip', '-q', File.join(dir, 'paper.zip'), '-d', unzip_dir)
          assert File.file?(File.join(unzip_dir, 'styles', 'mystyle.sty'))

          tex_content = File.read(File.join(unzip_dir, 'paper.tex'))
          assert_includes tex_content, '\\def\\input@path{{styles/}{./}}'
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

      File.write(File.join(dir, 'paper.tex'),
                 "\\documentclass{article}\n% author notes\n\\input{sections/intro.tex}\n\\begin{document}\nHello\n\\end{document}\n")
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

      builder = legacy_builder('paper.tex', zip_flat: true)
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
end
