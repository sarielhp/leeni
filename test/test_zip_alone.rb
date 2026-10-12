# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'

load File.expand_path('../leeni', __dir__)

class TestZipAlone < Minitest::Test
  BIN = File.expand_path('../leeni', __dir__)

  def test_no_env_spellings
    %w[--no-env -noenv --noenv -no-env].each do |flag|
      options = LatexCLI.build_default_options({}, 'l', [])
      argv = [flag, 'paper.tex']
      LatexCLI.normalize_argv!(argv)
      LatexCLI.build_option_parser(options).parse!(argv)
      assert_equal true, options[:no_env], flag
      assert_equal ['paper.tex'], argv
    end
  end

  def test_zip_alone_options_and_extra_files
    options = LatexCLI.build_default_options({}, 'l', [])
    argv = ['--zip-alone', 'paper.tex', '--', 'notes.txt']
    assert_equal ['notes.txt'], LatexCLI.extract_extra_cli_files(argv)
    LatexCLI.build_option_parser(options).parse!(argv)
    %i[zip_alone zip inject_styles verify force].each { |key| assert_equal true, options[key], key.to_s }
    assert_equal ['paper.tex'], argv
  end

  def test_external_styles_are_bundled_and_verified
    Dir.mktmpdir('zip_alone') do |root|
      project = File.join(root, 'project')
      external = File.join(root, 'external')
      FileUtils.mkdir_p([project, external])
      tex = "\\documentclass{article}\n\\usepackage{customouter}\n\\begin{document}\\customtext\\end{document}\n"
      File.write(File.join(project, 'paper.tex'), tex)
      File.write(File.join(project, 'notes.txt'), 'supplement')
      File.write(File.join(external, 'customouter.sty'), "\\ProvidesPackage{customouter}\n\\RequirePackage{custominner}\n")
      File.write(File.join(external, 'custominner.sty'), "\\ProvidesPackage{custominner}\n\\newcommand{\\customtext}{External style works.}\n")

      output, status = Open3.capture2e({ 'TEXINPUTS' => ".:#{external}:" }, BIN,
                                     '-zipalone', '--no-styles-inject', 'paper.tex', '--', 'notes.txt', chdir: project)
      assert status.success?, output
      assert_includes output, 'Isolated build has no errors or alerts'
      assert_includes output, 'Text layout exact match confirmed'
      assert_includes output, 'All PDF pages match visually'
      assert_equal tex, File.read(File.join(project, 'paper.tex'))

      extracted = File.join(root, 'extracted')
      _, unzip_status = Open3.capture2e('unzip', '-q', File.join(project, 'paper.zip'), '-d', extracted)
      assert unzip_status.success?
      %w[customouter.sty custominner.sty].each { |name| assert_path_exists File.join(extracted, 'styles', name) }
      assert_path_exists File.join(extracted, 'notes.txt')
      assert_includes File.read(File.join(extracted, 'paper.tex')), '\\def\\input@path{{styles/}{./}}'
    end
  end

  def test_alert_rejects_archive_and_preserves_existing_zip
    Dir.mktmpdir('zip_alone_alert') do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n\\begin{document}\\noindent\\rule{700pt}{1pt}\\end{document}\n")
      File.write(File.join(dir, 'paper.zip'), 'previous archive')
      output, status = Open3.capture2e(BIN, '--zip-alone', 'paper.tex', chdir: dir)
      refute status.success?, output
      assert_includes output, 'Isolated build reported errors or alerts'
      assert_includes output, 'Preserved existing paper.zip'
      assert_equal 'previous archive', File.read(File.join(dir, 'paper.zip'))
      assert_empty Dir.glob(File.join(dir, '.paper.tmp.*.zip'))
    end
  end

  def test_missing_external_tex_dependency_rejects_archive
    Dir.mktmpdir('zip_alone_missing') do |root|
      project = File.join(root, 'project')
      external = File.join(root, 'external')
      FileUtils.mkdir_p([project, external])
      File.write(File.join(external, 'externaltext.tex'), 'External input.')
      File.write(File.join(project, 'paper.tex'), "\\documentclass{article}\n\\begin{document}\\input{externaltext}\\end{document}\n")
      output, status = Open3.capture2e({ 'TEXINPUTS' => ".:#{external}:" }, BIN, '--zip-alone', 'paper.tex', chdir: project)
      refute status.success?, output
      assert_includes output, 'Document did not compile in clean environment'
      refute_path_exists File.join(project, 'paper.zip')
    end
  end

  def test_warnings_are_allowed_but_errors_and_alerts_are_rejected
    packager = LatexPackager.new(LatexBuilder.new('paper.tex', zip_alone: true))
    result = { success: true, summary: { errors: 0, alerts: 0, warnings: 1 } }
    capture_io { assert packager.send(:verify_clean_diagnostics, JSON.generate(result)) }
    %i[errors alerts].each do |tier|
      rejected = { success: true, summary: { errors: 0, alerts: 0 }.merge(tier => 1) }
      capture_io { refute packager.send(:verify_clean_diagnostics, JSON.generate(rejected)) }
    end
    capture_io { refute packager.send(:verify_clean_diagnostics, '{}') }
    capture_io { refute packager.send(:verify_clean_diagnostics, '{"summary":null}') }
    capture_io { refute packager.send(:verify_clean_diagnostics, 'null') }
    capture_io { refute packager.send(:verify_clean_diagnostics, 'not JSON') }
  end

  def test_missing_comparison_tools_are_fatal
    packager = LatexPackager.new(LatexBuilder.new('paper.tex', zip_alone: true))
    LaTeXUtils.stub(:command_available?, false) do
      capture_io { refute packager.send(:verify_pdf_diff, 'original.pdf', 'rebuilt.pdf') }
      capture_io { refute packager.send(:verify_pdf_visual_match, 'original.pdf', 'rebuilt.pdf') }
    end
  end

  def test_visual_comparison_catches_graphics_changes_with_identical_text
    Dir.mktmpdir('zip_alone_visual') do |dir|
      %w[original rebuilt].each_with_index do |name, index|
        tex = "\\documentclass{article}\n\\begin{document}Same text.\\rule{#{10 + (index * 10)}pt}{1pt}\\end{document}\n"
        File.write(File.join(dir, "#{name}.tex"), tex)
        output, status = Open3.capture2e(BIN, '--no-env', '--llm', "#{name}.tex", chdir: dir)
        assert status.success?, output
      end
      packager = LatexPackager.new(LatexBuilder.new('paper.tex', zip_alone: true))
      original = File.join(dir, 'original.pdf')
      rebuilt = File.join(dir, 'rebuilt.pdf')
      capture_io { assert packager.send(:verify_pdf_diff, original, rebuilt) }
      capture_io { refute packager.send(:verify_pdf_visual_match, original, rebuilt) }
    end
  end

  def test_existing_style_search_path_is_extended
    Dir.mktmpdir('zip_alone_path') do |dir|
      tex = "\\makeatletter\n\\def\\input@path{{./}}\n\\makeatother\n" \
            "\\documentclass{article}\n\\usepackage{customstyle}\n\\begin{document}Hello.\\end{document}\n"
      File.write(File.join(dir, 'paper.tex'), tex)
      File.write(File.join(dir, 'customstyle.sty'), "\\ProvidesPackage{customstyle}\n")
      output, status = Open3.capture2e(BIN, '--zip-alone', 'paper.tex', chdir: dir)
      assert status.success?, output
      assert_equal tex, File.read(File.join(dir, 'paper.tex'))
      packaged, unzip_status = Open3.capture2e('unzip', '-p', File.join(dir, 'paper.zip'), 'paper.tex')
      assert unzip_status.success?
      assert_includes packaged, '\\g@addto@macro\\input@path{{styles/}{./}}'
    end
  end
end
