#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "fileutils"
require "open3"

class TestArxivSupport < Minitest::Test
  BIN = File.expand_path("../latex_it", __dir__)
  load BIN

  def test_meta_extraction_title_and_math
    tex = <<~TEX
      \\documentclass{article}
      \\title{Fast \\textbf{Approximations} of $\\alpha \\le \\beta$ in $\\mathbb{R}^d$}
      \\begin{document}
      \\end{document}
    TEX
    assert_equal "Fast Approximations of α ≤ β in R^d", LaTeXMetaExtractor.extract_title(tex)
  end

  def test_clean_latex_math_comprehensive
    raw = "\\alpha \\beta \\gamma \\Delta \\Omega \\leq \\ge \\approx \\times \\cdot \\in \\infty \\sum \\log(x) \\sqrt{y+1} \\mathbb{R} \\mathcal{H} \\mathfrak{g} $z$"
    expected = "α β γ Δ Ω ≤ ≥ ≈ × · ∈ ∞ ∑ log(x) √(y+1) R H g z"
    assert_equal expected, LaTeXMetaExtractor.clean_latex_math(raw)
  end

  def test_meta_extraction_authors
    tex = <<~TEX
      \\documentclass{article}
      \\author{Alice Smith\\thanks{Supported by NSF}\\\\University of Illinois \\and Timothy M. Chan\\affil{UIUC}}
      \\begin{document}
      \\end{document}
    TEX
    authors = LaTeXMetaExtractor.extract_authors(tex)
    assert_includes authors, "Alice Smith"
    assert_includes authors, "Timothy M. Chan"
    refute_includes authors, "University of Illinois"
    refute_includes authors, "Supported by NSF"
  end

  def test_meta_extraction_abstract
    tex = <<~TEX
      \\documentclass{article}
      \\begin{document}
      \\begin{abstract}
        % This is a private draft note
        We study the problem of computing $\\mathcal{O}(n \\log n)$ approximations.
        Here is more text in the same paragraph.

        Second paragraph with $x \\in X$.
      \\end{abstract}
      \\end{document}
    TEX
    abstract = LaTeXMetaExtractor.extract_abstract(tex)
    refute_includes abstract, "private draft note"
    assert_includes abstract, "O(n log n)"
    assert_includes abstract, "x ∈ X"
    assert_includes abstract, "paragraph.\n\nSecond paragraph"
  end

  def test_meta_extraction_abstract_uses_arxiv_web_format
    tex = <<~TEX
      \\begin{abstract}
        First  paragraph with odd spacing.%
        % Empty and non-empty comments must disappear.
        continued text.

        Second paragraph with an escaped percent: 50\\% complete.% trailing comment
      \\end{abstract}
    TEX

    abstract = LaTeXMetaExtractor.extract_abstract(tex)
    expected = "First paragraph with odd spacing. continued text.\n\nSecond paragraph with an escaped percent: 50% complete."
    assert_equal expected, abstract
    refute_match(/%/, abstract.sub('50%', ''))
    refute_match(/[ \t]+\n|\n[ \t]+/, abstract)
  end

  def test_meta_extraction_abstract_for_arxiv_form
    tex = <<~TEX
      \\begin{abstract}
        First paragraph with Chérif and “odd” spacing. % private note
        continued with $\\alpha \\leq β$.

        Second paragraph with \\textbf{formatting} and 50\\% complete.
      \\end{abstract}
    TEX

    abstract = LaTeXMetaExtractor.extract_abstract_for_arxiv(tex)
    expected = "First paragraph with Ch\\'erif and \"odd\" spacing. continued with $\\alpha \\leq \\beta$.\n Second paragraph with formatting and 50% complete."
    assert_equal expected.encode(Encoding::US_ASCII), abstract
    assert_equal Encoding::US_ASCII, abstract.encoding
    refute_match(/% private note|\\textbf|[[:space:]]+\n[[:space:]]*\n/, abstract)
  end

  def test_flattener_recursive_inlining_and_comment_stripping
    Dir.mktmpdir do |dir|
      main_tex = <<~TEX
        %!TEX TS-program = xelatex
        \\documentclass{article}
        % Document level comment
        \\input{section1}
        \\begin{document}
        50\\% discount at \\url{https://example.com/%20test} % end of line comment
        \\include{section2}
        \\end{document}
      TEX
      sec1_tex = <<~TEX
        % Section 1 comment
        \\newcommand{\\foo}{bar}
      TEX
      sec2_tex = <<~TEX
        \\section{Second}
        Content of section 2.
      TEX

      File.write(File.join(dir, "main.tex"), main_tex)
      File.write(File.join(dir, "section1.tex"), sec1_tex)
      File.write(File.join(dir, "section2.tex"), sec2_tex)

      flattened = LaTeXFlattener.flatten("main.tex", dir)
      assert flattened.start_with?("%!TEX TS-program = xelatex\n")
      assert_includes flattened, "\\newcommand{\\foo}{bar}"
      assert_includes flattened, "\\section{Second}"
      assert_includes flattened, "50\\% discount at \\url{https://example.com/%20test}"
      refute_includes flattened, "Document level comment"
      refute_includes flattened, "Section 1 comment"
      refute_includes flattened, "end of line comment"
    end
  end

  def test_flattener_repeats_inputs_and_preserves_comment_newlines
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'part.tex'), "\\advance\\count0 by 1\n")
      File.write(File.join(dir, 'main.tex'), "\\def\\word{foo% hidden\nbar}\n\\input{part}\n\\input{part}\n")

      flattened = LaTeXFlattener.flatten('main.tex', dir)
      assert_equal 2, flattened.scan('\\advance\\count0 by 1').size
      assert_includes flattened, "\\def\\word{foo%\nbar}"
      refute_includes flattened, 'hidden'
    end
  end

  def test_flattener_reports_input_cycles
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.tex'), "\\input{b}\n")
      File.write(File.join(dir, 'b.tex'), "\\input{a}\n")

      error = assert_raises(RuntimeError) { LaTeXFlattener.flatten('a.tex', dir) }
      assert_includes error.message, 'Cyclic LaTeX input detected'
      assert_includes error.message, 'a.tex -> b.tex -> a.tex'
    end
  end

  def test_arxiv_packaging_and_dual_announcement
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "figs"))
      FileUtils.mkdir_p(File.join(dir, "junk"))

      File.write(File.join(dir, "paper.tex"), "\\documentclass{article}\n\\title{Test Paper}\n\\author{Jane Doe}\n\\begin{abstract}Abstract text\\end{abstract}\n\\begin{document}Hello\\end{document}\n")
      File.write(File.join(dir, "paper.pdf"), "PDF-DUMMY")
      File.write(File.join(dir, "paper.bbl"), "\\begin{thebibliography}{1}\n\\bibitem{key} Author, Title.\n\\end{thebibliography}\n")
      File.write(File.join(dir, "paper.bib"), "@article{key, title={T}}\n")
      File.write(File.join(dir, "figs", "fig1.pdf"), "PDF-FIGURE")
      File.write(File.join(dir, "figs", "fig1.fig"), "FIG-RAW-SOURCE")
      File.write(File.join(dir, "figs", "fig1.ipe"), "IPE-RAW-SOURCE")

      fls_content = <<~FLS
        INPUT /usr/share/texlive/texmf-dist/tex/latex/base/article.cls
        INPUT ./figs/fig1.pdf
        INPUT ./paper.tex
      FLS
      File.write(File.join(dir, "junk", "paper.fls"), fls_content)

      builder = LatexBuilder.new("paper.tex", {})
      packager = LatexArxivPackager.new(builder, { arxiv_verify: false })

      Dir.chdir(dir) do
        out, = capture_io do
          builder.stub(:run_in_current_directory!, true) { assert packager.package! }
        end

        assert File.file?("arxiv_paper.zip")
        assert File.file?("arxiv_paper_meta.txt")

        assert_includes out, "==> arXiv Preparation Complete!"
        assert_includes out, "[1] Submission Archive : arxiv_paper.zip"
        assert_includes out, "[2] Paper Metadata     : arxiv_paper_meta.txt"

        meta_content = File.read("arxiv_paper_meta.txt")
        assert_includes meta_content, "Title:\nTest Paper"
        assert_includes meta_content, "Authors:\nJane Doe"
        assert_includes meta_content, "Abstract:\nAbstract text"

        entries, = Open3.capture2("unzip", "-l", "arxiv_paper.zip")
        assert_includes entries, "paper.tex"
        assert_includes entries, "paper.bbl"
        assert_includes entries, "figs/fig1.pdf"

        refute_includes entries, "paper.pdf"
        refute_includes entries, "paper.bib"
        refute_includes entries, "figs/fig1.fig"
        refute_includes entries, "figs/fig1.ipe"
      end
    end
  end

  def test_arxiv_stages_recorded_eps_figures_preserving_paths
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        FileUtils.mkdir_p('figs/nested')
        File.write('paper.tex', '\\documentclass{article}\n')
        File.write('figs/nested/plot.EPS', 'EPS-CONTENTS')
        File.write('figs/unrecorded.eps', 'DO-NOT-COPY')
        File.write('junk/paper.fls', "INPUT ./figs/nested/plot.EPS\n")

        builder = LatexBuilder.new('paper.tex', {})
        packager = LatexArxivPackager.new(builder)
        stage = Dir.mktmpdir('arxiv_stage_')
        begin
          packager.send(:stage_active_figures, stage)
          staged = File.join(stage, 'figs/nested/plot.EPS')
          assert_equal 'EPS-CONTENTS', File.read(staged)
          refute File.exist?(File.join(stage, 'figs/unrecorded.eps'))
        ensure
          FileUtils.remove_entry(stage)
        end
      end
    end
  end

  def test_cli_meta_flag
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "paper.tex"), "\\documentclass{article}\n\\title{CLI Title}\n\\author{Bob Author}\n\\begin{abstract}Quick summary\\end{abstract}\n\\begin{document}\\end{document}\n")
      FileUtils.mkdir_p(File.join(dir, '.build'))
      FileUtils.mkdir_p(File.join(dir, 'figures'))
      File.write(File.join(dir, 'figures', 'chart.png'), 'PNG')
      File.write(File.join(dir, '.build', 'paper.fls'), "INPUT ./figures/chart.png\n")
      File.write(File.join(dir, '.build', 'paper.log'), 'Output written on paper.pdf (7 pages).')
      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '--meta', '--junk-dir', '.build', 'paper.tex')
        assert status.success?
        assert_includes stdout, "Title:"
        assert_includes stdout, "CLI Title"
        assert_includes stdout, "Authors:"
        assert_includes stdout, "Bob Author"
        assert_includes stdout, '7 pages, 1 figure.'
        assert_includes stdout, "==> Wrote paper metadata to: arxiv_paper_meta.txt"
        assert File.file?("arxiv_paper_meta.txt")
      end
    end
  end

  def test_cli_arxiv_flag
    Dir.mktmpdir do |dir|
      tex_content = <<~TEX
        \\documentclass{article}
        \\title{E2E Paper}
        \\author{Alice One \\and Bob Two}
        \\begin{document}
        \\maketitle
        \\begin{abstract}
          Sample abstract with $\\alpha \\le \\beta$.
        \\end{abstract}
        Hello world!
        \\end{document}
      TEX
      File.write(File.join(dir, 'paper.tex'), tex_content)

      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '--arxiv', '--junk-dir', '.build', 'paper.tex')
        assert status.success?, "l --arxiv failed: #{stdout}"
        assert_includes stdout, '==> arXiv Preparation Complete!'
        assert_includes stdout, '[1] Submission Archive : arxiv_paper.zip'
        assert_includes stdout, '[2] Paper Metadata     : arxiv_paper_meta.txt'

        assert File.file?('arxiv_paper.zip')
        assert File.file?('arxiv_paper_meta.txt')
        assert File.file?('.build/paper.fls')

        entries, = Open3.capture2('unzip', '-l', 'arxiv_paper.zip')
        assert_includes entries, 'paper.tex'
        refute_includes entries, 'paper.pdf'

        meta_txt = File.read('arxiv_paper_meta.txt')
        assert_includes meta_txt, "Title:\nE2E Paper"
        assert_includes meta_txt, "Authors:\nAlice One, Bob Two"
        assert_includes meta_txt, "Abstract:\nSample abstract with $\\alpha \\le \\beta$."
      end
    end
  end

  def test_copy_preserving_path_with_symlink_cwd
    Dir.mktmpdir('real_project') do |real_dir|
      Dir.mktmpdir('symlink_parent') do |parent_dir|
        sym_dir = File.join(parent_dir, 'sym_project')
        File.symlink(real_dir, sym_dir)

        fig_dir = File.join(real_dir, 'figures')
        FileUtils.mkdir_p(fig_dir)
        fig_path = File.join(fig_dir, 'chart.pdf')
        File.write(fig_path, '%PDF-1.4 dummy')

        stage_dir = File.join(real_dir, 'stage')
        FileUtils.mkdir_p(stage_dir)

        builder = LatexBuilder.new(File.join(sym_dir, 'paper.tex'), {})
        packager = LatexArxivPackager.new(builder)

        Dir.chdir(sym_dir) do
          packager.send(:copy_preserving_path, fig_path, stage_dir)
        end

        assert File.file?(File.join(stage_dir, 'figures', 'chart.pdf')),
               'copy_preserving_path dropped figure when executed from symlinked directory'
      end
    end
  end
end
