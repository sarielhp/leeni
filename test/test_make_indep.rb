# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

load File.expand_path('../leeni', __dir__)

class TestMakeIndep < Minitest::Test
  BIN = File.expand_path('../leeni', __dir__)

  BIB = <<~BIB
    @string{jacm = "J. ACM"}
    @inproceedings{a, author={A. Author}, title={Alpha}, crossref={proc}, year=2000}
    @proceedings{proc, title={Proceedings}, year=2000}
    @article{b, author={B. Author}, title={Beta}, journal=jacm, year=2001}
    @article{unused, author={U. Author}, title={Unused}, journal={X}, year=2002}
  BIB

  def test_short_and_long_spellings
    [%w[-I], %w[--make-indep], %w[-make-indep], %w[--makeindep]].each do |flags|
      options = LatexCLI.build_default_options({}, 'l', [])
      argv = flags + ['paper.tex']
      LatexCLI.normalize_argv!(argv)
      LatexCLI.build_option_parser(options).parse!(argv)
      assert_equal true, options[:make_indep], flags.inspect
      assert_equal false, options[:index], flags.inspect
    end
  end

  def test_index_keeps_its_long_name
    options = LatexCLI.build_default_options({}, 'l', [])
    LatexCLI.build_option_parser(options).parse!(%w[--index])
    assert_equal true, options[:index]
  end

  def test_rejects_packaging_combinations
    Dir.mktmpdir('make_indep_clash') do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\\begin{document}x\\end{document}\n")
      [%w[-I -z], %w[-I --arxiv], %w[-I --no-env]].each do |flags|
        output, status = Open3.capture2e(BIN, *flags, 'paper.tex', chdir: dir)
        assert_equal 2, status.exitstatus, output
        assert_includes output, '--make-indep cannot be combined'
      end
    end
  end

  def test_bibtex_paper_becomes_independent
    skip 'bibtool not available' unless LaTeXUtils.command_available?('bibtool')

    with_external_tree do |root, project, env|
      tex = <<~TEX
        \\documentclass{article}
        \\usepackage{customouter}
        \\begin{document}
        \\customtext{} See~\\cite{a,b}.
        \\bibliographystyle{myplain}
        \\bibliography{refs}
        \\end{document}
      TEX
      File.write(File.join(project, 'paper.tex'), tex)

      output, status = Open3.capture2e(env, BIN, '-e', 'p', '-I', 'paper.tex', chdir: project)
      assert status.success?, output
      assert_includes output, 'now compiles with --no-env'

      %w[styles/customouter.sty styles/custominner.sty myplain.bst paper.bib].each do |rel|
        assert_path_exists File.join(project, rel)
      end
      converted = File.read(File.join(project, 'paper.tex'))
      assert_includes converted, '\\def\\input@path{{styles/}}'
      assert_includes converted, '\\bibliography{paper}'
      bib = File.read(File.join(project, 'paper.bib'))
      %w[a proc b].each { |key| assert_match(/\{\s*#{key},/, bib) }
      refute_includes bib, 'unused'

      backups = Dir.glob(File.join(project, 'old_ver_*.zip'))
      assert_equal 1, backups.size
      assert_match(/old_ver_\d\d_\d\d_\d\d_\d\d_\d\d\.zip\z/, backups.first)
      extracted = File.join(root, 'backup')
      Open3.capture2e('unzip', '-q', backups.first, '-d', extracted)
      assert_equal tex, File.read(File.join(extracted, 'paper.tex'))
      listed = File.read(File.join(extracted, 'leeni-make-indep-new-files.txt'))
      %w[styles/customouter.sty myplain.bst paper.bib].each { |rel| assert_includes listed, rel }

      rebuilt, rebuilt_status = Open3.capture2e(BIN, '-e', 'p', '--no-env', '-f', paper_path(project))
      assert rebuilt_status.success?, rebuilt
      assert_includes rebuilt, 'Errors: 0, 🚨 Alerts: 0, ❕ Warnings: 1,'

      again, again_status = Open3.capture2e(env, BIN, '-e', 'p', '-I', 'paper.tex', chdir: project)
      assert again_status.success?, again
      assert_includes again, 'nothing to change'
      assert_equal 1, Dir.glob(File.join(project, 'old_ver_*.zip')).size
    end
  end

  def test_dry_run_shows_changes_and_changes_nothing
    with_external_tree do |root, project, env|
      File.write(File.join(root, 'shared.tex'), "Shared text.\n")
      tex = "\\documentclass{article}\n\\begin{document}\\input{../shared}\\end{document}\n"
      File.write(File.join(project, 'paper.tex'), tex)

      output, status = Open3.capture2e(env, BIN, '-e', 'p', '-I', '--dry-run', 'paper.tex', chdir: project)
      assert status.success?, output
      assert_includes output, 'Dry run: the project was not changed'
      assert_includes output, '+\\begin{document}\\input{styles/shared}\\end{document}'
      assert_match %r{ -- copy \S*/shared\.tex -> styles/shared\.tex}, output
      assert_equal tex, File.read(File.join(project, 'paper.tex'))
      refute_path_exists File.join(project, 'styles')
      assert_empty Dir.glob(File.join(project, 'old_ver_*.zip'))

      alone, alone_status = Open3.capture2e(BIN, '--dry-run', 'paper.tex', chdir: project)
      assert_equal 2, alone_status.exitstatus, alone
    end
  end

  # \input{sub/x} found through a TEXINPUTS entry for the parent directory.
  def test_search_path_subdirectory_is_kept
    with_external_tree do |root, project, env|
      FileUtils.mkdir_p(File.join(root, 'sub'))
      File.write(File.join(root, 'sub', 'x.tex'), "Sub X. \\input{sub/y}\n")
      File.write(File.join(root, 'sub', 'y.tex'), "Sub Y.\n")
      File.write(File.join(project, 'paper.tex'), "\\documentclass{article}\n\\begin{document}\\input{sub/x}\\end{document}\n")

      output, status = Open3.capture2e(env.merge('TEXINPUTS' => ".:#{root}/:"), BIN, '-e', 'p', '-I', 'paper.tex', chdir: project)
      assert status.success?, output
      %w[x.tex y.tex].each { |name| assert_path_exists File.join(project, 'styles', 'sub', name) }
      assert_includes File.read(File.join(project, 'paper.tex')), '\\input{sub/x}'
    end
  end

  # The converted paper keeps styles/ and a local .bst; -z and --arxiv must
  # bundle both, and never the backup zip.
  def test_converted_paper_packages_for_zip_and_arxiv
    skip 'bibtool not available' unless LaTeXUtils.command_available?('bibtool')

    with_external_tree do |_root, project, env|
      File.write(File.join(project, 'paper.tex'), <<~'TEX')
        \documentclass{article}
        \usepackage{customouter}
        \title{Independence}
        \author{Ann Author}
        \begin{document}
        \maketitle
        \customtext{} See~\cite{a,b}.
        \bibliographystyle{myplain}
        \bibliography{refs}
        \end{document}
      TEX
      output, status = Open3.capture2e(env, BIN, '-e', 'p', '-I', 'paper.tex', chdir: project)
      assert status.success?, output
      assert_includes output, 'Converted project compiles with --no-env and matches the original PDF'

      zipped, zip_status = Open3.capture2e(BIN, '-e', 'p', '-z', '-t', 'paper.tex', '--', '*.zip', chdir: project)
      assert zip_status.success?, zipped
      assert_includes zipped, 'Left out archive old_ver_'
      listing = Open3.capture2e('unzip', '-Z1', File.join(project, 'paper.zip')).first.lines.map(&:strip)
      %w[styles/customouter.sty styles/custominner.sty myplain.bst paper.bib].each { |rel| assert_includes listing, rel }
      assert_empty listing.grep(/\.zip\z/)

      arxiv, arxiv_status = Open3.capture2e(BIN, '-e', 'p', '--arxiv', 'paper.tex', chdir: project)
      assert arxiv_status.success?, arxiv
      arxiv_listing = Open3.capture2e('unzip', '-Z1', File.join(project, 'arxiv_paper.zip')).first
      assert_includes arxiv_listing, 'customouter.sty'
    end
  end

  def test_gitignore_rules_cover_backups
    assert_includes LaTeXConfig::GITIGNORE_LATEX_ENTRIES, 'old_ver_*.zip'
    assert_includes LaTeXConfig::DEFAULT_GITIGNORE_TEMPLATE, "old_ver_*.zip\n"
  end

  def test_biblatex_resources_are_replaced
    skip 'biber not available' unless LaTeXUtils.command_available?('biber')

    with_external_tree do |_root, project, env|
      File.write(File.join(project, 'paper.tex'), <<~TEX)
        \\documentclass{article}
        \\usepackage{biblatex}
        \\addbibresource{refs.bib}
        \\addbibresource{refs2.bib}
        \\begin{document}\\cite{a,b}\\printbibliography\\end{document}
      TEX
      output, status = Open3.capture2e(env, BIN, '-I', 'paper.tex', chdir: project)
      assert status.success?, output

      converted = File.read(File.join(project, 'paper.tex'))
      assert_includes converted, '\\addbibresource{paper.bib}'
      assert_includes converted, '% \\addbibresource{refs2.bib} % removed by leeni --make-indep'
      refute_includes File.read(File.join(project, 'paper.bib')), 'unused'
    end
  end

  def test_paths_outside_the_project_are_copied_and_rewritten
    with_external_tree do |root, project, env|
      FileUtils.mkdir_p(%w[a b gp].map { |dir| File.join(root, dir) })
      File.write(File.join(root, 'shared.tex'), "Shared text. \\input{../more}\n")
      File.write(File.join(root, 'more.tex'), "More text.\n")
      make_figure(File.join(root, 'a', 'fig.pdf'), 'A')
      make_figure(File.join(root, 'b', 'fig.pdf'), 'B')
      make_figure(File.join(root, 'gp', 'gp.pdf'), 'G')
      File.write(File.join(project, 'paper.tex'), <<~'TEX')
        \documentclass{article}
        \usepackage{graphicx}
        \graphicspath{{../gp/}}
        \begin{document}
        \input{../shared}
        \includegraphics{../a/fig}\includegraphics{../b/fig.pdf}\includegraphics{gp}
        \end{document}
      TEX

      output, status = Open3.capture2e(env, BIN, '-e', 'p', '-I', 'paper.tex', chdir: project)
      assert status.success?, output

      converted = File.read(File.join(project, 'paper.tex'))
      ['{styles/shared}', '{styles/fig}', '{styles/fig-2.pdf}', '\\graphicspath{{styles/}}'].each do |text|
        assert_includes converted, text
      end
      assert_includes File.read(File.join(project, 'styles', 'shared.tex')), '\\input{styles/more}'
      %w[more.tex fig.pdf fig-2.pdf gp.pdf].each { |name| assert_path_exists File.join(project, 'styles', name) }
      refute FileUtils.compare_file(File.join(project, 'styles', 'fig.pdf'), File.join(project, 'styles', 'fig-2.pdf'))
    end
  end

  def test_linked_styles_directory_is_refused
    with_external_tree do |root, project, env|
      shared = File.join(root, 'shared_styles')
      FileUtils.mkdir_p(shared)
      File.symlink(shared, File.join(project, 'styles'))
      tex = "\\documentclass{article}\n\\usepackage{customouter}\n\\begin{document}\\customtext\\end{document}\n"
      File.write(File.join(project, 'paper.tex'), tex)

      output, status = Open3.capture2e(env, BIN, '-e', 'p', '-I', 'paper.tex', chdir: project)
      assert_equal 1, status.exitstatus, output
      assert_includes output, 'is a symbolic link'
      assert_empty Dir.children(shared)
      assert_equal tex, File.read(File.join(project, 'paper.tex'))
      refute_path_exists File.join(project, 'paper.pdf')
      assert_empty Dir.glob(File.join(project, 'old_ver_*.zip'))
    end
  end

  def test_linked_target_file_is_refused
    skip 'bibtool not available' unless LaTeXUtils.command_available?('bibtool')

    with_external_tree do |root, project, env|
      shared_bib = File.join(root, 'ext', 'bib', 'refs.bib')
      before = File.read(shared_bib)
      File.symlink(shared_bib, File.join(project, 'paper.bib'))
      File.write(File.join(project, 'paper.tex'),
                 "\\documentclass{article}\n\\begin{document}\\cite{a}\n\\bibliographystyle{plain}\\bibliography{refs}\n\\end{document}\n")

      output, status = Open3.capture2e(env, BIN, '-e', 'p', '-I', 'paper.tex', chdir: project)
      refute status.success?, output
      assert_includes output, 'will not write through them'
      assert_includes output, 'paper.bib ->'
      assert_equal before, File.read(shared_bib)
      assert_empty Dir.glob(File.join(project, 'old_ver_*.zip'))
    end
  end

  # A .txt file is not something --make-indep copies, so the sandbox build
  # takes the other branch and its PDF text differs.
  def test_failed_check_changes_nothing
    with_external_tree do |root, project, env|
      File.write(File.join(root, 'marker.txt'), 'x')
      tex = <<~'TEX'
        \documentclass{article}
        \usepackage{customouter}
        \begin{document}\customtext\IfFileExists{../marker.txt}{Found}{Missing}\end{document}
      TEX
      File.write(File.join(project, 'paper.tex'), tex)

      output, status = Open3.capture2e(env, BIN, '-e', 'p', '-I', 'paper.tex', chdir: project)
      refute status.success?, output
      assert_includes output, 'nothing was changed'
      assert_equal tex, File.read(File.join(project, 'paper.tex'))
      refute_path_exists File.join(project, 'styles')
      assert_empty Dir.glob(File.join(project, 'old_ver_*.zip'))
    end
  end

  private

  def make_figure(path, label)
    Dir.mktmpdir('fig') do |dir|
      File.write(File.join(dir, 'f.tex'), "\\documentclass{standalone}\\begin{document}#{label}\\end{document}\n")
      Open3.capture2e('pdflatex', '-interaction=nonstopmode', 'f.tex', chdir: dir)
      FileUtils.cp(File.join(dir, 'f.pdf'), path)
    end
  end

  def paper_path(project)
    File.join(project, 'paper.tex')
  end

  def with_external_tree
    Dir.mktmpdir('make_indep') do |root|
      project = File.join(root, 'project')
      sty, bibdir, bst = %w[sty bib bst].map { |name| File.join(root, 'ext', name) }
      FileUtils.mkdir_p([project, sty, bibdir, bst])
      File.write(File.join(sty, 'customouter.sty'), "\\ProvidesPackage{customouter}\n\\RequirePackage{custominner}\n")
      File.write(File.join(sty, 'custominner.sty'),
                 "\\ProvidesPackage{custominner}\n\\newcommand{\\customtext}{External style works.}\n")
      File.write(File.join(bibdir, 'refs.bib'), BIB)
      File.write(File.join(bibdir, 'refs2.bib'), "@misc{other, title={Other}}\n")
      plain = Open3.capture2('kpsewhich', 'plain.bst').first.strip
      FileUtils.cp(plain, File.join(bst, 'myplain.bst'))
      env = { 'TEXINPUTS' => ".:#{sty}:", 'BIBINPUTS' => "#{bibdir}:", 'BSTINPUTS' => "#{bst}:" }
      yield root, project, env
    end
  end
end
