#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'

load File.expand_path('../leeni', __dir__)

# "Float(s) lost" is raised at the next \clearpage, often pages after the
# \marginpar or float that started inside a box. The runtime hook logs that
# start (LEENI_FLOAT_IN_BOX), and the error is moved there. Also: every
# catalogue entry links a docs/errors page that exists.
class TestLostFloats < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  LOST_TAIL = <<~LOG
    ./main.tex:30: LaTeX Error: Float(s) lost.

    See the LaTeX manual or LaTeX Companion for explanation.
    Type  H <return>  for immediate help.
     ...

    l.30 \\end{document}

  LOG

  def builder
    LatexBuilder.new('main.tex', { color: false })
  end

  def errors_of(log)
    b = builder
    [b, b.send(:relocate_lost_floats!, b.send(:extract_errors, log), log)]
  end

  def test_error_moves_to_the_float_started_in_a_box
    log = "(./main.tex\n(./sub.tex\nLEENI_FLOAT_IN_BOX:7:marginpar\n)\n[1]\n#{LOST_TAIL}"
    _, errors = errors_of(log)
    err = errors.first
    assert_equal :float_lost, err[:catalog_id]
    assert_equal 'sub.tex', File.basename(err[:file])
    assert_equal 7, err[:line]
    assert_match(/\\marginpar .*starts here/, err[:catalog][:hint])
    assert_match(/noticed the lost float only at main\.tex:30/, err[:catalog][:hint])
    assert_match(/\Asub\.tex:7: |\A\S*sub\.tex:7: /, err[:err_block].first, 'the --emacs block names the new line')
  end

  def test_each_error_takes_the_first_marker_since_the_previous_one
    log = "(./main.tex\nLEENI_FLOAT_IN_BOX:5:figure\nLEENI_FLOAT_IN_BOX:9:marginpar\n" \
          "#{LOST_TAIL.sub('30', '12').sub('l.30', 'l.12')}LEENI_FLOAT_IN_BOX:20:table\n#{LOST_TAIL}"
    _, errors = errors_of(log)
    assert_equal([5, 20], errors.map { |e| e[:line] })
    assert_match(/a figure environment .*\(and 1 more after it\)/, errors.first[:catalog][:hint])
    assert_match(/a table environment/, errors.last[:catalog][:hint])
  end

  def test_without_a_marker_the_error_keeps_its_line_and_general_hint
    _, errors = errors_of("(./main.tex\n[1]\n#{LOST_TAIL}")
    err = errors.first
    assert_equal 30, err[:line]
    assert_match(/only where LaTeX noticed/, err[:catalog][:hint])
  end

  def test_lost_float_links_its_doc_page_under_the_hint
    b, errors = errors_of("(./main.tex\n[1]\n#{LOST_TAIL}")
    text = b.send(:format_error_block, errors.first[:err_block], 30, catalog: errors.first[:catalog], item: errors.first)
    assert_includes text, '▸ See: https://sarielhp.github.io/leeni/errors/90_float_lost/'
  end

  def test_other_errors_do_not_print_a_doc_line
    log = "./main.tex:5: Undefined control sequence.\nl.5 \\nonexistentmacro\n\n"
    b = builder
    err = b.send(:extract_errors, log).first
    text = b.send(:format_error_block, err[:err_block], 5, catalog: err[:catalog], item: err)
    refute_includes text, 'See:'
    assert_equal 'https://sarielhp.github.io/leeni/errors/02_undefined_control_sequence/', err[:catalog][:doc_url]
  end

  def test_every_doc_slug_names_an_existing_page
    missing = LaTeXErrorCatalog::CATALOG.filter_map { |e| e[:doc_slug] }.uniq.reject do |slug|
      File.file?(File.join(ROOT, 'docs', 'errors', slug, 'README.md'))
    end
    assert_empty missing
    assert_equal 'https://sarielhp.github.io/leeni/errors/90_float_lost/',
                 LaTeXErrorCatalog.find_by_id(:float_lost)[:doc_url]
  end

  def test_runtime_hook_carries_the_float_box_hook
    assert_includes LatexBuilder::RUNTIME_HOOK, 'LEENI_FLOAT_IN_BOX'
    assert_includes LatexBuilder::RUNTIME_HOOK, '\AddToHook{begindocument/end}{\leeni@fltinstall}'
  end
end
