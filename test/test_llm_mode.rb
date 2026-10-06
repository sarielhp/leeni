#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
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
