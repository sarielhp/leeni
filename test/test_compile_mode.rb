#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/latex_it/utils'

class TestCompileMode < Minitest::Test
  def setup
    @bin_path = File.expand_path('../latex_it', __dir__)
  end

  def test_clean_build_in_compile_mode_is_silent
    Dir.mktmpdir('compile_clean') do |dir|
      tex = File.join(dir, 'clean.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Clean document text.
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--compile', 'clean.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"
      assert_includes out, 'Compilation succeeded.'

      out_cc, status_cc = Open3.capture2e(@bin_path, '-cc', 'clean.tex', chdir: dir)
      assert_equal 0, status_cc.exitstatus
      assert_includes out_cc, 'Compilation succeeded.'

      out_llm, status_llm = Open3.capture2e(@bin_path, '-cc', '-llm', 'clean.tex', chdir: dir)
      assert_equal 0, status_llm.exitstatus
      assert_empty out_llm.strip, "Expected silent success when -llm is used with -cc, got: #{out_llm}"
    end
  end

  def test_error_formatting_and_gnu_compliance
    Dir.mktmpdir('compile_err') do |dir|
      tex = File.join(dir, 'bad.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\foobarunknown
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--compile', '--no-color', 'bad.tex', chdir: dir)
      assert_equal 1, status.exitstatus, "Expected exit 1 on error. Output: #{out}"

      lines = out.lines.map(&:strip).reject(&:empty?)
      refute_empty lines, 'Expected at least one error line'

      # Assert standard GNU format: file:line:col: error: msg
      error_line = lines.find { |l| l.include?('error:') }
      refute_nil error_line, "Expected an error line in output: #{out}"
      assert_match(/\Abad\.tex:\d+(?::\d+)?: error: undefined control sequence/, error_line)
      refute_match(/\.\z/, error_line, 'GNU standard specifies message must not end with a period')

      # Assert no TUI artifacts
      refute_includes out, '── bad.tex'
      refute_includes out, 'Errors:'
      refute_includes out, 'Latex compilation failed'
    end
  end

  def test_alert_and_warning_formatting
    Dir.mktmpdir('compile_warn') do |dir|
      tex = File.join(dir, 'warn.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\hbox to 20pt{\\rule{100pt}{10pt}}
        Missing ref: \\ref{nonexistent_ref}.
        \\end{document}
      TEX

      out, status = Open3.capture2e(
        @bin_path, '--compile', '--no-color', '--link', '-u', 'warn.tex', chdir: dir
      )
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"

      lines = LaTeXUtils.strip_ansi(out).lines.map(&:strip).reject(&:empty?)
      alert_line = lines.find { |l| l.include?('warning: [alert]') }
      refute_nil alert_line, "Expected alert warning in output: #{out}"
      assert_match(/\Awarn\.tex:3: warning: \[alert\] 80\.00pt too wide/, alert_line)
      refute_match(/\.\z/, alert_line)

      warn_line = lines.find { |l| l.include?("undefined reference 'nonexistent_ref'") }
      refute_nil warn_line, "Expected regular warning in output: #{out}"
      assert_match(/\Awarn\.tex:4: warning: undefined reference 'nonexistent_ref'/, warn_line)
      refute_match(/\.\z/, warn_line)
      assert_match(%r{\e\]8;;file://[^\e]*warn\.tex#3\e\\}, out)
      assert_match(%r{\e\]8;;file://[^\e]*warn\.tex#4\e\\}, out)
    end
  end

  def test_whatevers_hidden_by_default_and_shown_with_all
    Dir.mktmpdir('compile_what') do |dir|
      tex = File.join(dir, 'what.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\hbox to 20pt{\\rule{21.5pt}{10pt}}
        \\end{document}
      TEX

      # Default: whatevers are suppressed
      out_default, = Open3.capture2e(@bin_path, '--compile', '--no-color', '-u', 'what.tex', chdir: dir)
      refute_includes out_default, 'note: 1.50pt too wide'

      # With -a (--all): whatevers are shown as note:
      out_all, = Open3.capture2e(@bin_path, '--compile', '--no-color', '-u', '-a', 'what.tex', chdir: dir)
      assert_includes out_all, 'what.tex:3: note: 1.50pt too wide'
    end
  end

  def test_mutual_exclusion_with_emacs_flag
    out, status = Open3.capture2e(@bin_path, '--compile', '--emacs', 'some_file.tex')
    assert_equal 2, status.exitstatus
    assert_includes out, 'cannot be used together'
  end

  def test_color_controls
    Dir.mktmpdir('compile_color') do |dir|
      tex = File.join(dir, 'doc.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\undefcmd
        \\end{document}
      TEX

      # --no-color suppresses all escapes
      out_nocolor, = Open3.capture2e(@bin_path, '--compile', '--no-color', 'doc.tex', chdir: dir)
      refute_includes out_nocolor, "\e["

      # --color forces ANSI escapes
      out_color, = Open3.capture2e(@bin_path, '--compile', '--color', 'doc.tex', chdir: dir)
      assert_includes out_color, "\e["
    end
  end

  def test_cc_short_form_and_redundant_aliases
    Dir.mktmpdir('compile_shorthand') do |dir|
      tex = File.join(dir, 'doc.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\undefcmd
        \\end{document}
      TEX

      # Canonical short form: -cc
      out_short, status_short = Open3.capture2e(@bin_path, '-cc', '--no-color', 'doc.tex', chdir: dir)
      assert_equal 1, status_short.exitstatus
      assert_match(/^doc\.tex:3:1: error: undefined control sequence/, out_short)

      # Canonical long form: --compile
      out_long, status_long = Open3.capture2e(@bin_path, '--compile', '--no-color', 'doc.tex', chdir: dir)
      assert_equal 1, status_long.exitstatus
      assert_match(/^doc\.tex:3:1: error: undefined control sequence/, out_long)

      # Redundant double-dash short alias --cc must be rejected
      _, stderr_double, status_double = Open3.capture3(@bin_path, '--cc', 'doc.tex')
      refute status_double.success?
      assert_match(/invalid option: --cc/i, stderr_double)

      # Redundant single-dash long alias -compile must be rejected
      _, stderr_compile, status_compile = Open3.capture3(@bin_path, '-compile', 'doc.tex')
      refute status_compile.success?
      assert_match(/invalid option/i, stderr_compile)
    end
  end

  def test_multiply_defined_label_pinpointing_in_compile_mode
    Dir.mktmpdir('compile_dup_labels') do |dir|
      File.write(File.join(dir, 'chap1.tex'), <<~TEX)
        \\section{Chapter One}
        \\label{sec:duplicate}
        Content of chapter one.
      TEX

      File.write(File.join(dir, 'chap2.tex'), <<~TEX)
        \\section{Chapter Two}
        \\label{sec:duplicate}
        Content of chapter two.
      TEX

      File.write(File.join(dir, 'main.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\input{chap1}
        \\input{chap2}
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--compile', '--no-color', 'main.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"

      lines = out.lines.map(&:strip)
      loc1 = lines.find { |l| l.include?('chap1.tex:2:') && l.include?("label 'sec:duplicate' duplicate (also at chap2.tex:2)") }
      loc2 = lines.find { |l| l.include?('chap2.tex:2:') && l.include?("label 'sec:duplicate' duplicate (also at chap1.tex:2)") }

      refute_nil loc1, "Expected location 1 in chap1.tex:2. Output:\n#{out}"
      refute_nil loc2, "Expected location 2 in chap2.tex:2. Output:\n#{out}"
      refute_match(/\.aux:1:/, out, 'Must not attribute multiply defined label to the .aux file')
    end
  end

  def test_multiply_defined_label_with_macro_in_compile_mode
    Dir.mktmpdir('compile_macro_dup') do |dir|
      File.write(File.join(dir, 'chap1.tex'), <<~TEX)
        \\section{Chapter One}
        \\mylabel{sec:custom}
        Content of chapter one.
      TEX

      File.write(File.join(dir, 'chap2.tex'), <<~TEX)
        \\section{Chapter Two}
        \\mylabel{sec:custom}
        Content of chapter two.
      TEX

      File.write(File.join(dir, 'main.tex'), <<~TEX)
        \\documentclass{article}
        \\newcommand{\\mylabel}[1]{\\label{#1}}
        \\begin{document}
        \\input{chap1}
        \\input{chap2}
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--compile', '--no-color', 'main.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"

      lines = out.lines.map(&:strip)
      loc1 = lines.find { |l| l.include?('chap1.tex:2:') && l.include?("label 'sec:custom' duplicate (also at chap2.tex:2)") }
      loc2 = lines.find { |l| l.include?('chap2.tex:2:') && l.include?("label 'sec:custom' duplicate (also at chap1.tex:2)") }

      refute_nil loc1, "Expected location 1 in chap1.tex:2. Output:\n#{out}"
      refute_nil loc2, "Expected location 2 in chap2.tex:2. Output:\n#{out}"
      refute_match(/\.aux:1:/, out, 'Must not attribute multiply defined label to the .aux file')
    end
  end

  def test_compile_mode_with_link_flag
    Dir.mktmpdir('compile_links') do |dir|
      File.write(File.join(dir, 'doc.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\undefcommand
        \\end{document}
      TEX

      # Explicit --link enables OSC 8 escape sequences even in non-tty subprocess
      out, status = Open3.capture2e(@bin_path, '--compile', '--link', 'doc.tex', chdir: dir)
      assert_equal 1, status.exitstatus
      assert_includes out, "\e]8;;file://"
      assert_includes out, "doc.tex:3:1:\e]8;;\e\\"

      # Explicit --no-link guarantees zero OSC 8 sequences
      out_nolink, status_nolink = Open3.capture2e(@bin_path, '--compile', '--no-link', 'doc.tex', chdir: dir)
      assert_equal 1, status_nolink.exitstatus
      refute_includes out_nolink, "\e]8;;"
      assert_match(/^doc\.tex:3:1: error: undefined control sequence/, out_nolink)
    end
  end

  def test_compile_mode_auto_detects_kitty_in_tty
    Dir.mktmpdir('compile_pty') do |dir|
      File.write(File.join(dir, 'doc.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\undefcommand
        \\end{document}
      TEX

      env = {
        'KITTY_WINDOW_ID' => '1', 'TERM' => 'xterm-kitty',
        'LATEX_IT_THEME' => 'blush', 'NO_COLOR' => nil
      }
      cmd = "cd #{dir} && #{@bin_path} --compile doc.tex"
      output = String.new
      require 'pty'
      PTY.spawn(env, 'bash', '-c', cmd) do |r, _w, _pid|
        begin
          r.each_line { |line| output << line }
        rescue Errno::EIO
          # Linux PTY raises Errno::EIO on EOF
        end
      end
      assert_includes output, "\e]8;;file://"
      assert_includes output, "doc.tex:3:1:"
      assert_includes output, "\e]8;;\e\\"
    end
  end

  def test_compile_mode_on_latex_file_via_ll_symlink
    Dir.mktmpdir('compile_ll_symlink') do |dir|
      ll_bin = File.join(dir, 'll')
      FileUtils.ln_s(@bin_path, ll_bin)

      File.write(File.join(dir, 'sample.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Hello world from ll compile mode.
        \\end{document}
      TEX

      # Explicit file target via ll --compile
      out, status = Open3.capture2e(ll_bin, '--compile', 'sample.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"
      assert File.file?(File.join(dir, 'sample.pdf')), 'Expected sample.pdf to be generated'

      # Implicit target via ll --compile (auto-detect main file in directory)
      FileUtils.rm_f(File.join(dir, 'sample.pdf'))
      FileUtils.rm_rf(File.join(dir, 'junk'))
      out_auto, status_auto = Open3.capture2e(ll_bin, '--compile', chdir: dir)
      assert_equal 0, status_auto.exitstatus, "Expected exit 0 with auto-detected file. Output: #{out_auto}"
      assert File.file?(File.join(dir, 'sample.pdf')), 'Expected sample.pdf to be generated on auto-detect'
    end
  end

  def test_compile_mode_in_directory_with_no_tex_files
    Dir.mktmpdir('compile_no_tex') do |dir|
      out, status = Open3.capture2e(@bin_path, '--compile', chdir: dir)
      assert_equal 1, status.exitstatus
      refute_includes out, 'from /'
      refute_includes out, 'Traceback'
      assert_includes out, 'No LaTeX (.tex) files found'
    end
  end

  def test_compile_mode_reports_errors_from_four_levels_of_nested_inputs
    Dir.mktmpdir('compile_nested_inputs') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'chapters'))
      File.write(File.join(dir, 'main.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\input{chapters/level1}
        \\end{document}
      TEX
      (1..3).each do |level|
        File.write(
          File.join(dir, "chapters/level#{level}.tex"),
          "Level #{level}.\n\\input{chapters/level#{level + 1}}\n"
        )
      end
      File.write(File.join(dir, 'chapters/level4.tex'), <<~TEX)
        Deepest level.
        \\typodCommand
        \\input{chapters/does-not-exist}
      TEX

      out, status = Open3.capture2e(
        @bin_path, '--compile', '--all', '--no-color', '--link', 'main.tex', chdir: dir
      )
      plain = LaTeXUtils.strip_ansi(out)

      assert_equal 1, status.exitstatus, "Expected exit 1. Output: #{out}"
      assert_match(
        %r{^chapters/level4\.tex:2:1: error: undefined control sequence \\typodCommand .*check spelling}i,
        plain
      )
      assert_match(
        %r{^chapters/level4\.tex:3(?::\d+)?: error: .*chapters/does-not-exist\.tex.*not found .*check file path or spelling}i,
        plain
      )
      assert_match(%r{\e\]8;;file://[^\e]*chapters/level4\.tex#2:1\e\\}, out)
      assert_match(%r{\e\]8;;file://[^\e]*chapters/level4\.tex#3\e\\}, out)
      refute_match(%r{^(?:main|chapters/level[1-3])\.tex:.*error:}i, plain)
      refute_match(/error: emergency stop/i, plain)
    end
  end

  def test_error_after_nested_input_returns_to_parent_file
    Dir.mktmpdir('compile_return_to_parent') do |dir|
      File.write(File.join(dir, 'main.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\input{parent}
        \\end{document}
      TEX
      File.write(File.join(dir, 'parent.tex'), "\\input{grandchild}\n\\parentTypodCommand\n")
      File.write(File.join(dir, 'grandchild.tex'), "Valid grandchild text.\n")

      out, status = Open3.capture2e(
        @bin_path, '--compile', '--all', '--no-color', 'main.tex', chdir: dir
      )

      assert_equal 1, status.exitstatus, "Expected exit 1. Output: #{out}"
      assert_match(/^parent\.tex:2:1: error: undefined control sequence \\parentTypodCommand/, out)
      refute_match(/^(?:main|grandchild)\.tex:.*error:/, out)
    end
  end

  def test_errors_in_sibling_inputs_keep_their_own_locations
    Dir.mktmpdir('compile_sibling_inputs') do |dir|
      File.write(File.join(dir, 'main.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\input{first}
        \\input{second}
        \\end{document}
      TEX
      File.write(File.join(dir, 'first.tex'), "First sibling.\n\\firstTypodCommand\n")
      File.write(File.join(dir, 'second.tex'), "Second sibling.\n\\secondTypodCommand\n")

      out, status = Open3.capture2e(
        @bin_path, '--compile', '--all', '--no-color', 'main.tex', chdir: dir
      )

      assert_equal 1, status.exitstatus, "Expected exit 1. Output: #{out}"
      assert_match(/^first\.tex:2:1: error: undefined control sequence \\firstTypodCommand/, out)
      assert_match(/^second\.tex:2:1: error: undefined control sequence \\secondTypodCommand/, out)
      refute_match(/^main\.tex:.*error:/, out)
    end
  end

  def test_nested_error_with_long_unicode_spaced_parenthesized_path
    Dir.mktmpdir('compile_hostile_path') do |dir|
      nested_dir = 'chapters with spaces'
      nested_file = "café(odd)'#{'long' * 14}.tex"
      relative_path = File.join(nested_dir, nested_file)
      FileUtils.mkdir_p(File.join(dir, nested_dir))
      File.write(File.join(dir, relative_path), "Hostile path.\n\\hostilePathTypodCommand\n")
      File.write(File.join(dir, 'main.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\input{"#{relative_path}"}
        \\end{document}
      TEX

      out, status = Open3.capture2e(
        @bin_path, '--compile', '--all', '--no-color', 'main.tex', chdir: dir
      )

      assert_equal 1, status.exitstatus, "Expected exit 1. Output: #{out}"
      assert_includes out, "#{relative_path}:2:1: error: undefined control sequence \\hostilePathTypodCommand"
      refute_match(/^main\.tex:.*error:/, out)
    end
  end

  def test_runaway_argument_at_nested_file_boundary_reports_child
    Dir.mktmpdir('compile_runaway_child') do |dir|
      File.write(File.join(dir, 'main.tex'), <<~TEX)
        \\documentclass{article}
        \\newcommand{\\takesone}[1]{#1}
        \\begin{document}
        \\input{child}
        \\end{document}
      TEX
      File.write(File.join(dir, 'child.tex'), "\\takesone{unterminated argument\n")

      out, status = Open3.capture2e(
        @bin_path, '--compile', '--all', '--no-color', 'main.tex', chdir: dir
      )

      assert_equal 1, status.exitstatus, "Expected exit 1. Output: #{out}"
      assert_match(
        /^child\.tex:1:10: error: unclosed open brace .*reached end of file/i, out
      )
      refute_match(/^main\.tex:.*error:/, out)
      refute_match(/error: (?:runaway argument|file ended while scanning)/i, out)
    end
  end

  def test_compile_mode_suppresses_warnings_when_errors_present
    Dir.mktmpdir('compile_err_and_warn') do |dir|
      File.write(File.join(dir, 'bad.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\hbox to 20pt{\\rule{100pt}{10pt}}
        Missing ref: \\ref{nonexistent_ref}.
        \\fatalundefinedcmd
        \\end{document}
      TEX

      # Default --compile: errors are emitted, but alerts and warnings are suppressed
      out, status = Open3.capture2e(@bin_path, '--compile', '--no-color', 'bad.tex', chdir: dir)
      assert_equal 1, status.exitstatus
      assert_includes out, 'error: undefined control sequence'
      refute_includes out, 'warning:'
      refute_includes out, 'overfull'
      refute_includes out, 'nonexistent_ref'

      # With -a / --all: warnings and alerts are shown alongside errors
      out_all, status_all = Open3.capture2e(@bin_path, '--compile', '-a', '--no-color', 'bad.tex', chdir: dir)
      assert_equal 1, status_all.exitstatus
      assert_includes out_all, 'error: undefined control sequence'
      assert_includes out_all, 'warning: [alert] 80.00pt too wide'
      assert_includes out_all, "warning: undefined reference 'nonexistent_ref'"
    end
  end

  def test_compile_mode_throttles_errors_to_ten_by_default
    Dir.mktmpdir('compile_throttle') do |dir|
      bad_tex = File.join(dir, 'many_errors.tex')
      error_cmds = (1..15).map { |i| "\\errCommand#{i}" }.join("\n")
      File.write(bad_tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        #{error_cmds}
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--compile', '--no-color', 'many_errors.tex', chdir: dir)
      assert_equal 1, status.exitstatus
      error_lines = out.lines.select { |l| l.include?('error: undefined control sequence') }
      assert_equal 10, error_lines.size, "Expected exactly 10 errors displayed, got #{error_lines.size}: #{out}"
      assert_includes out, 'note: 5 more errors in many_errors.tex were truncated'
      assert_includes out, "(run with 'l -a' to display all)"

      # With -a, all 15 errors should be displayed
      out_all, status_all = Open3.capture2e(@bin_path, '--compile', '-a', '--no-color', 'many_errors.tex', chdir: dir)
      assert_equal 1, status_all.exitstatus
      error_lines_all = out_all.lines.select { |l| l.include?('error: undefined control sequence') }
      assert_equal 15, error_lines_all.size, "Expected 15 errors with -a, got #{error_lines_all.size}: #{out_all}"
      refute_includes out_all, 'were truncated'
    end
  end

  def test_vscode_lw_success_with_warnings
    Dir.mktmpdir('vscode_lw_warn') do |dir|
      tex = File.join(dir, 'warn_doc.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\hbox to 20pt{\\rule{100pt}{10pt}}
        Missing ref: \\ref{bogi:shogi}.
        \\end{document}
      TEX

      out, err, status = Open3.capture3(@bin_path, '--vscode-lw', '-u', 'warn_doc.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0 on warning build. stderr: #{err}, stdout: #{out}"
      assert_empty err.strip, "Expected stderr to be empty in --vscode-lw mode, got: #{err}"
      assert_includes out, 'Output written on '
      assert_includes out, "LaTeX Warning: undefined reference 'bogi:shogi'"
      assert_includes out, '❓ Why: A \\ref{...} or \\pageref{...} references a label that does not exist in any .aux.'
      assert_includes out, '🔧 Fix: Check spelling of the key, ensure target chapter is included, and recompile.'
      assert_includes out, 'LaTeX Warning: 80.00pt too wide on input line 3.'
      assert_includes out, '❓ Why: Content spills significantly (≥24pt / ~8.4mm) into the page margin.'
      assert_includes out, '🔧 Might fix: Reword text, insert discretionary hyphens \\-, break equations, or resize figures.'
      refute_includes out, 'Compilation succeeded.'
    end
  end

  def test_vscode_lw_error_output
    Dir.mktmpdir('vscode_lw_err') do |dir|
      tex = File.join(dir, 'err_doc.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\unknownCommandHere
        \\end{document}
      TEX

      out, err, status = Open3.capture3(@bin_path, '--vscode-lw', 'err_doc.tex', chdir: dir)
      assert_equal 1, status.exitstatus, "Expected exit 1 on error build. stderr: #{err}, stdout: #{out}"
      assert_empty err.strip, "Expected stderr to be empty in --vscode-lw mode, got: #{err}"
      assert_includes out, 'Fatal error occurred, no output PDF file produced!'
      assert_match(%r{\./err_doc\.tex:3: undefined control sequence}, out)
      assert_includes out, '❓ Why: LaTeX does not recognize this macro or command name.'
      assert_includes out, '🔧 Fix: Check for typos or include the package defining this macro in preamble.'
    end
  end

  def test_vscode_lw_clean_build
    Dir.mktmpdir('vscode_lw_clean') do |dir|
      tex = File.join(dir, 'clean_doc.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Hello World.
        \\end{document}
      TEX

      out, err, status = Open3.capture3(@bin_path, '--vscode-lw', 'clean_doc.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. stderr: #{err}, stdout: #{out}"
      assert_empty err.strip
      assert_includes out, 'Output written on '
      refute_includes out, 'Compilation succeeded.'
      refute_includes out, 'LaTeX Warning:'
    end
  end

  def test_vscode_lw_subfile_warning
    Dir.mktmpdir('vscode_lw_sub') do |dir|
      sub = File.join(dir, 'sub.tex')
      File.write(sub, <<~TEX)
        Missing sub ref: \\ref{sub:ref}.
      TEX

      main = File.join(dir, 'main.tex')
      File.write(main, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\input{sub}
        \\end{document}
      TEX

      out, err, status = Open3.capture3(@bin_path, '--vscode-lw', '-u', 'main.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. stderr: #{err}, stdout: #{out}"
      assert_empty err.strip
      assert_includes out, 'Output written on '
      assert_match(%r{\(\./sub\.tex\nLaTeX Warning: undefined reference 'sub:ref'}, out)
      assert_includes out, '❓ Why: A \\ref{...} or \\pageref{...} references a label that does not exist in any .aux.'
    end
  end
end
