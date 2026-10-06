#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'

class TestCodeMetrics < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_ast_code_metrics_zero_violations
    audit_bin = File.join(ROOT, 'tools', 'gate_audit_code')
    leeni_bin = File.join(ROOT, 'leeni')
    lib_files = Dir.glob(File.join(ROOT, 'lib', '**', '*.rb'))
    tool_files = Dir.glob(File.join(ROOT, 'tools', '*')).select do |p|
      File.file?(p) && (File.extname(p) == '.rb' || File.open(p, &:gets).to_s.start_with?('#!/usr/bin/env ruby'))
    end
    test_files = Dir.glob(File.join(ROOT, 'test', '**', '*.rb'))
    targets = [leeni_bin] + lib_files + tool_files + test_files
    cmd = ['ruby', audit_bin] + targets
    output, status = Open3.capture2e(*cmd)

    assert status.success?, "Code metrics violations found:\n#{output}"
    if output.include?('Ruby audit standard not installed')
      skip 'Ruby audit standard not installed'
    else
      assert_includes output, 'Code metrics check passed'
    end
  end

  def test_standalone_bundle_syntax
    bundle_bin = File.join(ROOT, 'tools', 'bundle')
    output, status = Open3.capture2e('ruby', bundle_bin, '--check')

    assert status.success?, "Standalone bundle verification failed:\n#{output}"
    assert_includes output, 'Bundle verified: Syntax OK'
  end

  def test_standalone_bundle_compile_diagnostics_execution
    bundle_bin = File.join(ROOT, 'tools', 'bundle')
    bundle_code, status = Open3.capture2('ruby', bundle_bin)
    assert status.success?, 'Failed to generate standalone bundle'

    Dir.mktmpdir('bundle_exec_test') do |dir|
      bundle_script = File.join(dir, 'leeni')
      File.write(bundle_script, bundle_code)
      FileUtils.chmod(0755, bundle_script)

      tex_file = File.join(dir, 'sample.tex')
      File.write(tex_file, "\\documentclass{article}\n\\begin{document}\n\\badcmd\n\\end{document}\n")

      out, run_status = Open3.capture2e(bundle_script, '-cc', '--link', 'sample.tex', chdir: dir)
      assert_equal 1, run_status.exitstatus
      refute_includes out, 'uninitialized constant'
      refute_includes out, 'NameError'
      assert_includes out, "\e]8;;file://"
    end
  end
end
