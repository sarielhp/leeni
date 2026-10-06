# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require 'fileutils'

require_relative '../lib/leeni/utils'

class TestVimIntegration < Minitest::Test
  def setup
    @bin_path = File.expand_path('../leeni', __dir__)
    @compiler_vim = File.expand_path('../docs/vim/compiler/leeni.vim', __dir__)
  end

  def test_compiler_vim_file_exists
    assert File.file?(@compiler_vim), "Expected #{@compiler_vim} to exist"
    content = File.read(@compiler_vim)
    assert_includes content, 'let current_compiler = "leeni"'
    assert_includes content, 'CompilerSet makeprg=l\ --compile'
    assert_includes content, 'CompilerSet errorformat='
  end

  def test_clean_build_in_compile_mode_produces_no_diagnostic_noise
    Dir.mktmpdir('vim_clean') do |dir|
      tex = File.join(dir, 'clean.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Clean document text.
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--compile', 'clean.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"
      refute_includes out, '── clean.tex'
      refute_includes out, 'Errors: 0'
    end
  end

  def test_error_formatting_and_quickfix_parsing
    skip 'vim not installed' unless LaTeXUtils.command_available?('vim')

    Dir.mktmpdir('vim_err') do |dir|
      tex = File.join(dir, 'bad.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\undefinedcontrolsequence
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--compile', 'bad.tex', chdir: dir)
      assert_equal 1, status.exitstatus, "Expected exit 1 on compilation failure. Output: #{out}"

      # Check single-line GNU format
      assert_match(/^bad\.tex:\d+(?::\d+)?: error: undefined control sequence/i, out)
      refute_includes out, '── bad.tex'
      refute_includes out, 'Errors: 1'

      # Verify Vim parses this into quickfix list
      File.write(File.join(dir, 'out.txt'), out)
      efm = "%f:%l:%c:\\ %t%*[^:]:\\ %m,%f:%l:\\ %t%*[^:]:\\ %m,%f:%l:\\ %m,%-G%.%#"
      cmd = %(vim -N -u NONE -es -c "set efm=#{efm}" -c "cfile out.txt" -c "redir! > qf.txt | echom string(getqflist()) | redir END" -c "qall!")
      system(cmd, chdir: dir)

      qf_content = File.read(File.join(dir, 'qf.txt')) rescue ''
      assert_includes qf_content, "'valid': 1"
      assert_includes qf_content, "'type': 'e'"
      assert_includes qf_content, "'lnum': 3"
    end
  end

  def test_warning_and_alert_formatting_and_quickfix_parsing
    skip 'vim not installed' unless LaTeXUtils.command_available?('vim')

    Dir.mktmpdir('vim_warn') do |dir|
      tex = File.join(dir, 'warn.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Reference test: \\ref{nonexistent_label}.
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--compile', '-u', 'warn.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"

      assert_match(/^warn\.tex:3: warning: .*undefined/i, out)
      refute_includes out, '── warn.tex'

      File.write(File.join(dir, 'out.txt'), out)
      efm = "%f:%l:%c:\\ %t%*[^:]:\\ %m,%f:%l:\\ %t%*[^:]:\\ %m,%f:%l:\\ %m,%-G%.%#"
      cmd = %(vim -N -u NONE -es -c "set efm=#{efm}" -c "cfile out.txt" -c "redir! > qf.txt | echom string(getqflist()) | redir END" -c "qall!")
      system(cmd, chdir: dir)

      qf_content = File.read(File.join(dir, 'qf.txt')) rescue ''
      assert_includes qf_content, "'valid': 1"
      assert_includes qf_content, "'type': 'w'"
      assert_includes qf_content, "'lnum': 3"
    end
  end

  def test_vim_and_qf_flags_removed
    _out, status = Open3.capture2e(@bin_path, '--vim')
    assert_equal 2, status.exitstatus

    _out, status = Open3.capture2e(@bin_path, '--qf')
    assert_equal 2, status.exitstatus
  end
end
