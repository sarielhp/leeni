# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/leeni/macro_harvester'
require_relative '../lib/leeni/error_catalog'

class TestMacroHarvester < Minitest::Test
  def setup
    LaTeXMacroHarvester.clear_cache!
  end

  def teardown
    LaTeXMacroHarvester.clear_cache!
  end

  def test_harvest_extracts_various_macro_definition_forms
    Dir.mktmpdir('leeni_harvest_test') do |dir|
      main_file = File.join(dir, 'main.tex')
      File.write(main_file, <<~TEX)
        \\documentclass{article}
        \\newcommand{\\QuotePExt}[1]{``#1''}
        \\newcommand*\\singleStar{val}
        \\renewcommand{\\redefCmd}{renewed}
        \\providecommand{\\provCmd}{provided}
        \\def\\plainDef#1{#1}
        \\gdef\\globalDef{glob}
        \\let\\aliasedCmd=\\QuotePExt
        % \\newcommand{\\commentedMacro}{ignore_me}
        \\begin{document}
        Hello
        \\end{document}
      TEX

      macros = LaTeXMacroHarvester.harvest(main_file)
      assert_includes macros, 'QuotePExt'
      assert_includes macros, 'singleStar'
      assert_includes macros, 'redefCmd'
      assert_includes macros, 'provCmd'
      assert_includes macros, 'plainDef'
      assert_includes macros, 'globalDef'
      assert_includes macros, 'aliasedCmd'
      refute_includes macros, 'commentedMacro'
    end
  end

  def test_harvest_includes_sty_and_subdirectories_but_ignores_junk
    Dir.mktmpdir('leeni_harvest_test') do |dir|
      sub_dir = File.join(dir, 'styles')
      junk_dir = File.join(dir, 'junk')
      FileUtils.mkdir_p(sub_dir)
      FileUtils.mkdir_p(junk_dir)

      main_file = File.join(dir, 'main.tex')
      File.write(main_file, "\\documentclass{article}\n\\begin{document}\n\\end{document}\n")

      sty_file = File.join(sub_dir, 'custom.sty')
      File.write(sty_file, "\\DeclareMathOperator{\\dist}{dist}\n\\NewDocumentCommand\\smartBox{ m }{#1}\n")

      junk_file = File.join(junk_dir, 'cached.tex')
      File.write(junk_file, "\\newcommand{\\junkOnlyMacro}{trash}\n")

      macros = LaTeXMacroHarvester.harvest(main_file)
      assert_includes macros, 'dist'
      assert_includes macros, 'smartBox'
      refute_includes macros, 'junkOnlyMacro'
    end
  end

  def test_suggest_command_fuzzy_matches_project_macro_typo
    Dir.mktmpdir('leeni_harvest_test') do |dir|
      main_file = File.join(dir, 'k_wise_reviewed.tex')
      File.write(main_file, <<~TEX)
        \\documentclass{article}
        \\newcommand{\\QuotePExt}[1]{``#1''}
        \\begin{document}
        \\QoutePExt{``Independence? That's middle-class blasphemy.''}
        \\end{document}
      TEX

      hint = LaTeXErrorCatalog.suggest_command('\\QoutePExt', file: main_file)
      assert_equal "Did you mean '\\QuotePExt'?", hint
    end
  end

  def test_classify_with_project_macro_typo
    Dir.mktmpdir('leeni_harvest_test') do |dir|
      main_file = File.join(dir, 'k_wise_reviewed.tex')
      File.write(main_file, <<~TEX)
        \\documentclass{article}
        \\newcommand{\\QuotePExt}[1]{``#1''}
        \\begin{document}
        \\QoutePExt{test}
        \\end{document}
      TEX

      err_text = "#{main_file}:15:1: Undefined control sequence."
      err_block = [
        err_text,
        '<recently read> \\QoutePExt ',
        'l.15 \\QoutePExt',
        '               {test}'
      ]

      item = LaTeXErrorCatalog.classify(err_text, err_block, file: main_file, line: 15)
      assert item
      assert_equal :undefined_control_sequence, item[:id]
      assert_equal '\\QoutePExt', item[:token]
      assert_equal "Did you mean '\\QuotePExt'?", item[:hint]
    end
  end

  def test_suggest_command_falls_back_gracefully_without_project_file
    hint = LaTeXErrorCatalog.suggest_command('\\alpa', file: nil)
    assert_equal "Did you mean '\\alpha'?", hint

    hint_pkg = LaTeXErrorCatalog.suggest_command('\\toprule', file: nil)
    assert_equal "Command '\\toprule' requires \\usepackage{booktabs}", hint_pkg
  end

  def test_harvest_resolves_project_root_from_nested_file
    Dir.mktmpdir('leeni_harvest_test') do |dir|
      root_sty = File.join(dir, 'macros.sty')
      File.write(root_sty, "\\newcommand{\\RootMacro}{hello}\n")

      sub_dir = File.join(dir, 'chapters')
      FileUtils.mkdir_p(sub_dir)
      chapter_file = File.join(sub_dir, 'ch1.tex')
      File.write(chapter_file, "\\input{../macros.sty}\n\\RottMacro\n")

      # When called with a nested subfile, it harvests from project root and finds \RootMacro
      hint = LaTeXErrorCatalog.suggest_command('\\RottMacro', file: chapter_file)
      assert_equal "Did you mean '\\RootMacro'?", hint
    end
  end

  def test_caching_and_cache_invalidation
    Dir.mktmpdir('leeni_harvest_test') do |dir|
      main_file = File.join(dir, 'main.tex')
      File.write(main_file, "\\newcommand{\\InitialMacro}{1}\n")

      macros = LaTeXMacroHarvester.harvest(main_file)
      assert_includes macros, 'InitialMacro'

      # Modify file on disk without clearing cache
      File.write(main_file, "\\newcommand{\\InitialMacro}{1}\n\\newcommand{\\NewMacro}{2}\n")
      cached_macros = LaTeXMacroHarvester.harvest(main_file)
      refute_includes cached_macros, 'NewMacro'

      # Clear cache and verify updated macros are harvested
      LaTeXMacroHarvester.clear_cache!
      fresh_macros = LaTeXMacroHarvester.harvest(main_file)
      assert_includes fresh_macros, 'NewMacro'
    end
  end

  def test_suggest_command_suggests_nothing_when_edit_distance_too_large_or_ambiguous
    Dir.mktmpdir('leeni_harvest_test') do |dir|
      main_file = File.join(dir, 'main.tex')
      File.write(main_file, <<~TEX)
        \\newcommand{\\QuotePExt}[1]{``#1''}
        \\newcommand{\\myCat}{1}
        \\newcommand{\\myBat}{2}
        \\newcommand{\\myLongAlgorithmName}{3}
      TEX

      # 1. Too distant from any macro (distance > len / 3)
      hint = LaTeXErrorCatalog.suggest_command('\\CompletelyUnrelatedMacro', file: main_file)
      assert_equal "Undefined command '\\CompletelyUnrelatedMacro'; check spelling or \\usepackage", hint
      refute_includes hint, 'Did you mean'

      # 2. Ambiguous tie: \myRat is equidistant (dist 1) from \myCat and \myBat -> suggests nothing!
      hint_ambiguous = LaTeXErrorCatalog.suggest_command('\\myRat', file: main_file)
      assert_equal "Undefined command '\\myRat'; check spelling or \\usepackage", hint_ambiguous
      refute_includes hint_ambiguous, 'Did you mean'

      # 3. Very short token (< 3 characters) -> suggests nothing
      hint_short = LaTeXErrorCatalog.suggest_command('\\xy', file: main_file)
      assert_equal "Undefined command '\\xy'; check spelling or \\usepackage", hint_short
      refute_includes hint_short, 'Did you mean'

      # 4. Multi-typo in a long string (3 transpositions in a 19-character identifier: len/3 = 6)
      hint_long = LaTeXErrorCatalog.suggest_command('\\myLognAlgortihmNmae', file: main_file)
      assert_equal "Did you mean '\\myLongAlgorithmName'?", hint_long

      # 5. Case-insensitive exact match
      hint_case = LaTeXErrorCatalog.suggest_command('\\quotepext', file: main_file)
      assert_equal "Did you mean '\\QuotePExt'?", hint_case
    end
  end

  def test_harvest_discovers_macros_from_fls_recorder
    Dir.mktmpdir('leeni_harvest_test') do |dir|
      main_file = File.join(dir, 'doc.tex')
      File.write(main_file, "\\documentclass{article}\n\\begin{document}\n\\end{document}\n")

      external_dir = File.join(dir, 'outside')
      FileUtils.mkdir_p(external_dir)
      external_sty = File.join(external_dir, 'remote.sty')
      File.write(external_sty, "\\newcommand{\\RemoteFlsMacro}{val}\n")

      # Create junk/doc.fls recording the external input
      junk_dir = File.join(dir, 'junk')
      FileUtils.mkdir_p(junk_dir)
      fls_file = File.join(junk_dir, 'doc.fls')
      File.write(fls_file, "PWD #{dir}\nINPUT #{main_file}\nINPUT #{external_sty}\n")

      macros = LaTeXMacroHarvester.harvest(main_file)
      assert_includes macros, 'RemoteFlsMacro'

      hint = LaTeXErrorCatalog.suggest_command('\\RemoteFlsMcro', file: main_file)
      assert_equal "Did you mean '\\RemoteFlsMacro'?", hint
    end
  end

  def test_harvest_discovers_macros_from_symlinked_directory
    Dir.mktmpdir('leeni_harvest_test') do |dir|
      shared_styles = File.join(dir, 'shared_styles')
      FileUtils.mkdir_p(shared_styles)
      File.write(File.join(shared_styles, 'macros.tex'), "\\newcommand{\\SymlinkedDirMacro}{val}\n")

      proj_dir = File.join(dir, 'paper')
      FileUtils.mkdir_p(proj_dir)
      main_file = File.join(proj_dir, 'main.tex')
      File.write(main_file, "\\documentclass{article}\n\\begin{document}\n\\end{document}\n")

      # Symlink styles -> ../shared_styles
      File.symlink(shared_styles, File.join(proj_dir, 'styles'))

      macros = LaTeXMacroHarvester.harvest(main_file)
      assert_includes macros, 'SymlinkedDirMacro'

      hint = LaTeXErrorCatalog.suggest_command('\\SymlinkedDirMcro', file: main_file)
      assert_equal "Did you mean '\\SymlinkedDirMacro'?", hint
    end
  end
end
