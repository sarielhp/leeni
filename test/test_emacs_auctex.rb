#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'stringio'
require 'tmpdir'

load File.expand_path('../leeni', __dir__)

class TestEmacsAuctex < Minitest::Test
  def test_error_block_continuation_line_in_emacs_mode
    builder = LatexBuilder.new('main.tex', emacs: true)
    err_block = [
      './main.tex:10: Undefined control sequence.',
      'l.10 \\badcommand'
    ]
    formatted = builder.send(:format_error_block, err_block, 10)
    assert_equal "./main.tex:10: Undefined control sequence.\nl.10 \\badcommand\n ", formatted

    # When emacs is false, no trailing space continuation line
    plain_builder = LatexBuilder.new('main.tex', emacs: false, color: false)
    plain_formatted = plain_builder.send(:format_error_block, err_block, 10)
    refute_match(/\n \z/, plain_formatted)
  end

  def test_error_block_includes_suggestion_in_emacs_mode
    builder = LatexBuilder.new('main.tex', emacs: true)
    err_block = [
      './main.tex:15: Undefined control sequence.',
      'l.15 \\QoutePExt'
    ]
    catalog = { hint: "Did you mean '\\QuotePExt'?" }
    formatted = builder.send(:format_error_block, err_block, 15, catalog: catalog)
    expected = "./main.tex:15: Undefined control sequence.\nl.15 \\QoutePExt\n \nDid you mean '\\QuotePExt'?"
    assert_equal expected, formatted

    # When item contains catalog
    item_with_cat = { catalog: catalog }
    formatted_item = builder.send(:format_error_block, err_block, 15, item: item_with_cat)
    assert_equal expected, formatted_item
  end

  def test_render_diagnostic_entry_emits_continuation_and_blank_line
    builder = LatexBuilder.new('main.tex', emacs: true)
    item = {
      file: './main.tex',
      line: 10,
      line_str: '10',
      text: './main.tex:10: Undefined control sequence.\nl.10 \\badcommand',
      err_block: ['./main.tex:10: Undefined control sequence.', 'l.10 \\badcommand'],
      catalog: { hint: "Did you mean '\\goodcommand'?" }
    }
    sio = StringIO.new
    builder.send(:render_diagnostic_entry, item, 2, nil, 'errors', io: sio)
    output = sio.string

    assert_includes output, "(main.tex\n"
    assert_includes output, "l.10 \\badcommand\n \nDid you mean '\\goodcommand'?\n\n"
    refute_match(/\e\[/, output) # strictly no ANSI escape codes in emacs mode
  end

  def test_custom_alerts_formatted_as_latex_warning_for_auctex
    builder = LatexBuilder.new('main.tex', emacs: true)

    # Custom alert with line number
    alert_msg = 'Inverted \\label: \\label{sec:intro} appears before \\section'
    formatted = builder.send(:format_diagnostic_line, '25', alert_msg, :red)
    assert_equal 'LaTeX Warning: Inverted \label: \label{sec:intro} appears before \section on input line 25.', formatted

    # Custom alert without line number
    font_msg = 'Type 3 (raster bitmap) font detected: cmr10'
    formatted_font = builder.send(:format_diagnostic_line, '', font_msg, :red)
    assert_equal 'LaTeX Warning: Type 3 (raster bitmap) font detected: cmr10', formatted_font

    # Standard LaTeX warning remains unchanged
    std_warn = 'LaTeX Warning: Reference `sec:unknown` undefined on input line 42.'
    formatted_std = builder.send(:format_diagnostic_line, '42', std_warn, :yellow)
    assert_equal std_warn, formatted_std

    # Overfull hbox remains unchanged
    box_msg = 'Overfull \\hbox (15.0pt too wide) in paragraph at lines 50--52'
    formatted_box = builder.send(:format_diagnostic_line, '50', box_msg, :yellow)
    assert_equal box_msg, formatted_box
  end

  def test_non_error_tiers_not_suppressed_when_errors_present_in_emacs_mode
    builder = LatexBuilder.new('main.tex', emacs: true)
    errors = [
      { file: './main.tex', line: 10, line_str: '10', text: 'err', err_block: ['./main.tex:10: err', 'l.10 \\foo'] }
    ]
    alerts = [
      { file: './main.tex', line: 20, line_str: '20', text: 'Inverted \\label: \\label{a} before \\section' }
    ]
    warnings = [
      { file: './main.tex', line: 30, line_str: '30', text: 'LaTeX Warning: Reference `b` undefined on input line 30.' }
    ]

    out, = capture_io do
      builder.send(:render_diagnostics_tiers, errors, alerts, warnings, [], 1)
    end

    assert_includes out, 'l.10 \\foo'
    assert_includes out, 'LaTeX Warning: Inverted \\label'
    assert_includes out, 'LaTeX Warning: Reference `b` undefined'
  end

  def test_throttle_errors_disabled_in_emacs_mode
    builder = LatexBuilder.new('main.tex', emacs: true)
    many_errors = (1..15).map do |i|
      { file: './main.tex', line: i, line_str: i.to_s, text: "err #{i}", err_block: ["./main.tex:#{i}: err", "l.#{i} \\cmd"] }
    end
    displayed, cascade = builder.send(:throttle_errors, many_errors)
    assert_equal 15, displayed.size
    assert_nil cascade
  end

  def test_auctex_batch_parses_all_diagnostics_sequentially
    auctex_site = File.expand_path('~/.emacs.d/straight/build/auctex/tex-site.el')
    skip 'AUCTeX not installed in ~/.emacs.d/straight' unless File.exist?(auctex_site)

    Dir.mktmpdir do |dir|
      tex_file = File.join(dir, 'main.tex')
      File.write(tex_file, "\\documentclass{article}\n\\begin{document}\nHi\n\\end{document}\n")

      builder = LatexBuilder.new(tex_file, emacs: true)
      errors = [
        { file: tex_file, line: 10, line_str: '10', text: "#{tex_file}:10: Undefined control sequence.\nl.10 \\foo", err_block: ["#{tex_file}:10: Undefined control sequence.", 'l.10 \\foo'], catalog: { hint: "Did you mean '\\food'?" } },
        { file: tex_file, line: 20, line_str: '20', text: "#{tex_file}:20: Undefined control sequence.\nl.20 \\bar", err_block: ["#{tex_file}:20: Undefined control sequence.", 'l.20 \\bar'] }
      ]
      warnings = [
        { file: tex_file, line: 30, line_str: '30', text: 'Inverted \\label: \\label{sec:intro} appears before \\section' },
        { file: tex_file, line: 40, line_str: '40', text: 'LaTeX Warning: Citation "xyz" on page 1 undefined on input line 40.' },
        { file: tex_file, line: 50, line_str: '50', text: 'Overfull \\hbox (15.0pt too wide) in paragraph at lines 50--52' }
      ]

      sio = StringIO.new
      builder.send(:print_diagnostics_body, warnings, errors, io: sio)
      log_path = File.join(dir, 'run.log')
      File.write(log_path, sio.string)

      elisp = <<~ELISP
        (progn
          (require (quote tex))
          (with-temp-buffer
            (insert-file-contents "#{log_path}")
            (setq TeX-error-file nil)
            (setq TeX-error-offset nil)
            (setq TeX-error-list nil)
            (goto-char (point-min))
            (while (TeX-parse-error nil t))
            (message "PARSED_COUNT: %d" (length TeX-error-list))
            (dolist (item TeX-error-list)
              (message "ITEM: type=%s line=%s" (nth 0 item) (nth 2 item)))))
      ELISP

      _out, err, st = Open3.capture3('emacs', '-Q', '--batch', '-l', auctex_site, '--eval', elisp)
      assert_equal 0, st.exitstatus
      assert_includes err, 'PARSED_COUNT: 5'
      assert_includes err, 'ITEM: type=error line=10'
      assert_includes err, 'ITEM: type=error line=20'
      assert_includes err, 'ITEM: type=warning line=30'
      assert_includes err, 'ITEM: type=warning line=40'
      assert_includes err, 'ITEM: type=bad-box line=50'
    end
  end
end
