#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/leeni/utils'
require_relative '../lib/leeni/box_context'

class TestBoxContext < Minitest::Test
  def describe(source, line, kind)
    Dir.mktmpdir('box_context') do |dir|
      path = File.join(dir, 'doc.tex')
      File.write(path, source)
      LaTeXBoxContext.describe(path, line, kind)
    end
  end

  def test_display_reports_environment_and_widest_row
    src = <<~'TEX'
      Text.
      \begin{align*}
        a &= b
      \\
        c &= d + e + f + g + h + i
          + j + k
      \\
        x &= y
      \end{align*}
    TEX
    info = describe(src, 9, 'detected_line')
    assert_equal 'align*', info[:env]
    assert_equal 2, info[:env_start]
    assert_equal 3, info[:rows]
    assert_equal '5-6', info[:widest]
  end

  def test_single_row_display_has_no_row_info
    src = "\\begin{equation*}\n  a + b\n\\end{equation*}\n"
    info = describe(src, 3, 'detected_line')
    assert_equal({ env: 'equation*', env_start: 1 }, info)
  end

  def test_separators_inside_braces_and_nested_environments_are_not_rows
    src = <<~'TEX'
      \begin{align*}
        f(x) &= \begin{cases} 1 \\ 2 \end{cases} + \substack{a \\ b}
      \end{align*}
    TEX
    info = describe(src, 3, 'detected_line')
    assert_equal 'align*', info[:env]
    refute info.key?(:rows), "nested \\\\ must not split rows: #{info}"
  end

  def test_row_spacing_argument_is_not_read_as_display_opener
    src = <<~'TEX'
      \begin{align*}
        a &= b \\[1ex]
        c &= d
      \end{align*}
    TEX
    info = describe(src, 4, 'detected_line')
    assert_equal 'align*', info[:env]
    assert_equal 1, info[:env_start]
    assert_equal 2, info[:rows]
  end

  def test_nested_same_name_environment_finds_matching_begin
    src = <<~'TEX'
      \begin{align*}
      a &= \begin{aligned} b \\ c \end{aligned}
      \end{align*}
    TEX
    assert_equal 1, describe(src, 3, 'detected_line')[:env_start]
  end

  def test_bracket_display_and_comments
    src = "% \\begin{align*}\n\\[\n  a + b % \\end{x}\n\\]\n"
    info = describe(src, 4, 'detected_line')
    assert_equal '\\[ ... \\]', info[:env]
    assert_equal 2, info[:env_start]
  end

  def test_dollar_display_pairs_within_paragraph
    src = "Some text.\n\n$$\n a + b\n$$\n"
    assert_equal({ env: '$$', env_start: 3 }, describe(src, 5, 'detected_line'))
  end

  def test_odd_dollar_display_count_claims_nothing
    assert_equal({}, describe("Para\n$$ x\n$$ y\n$$\n", 4, 'detected_line'))
  end

  def test_stray_dollar_display_in_earlier_paragraph_is_ignored
    src = "Text $$ stray.\n\n$$\n a + b\n$$\n"
    assert_equal({ env: '$$', env_start: 3 }, describe(src, 5, 'detected_line'))
  end

  def test_paragraph_span_reports_enclosing_environment
    src = "\\begin{theorem}\n  \\index{x}\n  Let $x$ be long.\n\\end{theorem}\n"
    info = describe(src, 3, 'paragraph')
    assert_equal({ env: 'theorem', env_start: 1 }, info)
  end

  def test_document_body_is_not_reported
    src = "\\begin{document}\nPlain paragraph.\n\\end{document}\n"
    assert_equal({}, describe(src, 2, 'paragraph'))
  end

  def test_missing_file_returns_empty
    assert_equal({}, LaTeXBoxContext.describe('/no/such/file.tex', 3, 'detected_line'))
  end
end
