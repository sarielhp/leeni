# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require 'fileutils'

require_relative '../lib/latex_it/utils'
require_relative '../lib/latex_it/error_catalog'
require_relative '../lib/latex_it/bib_locator'
require_relative '../lib/latex_it/diagnostics'
require_relative '../lib/latex_it/builder'

class TestBibIntegration < Minitest::Test
  def test_standard_bibtex_compilation_not_broken
    Dir.mktmpdir('bibtex_compat_test') do |dir|
      tex_content = <<~'TEX'
        \documentclass{article}
        \begin{document}
        Citation test: \cite{testentry}.
        \bibliographystyle{plain}
        \bibliography{refs}
        \end{document}
      TEX
      bib_content = <<~'BIB'
        @article{testentry,
          author = {Euler, Leonhard},
          title = {On something interesting},
          journal = {Memoirs},
          year = {1750}
        }
      BIB
      File.write(File.join(dir, 'main.tex'), tex_content)
      File.write(File.join(dir, 'refs.bib'), bib_content)

      bin_path = File.expand_path('../latex_it', __dir__)
      out, status = Open3.capture2e(bin_path, 'main.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Compilation failed with output:\n#{out}"
      assert File.file?(File.join(dir, 'main.pdf')), 'Expected main.pdf to be generated'
    end
  end

  def test_bib_locator_resolution
    Dir.mktmpdir('bib_locator_test') do |dir|
      bib_content = <<~'BIB'
        @article{Alpha:2000,
          author = {Author, A.},
          title = {First Paper},
          year = {2000}
        }

        @article{Beta:2010,
          author = {Writer, B.},
          journal = {NORDIC_J_COMP},
          title = {Second Paper},
          year = {2010}
        }
      BIB
      bib_file = File.join(dir, 'sample.bib')
      File.write(bib_file, bib_content)

      # Test locator by searching directory
      loc = LaTeXBibLocator.locate('Beta:2010', 'NORDIC_J_COMP', 'book', dir)
      refute_nil loc
      assert_equal bib_file, loc[:file]
      assert_equal 9, loc[:line]
      assert_includes loc[:field_text], 'NORDIC_J_COMP'

      # Test locator entry fallback when token is nil
      loc_entry = LaTeXBibLocator.locate('Alpha:2000', nil, 'book', dir)
      refute_nil loc_entry
      assert_equal bib_file, loc_entry[:file]
      assert_equal 1, loc_entry[:line]
    end
  end

  def test_bib_locator_prefers_configured_junk_directory
    Dir.mktmpdir('bib_locator_junk_test') do |dir|
      FileUtils.mkdir_p(File.join(dir, '.build'))
      FileUtils.mkdir_p(File.join(dir, 'external'))
      bib_file = File.join(dir, 'external', 'references.bib')
      File.write(bib_file, "@article{Configured:2026,\n  title = {Configured Path}\n}\n")
      File.write(File.join(dir, '.build', 'paper.blg'), "Database file #1: #{bib_file}\n")

      location = LaTeXBibLocator.locate(
        'Configured:2026', nil, 'paper', dir, junk_dir: '.build'
      )

      refute_nil location
      assert_equal bib_file, location[:file]
    end
  end

  def test_decluster_errors
    diag_class = Class.new do
      include LaTeXDiagnostics
      attr_accessor :options, :filename
      def initialize
        @options = {}
        @filename = 'test.tex'
      end
    end
    diag = diag_class.new

    raw_errors = [
      { file: 'ch.tex', line: 10, text: 'Missing $ inserted.', err_block: ['Missing $ inserted.', 'l.10 $'], index: 1 },
      { file: 'ch.tex', line: 10, text: 'Double subscript.', err_block: ['Double subscript.', 'l.10 x_a_b'], index: 2 },
      { file: 'ch.tex', line: 10, text: 'Missing $ inserted.', err_block: ['Missing $ inserted.', 'l.10 $'], index: 3 },
      { file: 'ch.tex', line: 10, text: 'Missing $ inserted.', err_block: ['Missing $ inserted.', 'l.10 $'], index: 4 }
    ]

    declustered = diag.decluster_errors(raw_errors)
    assert_equal 2, declustered.size
    first_item = declustered.find { |e| e[:text] == 'Missing $ inserted.' }
    second_item = declustered.find { |e| e[:text] == 'Double subscript.' }

    assert_equal 3, first_item[:repeat_count]
    assert_nil second_item[:repeat_count]
  end

  def test_companion_generation_and_sorting
    Dir.mktmpdir('companion_test') do |dir|
      bib_content = <<~'BIB'
        @article{Key1:2020,
          author = {Doe, John},
          journal = {BAD_MACRO},
          title = {A Title},
          year = {2020}
        }
      BIB
      bib_file = File.join(dir, 'refs.bib')
      File.write(bib_file, bib_content)

      diag_class = Class.new do
        include LaTeXDiagnostics
        attr_accessor :options, :filename, :bfilename
        def initialize(bfilename, search_dir)
          @options = {}
          @filename = 'book.tex'
          @bfilename = bfilename
          @search_dir = search_dir
        end
      end
      diag = diag_class.new('book', dir)

      mock_log = <<~LOG
        (./01_intro/intro.tex
        BIB_ENTRY: Key1:2020
        ./01_intro/intro.tex:50: Double subscript.
        <argument> BAD_MACRO
        l.50 \\printbibliography
        )
      LOG

      Dir.chdir(dir) do
        compiler_errors = diag.extract_errors(mock_log)
        assert_equal 1, compiler_errors.size
        assert_equal 'Key1:2020', compiler_errors.first[:bib_entry]
        assert_equal 'BAD_MACRO', compiler_errors.first[:token]

        prepared = diag.prepare_error_items(compiler_errors)
        assert_equal 2, prepared.size

        primary = prepared[0]
        companion = prepared[1]
        assert_equal './01_intro/intro.tex', primary[:file]
        assert_equal bib_file, companion[:file]
        assert_equal 3, companion[:line]
        assert_equal :latex_it, companion[:source]
        assert_equal true, companion[:synthetic]
        assert_equal '01_intro/intro.tex', companion[:companion_to]

        # Verify companion error line formatting
        assert_equal "refs.bib:3: [latex_it] Bibliography error in entry 'Key1:2020'", companion[:err_block].first
        assert_includes companion[:formatted], '[latex_it]'
        refute_match(/^\s*3:\s*:/, companion[:formatted])

        # Verify sorting: primary file is first, companion is second
        all_sorted, _, _ = diag.sort_diagnostic_items([], prepared)
        assert_equal './01_intro/intro.tex', all_sorted[0][:file]
        assert_equal bib_file, all_sorted[1][:file]

        # Verify throttle: companion is included with primary file without cascade alert
        displayed, cascade = diag.throttle_errors(prepared)
        assert_nil cascade
        assert_equal 2, displayed.size
      end
    end
  end

  def test_wrap_text_hanging_indent_and_ansi
    text = '▸ 9 more errors were detected across 8 other files (23_two_choices/two_choices.tex, 26_jl/jl.tex, 30_lsh/lsh.tex, and 5 more files).'
    wrapped = LaTeXUtils.wrap_text(text, width: 60)
    lines = wrapped.lines.map(&:chomp)

    assert lines.size >= 2
    assert lines[0].start_with?('▸ ')
    lines[1..].each do |ln|
      assert ln.start_with?('  '), "Expected line to start with 2-space hanging indent: #{ln.inspect}"
      refute ln.start_with?('   ')
    end

    # Test multi-space indentation preservation
    msg = '  Handle above errors first to ensure these errors are not cascades.'
    w_msg = LaTeXUtils.wrap_text(msg, width: 45)
    w_lines = w_msg.lines.map(&:chomp)
    assert w_lines.size >= 2
    w_lines.each do |ln|
      assert ln.start_with?('  '), "Expected line to start with 2 spaces: #{ln.inspect}"
    end

    # Test explicit prefix and indent
    custom = LaTeXUtils.wrap_text('alpha beta gamma delta epsilon zeta eta theta', width: 25, prefix: '==> ', indent: '    ')
    c_lines = custom.lines.map(&:chomp)
    assert c_lines[0].start_with?('==> ')
    c_lines[1..].each { |ln| assert ln.start_with?('    ') }

    # Test ANSI stripping for width calculation
    colored = Rainbow(text).yellow
    c_wrapped = LaTeXUtils.wrap_text(colored, width: 60)
    plain_wrapped = LaTeXUtils.strip_ansi(c_wrapped)
    plain_lines = plain_wrapped.lines.map(&:chomp)
    assert plain_lines[0].start_with?('▸ ')
    plain_lines[1..].each { |ln| assert ln.start_with?('  ') }

    # Test empty / nil
    assert_equal '', LaTeXUtils.wrap_text('')
    assert_equal '', LaTeXUtils.wrap_text(nil)
  end

  def test_empty_bibliography_completes_and_resolves_labels_on_clean_dir
    Dir.mktmpdir('empty_bib_test') do |dir|
      tex = <<~'TEX'
        \documentclass{article}
        \begin{document}
        \section{Introduction}\label{sec:intro}
        See section \ref{sec:intro}.
        Citation: \cite{nonexistent}.
        \bibliographystyle{plain}
        \bibliography{refs}
        \end{document}
      TEX
      File.write(File.join(dir, 'main.tex'), tex)
      File.write(File.join(dir, 'refs.bib'), '')

      bin_path = File.expand_path('../latex_it', __dir__)
      out, status = Open3.capture2e(bin_path, 'main.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Compilation failed on clean dir: #{out}"
      pdf_path = File.join(dir, 'main.pdf')
      assert File.file?(pdf_path), 'Expected main.pdf to be generated'

      # Verify cross-references were resolved on pass 2
      txt, _ = Open3.capture2('pdftotext', pdf_path, '-')
      assert_includes txt, 'See section 1'

      # Second run untouched: should be up to date
      out2, status2 = Open3.capture2e(bin_path, 'main.tex', chdir: dir)
      assert_equal 0, status2.exitstatus
      assert_includes out2, 'up-to-date'

      # Third run with text edit only: should run single pass without bibtex
      File.write(File.join(dir, 'main.tex'), tex.sub('See section', 'See section updated'))
      out3, status3 = Open3.capture2e(bin_path, 'main.tex', chdir: dir)
      assert_equal 0, status3.exitstatus
      assert_includes out3, 'xelatex (1)'
      refute_includes out3, 'bibtex'
    end
  end

  def test_syntax_error_in_bib_halts_compilation
    Dir.mktmpdir('bib_syntax_err_test') do |dir|
      tex = <<~'TEX'
        \documentclass{article}
        \begin{document}
        \section{Intro}\label{sec:intro}
        \cite{broken}.
        \bibliographystyle{plain}
        \bibliography{refs}
        \end{document}
      TEX
      File.write(File.join(dir, 'main.tex'), tex)
      File.write(File.join(dir, 'refs.bib'), '@article{broken, author = {Incomplete')

      bin_path = File.expand_path('../latex_it', __dir__)
      _out, status = Open3.capture2e(bin_path, 'main.tex', chdir: dir)
      assert_equal 1, status.exitstatus, 'Expected compilation to halt on bib syntax error'
    end
  end

  def test_biber_reruns_when_bbl_stale_after_citation_removed_with_force
    Dir.mktmpdir('biber_stale_bbl_test') do |dir|
      tex1 = <<~'TEX'
        \documentclass{article}
        \usepackage[backend=biber]{biblatex}
        \addbibresource{refs.bib}
        \begin{document}
        Citing: \cite{itemA} and \cite{missingKey}.
        \printbibliography
        \end{document}
      TEX
      bib = <<~'BIB'
        @article{itemA,
          author = {Author, Real},
          title = {A Valid Title},
          journal = {Journal},
          year = {2020}
        }
      BIB
      File.write(File.join(dir, 'main.tex'), tex1)
      File.write(File.join(dir, 'refs.bib'), bib)

      bin_path = File.expand_path('../latex_it', __dir__)
      # Pass 1: compiles with missingKey
      out1, _ = Open3.capture2e(bin_path, 'main.tex', chdir: dir)
      assert File.exist?(File.join(dir, 'main.bbl')), 'Expected main.bbl to be created'
      assert_includes out1, 'missingKey'

      # Now fix main.tex by removing the citation to missingKey
      tex2 = <<~'TEX'
        \documentclass{article}
        \usepackage[backend=biber]{biblatex}
        \addbibresource{refs.bib}
        \begin{document}
        Citing: \cite{itemA}.
        \printbibliography
        \end{document}
      TEX
      File.write(File.join(dir, 'main.tex'), tex2)
      # refs.bib is NOT touched, so its mtime is older than main.bbl!

      # Recompile with -cc -f (as reported by user)
      out2, status2 = Open3.capture2e(bin_path, '-cc', '-f', 'main.tex', chdir: dir)
      assert_equal 0, status2.exitstatus
      refute_includes out2, 'Please (re)run Biber', 'Biber should have rerun to convergence'
      refute_includes out2, 'missingKey', 'Stale missing database entry must not be reported'
    end
  end

  def test_biber_reruns_when_bib_file_hash_changes_even_with_older_mtime
    Dir.mktmpdir('biber_bib_hash_test') do |dir|
      tex = <<~'TEX'
        \documentclass{article}
        \usepackage[backend=biber]{biblatex}
        \addbibresource{refs.bib}
        \begin{document}
        Citing: \cite{itemA}.
        \printbibliography
        \end{document}
      TEX
      bib1 = <<~'BIB'
        @article{itemA,
          author = {Initial, Author},
          title = {Initial Title},
          journal = {Journal},
          year = {2020}
        }
      BIB
      File.write(File.join(dir, 'main.tex'), tex)
      File.write(File.join(dir, 'refs.bib'), bib1)

      bin_path = File.expand_path('../latex_it', __dir__)
      _out1, status1 = Open3.capture2e(bin_path, 'main.tex', chdir: dir)
      assert_equal 0, status1.exitstatus
      pdf_path = File.join(dir, 'main.pdf')
      txt1, _ = Open3.capture2('pdftotext', pdf_path, '-')
      assert_includes txt1, 'Initial Title'

      # Update refs.bib content, but forcibly backdate its mtime to be older than main.bbl!
      bib2 = bib1.sub('Initial Title', 'Updated Title')
      File.write(File.join(dir, 'refs.bib'), bib2)
      bbl_path = File.join(dir, 'main.bbl')
      past_time = File.mtime(bbl_path) - 100
      File.utime(past_time, past_time, File.join(dir, 'refs.bib'))

      _out2, status2 = Open3.capture2e(bin_path, 'main.tex', chdir: dir)
      assert_equal 0, status2.exitstatus
      txt2, _ = Open3.capture2('pdftotext', pdf_path, '-')
      assert_includes txt2, 'Updated Title', 'Biber should rerun because .bib content hash changed'
    end
  end

  def test_biber_single_pass_when_citations_and_bib_unchanged
    Dir.mktmpdir('biber_single_pass_test') do |dir|
      tex1 = <<~'TEX'
        \documentclass{article}
        \usepackage[backend=biber]{biblatex}
        \addbibresource{refs.bib}
        \begin{document}
        Citing: \cite{itemA}.
        \printbibliography
        \end{document}
      TEX
      bib = <<~'BIB'
        @article{itemA,
          author = {Author, Real},
          title = {A Valid Title},
          journal = {Journal},
          year = {2020}
        }
      BIB
      File.write(File.join(dir, 'main.tex'), tex1)
      File.write(File.join(dir, 'refs.bib'), bib)

      bin_path = File.expand_path('../latex_it', __dir__)
      out1, status1 = Open3.capture2e(bin_path, 'main.tex', chdir: dir)
      assert_equal 0, status1.exitstatus, "Pass 1 setup failed:\n#{out1}"
      assert File.exist?(File.join(dir, 'main.bbl')), 'Expected main.bbl to be created'

      # Text-only edit: no citations or bib files modified
      tex2 = tex1.sub('Citing:', 'Updated text citing:')
      File.write(File.join(dir, 'main.tex'), tex2)

      out2, status2 = Open3.capture2e(bin_path, 'main.tex', chdir: dir)
      assert_equal 0, status2.exitstatus, "Recompile failed:\n#{out2}"
      refute_includes out2, 'biber', 'Biber must not rerun on text-only edit'
      refute_includes out2, '(2)', 'Must converge in exactly 1 pass'
    end
  end

  def test_biber_reruns_when_bcf_options_change_in_source
    Dir.mktmpdir('biber_bcf_option_test') do |dir|
      tex1 = <<~'TEX'
        \documentclass{article}
        \usepackage[backend=biber]{biblatex}
        \addbibresource{refs.bib}
        \begin{document}
        Citing: \cite{itemA}.
        \printbibliography
        \end{document}
      TEX
      bib = <<~'BIB'
        @article{itemA,
          author = {Author, Real},
          title = {A Valid Title},
          journal = {Journal},
          year = {2020}
        }
      BIB
      File.write(File.join(dir, 'main.tex'), tex1)
      File.write(File.join(dir, 'refs.bib'), bib)

      bin_path = File.expand_path('../latex_it', __dir__)
      out1, status1 = Open3.capture2e(bin_path, 'main.tex', chdir: dir)
      assert_equal 0, status1.exitstatus, "Pass 1 setup failed:\n#{out1}"

      # Change biblatex options in TeX preamble: alters .bcf control file
      tex2 = tex1.sub('\usepackage[backend=biber]{biblatex}', '\usepackage[backend=biber,sorting=none]{biblatex}')
      File.write(File.join(dir, 'main.tex'), tex2)

      out2, status2 = Open3.capture2e(bin_path, 'main.tex', chdir: dir)
      assert_equal 0, status2.exitstatus, "Option change compile failed:\n#{out2}"
      assert_includes out2, 'biber', 'Biber must rerun when .bcf configuration options change'
    end
  end
end
