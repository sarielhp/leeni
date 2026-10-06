# frozen_string_literal: true

require 'minitest/autorun'
require 'stringio'
require_relative '../lib/leeni/presenters'

class TestPresenters < Minitest::Test
  def test_compiler_presenter_gnu_format
    presenter = Leeni::CompilerPresenter.new(color: false, link: false)
    rec = { file: 'main.tex', line: 12, col: 3, tier: 'errors', message: 'syntax error' }
    io = StringIO.new
    presenter.render_record(rec, io: io)
    assert_equal "main.tex:12:3: error: syntax error\n", io.string
  end

  def test_agent_presenter_plain_text_and_folding
    presenter = Leeni::AgentPresenter.new(color: false, link: false, fold_threshold: 2)
    warnings = (1..6).map do |i|
      { file: 'main.tex', line: i * 10, tier: 'warnings', category: :undefined_citation, message: "undefined citation 'cite#{i}'" }
    end
    io = StringIO.new
    presenter.render_diagnostics(warnings: warnings, io: io)
    lines = io.string.lines.map(&:strip)

    # Top 2 citations shown
    assert_includes lines[0], "undefined citation 'cite1'"
    assert_includes lines[1], "undefined citation 'cite2'"
    # Fold note for remaining 4
    assert_equal "leeni: note: 4 more undefined citations in main.tex (pass -a to show all)", lines[2]
    assert_equal 3, lines.size
    # No ANSI escapes
    refute_match(/\e\[/, io.string)
  end

  def test_agent_presenter_unparsed_failure
    presenter = Leeni::AgentPresenter.new
    io = StringIO.new
    presenter.render_diagnostics(errors: [], log_tail: "! Emergency stop.\nFatal error\n", file: 'paper.tex', io: io)
    out = io.string
    assert_includes out, "paper.tex:1: error: compilation failed with unclassified error"
    assert_includes out, "paper.tex:1: note: compiler log tail:"
    assert_includes out, "> ! Emergency stop."
    assert_includes out, "> Fatal error"
  end

  def test_agent_presenter_suppresses_warnings_when_errors_exist
    presenter = Leeni::AgentPresenter.new
    errs = [{ file: 'main.tex', line: 5, tier: 'errors', message: 'fatal syntax crash' }]
    warns = [{ file: 'main.tex', line: 10, tier: 'warnings', message: 'minor warning' }]
    io = StringIO.new
    presenter.render_diagnostics(errors: errs, warnings: warns, io: io)
    assert_includes io.string, 'main.tex:5: error: fatal syntax crash'
    refute_includes io.string, 'minor warning'
  end

  def test_json_presenter
    presenter = Leeni::JsonPresenter.new
    result = Leeni::DiagnosticResult.new(
      success: true,
      exit_code: 0,
      pdf_path: 'doc.pdf',
      records: [],
      summary: { errors: 0, alerts: 0, warnings: 0, whatevers: 0 }
    )
    io = StringIO.new
    presenter.render_result(result, io: io)
    parsed = JSON.parse(io.string)
    assert_equal true, parsed['success']
    assert_equal 'doc.pdf', parsed['pdf_path']
  end
end
