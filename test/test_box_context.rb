#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/leeni/utils'
require_relative '../lib/leeni/box_context'

class TestBoxContext < Minitest::Test
  def describe(source, line, kind, line_end = nil)
    Dir.mktmpdir('box_context') do |dir|
      path = File.join(dir, 'doc.tex')
      File.write(path, source)
      LaTeXBoxContext.describe(path, line, kind, line_end)
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

  def test_comment_with_row_separator_does_not_split_rows
    src = "\\begin{align*}\n  a &= b % c \\\\ d\n  &= e\n\\end{align*}\n"
    info = describe(src, 4, 'detected_line')
    assert_equal 'align*', info[:env]
    refute info.key?(:rows), "a commented \\\\ must not split rows: #{info}"
  end

  # --- headings -------------------------------------------------------------

  def test_section_head_line_is_a_heading
    src = "\\section{A very long title}\nText.\n"
    assert_equal 'section', describe(src, 1, 'paragraph', 1)[:heading]
  end

  def test_run_in_paragraph_head_is_not_a_heading
    refute describe("\\paragraph{Run in title.} Text.\n", 1, 'paragraph', 1).key?(:heading)
  end

  def test_titled_theorem_with_opening_macros_is_a_heading
    src = "\\begin{theorem}[Long title]\n  \\index{x}\n  % note\n  \\thmlab{t}%\n  Let $x$ be.\n\\end{theorem}\n"
    info = describe(src, 5, 'paragraph', 5)
    assert_equal 'theorem', info[:heading]
    assert_equal 1, info[:env_start]
  end

  def test_heading_when_text_shares_the_begin_line
    src = "\\begin{lemma}[Title] Let $x$ be.\n\\end{lemma}\n"
    assert_equal 'lemma', describe(src, 1, 'paragraph', 1)[:heading]
  end

  def test_untitled_theorem_is_not_a_heading
    src = "\\begin{theorem}\n  Let $x$ be.\n\\end{theorem}\n"
    refute describe(src, 2, 'paragraph', 2).key?(:heading)
  end

  def test_text_before_the_box_means_not_a_heading
    src = "\\begin{theorem}[T]\n  Some intro text.\n  More text.\n\\end{theorem}\n"
    refute describe(src, 3, 'paragraph', 3).key?(:heading)
  end

  def test_list_environment_with_optional_argument_is_not_a_heading
    src = "\\begin{enumerate}[label=(\\alph*)]\n  \\item text\n\\end{enumerate}\n"
    refute describe(src, 2, 'paragraph', 2).key?(:heading)
  end

  # --- longest inline math --------------------------------------------------

  def test_longest_inline_math_picks_the_longest_dollar_span
    src = "We have $a$ and $\\sum_{i=1}^{n} \\frac{x_i}{y_i} + z_i$ here.\n"
    info = describe(src, 1, 'paragraph', 1)
    assert_equal 1, info[:math_line]
    assert_equal 'sum_{i=1}^{n}\\frac{x_i}{y_i}+z_i'.length + 1, info[:math_chars]
  end

  def test_longest_inline_math_reports_the_line_where_the_span_starts
    src = "Text here and then\n$\\alpha_1 + \\alpha_2 +\n\\alpha_3 + \\alpha_4$ more.\n"
    info = describe(src, 1, 'paragraph', 3)
    assert_equal 2, info[:math_line]
  end

  def test_paren_and_math_environment_spans_are_found
    src = "Text \\( x_1 + x_2 + x_3 + x_4 + x_5 \\) and\n\\begin{math}\n  y_1 + y_2 + y_3 + y_4 + y_5 + y_6 + y_7\n\\end{math}\n"
    assert_equal 2, describe(src, 1, 'paragraph', 4)[:math_line]
  end

  def test_short_math_gives_no_hint
    refute describe("Let $x$ and $y$ be.\n", 1, 'paragraph', 1).key?(:math_chars)
  end

  def test_odd_dollar_count_gives_no_dollar_hint
    src = "Cost is \\$5 but $a_1 + a_2 + a_3 + a_4 + a_5 + a_6 + a_7$ and a stray $ here.\n"
    refute describe(src, 1, 'paragraph', 1).key?(:math_chars)
  end

  def test_display_dollars_in_the_span_give_no_dollar_hint
    src = "Text $$ a_1 + a_2 + a_3 + a_4 + a_5 + a_6 + a_7 + a_8 $$ more.\n"
    refute describe(src, 1, 'paragraph', 1).key?(:math_chars)
  end

  def test_comment_dollar_is_ignored
    src = "Text $a_1 + a_2 + a_3 + a_4 + a_5 + a_6$ % stray $ in a comment\n"
    assert_equal 1, describe(src, 1, 'paragraph', 1)[:math_line]
  end
end
