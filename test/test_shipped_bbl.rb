#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/leeni/utils'
require_relative '../lib/leeni/packaging_shared'

# Packages ship the .bbl the PDF was built with, and say so when the
# working-tree copy differs or the shipped one fits the other bibliography system.
class TestShippedBbl < Minitest::Test
  BIBTEX_BBL = "\\begin{thebibliography}{1}\n\\bibitem{k} A. Author.\n\\end{thebibliography}\n"
  BIBLATEX_BBL = "% $ biblatex bbl format version 3.3 $\n\\entry{k}{article}{}\n\\endentry\n"
  BIBLATEX_FLS = "PWD /p\nINPUT /usr/share/texmf/tex/latex/biblatex/biblatex.sty\n"
  PLAIN_FLS = "PWD /p\nINPUT /usr/share/texmf/tex/latex/base/article.cls\n"

  def in_dir
    Dir.mktmpdir('leeni_shipped_bbl') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        yield
      end
    end
  end

  def ship = LaTeXPackagingShared.shipped_bbl('main', 'junk')

  def test_the_build_copy_wins_over_a_different_working_tree_copy
    in_dir do
      File.write('main.bbl', BIBLATEX_BBL)
      File.write('junk/main.bbl', BIBTEX_BBL)
      File.write('junk/main.fls', PLAIN_FLS)
      source, warnings = ship
      assert_equal 'junk/main.bbl', source
      assert_equal 1, warnings.size
      assert_includes warnings.first, 'main.bbl in the working tree differs'
    end
  end

  def test_identical_copies_and_a_tree_only_bbl_ship_silently
    in_dir do
      File.write('main.bbl', BIBTEX_BBL)
      File.write('junk/main.fls', PLAIN_FLS)
      assert_equal ['main.bbl', []], ship, 'a supplied .bbl with no build copy ships as is'
      File.write('junk/main.bbl', BIBTEX_BBL)
      assert_equal ['junk/main.bbl', []], ship
    end
  end

  def test_format_that_does_not_fit_the_build_is_reported
    in_dir do
      File.write('main.bbl', BIBTEX_BBL)
      File.write('junk/main.fls', BIBLATEX_FLS)
      _, warnings = ship
      assert_equal ['the shipped main.bbl was written for BibTeX, but the document loads biblatex; ' \
                    'rebuild with l -c before submitting'], warnings
      File.write('main.bbl', BIBLATEX_BBL)
      File.write('junk/main.fls', PLAIN_FLS)
      assert_includes ship.last.first, 'written for biblatex, but the document does not load biblatex'
      File.delete('junk/main.fls')
      assert_empty ship.last, 'no recorder file, no verdict'
    end
  end

  def test_no_entries_ships_nothing
    in_dir do
      File.write('junk/main.bbl', "\\begin{thebibliography}{1}\n\\end{thebibliography}\n")
      assert_equal [nil, []], ship
    end
  end
end
