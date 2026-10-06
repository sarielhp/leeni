#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/leeni/color'
require_relative '../lib/leeni/compile_format'

class TestCompileFormat < Minitest::Test
  def test_clean_message_stripping_headers
    # Package warning
    msg1 = 'Package hyperref Warning: Token not allowed in PDF string on input line 42.'
    assert_equal "[hyperref] Token not allowed in PDF string", LaTeXCompileFormat.clean_message(msg1)

    # Package warning with dot in name (pdftex.def regression)
    msg2 = 'Package pdftex.def Warning: Option `pdftex\' not used on input line 15.'
    assert_equal "[pdftex.def] Option `pdftex' not used", LaTeXCompileFormat.clean_message(msg2)

    # Standard LaTeX warning
    msg3 = "LaTeX Warning: Reference `fig:arch' on page 2 undefined on input line 99."
    assert_equal "reference `fig:arch' on page 2 undefined", LaTeXCompileFormat.clean_message(msg3)

    # Overfull hbox
    msg4 = 'Overfull \hbox (15.2pt too wide) in paragraph at lines 50--55'
    assert_equal 'overfull \hbox (15.2pt too wide) in paragraph', LaTeXCompileFormat.clean_message(msg4)

    # Font warning with continuation line
    msg5 = "LaTeX Font Warning: Font shape `TU/lmss/m/sc' in size <10.95> not available\n(Font)              Font shape `TU/lmr/m/sc' tried instead on input line 116."
    assert_equal "[font] Font shape `TU/lmss/m/sc' in size <10.95> not available, Font shape `TU/lmr/m/sc' tried instead", LaTeXCompileFormat.clean_message(msg5)

    # Inline location noise stripping
    msg6 = "LaTeX Warning: You have requested, on input line 13, version `2099/01/01' of package amsmath, but only version `2026/05/19' is available."
    assert_equal "you have requested version `2099/01/01' of package amsmath, but only version `2026/05/19' is available", LaTeXCompileFormat.clean_message(msg6)
  end

  def test_clean_message_trailing_period_and_ellipsis
    assert_equal 'undefined control sequence \foo', LaTeXCompileFormat.clean_message('Undefined control sequence \foo.')
    assert_equal 'reading file...', LaTeXCompileFormat.clean_message('Reading file...')
  end

  def test_render_uncolored_gnu_format
    rec = {
      file: 'paper.tex',
      line: 42,
      col: 5,
      tier: 'errors',
      message: 'Undefined control sequence.',
      token: '\\unknowncmd',
      hint: 'Did you mean \\knowncmd?'
    }

    rendered = LaTeXCompileFormat.render(rec, color: false)
    expected = "paper.tex:42:5: error: undefined control sequence \\unknowncmd (hint: Did you mean \\knowncmd?)"
    assert_equal expected, rendered
    assert_match(/\A[^:\n]+:\d+:\d+: error: [^A-Z\n].+[^.\n]\z/, rendered)
  end

  def test_render_missing_line_defaults_to_one
    rec = {
      file: 'main.tex',
      line: 0,
      col: nil,
      tier: 'errors',
      message: 'Emergency stop.'
    }

    rendered = LaTeXCompileFormat.render(rec, color: false)
    assert_equal 'main.tex:1: error: emergency stop', rendered
  end

  def test_render_alert_severity
    rec = {
      file: 'paper.tex',
      line: 15,
      col: nil,
      tier: 'alerts',
      message: "LaTeX Warning: Reference 'sec:intro' undefined on input line 15."
    }

    rendered = LaTeXCompileFormat.render(rec, color: false)
    assert_equal "paper.tex:15: warning: [alert] reference 'sec:intro' undefined", rendered
    assert_match(/\A[^:\n]+:\d+: warning: \[alert\] /, rendered)
  end

  def test_render_whatever_severity
    rec = {
      file: 'paper.tex',
      line: 88,
      col: nil,
      tier: 'whatevers',
      message: 'Underfull \hbox (badness 10000) in paragraph at lines 88--90'
    }

    rendered = LaTeXCompileFormat.render(rec, color: false)
    assert_equal 'paper.tex:88: note: underfull \hbox (badness 10000) in paragraph', rendered
  end

  def test_render_colored_has_ansi_escapes
    rec = {
      file: 'paper.tex',
      line: 10,
      col: 2,
      tier: 'errors',
      message: 'Undefined control sequence \foo.'
    }

    orig = Rainbow.enabled
    begin
      Rainbow.enabled = true
      rendered = LaTeXCompileFormat.render(rec, color: true)
      # File is bold, line/col is cyan bright, error is red bright bold
      assert_includes rendered, "\e["
      # Strip ANSI and ensure it matches the uncolored version
      plain = rendered.gsub(/\e\[[0-9;]*m/, '')
      assert_equal 'paper.tex:10:2: error: undefined control sequence \foo', plain
    ensure
      Rainbow.enabled = orig
    end
  end

  def test_render_hyperlink_format
    rec = {
      file: 'chap1.tex',
      line: 42,
      col: nil,
      tier: 'alerts',
      message: "LaTeX Warning: Label `sec:dup' multiply defined."
    }

    rendered = LaTeXCompileFormat.render(rec, color: false, link: true)
    abs_path = URI::DEFAULT_PARSER.escape(File.expand_path('chap1.tex'))
    expected_link = "\e]8;;file://#{abs_path}#42\e\\chap1.tex:42:\e]8;;\e\\"
    assert_includes rendered, expected_link
    assert_includes rendered, "warning: [alert] label `sec:dup' multiply defined"

    # Stripping OSC 8 and ANSI yields exact plain compiler format
    plain = rendered.gsub(/\e\]8;;[^\e]*\e\\/, '').gsub(/\e\[[0-9;]*m/, '')
    assert_equal "chap1.tex:42: warning: [alert] label `sec:dup' multiply defined", plain
  end

  def test_render_hyperlink_with_color_uses_cyan_bold
    rec = {
      file: 'chap1.tex',
      line: 42,
      col: nil,
      tier: 'errors',
      message: 'Undefined control sequence.'
    }

    orig = Rainbow.enabled
    begin
      Rainbow.enabled = true
      rendered = LaTeXCompileFormat.render(rec, color: true, link: true)
      assert_includes rendered, "\e]8;;file://"
      assert_includes rendered, "\e[1mchap1.tex:42:\e[0m"
      plain = rendered.gsub(/\e\]8;;[^\e]*\e\\/, '').gsub(/\e\[[0-9;]*m/, '')
      assert_equal "chap1.tex:42: error: undefined control sequence", plain
    ensure
      Rainbow.enabled = orig
    end
  end
end
