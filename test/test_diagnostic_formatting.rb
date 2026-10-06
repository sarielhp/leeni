#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'rainbow'

load File.expand_path('../leeni', __dir__)

class TestDiagnosticFormatting < Minitest::Test
  def strip_ansi(str)
    str.gsub(/\e\[[0-9;]*m/, '').gsub(/\e\]8;;[^\e]*\e\\/, '')
  end

  def test_box_warning_cleaning
    builder = LatexBuilder.new('main.tex', {})
    
    # 1. Floating point rounding and redundancy stripping
    cleaned = builder.send(:clean_box_diagnostic, 'Overfull \hbox (54.46506pt too wide) detected at line 125', :alert)
    assert_equal 'Alert: 54.47pt too wide', cleaned

    # 2. Paragraph range
    cleaned_range = builder.send(:clean_box_diagnostic, 'Overfull \hbox (5.72282pt too wide) in paragraph at lines 71--75', :warning)
    assert_equal 'Warning: 5.72pt too wide', cleaned_range

    # 3. Alignment
    cleaned_align = builder.send(:clean_box_diagnostic, 'Overfull \hbox (10.08925pt too wide) in alignment at lines 158--181', :warning)
    assert_equal 'Warning: 10.09pt too wide (alignment)', cleaned_align

    # 4. Underfull box badness
    cleaned_under = builder.send(:clean_box_diagnostic, 'Underfull \hbox (badness 10000) in paragraph at lines 169--171', :note)
    assert_equal 'Note: underfull \hbox (badness 10000)', cleaned_under
  end

  def test_duplicate_ranges_collapsed
    builder = LatexBuilder.new('main.tex', {})
    lines = [
      'Overfull \hbox (50.97342pt too wide) in paragraph at lines 108--108',
      'l.108 \somecode'
    ]
    item, = builder.send(:parse_box_warning, lines, 0, ['main.tex'], false)
    assert_equal '108', item[:line_str]
    assert_equal 108, item[:line]
    assert_nil item[:line_end]
    assert_equal 'Warning: 50.97pt too wide', item[:text]
  end

  def test_multiline_ranges_use_ellipsis
    builder = LatexBuilder.new('main.tex', {})
    lines = [
      'Overfull \hbox (22.19pt too wide) in paragraph at lines 136--137',
      'l.137 \somecode'
    ]
    item, = builder.send(:parse_box_warning, lines, 0, ['main.tex'], false)
    assert_equal "136\u{2026}", item[:line_str]
    assert_equal 136, item[:line]
    assert_equal 137, item[:line_end]
    assert_equal 'Warning: 22.19pt too wide', item[:text]
  end

  def test_monotonic_line_number_sorting
    builder = LatexBuilder.new('main.tex', {})
    # Items with unordered lines and differing severities (which previously caused jumps)
    items = [
      { file: 'chapter.tex', line: 304, line_str: '304', text: 'Alert: 44.05pt too wide', severity: 44.05, index: 2 },
      { file: 'chapter.tex', line: 99, line_str: '99--110', text: 'Alert: 29.57pt too wide', severity: 29.57, index: 1 },
      { file: 'chapter.tex', line: 157, line_str: '157', text: 'Alert: 82.31pt too wide', severity: 82.31, index: 3 },
      { file: 'chapter.tex', line: 121, line_str: '121', text: 'Alert: 115.01pt too wide', severity: 115.01, index: 6 },
      { file: 'chapter.tex', line: 546, line_str: '546', text: 'Alert: 107.67pt too wide', severity: 107.67, index: 5 },
      { file: 'chapter.tex', line: 371, line_str: '371--393', text: 'Alert: 91.55pt too wide', severity: 91.55, index: 4 }
    ]

    all_sorted, = builder.send(:sort_diagnostic_items, items, [])
    sorted_lines = all_sorted.map { |i| i[:line] }
    assert_equal [99, 121, 157, 304, 371, 546], sorted_lines
  end

  def test_reference_and_citation_cleaning_and_deduplication
    builder = LatexBuilder.new('main.tex', {})

    # Reference cleaning
    raw_ref = "LaTeX Warning: Reference `lemma:test' on page 239 undefined on input line 219."
    assert_equal "Warning: undefined reference 'lemma:test' (page 239)", builder.send(:clean_diagnostic_warning, raw_ref)

    # Citation cleaning
    raw_cite = "LaTeX Warning: Citation 'smith2020' on page 42 undefined on input line 354."
    assert_equal "Warning: undefined citation 'smith2020' (page 42)", builder.send(:clean_diagnostic_warning, raw_cite)

    # Math mode cleaning
    raw_math = 'LaTeX Warning: Command \L invalid in math mode on input line 133.'
    assert_equal 'Warning: command \L invalid in math mode', builder.send(:clean_diagnostic_warning, raw_math)

    # Font warning cleaning
    raw_font = "LaTeX Font Warning: Font shape `TU/lmss/m/sc' in size <10.95> not available\n(Font)              Font shape `TU/lmr/m/sc' tried instead on input line 116."
    assert_equal "Warning: [font] Font shape `TU/lmss/m/sc' in size <10.95> not available, Font shape `TU/lmr/m/sc' tried instead", builder.send(:clean_diagnostic_warning, raw_font)

    # Inline package request location cleaning
    raw_pkg = "LaTeX Warning: You have requested, on input line 13, version `2099/01/01' of package amsmath, but only version `2026/05/19' is available."
    assert_equal "Warning: You have requested version `2099/01/01' of package amsmath, but only version `2026/05/19' is available.", builder.send(:clean_diagnostic_warning, raw_pkg)

    # Float too large float rounding
    raw_float = "LaTeX Warning: Float too large for page by 176.81013pt on input line 105."
    assert_equal "Warning: Float too large for page by 176.81pt", builder.send(:clean_diagnostic_warning, raw_float)

    # Deduplication of Hyper reference and Reference
    log = <<~LOG
      (./chapter.tex
      LaTeX Warning: Hyper reference `lemma:test' on page 239 undefined on input line 219.
      LaTeX Warning: Reference `lemma:test' on page 239 undefined on input line 219.
      )
    LOG
    warns = builder.send(:extract_warnings, log)
    assert_equal 1, warns.size
    assert_equal "Warning: undefined reference 'lemma:test' (page 239)", warns.first[:text]
  end

  def test_duplicate_label_cross_referencing_with_links
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'chap1.tex'), "\\section{A}\n\\label{sec:dup}\n")
      File.write(File.join(dir, 'chap2.tex'), "\\section{B}\n\\label{sec:dup}\n")

      builder = LatexBuilder.new('main.tex', link: true)
      locs = [
        { file: File.join(dir, 'chap1.tex'), line: 2 },
        { file: File.join(dir, 'chap2.tex'), line: 2 }
      ]

      alerts = builder.send(:build_duplicate_label_alerts, 'sec:dup', locs, 0)
      assert_equal 2, alerts.size

      # Check chap1 alert mentions chap2
      a1 = alerts[0]
      assert_equal File.join(dir, 'chap1.tex'), a1[:file]
      assert_includes a1[:text], "Alert: label 'sec:dup' duplicate (also at"
      assert_includes a1[:text], 'chap2.tex:2'
      # Verify OSC 8 link is embedded for the other target
      assert_includes a1[:text], "\e]8;;file://"
      assert_includes a1[:text], 'chap2.tex#2'

      # Check chap2 alert mentions chap1
      a2 = alerts[1]
      assert_equal File.join(dir, 'chap2.tex'), a2[:file]
      assert_includes a2[:text], "Alert: label 'sec:dup' duplicate (also at"
      assert_includes a2[:text], 'chap1.tex:2'
      assert_includes a2[:text], "\e]8;;file://"
      assert_includes a2[:text], 'chap1.tex#2'
    end
  end

  def test_osc8_links_in_regular_mode
    Dir.mktmpdir do |dir|
      test_file = File.join(dir, 'test.tex')
      File.write(test_file, "line 1\nline 2\n")

      builder = LatexBuilder.new(test_file, link: true)
      
      # Line number prefix
      line_formatted = builder.send(:format_diagnostic_line, '455', 'Warning: test warning', :yellow, file: test_file)
      assert_includes line_formatted, "\e]8;;file://"
      assert_includes line_formatted, "#{test_file}#455"
      assert_includes line_formatted, '455:'

      # File header banner link
      banner = builder.send(:format_file_separator, test_file, 'alerts', 2)
      assert_includes banner, "\e]8;;file://"
      assert_includes banner, test_file
    end
  end

  def test_themes_have_magenta_and_blue
    LatexColor::THEMES.each do |theme_name, palette|
      assert palette.key?(:magenta), "Theme #{theme_name} missing :magenta"
      assert palette.key?(:blue), "Theme #{theme_name} missing :blue"
    end
  end

  def test_unwrap_log_lines_rejoins_hardwrapped_file_paths
    line1 = '(./very/deeply/nested/directory/path/with/a/long/filename_that_crosses_col_79_x'
    assert_equal 79, line1.length
    line2 = 'yz.tex'
    log = "#{line1}\n#{line2}\n[1]\n)"
    unwrapped = LaTeXUtils.unwrap_log_lines(log, 79)
    assert_includes unwrapped, "(./very/deeply/nested/directory/path/with/a/long/filename_that_crosses_col_79_xyz.tex\n"
  end

  def test_embedded_url_clean_osc8_by_default
    builder = LatexBuilder.new('main.tex', link: true, color: true)
    url = 'https://example.com/guide'
    formatted = builder.send(:format_terminal_url, url, 'underfull \hbox')
    assert_equal "\e]8;;https://example.com/guide\e\\underfull \\hbox\e]8;;\e\\", formatted
  end

  def test_embedded_link_in_diagnostic_line_preserves_surrounding_base_color
    builder = LatexBuilder.new('main.tex', link: true, color: true)
    orig_rainbow = Rainbow.enabled
    begin
      Rainbow.enabled = true
      item = {
        type: 'Underfull \hbox',
        file: 'test.tex',
        line: 12,
        line_str: '12',
        text: 'Note: underfull \hbox (badness 10000)',
        base_color: :cyan
      }
      rendered = builder.send(:render_diagnostic_item, item, width: 3)
      assert_includes rendered, "\e]8;;https://sarielhp.github.io/leeni/docs/guides/underfull_boxes/\e\\underfull \\hbox\e]8;;\e\\"
      # Verify that the suffix text after the link is also colored in cyan
      assert_includes rendered, '(badness 10000)'
      refute_includes rendered, "\e[4m"
    ensure
      Rainbow.enabled = orig_rainbow
    end
  end

  def test_duplicate_label_link_is_cyan_without_forced_underline
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'chap1.tex'), "\\section{A}\n\\label{sec:dup}\n")
      File.write(File.join(dir, 'chap2.tex'), "\\section{B}\n\\label{sec:dup}\n")

      builder = LatexBuilder.new('main.tex', link: true, color: true)
      locs = [
        { file: File.join(dir, 'chap1.tex'), line: 2 },
        { file: File.join(dir, 'chap2.tex'), line: 2 }
      ]

      alerts = builder.send(:build_duplicate_label_alerts, 'sec:dup', locs, 0)
      a1 = alerts[0]
      assert_includes a1[:text], "\e]8;;file://"
      refute_includes a1[:text], "\e[4m"
      refute_includes a1[:text], "\e[24m"
      assert_includes a1[:text], 'chap2.tex:2'
    end
  end

  def test_boxed_explanation_doc_url_styled_in_blue
    builder = LatexBuilder.new('main.tex', link: true, color: true, explain: true)
    orig_rainbow = Rainbow.enabled
    begin
      Rainbow.enabled = true
      box = builder.send(:format_boxed_explanation, :underfull_hbox)
      assert_includes box, "\e]8;;https://sarielhp.github.io/leeni/docs/guides/underfull_boxes/\e\\"
      # Check that blue color is included in the URL field
      assert_includes box, 'See:'
    ensure
      Rainbow.enabled = orig_rainbow
    end
  end

  def test_cli_numeric_flag_context_normalization
    argv = ['-3', 'paper.tex']
    LatexCLI.normalize_argv!(argv)
    assert_equal ['--context=3', 'paper.tex'], argv

    argv2 = ['-12', '-u', 'main.tex']
    LatexCLI.normalize_argv!(argv2)
    assert_equal ['--context=12', '-u', 'main.tex'], argv2
  end

  def test_render_context_snippet_basic
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.tex')
      content = (1..20).map { |i| "Line #{i}: content of line #{i}\n" }.join
      File.write(file, content)

      builder = LatexBuilder.new(file, color: false, link: false, context_lines: 3)
      lines = builder.send(:render_context_snippet, file, 10, 3)

      assert_equal 7, lines.size
      assert_match(/^\s+7 \| Line 7:/, lines[0])
      assert_match(/^>\s+10 \| Line 10:/, lines[3])
      assert_match(/^\s+13 \| Line 13:/, lines[6])
    end
  end

  def test_render_context_snippet_with_range
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.tex')
      content = (1..20).map { |i| "Line #{i}: content of line #{i}\n" }.join
      File.write(file, content)

      builder = LatexBuilder.new(file, color: false, link: false, context_lines: 2)
      lines = builder.send(:render_context_snippet, file, 8, 2, target_line_end: 10)

      assert_equal 7, lines.size
      assert_match(/^\s+6 \| Line 6:/, lines[0])
      assert_match(/^\s+7 \| Line 7:/, lines[1])
      assert_match(/^>\s+8 \| Line 8:/, lines[2])
      assert_match(/^>\s+9 \| Line 9:/, lines[3])
      assert_match(/^>\s+10 \| Line 10:/, lines[4])
      assert_match(/^\s+11 \| Line 11:/, lines[5])
      assert_match(/^\s+12 \| Line 12:/, lines[6])
    end
  end

  def test_render_context_snippet_with_hyperlinks_and_carets
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.tex')
      content = (1..10).map { |i| "Line #{i}: \\foo command here\n" }.join
      File.write(file, content)

      builder = LatexBuilder.new(file, color: true, link: true, context_lines: 2)
      lines = builder.send(:render_context_snippet, file, 5, 2, col_pos: 8, token_len: 4)

      combined = lines.join("\n")
      assert_includes combined, "\e]8;;file://"
      assert_includes combined, "test.tex#5"
      assert_includes combined, '^^^^'
    end
  end

  def test_highlight_latex_in_process
    orig = Rainbow.enabled
    begin
      Rainbow.enabled = true
      line = "\\begin{align*} \\DotProd{ \\nu_h }{ q } = 0 % note"
      colored = LatexColor.highlight_latex(line, color_enabled: true)
      assert_match(/\e\[(?:35|\d+;2;\d+;\d+;\d+)m/, colored)
      assert_includes colored, "align*"
      assert_includes colored, "\\DotProd"
      assert_includes colored, "\e[2m% note"
    ensure
      Rainbow.enabled = orig
    end
  end

  def test_context_snippet_deduplication_on_repeated_lines
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'dup.tex')
      content = (1..20).map { |i| "Line #{i}\n" }.join
      File.write(file, content)

      builder = LatexBuilder.new(file, color: false, link: false, context_lines: 2)
      first = builder.send(:render_context_snippet, file, 10, 2)
      refute_empty first
      second = builder.send(:render_context_snippet, file, 10, 2)
      assert_empty second
      forced = builder.send(:render_context_snippet, file, 10, 2, force: true)
      refute_empty forced
    end
  end

  def test_context_snippet_deduplication_on_covered_ranges
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'range.tex')
      content = (1..30).map { |i| "Line #{i}\n" }.join
      File.write(file, content)

      builder = LatexBuilder.new(file, color: false, link: false, context_lines: 2)
      range_lines = builder.send(:render_context_snippet, file, 10, 2, target_line_end: 15)
      refute_empty range_lines
      subsumed = builder.send(:render_context_snippet, file, 12, 2)
      assert_empty subsumed
      outside = builder.send(:render_context_snippet, file, 20, 2)
      refute_empty outside
    end
  end

  def test_option_1_tier_badges_under_all_mode
    builder = LatexBuilder.new('main.tex', color: false, link: false, all: true)

    alert_item = { file: 'main.tex', line_str: '50', text: "Alert: label 'foo' duplicate", tier: 'alerts' }
    rendered_alert = builder.send(:render_diagnostic_item, alert_item, width: 4)
    assert_includes rendered_alert, "50: 🚨 label 'foo' duplicate"

    warn_item = { file: 'main.tex', line_str: '13', text: 'Warning: Unused option', tier: 'warnings' }
    rendered_warn = builder.send(:render_diagnostic_item, warn_item, width: 4)
    assert_includes rendered_warn, '13: ❕ Unused option'

    what_item = { file: 'main.tex', line_str: '108', text: 'Note: underfull \hbox', tier: 'whatevers' }
    rendered_what = builder.send(:render_diagnostic_item, what_item, width: 4)
    assert_includes rendered_what, '108: ☕ underfull \hbox'
  end

  def test_category_normalization_strips_redundant_prefixes_with_badges
    builder = LatexBuilder.new('main.tex', color: false, link: false, all: true)

    what_font = { file: 'main.tex', line_str: '116', text: "Warning: [font] Font shape 'foo' not available", tier: 'whatevers' }
    rendered = builder.send(:render_diagnostic_item, what_font, width: 4)
    assert_includes rendered, "116: ☕ [font] Font shape 'foo' not available"
    refute_includes rendered, 'Warning: [font]'

    bib_warn = { file: 'main.tex', line_str: 'bib', text: 'Warning--empty author in foo', tier: 'warnings' }
    rendered_bib = builder.send(:render_diagnostic_item, bib_warn, width: 4)
    assert_includes rendered_bib, 'bib: ❕ empty author in foo'
    refute_includes rendered_bib, 'Warning--'
  end

  def test_diagnostic_message_terminal_wrapping_hanging_indent
    builder = LatexBuilder.new('main.tex', color: false, link: false, all: true)
    ENV['COLUMNS'] = '70'
    begin
      long_msg = 'You have requested version `2099/01/01` of package amsmath, but only version `2026/05/19 v2.18d AMS math features` is available.'
      item = { file: 'main.tex', line_str: '13', text: long_msg, tier: 'warnings' }
      rendered = builder.send(:render_diagnostic_item, item, width: 3)
      lines = rendered.lines.map(&:chomp)
      assert lines.size > 1
      assert_match(/\A\s*13: ❕\s+/, lines[0])
      prefix_str = lines[0][0...lines[0].index('You')]
      vis_prefix = LaTeXUtils.visible_width(prefix_str)
      assert_equal 8, vis_prefix
      lines[1..].each do |continuation|
        assert continuation.start_with?(' ' * vis_prefix)
        assert LaTeXUtils.visible_width(continuation) <= 70
      end
    ensure
      ENV.delete('COLUMNS')
    end
  end

  def test_summary_line_emojis_under_badges_mode
    builder = LatexBuilder.new('main.tex', color: false, link: false, all: true)
    io = StringIO.new
    builder.send(:print_nonzero_summary, io, 0, 7, 21, 14, false, false, false)
    plain = io.string
    assert_includes plain, '🛑 Errors: 0, 🚨 Alerts: 7, ❕ Warnings: 21, ☕ Whatevers: 14'
  end

  def test_tier_badges_active_in_default_mode_and_disableable
    builder = LatexBuilder.new('main.tex', color: false, link: false)
    warn_item = { file: 'main.tex', line_str: '13', text: 'Warning: Unused option', tier: 'warnings' }
    rendered_default = builder.send(:render_diagnostic_item, warn_item, width: 4)
    assert_includes rendered_default, '13: ❕ Unused option'

    builder_no_badges = LatexBuilder.new('main.tex', color: false, link: false, badges: false)
    rendered_disabled = builder_no_badges.send(:render_diagnostic_item, warn_item, width: 4)
    assert_includes rendered_disabled, '13: Warning: Unused option'
    refute_includes rendered_disabled, '❕'
  end

  def test_error_header_badge_formatting
    builder = LatexBuilder.new('main.tex', color: false, link: false)
    header = builder.send(:format_error_header, '! Undefined control sequence.', 'main.tex', 10, 10, 1, 0)
    assert_includes header, 'main.tex:10:1: 🛑 Undefined control sequence.'

    builder_nb = LatexBuilder.new('main.tex', color: false, link: false, badges: false)
    header_nb = builder_nb.send(:format_error_header, '! Undefined control sequence.', 'main.tex', 10, 10, 1, 0)
    assert_includes header_nb, 'main.tex:10:1: Undefined control sequence.'
    refute_includes header_nb, '🛑'
  end
end
