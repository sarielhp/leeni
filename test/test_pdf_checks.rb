#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/leeni/pdf_checks'

# pdfinfo output is parsed into page-size groups; only a mixed set is reported.
class TestPdfChecks < Minitest::Test
  UNIFORM = <<~INFO
    Title:           x
    Page    1 size:  612 x 792 pts (letter)
    Page    2 size:  612 x 792 pts (letter)
    File size:       1 bytes
  INFO

  MIXED = <<~INFO
    Page    1 size:  612 x 792 pts (letter)
    Page    2 size:  612 x 792 pts (letter)
    Page    3 size:  595.276 x 841.89 pts (A4)
    Page    4 size:  612 x 792 pts (letter)
    Page    5 size:  792 x 612 pts
  INFO

  def test_uniform_pages_are_not_reported
    assert_nil LaTeXPdfChecks.mixed_page_sizes(UNIFORM)
    assert_nil LaTeXPdfChecks.mixed_page_sizes('')
  end

  def test_mixed_pages_are_grouped_with_the_dominant_size_first
    groups = LaTeXPdfChecks.mixed_page_sizes(MIXED)
    assert_equal ['letter (612 x 792 pt)', 'A4 (595 x 842 pt)', '792 x 612 pt'], groups.map(&:first)
    assert_equal [1, 2, 4], groups[0][1]
    msg = LaTeXPdfChecks.page_size_message(groups)
    assert_equal 'Mixed page sizes: 3 pages letter (612 x 792 pt), but A4 (595 x 842 pt) on page 3; 792 x 612 pt on page 5', msg
  end

  def test_long_page_lists_are_compacted
    info = (1..20).map { |n| "Page #{n} size: 612 x 792 pts (letter)" }.join("\n")
    info += "\n" + (21..40).map { |n| "Page #{n} size: 595 x 842 pts (A4)" }.join("\n")
    msg = LaTeXPdfChecks.page_size_message(LaTeXPdfChecks.mixed_page_sizes(info))
    assert_includes msg, 'on pages 21, 22, 23, 24, 25, 26, ... (20 pages)'
  end
end
