# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/leeni/diagnostic_record'

class TestDiagnosticRecord < Minitest::Test
  def test_record_initialization_and_helpers
    rec = Leeni::DiagnosticRecord.new(
      file: 'paper.tex',
      line: 42,
      col: 5,
      tier: 'errors',
      category: :undefined_control_sequence,
      message: "undefined control sequence \\foo",
      token: '\\foo'
    )

    assert rec.error?
    refute rec.warning?
    refute rec.alert?
    refute rec.whatever?

    h = rec.to_h
    assert_equal 'paper.tex', h[:file]
    assert_equal 42, h[:line]
    assert_equal 5, h[:col]
    assert_equal 'errors', h[:tier]
    assert_equal :undefined_control_sequence, h[:category]
    assert_nil h[:hint] # compacted out
  end

  def test_result_serialization
    rec = Leeni::DiagnosticRecord.new(
      file: 'paper.tex',
      line: 10,
      tier: 'warnings',
      category: :undefined_citation,
      message: "undefined citation 'knuth1984'"
    )

    res = Leeni::DiagnosticResult.new(
      success: true,
      exit_code: 0,
      pdf_path: 'paper.pdf',
      records: [rec],
      summary: { errors: 0, alerts: 0, warnings: 1, whatevers: 0 },
      folded_counts: { undefined_citation: 5 }
    )

    json_str = res.to_json
    data = JSON.parse(json_str)

    assert_equal true, data['success']
    assert_equal 0, data['exit_code']
    assert_equal 'paper.pdf', data['pdf_path']
    assert_equal 1, data['summary']['warnings']
    assert_equal 1, data['diagnostics'].size
    assert_equal "undefined citation 'knuth1984'", data['diagnostics'][0]['message']
    assert_equal 5, data['folded_counts']['undefined_citation']
  end
end
