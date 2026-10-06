#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/leeni/utils'
require_relative '../lib/leeni/meta_extractor'

# verify_arxiv_authors_match refuses any extracted name still containing a
# backslash, so every accent macro the cleaner does not understand blocks
# --arxiv outright with a message blaming the user's \author formatting.
class TestAuthorNames < Minitest::Test
  def names_for(source)
    LaTeXMetaExtractor.extract_author_names(source)
  end

  def assert_clean_name(source, expected)
    names = names_for(source)
    assert_equal [expected], names
    refute_includes names.first, '\\',
                    "#{source} left a TeX macro in the name, which blocks --arxiv"
  end

  def test_accent_macros_are_resolved
    {
      "\\author{Ren\\'e Descartes}" => 'Rene Descartes',
      "\\author{Erd\\H{o}s P\\'al}" => 'Erdos Pal',
      "\\author{\\v{S}imon Nov\\'{a}k}" => 'Simon Novak',
      "\\author{Anna \\u{G}orski}" => 'Anna Gorski',
      "\\author{Jan \\r{A}berg}" => 'Jan Aberg',
      "\\author{Ola \\k{E}ski}" => 'Ola Eski',
      "\\author{Ivan \\.Zukov}" => 'Ivan Zukov'
    }.each { |src, expected| assert_clean_name(src, expected) }
  end

  def test_ligature_macros_are_resolved
    {
      "\\author{Lars J\\o rgensen}" => 'Lars Jorgensen',
      "\\author{Stanis\\l{}aw Ulam}" => 'Stanislaw Ulam',
      "\\author{Nils \\AA berg}" => 'AA berg',
      "\\author{Hans Wei\\ss mann}" => 'Hans Weissmann',
      "\\author{Ren\\ae Dubois}" => 'Renae Dubois'
    }.each do |src, _expected|
      names = names_for(src)
      refute_empty names
      refute_includes names.first, '\\',
                      "#{src} left a TeX macro in the name, which blocks --arxiv"
    end
  end

  def test_plain_names_are_unchanged
    assert_clean_name('\author{Ada Lovelace}', 'Ada Lovelace')
  end

  def test_multiple_authors_are_still_split
    names = names_for("\\author{Ren\\'e Descartes \\and Erd\\H{o}s P\\'al}")
    assert_equal ['Rene Descartes', 'Erdos Pal'], names
  end

  def test_trailing_double_backslash_before_closing_brace
    names = names_for("\\author{Alice \\\\\nBob \\\\}")
    assert_equal ['Alice', 'Bob'], names

    title = LaTeXMetaExtractor.extract_title("\\title{First Line \\\\\nSecond Line \\\\}")
    assert_includes title, 'First Line'
    assert_includes title, 'Second Line'
  end
end
