# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

require_relative '../lib/leeni/utils'
require_relative '../lib/leeni/builder'
require_relative '../lib/leeni/arxiv'
require_relative '../lib/leeni/packager'

# Guards every path that deletes files in the user's project directory.
# The tool writes all of its own scratch output under junk/; anything these
# sweeps match in the project root can therefore only be a file the user wrote.
class TestDestructivePaths < Minitest::Test
  BIN = File.expand_path('../leeni', __dir__)
  load BIN

  def build_options
    { engine: 'xelatex', lock: false, junk_subdirs: [], auto_mirror_subdirs: false }
  end

  def test_paper_cleanup_preserves_user_log_txt
    Dir.mktmpdir('leeni_cleanup_test') do |dir|
      Dir.chdir(dir) do
        File.write('paper.tex', "\\documentclass{article}\n\\begin{document}\nx\n\\end{document}\n")
        File.write('log.txt', "experiment results, not a LaTeX artifact\n")

        LatexBuilder.new('paper.tex', build_options).send(:paper_cleanup)

        assert_path_exists 'log.txt', 'paper_cleanup deleted a user-authored log.txt'
        assert_equal "experiment results, not a LaTeX artifact\n", File.read('log.txt')
      end
    end
  end

  def test_clean_directory_preserves_user_authored_files
    Dir.mktmpdir('leeni_clean_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('figs/bak')
        File.write('figs/bak/old_figure.pdf', 'user backup')
        File.write('err_analysis.rb', 'user script')
        File.write('bounds.err.tex', 'user source')
        File.write('log.txt', 'user log')
        File.write('paper.bbl', '\\bibitem{only-copy} Supplied bibliography')
        File.write('paper.bbl.bak', '\\bibitem{backup} Previous bibliography')
        File.write('arxiv_paper_meta.txt', 'submission metadata')

        LaTeXUtils.clean_directory('.', false)

        assert_path_exists 'figs/bak/old_figure.pdf', 'clean_directory removed the user backup directory figs/bak'
        assert_path_exists 'err_analysis.rb', "clean_directory removed a user file matching 'err_*'"
        assert_path_exists 'bounds.err.tex', "clean_directory removed a user file matching '*.err*'"
        assert_path_exists 'log.txt', 'clean_directory removed a user-authored log.txt'
        assert_path_exists 'paper.bbl', 'clean_directory removed the only supplied bibliography'
        assert_path_exists 'paper.bbl.bak', 'clean_directory removed a bibliography backup'
        assert_path_exists 'arxiv_paper_meta.txt', 'clean_directory removed final submission metadata'
      end
    end
  end

  def test_clean_directory_still_removes_real_artifacts
    Dir.mktmpdir('leeni_clean_real_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('junk/paper.aux', 'artifact')
        %w[paper.aux paper.blg paper.log paper.out paper.toc texput.log missfont.log].each do |f|
          File.write(f, 'artifact')
        end
        File.write('paper.bbl', '\\bibitem{preserved} Bibliography')

        LaTeXUtils.clean_directory('.', false)

        refute Dir.exist?('junk'), 'clean_directory left junk/ in place'
        %w[paper.aux paper.blg paper.log paper.out paper.toc texput.log missfont.log].each do |f|
          refute_path_exists f, "clean_directory left the build artifact #{f}"
        end
        assert_path_exists 'paper.bbl', 'clean_directory removed a non-regenerable bibliography'
      end
    end
  end

  def test_directory_argument_rejects_a_path_that_does_not_exist
    Dir.mktmpdir('leeni_target_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('sub')
        File.write('paper.tex', "\\documentclass{article}\n")

        assert_nil LatexCLI.directory_argument('typo_dir'),
                   'a non-existent argument must not silently resolve to the current directory'
        assert_nil LatexCLI.directory_argument('nested/typo_dir')
        assert_equal '.', LatexCLI.directory_argument(nil)
        assert_equal 'sub', LatexCLI.directory_argument('sub')
        assert_equal '.', LatexCLI.directory_argument('paper.tex')
      end
    end
  end

  def test_clean_only_with_a_bad_directory_exits_without_cleaning
    Dir.mktmpdir('leeni_badtarget_test') do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n")
      File.write(File.join(dir, 'paper.aux'), 'artifact')

      _out, status = Open3.capture2e(BIN, '-C', 'typo_dir', chdir: dir)

      refute status.success?, 'a non-existent clean target must be an error'
      assert_path_exists File.join(dir, 'paper.aux'),
                         'l -C <typo> cleaned the current directory instead of erroring'
    end
  end

  def test_clean_directory_prints_relative_path_to_pwd
    Dir.mktmpdir('leeni_clean_rel_test') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'notes', '40_vc'))
      out, status = Open3.capture2e(BIN, '-C', 'notes/40_vc', chdir: dir)
      assert status.success?
      assert_includes out, 'Cleaning LaTeX auxiliary files in notes/40_vc...'
      refute_includes out, dir

      out_curr, status_curr = Open3.capture2e(BIN, '-C', '.', chdir: File.join(dir, 'notes', '40_vc'))
      assert status_curr.success?
      assert_includes out_curr, 'Cleaning LaTeX auxiliary files in ....'
      refute_includes out_curr, dir

      File.write(File.join(dir, 'notes', '40_vc', 'paper.tex'), "\\documentclass{article}\\begin{document}Hi\\end{document}\n")
      out_build, status_build = Open3.capture2e(BIN, '-c', '-f', 'notes/40_vc/paper.tex', chdir: dir)
      assert status_build.success?
      assert_includes out_build, 'Cleaning LaTeX auxiliary files in notes/40_vc...'
      refute_includes out_build.lines.grep(/Cleaning LaTeX/).join, dir
    end
  end

  def test_help_wins_over_clean_only
    Dir.mktmpdir('leeni_help_test') do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n")
      File.write(File.join(dir, 'paper.aux'), 'artifact')

      stdout, status = Open3.capture2e(BIN, '-C', '-h', chdir: dir)

      assert status.success?
      assert_match(/Usage:/, stdout, 'l -C -h did not print help')
      assert_path_exists File.join(dir, 'paper.aux'),
                         'l -C -h performed the destructive sweep instead of printing help'
    end
  end

  def test_normalize_engine_rejects_arbitrary_programs
    # A project-local .l.jsonc ships inside any cloned repository, and its
    # engine value used to flow straight through to the executed binary.
    %w[python3 sh curl bash ruby nc].each do |hostile|
      assert_equal 'xelatex', LaTeXUtils.normalize_engine(hostile),
                   "normalize_engine passed #{hostile.inspect} through as an engine"
    end
    assert_equal 'xelatex', LaTeXUtils.normalize_engine('/usr/bin/python3')
  end

  def test_normalize_engine_keeps_real_engines
    assert_equal 'xelatex', LaTeXUtils.normalize_engine('xelatex')
    assert_equal 'xelatex', LaTeXUtils.normalize_engine('xetex')
    assert_equal 'lualatex', LaTeXUtils.normalize_engine('lualatex')
    assert_equal 'pdflatex', LaTeXUtils.normalize_engine('pdftex')
    assert_equal 'tectonic', LaTeXUtils.normalize_engine('tectonic')
    assert_equal 'xelatex', LaTeXUtils.normalize_engine('xelatex -shell-escape')
  end

  def test_double_dash_does_not_swallow_the_target
    argv = ['--', 'weird--name.tex']
    extras = LatexCLI.extract_extra_cli_files(argv)

    assert_empty extras
    assert_equal ['weird--name.tex'], argv,
                 '`--` claimed the target as bundle payload with no packaging flag present'
  end

  def test_double_dash_still_harvests_for_packaging_modes
    [%w[-z -- notes.txt], %w[--arxiv -- notes.txt], %w[-t -- notes.txt]].each do |base|
      argv = base.dup
      extras = LatexCLI.extract_extra_cli_files(argv)
      assert_equal ['notes.txt'], extras, "#{base.inspect} did not harvest the payload"
      refute_includes argv, '--'
    end
  end

  def test_unknown_flag_reports_usage_instead_of_a_backtrace
    Dir.mktmpdir('leeni_badflag_test') do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n")

      out, status = Open3.capture2e(BIN, '--typpo', chdir: dir)

      refute status.success?
      refute_match(/\(OptionParser|backtrace|\.rb:\d+:in /, out, 'a mistyped flag printed a Ruby backtrace')
      assert_match(/invalid option/i, out)
      assert_match(/Usage:/, out)
    end
  end

  def test_lock_directory_must_be_private_and_owned
    Dir.mktmpdir('leeni_tmpdir_test') do |dir|
      hostile = File.join(dir, "leeni_#{Process.uid}")
      Dir.mkdir(hostile, 0o777)
      File.chmod(0o777, hostile)

      builder = LatexBuilder.new('paper.tex', build_options)
      original = ENV['TMPDIR']
      begin
        ENV['TMPDIR'] = dir
        assert_raises(SystemExit, 'a world-writable temp directory was accepted') do
          capture_io { builder.send(:project_tmp_dir) }
        end
      ensure
        ENV['TMPDIR'] = original
      end
    end
  end

  def test_private_lock_directory_is_accepted
    Dir.mktmpdir('leeni_tmpdir_ok_test') do |dir|
      builder = LatexBuilder.new('paper.tex', build_options)
      original = ENV['TMPDIR']
      begin
        ENV['TMPDIR'] = dir
        path = builder.send(:project_tmp_dir)
        assert_equal 0o700, File.stat(path).mode & 0o777
      ensure
        ENV['TMPDIR'] = original
      end
    end
  end

  def test_meta_target_writes_next_to_the_document
    Dir.mktmpdir('leeni_meta_test') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'sub'))
      File.write(File.join(dir, 'sub', 'paper.tex'),
                 "\\documentclass{article}\n\\title{A Title}\n\\author{Ada Lovelace}\n" \
                 "\\begin{document}\n\\begin{abstract}Short.\\end{abstract}\n\\end{document}\n")

      _out, status = Open3.capture2e(BIN, '--meta', 'sub/paper.tex', chdir: dir)

      assert status.success?
      assert_path_exists File.join(dir, 'sub', 'arxiv_paper_meta.txt'),
                         '--meta wrote the metadata file next to the caller, not the document'
      refute_path_exists File.join(dir, 'arxiv_paper_meta.txt')
    end
  end

  def test_arxiv_copy_preserving_path_rejects_out_of_tree_and_symlinks
    Dir.mktmpdir('leeni_arxiv_copy_test') do |root|
      outside = File.join(root, 'outside.png')
      File.write(outside, 'secret outside')

      proj = File.join(root, 'proj')
      stage = File.join(root, 'stage')
      FileUtils.mkdir_p(File.join(proj, 'figs'))
      FileUtils.mkdir_p(stage)

      local = File.join(proj, 'figs', 'local.png')
      File.write(local, 'local figure')

      link = File.join(proj, 'figs', 'link.png')
      File.symlink(outside, link)

      Dir.chdir(proj) do
        arxiv = LatexArxivPackager.allocate
        arxiv.send(:copy_preserving_path, outside, stage)
        arxiv.send(:copy_preserving_path, '../outside.png', stage)
        arxiv.send(:copy_preserving_path, 'figs/link.png', stage)
        arxiv.send(:copy_preserving_path, 'figs/local.png', stage)
      end

      refute_path_exists File.join(stage, 'outside.png')
      refute_path_exists File.join(stage, 'figs', 'link.png')
      assert_path_exists File.join(stage, 'figs', 'local.png')
    end
  end

  def test_packager_copy_preserving_path_rejects_out_of_tree_and_symlinks
    Dir.mktmpdir('leeni_packager_copy_test') do |root|
      outside = File.join(root, 'outside.png')
      File.write(outside, 'secret outside')

      proj = File.join(root, 'proj')
      stage = File.join(root, 'stage')
      FileUtils.mkdir_p(File.join(proj, 'figs'))
      FileUtils.mkdir_p(stage)

      local = File.join(proj, 'figs', 'local.png')
      File.write(local, 'local figure')

      link = File.join(proj, 'figs', 'link.png')
      File.symlink(outside, link)

      Dir.chdir(proj) do
        packager = LatexPackager.allocate
        packager.send(:copy_preserving_path, outside, stage)
        packager.send(:copy_preserving_path, '../outside.png', stage)
        packager.send(:copy_preserving_path, 'figs/link.png', stage)
        packager.send(:copy_preserving_path, 'figs/local.png', stage)
      end

      refute_path_exists File.join(stage, 'outside.png')
      refute_path_exists File.join(stage, 'figs', 'link.png')
      assert_path_exists File.join(stage, 'figs', 'local.png')
    end
  end

  def test_review_cycle_run_with_auto_triage_prevents_shell_injection
    load File.expand_path('../tools/review_cycle', __dir__) unless defined?(MultiProfileReviewCycle)
    skip 'MultiProfileReviewCycle standard not installed' unless defined?(MultiProfileReviewCycle)
    Dir.mktmpdir('review_cycle_pty_test') do |dir|
      out_file = File.join(dir, 'output.txt')
      marker = 'ARG_WITH_METAS_`echo evil`_${PATH}_;&|'
      cmd = ['ruby', '-e', 'File.write(ARGV[0], ARGV[1])', out_file, marker]
      cycle = MultiProfileReviewCycle.allocate
      def cycle.log_write(_msg); end
      def cycle.stream_pty_output(_stdout, _stdin); end

      cycle.send(:run_with_auto_triage, cmd)
      assert_path_exists out_file
      assert_equal marker, File.read(out_file), 'argument with metacharacters was altered or evaluated by shell'
    end
  end

  def test_image_generation_scripts_avoid_shell_string_interpolation
    gallery_src = File.read(File.expand_path('../tools/generate_gallery', __dir__))
    error_src = File.read(File.expand_path('../tools/generate_error_comparison', __dir__))

    refute_match(/system\(["']convert .*#\{/, gallery_src, 'generate_gallery interpolates paths into convert shell string')
    refute_match(/system\(["']convert .*#\{/, error_src, 'generate_error_comparison interpolates paths into convert shell string')
  end
end
