#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestLLMMode < Minitest::Test
  def setup
    @bin_path = File.expand_path('../leeni', __dir__)
  end

  def test_clean_build_in_llm_mode_is_100_percent_silent
    Dir.mktmpdir('llm_clean') do |dir|
      tex = File.join(dir, 'clean.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Clean text for LLM test.
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--llm', 'clean.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"
      assert_empty out.strip, "Expected zero output on clean build in --llm mode, got: #{out}"

      # Second run (cache up-to-date) must also be 100% silent
      out2, status2 = Open3.capture2e(@bin_path, '--llm', 'clean.tex', chdir: dir)
      assert_equal 0, status2.exitstatus, "Expected exit 0 on cached build. Output: #{out2}"
      assert_empty out2.strip, "Expected zero output on cached build in --llm mode, got: #{out2}"
    end
  end

  def test_error_formatting_plaintext_guarantee
    Dir.mktmpdir('llm_err') do |dir|
      tex = File.join(dir, 'bad.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\undefinedcommandxyz
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--llm', 'bad.tex', chdir: dir)
      assert_equal 1, status.exitstatus, "Expected exit 1 on compilation error. Output: #{out}"

      # Plaintext assertions: zero ANSI sequences, zero OSC-8 hyperlinks
      refute_match(/\e\[/, out, 'Expected zero ANSI escape codes in --llm mode')
      refute_match(/\e\]8;;/, out, 'Expected zero OSC-8 hyperlinks in --llm mode')

      # Standard GNU format: bad.tex:3: error: undefined control sequence
      error_line = out.lines.map(&:strip).find { |l| l.include?('error:') }
      refute_nil error_line, "Expected an error line in output: #{out}"
      assert_match(/\Abad\.tex:\d+(?::\d+)?: error:/, error_line)

      # No human TUI artifacts
      refute_includes out, '── bad.tex'
      refute_includes out, 'Errors:'
      refute_includes out, 'Latex compilation failed'
    end
  end

  def test_warning_category_folding_for_undefined_citations
    Dir.mktmpdir('llm_citations') do |dir|
      tex = File.join(dir, 'cites.tex')
      # 5 undefined citations
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Testing citations \\cite{refA}, \\cite{refB}, \\cite{refC}, \\cite{refD}, \\cite{refE}.
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--llm', 'cites.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0 for warnings. Output: #{out}"

      lines = out.lines.map(&:strip).reject(&:empty?)
      # Top 2 citations should be rendered
      assert_includes out, "undefined citation 'refA'"
      assert_includes out, "undefined citation 'refB'"

      # The 3rd, 4th, 5th should be folded away
      refute_includes out, "undefined citation 'refC'"
      refute_includes out, "undefined citation 'refD'"
      refute_includes out, "undefined citation 'refE'"

      # Fold note should be emitted
      fold_note = lines.find { |l| l.include?('more undefined citations') }
      refute_nil fold_note, "Expected folding note in output: #{out}"
      assert_match(/leeni: note: 3 more undefined citations in cites\.tex \(pass -a to show all\)/, fold_note)
      assert_equal 3, lines.size
    end
  end

  def test_dash_a_disables_folding_in_llm_mode
    Dir.mktmpdir('llm_all') do |dir|
      tex = File.join(dir, 'cites.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Testing citations \\cite{refA}, \\cite{refB}, \\cite{refC}.
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--llm', '-a', 'cites.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"

      # All 3 citations present with -a
      assert_includes out, "undefined citation 'refA'"
      assert_includes out, "undefined citation 'refB'"
      assert_includes out, "undefined citation 'refC'"
      refute_includes out, 'more undefined citations'
    end
  end

  OVERFULL_TEX = <<~'TEX'
    \documentclass{article}
    \begin{document}
    Text \rule{1.5\textwidth}{1pt} done.

    \[
    \rule{1.5\textwidth}{1pt}
    \]
    \end{document}
  TEX

  def run_overfull(dir, *flags)
    File.write(File.join(dir, 'box.tex'), OVERFULL_TEX)
    Open3.capture3(@bin_path, *flags, '-f', 'box.tex', chdir: dir)
  end

  HEADING_AND_MATH_TEX = <<~'TEX'
    \documentclass{article}
    \usepackage{amsthm}
    \newtheorem{theorem}{Theorem}
    \begin{document}
    \section{AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA}

    The value is $\mathrm{BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB}$ here.
    \end{document}
  TEX

  def test_heading_and_longest_math_hints
    Dir.mktmpdir('llm_heading') do |dir|
      File.write(File.join(dir, 'head.tex'), HEADING_AND_MATH_TEX)
      _out, err, = Open3.capture3(@bin_path, '-llm', '-a', '-f', 'head.tex', chdir: dir)
      assert_match(/\[box: heading \d+\]/, err, "Expected a heading box: #{err}")
      assert_match(/\(longest inline math: line 7, \d+ chars\)/, err, "Expected the math hint: #{err}")
    end
  end

  def test_llm_mode_sorts_boxes_and_tags_header_kind
    Dir.mktmpdir('llm_box') do |dir|
      _out, err, = run_overfull(dir, '-llm', '-a')
      lines = err.lines.grep(/too wide/)
      refute_empty lines, "Expected overfull diagnostics: #{err}"
      assert_equal lines.sort_by { |l| l[/box.tex:(\d+)/, 1].to_i }, lines
      assert(lines.all? { |l| l.include?('[box: ') }, "Expected [box: ...] tags: #{err}")
      assert(lines.any? { |l| l.include?('detected-line') }, "Expected a display-math box: #{err}")
    end
  end

  def test_json_mode_carries_box_fields
    Dir.mktmpdir('json_box') do |dir|
      out, = run_overfull(dir, '--json')
      boxes = JSON.parse(out)['diagnostics'].select { |d| d['box_kind'] }
      refute_empty boxes, "Expected box diagnostics in JSON: #{out}"
      assert(boxes.all? { |d| %w[paragraph alignment detected_line other].include?(d['box_kind']) })
      spans = boxes.select { |d| d['box_kind'] == 'paragraph' }
      assert(spans.all? { |d| d['line_end'].to_i >= d['line'].to_i })
    end
  end

  def test_regular_mode_output_has_no_box_tags
    Dir.mktmpdir('plain_box') do |dir|
      out, err, = run_overfull(dir, '-a')
      refute_includes out + err, '[box: '
    end
  end

  def test_aliases_hyphen_llm_and_agent
    Dir.mktmpdir('llm_alias') do |dir|
      tex = File.join(dir, 'clean.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Alias test.
        \\end{document}
      TEX

      out_dash, status_dash = Open3.capture2e(@bin_path, '-llm', 'clean.tex', chdir: dir)
      assert_equal 0, status_dash.exitstatus
      assert_empty out_dash.strip

      out_agent, status_agent = Open3.capture2e(@bin_path, '--agent', '-f', 'clean.tex', chdir: dir)
      assert_equal 0, status_agent.exitstatus
      assert_empty out_agent.strip
    end
  end
end
