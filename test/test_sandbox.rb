# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

load File.expand_path('../leeni', __dir__)

# Stale style copies, tracking of styles outside the project, and --sandbox.
class TestSandbox < Minitest::Test
  BIN = File.expand_path('../leeni', __dir__)
  BIB = "@article{b, author={B. Author}, title={Beta}, journal={J. ACM}, year=2001}\n"

  def setup
    @tmp = Dir.mktmpdir('leeni_sandbox_test')
    @env = { 'XDG_CACHE_HOME' => File.join(@tmp, 'cache'), 'TEXINPUTS' => nil, 'BIBINPUTS' => nil, 'BSTINPUTS' => nil }
    @project = File.join(@tmp, 'project')
    FileUtils.mkdir_p(@project)
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  # BibTeX used to get a copy of styles/ in the build directory, where TeX
  # then read it instead of the project's file, so edits never showed.
  def test_edits_in_styles_show_with_a_bibliography
    write('styles/foo.sty', "\\ProvidesPackage{foo}\n\\newcommand{\\msg}{OLD VERSION}\n")
    write('refs.bib', BIB)
    write('paper.tex', <<~'TEX')
      \makeatletter\def\input@path{{styles/}}\makeatother
      \documentclass{article}
      \usepackage{foo}
      \begin{document}\msg\ \cite{b}\bibliographystyle{plain}\bibliography{refs}\end{document}
    TEX
    assert_build_success
    write('styles/foo.sty', "\\ProvidesPackage{foo}\n\\newcommand{\\msg}{NEW VERSION}\n")
    assert_build_success
    assert_includes pdf_text, 'NEW VERSION'
    cache = LeeniBuildWorkspace.cache_dir(@project).sub(LeeniBuildWorkspace.cache_home, @env['XDG_CACHE_HOME'])
    assert_empty Dir.glob(File.join(cache, '**', '*.sty'))
  end

  def test_bst_files_are_found_in_the_project_and_styles
    write('refs.bib', BIB)
    plain = Open3.capture2('kpsewhich', 'plain.bst').first.strip
    FileUtils.mkdir_p(File.join(@project, 'styles'))
    FileUtils.cp(plain, File.join(@project, 'rootstyle.bst'))
    FileUtils.cp(plain, File.join(@project, 'styles', 'substyle.bst'))
    %w[rootstyle styles/substyle].each do |style|
      write('paper.tex', "\\documentclass{article}\n\\begin{document}\\cite{b}" \
                         "\\bibliographystyle{#{style}}\\bibliography{refs}\\end{document}\n")
      assert_build_success('--no-env', '-f')
      assert_includes pdf_text, 'J. ACM', style
    end
  end

  def test_editing_a_style_outside_the_project_rebuilds
    outside = File.join(@tmp, 'outside')
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, 'bar.sty'), "\\ProvidesPackage{bar}\n\\newcommand{\\msg}{OLD}\n")
    write('paper.tex', "\\documentclass{article}\n\\usepackage{bar}\n\\begin{document}\\msg\\end{document}\n")
    @env['TEXINPUTS'] = ".:#{outside}:"
    assert_build_success
    assert_includes assert_build_success, 'up-to-date'
    File.write(File.join(outside, 'bar.sty'), "\\ProvidesPackage{bar}\n\\newcommand{\\msg}{NEW}\n")
    refute_includes assert_build_success, 'up-to-date'
    assert_includes pdf_text, 'NEW'
  end

  def test_sandbox_rebuilds_without_the_environment_and_stays_incremental
    outside = File.join(@tmp, 'outside')
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, 'bar.sty'), "\\ProvidesPackage{bar}\n\\newcommand{\\msg}{OLD}\n")
    write('paper.tex', "\\documentclass{article}\n\\usepackage{bar}\n\\begin{document}\\msg\\end{document}\n")
    @env['TEXINPUTS'] = ".:#{outside}:"

    first = assert_build_success('--sandbox')
    assert_includes first, 'Sandbox refreshed: 2 copied'
    assert_includes first, 'Sandbox build with --no-env matches paper.pdf'
    sandbox = File.join(@env['XDG_CACHE_HOME'], 'leeni', 'sandboxes',
                        File.basename(LeeniBuildWorkspace.cache_dir(@project)), 'paper')
    assert_path_exists File.join(sandbox, 'styles', 'bar.sty')
    assert_equal File.read(File.join(@project, 'paper.tex')).lines.last,
                 File.read(File.join(sandbox, 'paper.tex')).lines.last

    refute_includes assert_build_success('--sandbox'), 'Sandbox refreshed'
    File.write(File.join(outside, 'bar.sty'), "\\ProvidesPackage{bar}\n\\newcommand{\\msg}{NEW}\n")
    assert_includes assert_build_success('--sandbox'), 'Sandbox refreshed: 1 copied'

    _, status = Open3.capture2e(@env, BIN, '-C', chdir: @project)
    assert status.success?
    refute_path_exists File.dirname(sandbox)
  end

  def test_sandbox_fails_when_the_paper_needs_the_environment
    File.write(File.join(@tmp, 'marker.txt'), 'x')
    write('paper.tex', "\\documentclass{article}\n\\begin{document}\\IfFileExists{../marker.txt}{Found}{Missing}\\end{document}\n")
    output, status = Open3.capture2e(@env, BIN, '--sandbox', 'paper.tex', chdir: @project)
    assert_equal 1, status.exitstatus, output
    assert_includes output, 'PDF text layout differs'
  end

  def test_sandbox_rejects_arxiv
    write('paper.tex', "\\documentclass{article}\n\\begin{document}x\\end{document}\n")
    output, status = Open3.capture2e(@env, BIN, '--sandbox', '--arxiv', 'paper.tex', chdir: @project)
    assert_equal 2, status.exitstatus, output
  end

  def test_zip_alone_archives_the_sandbox
    write('styles/foo.sty', "\\ProvidesPackage{foo}\n\\newcommand{\\msg}{Styled}\n")
    write('paper.tex', "\\documentclass{article}\n\\usepackage{styles/foo}\n\\begin{document}\\msg\\end{document}\n")
    assert_build_success('--zip-alone')
    listing = Open3.capture2e('unzip', '-Z1', File.join(@project, 'paper.zip')).first.lines.map(&:strip)
    assert_includes listing, 'styles/foo.sty'
    assert_includes listing, 'paper.pdf'
    assert_empty listing.grep(/synctex/)
  end

  def test_pruner_removes_sandboxes_without_a_project
    cache = File.join(@tmp, 'prune')
    orphan = File.join(cache, 'leeni', 'sandboxes', 'gone-0123456789abcdef', 'paper')
    FileUtils.mkdir_p(orphan)
    saved = ENV.fetch('XDG_CACHE_HOME', nil)
    ENV['XDG_CACHE_HOME'] = cache
    LeeniCachePruner.run(days: 10)
    refute_path_exists File.dirname(orphan)
  ensure
    ENV['XDG_CACHE_HOME'] = saved
  end

  private

  def write(rel, content)
    path = File.join(@project, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def assert_build_success(*flags)
    output, status = Open3.capture2e(@env, BIN, '-e', 'p', *flags, 'paper.tex', chdir: @project)
    assert status.success?, output
    output
  end

  def pdf_text
    Open3.capture2e('pdftotext', File.join(@project, 'paper.pdf'), '-').first
  end
end
