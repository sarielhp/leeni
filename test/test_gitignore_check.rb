# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

# --gitignore-init: build, add the ignore rules, then check that git ignores
# no project file the paper uses.
class TestGitignoreCheck < Minitest::Test
  BIN = File.expand_path('../leeni', __dir__)
  PAPER = <<~'TEX'
    \documentclass{article}
    \usepackage{graphicx}
    \begin{document}
    \input{parts/part}
    \includegraphics{figs/plot.pdf}
    \end{document}
  TEX

  def test_failed_build_leaves_gitignore_alone
    in_project do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n\\begin{document}\\undefinedmacro\\end{document}\n")
      output, status = run_init(dir)
      assert_equal 1, status.exitstatus, output
      refute_path_exists File.join(dir, '.gitignore')
    end
  end

  # *.pdf would hide figs/plot.pdf, but the rules keep figures under figs/;
  # parts/ hides an input of the paper, which is reported.
  def test_figures_are_kept_and_ignored_inputs_are_reported
    in_project do |dir|
      write_paper(dir)
      File.write(File.join(dir, '.gitignore'), "*.pdf\nparts/\n")
      output, status = run_init(dir)
      assert_equal 1, status.exitstatus, output
      assert_includes File.read(File.join(dir, '.gitignore')), "!**/figs/**/*.pdf\n"
      assert_match %r{parts/part\.tex\s+\(\.gitignore:2:parts/\)}, output
      refute_includes output, 'figs/plot.pdf'
      refute_includes output, 'paper.pdf'

      File.write(File.join(dir, '.gitignore'), File.read(File.join(dir, '.gitignore')).sub("parts/\n", ''))
      output, status = run_init(dir)
      assert status.success?, output
      assert_includes output, 'Git ignores none of the project files the paper uses'
    end
  end

  # A tracked file is in every clone whatever the ignore rules say.
  def test_tracked_files_are_not_reported
    in_project do |dir|
      write_paper(dir)
      File.write(File.join(dir, '.gitignore'), "parts/\n")
      Open3.capture2e('git', 'add', '-f', 'parts/part.tex', chdir: dir)
      output, status = run_init(dir)
      assert status.success?, output
    end
  end

  # With TEXINPUTS the build reads the shared file, but a clone built without
  # it uses the project copy -I made in styles/; that copy must not be ignored.
  def test_project_copy_of_an_outside_file_is_checked
    Dir.mktmpdir('gitignore_outside') do |root|
      dir = File.join(root, 'project')
      shared = File.join(root, 'shared')
      FileUtils.mkdir_p([dir, shared, File.join(dir, 'styles')])
      sty = "\\ProvidesPackage{sharedsty}\n"
      [shared, File.join(dir, 'styles')].each { |where| File.write(File.join(where, 'sharedsty.sty'), sty) }
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n\\usepackage{sharedsty}\n\\begin{document}x\\end{document}\n")
      File.write(File.join(dir, '.gitignore'), "styles/\n")
      Open3.capture2e('git', 'init', '-q', chdir: dir)
      output, status = Open3.capture2e({ 'TEXINPUTS' => "#{shared}:.:" }, BIN, '-e', 'p', '--gitignore-init', 'paper.tex', chdir: dir)
      assert_equal 1, status.exitstatus, output
      assert_match %r{styles/sharedsty\.sty\s+\(\.gitignore:1:styles/\)}, output
    end
  end

  def test_outside_a_repository_only_writes_the_rules
    Dir.mktmpdir('gitignore_norepo') do |dir|
      write_paper(dir)
      output, status = run_init(dir)
      assert status.success?, output
      assert_includes output, 'Not inside a git repository'
      assert_includes File.read(File.join(dir, '.gitignore')), "!**/figs/**/*.pdf\n"
    end
  end

  private

  def in_project
    Dir.mktmpdir('gitignore_check') do |dir|
      Open3.capture2e('git', 'init', '-q', chdir: dir)
      yield dir
    end
  end

  def write_paper(dir)
    FileUtils.mkdir_p([File.join(dir, 'parts'), File.join(dir, 'figs')])
    File.write(File.join(dir, 'parts', 'part.tex'), "Part.\n")
    make_pdf(File.join(dir, 'figs', 'plot.pdf'))
    File.write(File.join(dir, 'paper.tex'), PAPER)
  end

  def make_pdf(path)
    Dir.mktmpdir('plot') do |tmp|
      File.write(File.join(tmp, 'p.tex'), "\\documentclass{standalone}\\begin{document}P\\end{document}\n")
      Open3.capture2e('pdflatex', '-interaction=nonstopmode', 'p.tex', chdir: tmp)
      FileUtils.cp(File.join(tmp, 'p.pdf'), path)
    end
  end

  def run_init(dir)
    Open3.capture2e(BIN, '-e', 'p', '-G', 'paper.tex', chdir: dir)
  end
end
