#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
load File.expand_path('../leeni', __dir__)

class TestCompatibility < Minitest::Test
  def test_revtex4_tree_is_available_to_compiler_subprocesses
    environment = LaTeXCompatibility.compiler_environment(revtex4: { 'enabled' => true })
    expected = File.join(LaTeXCompatibility::REPO_TEXMF, 'tex', 'latex', 'revtex4')
    assert_includes environment.fetch('TEXINPUTS').split(File::PATH_SEPARATOR), expected
  end

  def test_revtex4_can_be_disabled
    environment = LaTeXCompatibility.compiler_environment({ revtex4: { 'enabled' => false } }, {})
    assert_empty environment
  end

  def test_compiler_environment_preserves_bibinputs
    base = { 'BIBINPUTS' => '/path/to/my/bibs:' }
    environment = LaTeXCompatibility.compiler_environment({ revtex4: { 'enabled' => true } }, base)
    assert_equal '/path/to/my/bibs:', environment['BIBINPUTS']
  end

  def test_source_needs_revtex4_detection
    assert LaTeXCompatibility.source_needs_revtex4?('\\documentclass{revtex4}')
    assert LaTeXCompatibility.source_needs_revtex4?("\\documentclass[prl,twocolumn]{revtex4}\n")
    assert LaTeXCompatibility.source_needs_revtex4?("\\documentclass [10pt] {revtex4}")
    refute LaTeXCompatibility.source_needs_revtex4?('\\documentclass{revtex4-1}')
    refute LaTeXCompatibility.source_needs_revtex4?('\\documentclass{revtex4-2}')
    refute LaTeXCompatibility.source_needs_revtex4?('\\documentclass{article}')
    refute LaTeXCompatibility.source_needs_revtex4?("% \\documentclass{revtex4}\n\\documentclass{article}")
  end

  def test_auto_detection_injects_only_when_source_needs_it
    base = { 'TEXINPUTS' => '.:' }
    # Normal article: not injected
    normal_env = LaTeXCompatibility.compiler_environment({}, base, "\\documentclass{article}\n")
    assert_equal base, normal_env

    # Without target file: not injected
    nil_env = LaTeXCompatibility.compiler_environment({}, base, nil)
    assert_equal base, nil_env

    # Revtex4 document: auto-injected
    revtex_env = LaTeXCompatibility.compiler_environment({}, base, "\\documentclass{revtex4}\n")
    expected = File.join(LaTeXCompatibility::REPO_TEXMF, 'tex', 'latex', 'revtex4')
    assert_includes revtex_env['TEXINPUTS'].split(File::PATH_SEPARATOR), expected
  end

  def test_fls_identifies_used_compatibility_files
    Dir.mktmpdir('leeni-compat-') do |dir|
      path = File.join(LaTeXCompatibility::REPO_TEXMF, 'tex/latex/revtex4/revtex4.cls')
      fls = File.join(dir, 'paper.fls')
      File.write(fls, "INPUT #{path}\nINPUT /usr/share/texlive/texmf-dist/tex/latex/base/article.cls\n")
      assert_equal [path], LaTeXCompatibility.files_used_by_fls(fls, revtex4: { 'enabled' => true })
    end
  end

  def test_portable_packager_treats_revtex_rtx_files_as_styles
    Dir.mktmpdir('leeni-compat-') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('paper.tex', '\\documentclass{revtex4}')
        rtx = File.join(LaTeXCompatibility::REPO_TEXMF, 'tex/latex/revtex4/aps.rtx')
        File.write('junk/paper.fls', "INPUT #{rtx}\n")
        packager = LatexPackager.new(LatexBuilder.new('paper.tex', {}))
        assert_includes packager.send(:collect_fls_dependencies, 'junk/paper.fls')[:styles], rtx
      end
    end
  end
end
