#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/leeni/config'

# parse_jsonc reads the user's whole configuration. A parse failure is not
# localised: it returns {} and every setting silently reverts to the template
# default, so the scanner has to be exactly right about string boundaries.
class TestJsoncParser < Minitest::Test
  def test_escaped_quote_does_not_end_the_string
    src = '{"arxiv": {"comments": "5 \" wide // note"}, "passes": 1}'
    cfg = LaTeXConfig.parse_jsonc(src)

    assert_equal 1, cfg['passes'], 'an escaped quote followed by // discarded the entire config'
    assert_equal '5 " wide // note', cfg.dig('arxiv', 'comments')
  end

  def test_escaped_quote_before_a_block_comment
    src = '{"arxiv": {"comments": "a \" b /* not a comment */ c"}, "passes": 2}'
    cfg = LaTeXConfig.parse_jsonc(src)

    assert_equal 2, cfg['passes']
    assert_equal 'a " b /* not a comment */ c', cfg.dig('arxiv', 'comments')
  end

  def test_paired_escaped_quotes_still_work
    src = '{"arxiv": {"comments": "see \"note\" // hidden"}, "passes": 3}'
    cfg = LaTeXConfig.parse_jsonc(src)

    assert_equal 3, cfg['passes']
    assert_equal 'see "note" // hidden', cfg.dig('arxiv', 'comments')
  end

  def test_escaped_backslash_at_end_of_string
    cfg = LaTeXConfig.parse_jsonc('{"a": "ends with a backslash \\\\", "passes": 2}')

    assert_equal 2, cfg['passes']
    assert_equal 'ends with a backslash \\', cfg['a']
  end

  def test_commas_inside_strings_are_preserved
    cfg = LaTeXConfig.parse_jsonc('{"arxiv": {"comments": "tables, ] and lists, } done"}}')

    assert_equal 'tables, ] and lists, } done', cfg.dig('arxiv', 'comments'),
                 'the trailing-comma rewrite deleted commas inside a string value'
  end

  def test_commas_inside_array_strings_are_preserved
    cfg = LaTeXConfig.parse_jsonc('{"zip": {"include": ["a, ]", "b"]}}')

    assert_equal ['a, ]', 'b'], cfg.dig('zip', 'include')
  end

  def test_real_trailing_commas_are_still_stripped
    cfg = LaTeXConfig.parse_jsonc(<<~JSONC)
      {
        // a line comment
        "engine": "lualatex",
        "passes": 2,
        "bib_dirs": ["refs", "bib", ],
        /* a block comment */
      }
    JSONC

    assert_equal 'lualatex', cfg['engine']
    assert_equal 2, cfg['passes']
    assert_equal %w[refs bib], cfg['bib_dirs']
  end

  def test_comments_outside_strings_are_still_removed
    cfg = LaTeXConfig.parse_jsonc('{"url": "http://x.org/a", // trailing
      "passes": 1}')

    assert_equal 1, cfg['passes']
    assert_equal 'http://x.org/a', cfg['url'], 'a // inside a string value was treated as a comment'
  end
end
