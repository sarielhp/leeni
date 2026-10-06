#!/usr/bin/env ruby
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class TestReviewIntegration < Minitest::Test
  BIN = File.expand_path("../leeni", __dir__)
  load BIN

  def fixture
    Dir.mktmpdir('leeni_independent_') do |dir|
      File.write(File.join(dir, '.l.jsonc'), '{"engine":"xelatex"}')
      yield dir
    end
  end

  def run_cli(dir, *args)
    cache_dir = File.join(dir, 'junk', 'texmf-cache')
    FileUtils.mkdir_p(cache_dir)
    Open3.capture2e({ 'TEXMFCACHE' => cache_dir }, BIN, *args, chdir: dir)
  end

  def document(body)
    "\\documentclass{article}\n\\title{Review Paper}\n\\author{Fixture Author}\n\\date{}\n" \
      "\\begin{document}\n\\maketitle\n#{body}\n\\end{document}\n"
  end

  def test_arxiv_rejects_author_names_hidden_from_both_pdfs
    fixture do |dir|
      File.write(File.join(dir, 'paper.tex'), document('Anonymous submission.').sub('\\maketitle', ''))
      output, status = run_cli(dir, '-e', 'pdflatex', '--arxiv', '--no-biblatex-shield', 'paper.tex')
      refute status.success?, output
      assert_includes output, 'Fixture Author'
      assert_match(/first page|page 1/i, output)
      refute_includes output, '[VERIFIED]'
      refute_includes output, 'Preparation Complete'
    end
  end

  def test_arxiv_rejects_author_names_appearing_only_on_later_pages
    fixture do |dir|
      tex = document("Anonymous submission.\\newpage\nReferences mention Fixture Author.")
      File.write(File.join(dir, 'paper.tex'), tex.sub('\\maketitle', ''))
      output, status = run_cli(dir, '-e', 'pdflatex', '--arxiv', '--no-arxiv-visual-verify',
                               '--no-biblatex-shield', 'paper.tex')
      refute status.success?, output
      assert_includes output, 'Fixture Author'
      assert_match(/first page|page 1/i, output)
      refute_includes output, '[VERIFIED]'
    end
  end

  def test_arxiv_rejects_one_missing_coauthor
    fixture do |dir|
      tex = document('Visible Author presents the paper.').sub('\\maketitle', '')
      tex.sub!('Fixture Author', 'Visible Author \\and Missing Author')
      File.write(File.join(dir, 'paper.tex'), tex)
      output, status = run_cli(dir, '-e', 'pdflatex', '--arxiv', '--no-biblatex-shield', 'paper.tex')
      refute status.success?, output
      assert_includes output, 'Missing Author'
      refute_includes output, '[VERIFIED]'
    end
  end

  def test_arxiv_accepts_visible_accented_and_hyphenated_authors
    fixture do |dir|
      names = "Jos\\'{e} Garc\\'{i}a \\and Anne-Marie O'Neill \\and Jörg Müller"
      tex = document('Named submission.').sub('Fixture Author', names)
      File.write(File.join(dir, 'paper.tex'), tex)
      output, status = run_cli(dir, '--arxiv', '--no-biblatex-shield', 'paper.tex')
      assert status.success?, output
      assert_includes output, '[VERIFIED]'
      assert_match(/author.*(?:first page|page 1)/i, output)
    end
  end

  def test_real_subdirectory_archive_and_verification
    fixture do |dir|
      FileUtils.mkdir_p(File.join(dir, 'sub'))
      File.write(File.join(dir, 'sub/paper.tex'), document('Subdirectory test'))
      output, status = run_cli(dir, '--arxiv', '--no-biblatex-shield', 'sub/paper.tex')
      assert status.success?, output
      assert_includes output, '[VERIFIED]'
      assert File.file?(File.join(dir, 'sub/arxiv_paper.zip'))
    end
  end

  def test_real_engine_switch_and_cache_hit
    fixture do |dir|
      File.write(File.join(dir, 'paper.tex'), document('Engine test'))
      output, status = run_cli(dir, 'paper.tex')
      assert status.success?, output
      output, status = run_cli(dir, 'paper.tex')
      assert status.success?, output
      assert_includes output, 'up-to-date'
      output, status = run_cli(dir, '-e', 'lualatex', 'paper.tex')
      assert status.success?, output
      refute_includes output, 'up-to-date'
      assert_includes output, 'lualatex'
    end
  end

  def test_pdflatex_build_cache_and_switch_to_default_engine
    fixture do |dir|
      body = '\\ifdefined\\pdftexversion PDF engine selected\\else Other engine selected\\fi'
      File.write(File.join(dir, 'paper.tex'), document(body))
      output, status = run_cli(dir, '-e', 'pdflatex', 'paper.tex')
      assert status.success?, output
      assert_includes File.read(File.join(dir, 'junk/paper.log')), 'pdfTeX'
      text, status = Open3.capture2e('pdftotext', File.join(dir, 'paper.pdf'), '-')
      assert status.success?, text
      assert_includes text, 'PDF engine selected'
      output, status = run_cli(dir, '--engine', 'pdflatex', 'paper.tex')
      assert status.success?, output
      assert_includes output, 'up-to-date'
      output, status = run_cli(dir, 'paper.tex')
      assert status.success?, output
      refute_includes output, 'up-to-date'
      assert_includes File.read(File.join(dir, 'junk/paper.log')), 'XeTeX'
    end
  end

  def test_pdflatex_config_and_both_archive_verifiers
    fixture do |dir|
      File.write(File.join(dir, '.l.jsonc'), '{"engine":"pdflatex"}')
      body = '\\ifdefined\\pdftexversion PDF engine selected\\else Wrong engine selected\\fi'
      File.write(File.join(dir, 'paper.tex'), document(body))
      output, status = run_cli(dir, '--arxiv', '--no-biblatex-shield', 'paper.tex')
      assert status.success?, output
      assert_includes output, '[VERIFIED]'
      assert_includes File.read(File.join(dir, 'junk/paper.log')), 'pdfTeX'
      output, status = run_cli(dir, '--zip', '--verify', 'paper.tex')
      assert status.success?, output
      assert_includes output, '[VERIFIED]'
    end
  end

  def test_arxiv_rejects_archive_that_compiles_with_different_text
    fixture do |dir|
      File.write(File.join(dir, 'paper.tex'), document('Original paper words'))
      output, status = run_cli(dir, 'paper.tex')
      assert status.success?, output
      File.write(File.join(dir, 'paper.tex'), document('Changed submission words'))
      output, status = Open3.capture2e('zip', '-q', 'changed.zip', 'paper.tex', chdir: dir)
      assert status.success?, output
      Dir.chdir(dir) do
        packager = LatexArxivPackager.new(LatexBuilder.new('paper.tex', {}))
        verified = nil
        out, err = capture_io { verified = packager.send(:verify_arxiv_sandbox!, 'changed.zip') }
        refute verified, 'Different text was accepted after a successful compilation'
        refute_includes out, '[VERIFIED]'
        assert_match(/text.*differ/i, out + err)
      end
    end
  end

  def test_arxiv_refreshes_reference_despite_existing_bibliography_and_recorder
    fixture do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, document('Original paper words'))
      output, status = run_cli(dir, 'paper.tex')
      assert status.success?, output
      File.write(File.join(dir, 'paper.bbl'), "\\bibitem{x} Existing bibliography\n")
      File.write(path, document('Updated paper words'))
      output, status = run_cli(dir, '--arxiv', '--no-biblatex-shield', 'paper.tex')
      assert status.success?, output
      assert_includes output, '[VERIFIED]'
      text, status = Open3.capture2e('pdftotext', '-layout', File.join(dir, 'paper.pdf'), '-')
      assert status.success?, text
      assert_includes text, 'Updated paper words'
    end
  end

  def test_arxiv_verifies_with_explicit_lua_engine
    fixture do |dir|
      body = '\\ifdefined\\directlua Lua engine selected\\else Wrong engine selected\\fi'
      File.write(File.join(dir, 'paper.tex'), document(body))
      output, status = run_cli(dir, '-e', 'lualatex', '--arxiv', '--no-biblatex-shield', 'paper.tex')
      assert status.success?, output
      assert_includes output, '[VERIFIED]'
    end
  end

  def test_arxiv_cli_fails_when_sandbox_changes_document_text
    fixture do |dir|
      File.write(File.join(dir, 'local-marker'), 'present only in original project')
      body = "Shared document text.\n" \
             '\\IfFileExists{local-marker}{Original project text}{Different sandbox text}'
      File.write(File.join(dir, 'paper.tex'), document(body))
      output, status = run_cli(dir, '--arxiv', '--no-biblatex-shield', 'paper.tex')
      refute status.success?, output
      assert_match(/text.*differ/i, output)
      refute_includes output, '[VERIFIED]'
      refute_includes output, 'Preparation Complete'
    end
  end

  def test_arxiv_visual_check_rejects_changed_figure_after_matching_text
    fixture do |dir|
      File.write(File.join(dir, 'local-color'), 'present')
      tex = document("First page.\\newpage\nSecond page.\n" \
        "{\\IfFileExists{local-color}{\\redink}{\\blueink}\n\\rule{30pt}{30pt}}")
      tex.sub!('\\begin{document}', "\\usepackage{xcolor}\n" \
        "\\def\\redink{\\color{red}}\n\\def\\blueink{\\color{blue}}\n\\begin{document}")
      File.write(File.join(dir, 'paper.tex'), tex)
      args = ['-e', 'pdflatex', '--arxiv', '--no-biblatex-shield', 'paper.tex']
      output, status = run_cli(dir, *args)
      refute status.success?, output
      assert_includes output, 'text layout exactly matches'
      assert_match(/(?:visual|pixel|rendered).*?(?:differ|mismatch)|(?:differ|mismatch).*?(?:visual|pixel|rendered)/i, output)
      refute_includes output, '[VERIFIED]'
      refute_includes output, 'Preparation Complete'
      output, status = run_cli(dir, '--no-arxiv-visual-verify', *args)
      assert status.success?, output
      assert_match(/visual.*skip/i, output)
      assert_includes output, '[VERIFIED]'
      File.write(File.join(dir, '.l.jsonc'), '{"arxiv":{"visual_verify":false}}')
      output, status = run_cli(dir, *args)
      assert status.success?, output
      assert_match(/visual.*skip/i, output)
      output, status = run_cli(dir, '--arxiv-visual-verify', *args)
      refute status.success?, output
      refute_includes output, '[VERIFIED]'
    end
  end

  def test_arxiv_visual_check_accepts_matching_multiple_pages
    fixture do |dir|
      File.write(File.join(dir, 'paper.tex'), document("First page.\\newpage\nSecond page.\\rule{30pt}{30pt}"))
      output, status = run_cli(dir, '-e', 'pdflatex', '--arxiv', '--no-biblatex-shield', 'paper.tex')
      assert status.success?, output
      assert_includes output, '[VERIFIED]'
      assert_match(/visual|pixel|rendered/i, output)
    end
  end

  def test_real_flattening_macro_tokens_and_repeated_inputs
    fixture do |dir|
      File.write(File.join(dir, 'part.tex'), "\\advance\\reviewcount by 1\n")
      tex = "\\documentclass{article}\n\\newcount\\reviewcount\n" \
            "\\def\\reviewword{foo% remove me\nbar}\n" \
            "\\def\\reviewfirst{foo}\n\\def\\reviewcommand{\\reviewfirst% remove me\nbar}\n" \
            "\\def\\reviewindented{foo% remove me\n  bar}\n" \
            "\\input{part}\n\\input{part}\n" \
            "\\begin{document}\n\\reviewword: \\the\\reviewcount. \\reviewcommand. \\reviewindented.\n\\end{document}\n"
      File.write(File.join(dir, 'paper.tex'), tex)
      output, status = run_cli(dir, 'paper.tex')
      assert status.success?, output
      original, status = Open3.capture2e('pdftotext', '-layout', File.join(dir, 'paper.pdf'), '-')
      assert status.success?, original
      File.write(File.join(dir, 'flat.tex'), LaTeXFlattener.flatten('paper.tex', dir))
      output, status = run_cli(dir, 'flat.tex')
      assert status.success?, output
      flattened, status = Open3.capture2e('pdftotext', '-layout', File.join(dir, 'flat.pdf'), '-')
      assert status.success?, flattened
      assert_equal original, flattened
    end
  end

  def test_failed_verification_has_nonzero_exit
    fixture do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'paper.tex'), document('\\undefinedreviewcommand'))
      File.write(File.join(dir, 'paper.bbl'), "\\bibitem{x} Previous bibliography\n")
      File.write(File.join(dir, 'junk/paper.fls'), "INPUT ./paper.tex\n")
      output, status = run_cli(dir, '--arxiv', '--no-biblatex-shield', 'paper.tex')
      refute status.success?, output
      refute_includes output, 'Preparation Complete'
    end
  end

  def test_nested_source_same_second_rebuilds
    fixture do |dir|
      FileUtils.mkdir_p(File.join(dir, 'sections'))
      File.write(File.join(dir, 'paper.tex'), document('\\input{sections/intro}'))
      path = File.join(dir, 'sections/intro.tex')
      File.write(path, 'Original words')
      original_time = File.mtime(path)
      output, status = run_cli(dir, 'paper.tex')
      assert status.success?, output
      File.write(path, 'Changed words!')
      changed_time = Time.at(original_time.to_i, 800_000)
      File.utime(changed_time, changed_time, path)
      output, status = run_cli(dir, 'paper.tex')
      assert status.success?, output
      refute_includes output, 'up-to-date'
      text, = Open3.capture2e('pdftotext', File.join(dir, 'paper.pdf'), '-')
      assert_includes text, 'Changed words!'
    end
  end

  def test_single_pass_does_not_cache_unresolved_references
    fixture do |dir|
      File.write(File.join(dir, 'paper.tex'), document('See Section \\ref{sec:test}. \\section{Test}\\label{sec:test}'))
      output, status = run_cli(dir, '-u', 'paper.tex')
      assert status.success?, output
      output, status = run_cli(dir, 'paper.tex')
      assert status.success?, output
      refute_includes output, 'up-to-date'
      text, = Open3.capture2e('pdftotext', File.join(dir, 'paper.pdf'), '-')
      refute_includes text, '??'
    end
  end

  def test_real_bibliography_failure_preserves_previous_root
    fixture do |dir|
      File.write(File.join(dir, 'paper.tex'), document("\\cite{key}\n\\bibliographystyle{plain}\n\\bibliography{refs}"))
      File.write(File.join(dir, 'refs.bib'), '@article{key, author={A Author}, title={Old Title}, journal={Journal}, year={2026}}')
      output, status = run_cli(dir, 'paper.tex')
      assert status.success?, output
      old_bbl = File.read(File.join(dir, 'paper.bbl'))
      File.write(File.join(dir, 'refs.bib'), '@article{key, author= broken syntax')
      output, status = run_cli(dir, '--bib', 'paper.tex')
      refute status.success?, output
      assert_equal old_bbl, File.read(File.join(dir, 'paper.bbl'))
      refute File.exist?(File.join(dir, 'junk/.build_state.json'))
    end
  end

  def test_sandbox_cannot_use_ambient_personal_tex_tree
    original_texmfhome = ENV['TEXMFHOME']
    fixture do |dir|
      personal_tree = File.join(dir, 'personal-texmf')
      package_dir = File.join(personal_tree, 'tex', 'latex', 'reviewonly')
      FileUtils.mkdir_p(package_dir)
      File.write(File.join(package_dir, 'reviewonly.sty'), "\\ProvidesPackage{reviewonly}\n")
      ENV['TEXMFHOME'] = personal_tree
      File.write(File.join(dir, 'paper.tex'), document('Personal package test').sub(
        '\\begin{document}', "\\usepackage{reviewonly}\n\\begin{document}"
      ))
      output, status = run_cli(dir, 'paper.tex')
      assert status.success?, output
      output, status = Open3.capture2e('zip', '-q', 'manual.zip', 'paper.tex', chdir: dir)
      assert status.success?, output
      Dir.chdir(dir) do
        packager = LatexArxivPackager.new(LatexBuilder.new('paper.tex', {}))
        verified = nil
        _out, err = capture_io { verified = packager.send(:verify_arxiv_sandbox!, 'manual.zip') }
        refute verified, 'Sandbox unexpectedly loaded the excluded personal package'
        assert_includes err, 'reviewonly.sty'
      end
    end
  ensure
    ENV['TEXMFHOME'] = original_texmfhome
  end
end
