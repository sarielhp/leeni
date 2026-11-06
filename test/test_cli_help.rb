# frozen_string_literal: true

require_relative 'test_env'
require_relative 'leeni_test_support'

# The condensed help has a hard size limit. It sits in the fast tier so a new
# option listed there fails while editing, not at release time.
class TestCLIHelp < LeeniTestBase
  def test_help_flag
    stdout, status = Open3.capture2(BIN, '-h')
    assert status.success?, "Expected exit code 0, got: #{status.exitstatus}"
    assert stdout.lines.count <= 25, "Expected -h to be strictly <= 25 lines, got #{stdout.lines.count}"
    assert_includes stdout, 'Usage: l [options]'
    assert_includes stdout, 'Common Options:'
    assert_includes stdout, '-e, --engine ENGINE'
    assert_includes stdout, '-u, --single-pass'
    assert_includes stdout, '-f, --force'
    assert_includes stdout, '-c, --clean'
    assert_includes stdout, '-x, --explain'
    assert_includes stdout, '-E, --examples'
    assert_includes stdout, '--help-all'
    assert_includes stdout, '-h, --help'

    # Verify options demoted to -H are not in condensed help
    refute_includes stdout, '-m, --main'
    refute_includes stdout, '--update-if-changed'
    refute_includes stdout, '-z, --zip'
    refute_includes stdout, '-t, --verify'
    refute_includes stdout, '-W, --werror'
    refute_includes stdout, '--arxiv'

    # Verify shortcuts and no-ops are not present in condensed help output
    refute_includes stdout, '--lua'
    refute_match(/(^|\s)--xe\b(?!latex-preview)/, stdout)
    refute_includes stdout, '--pdflatex'
    refute_includes stdout, '--fast'
    refute_includes stdout, '--pdf'

    # Verify redundant aliases are not present in help output
    refute_includes stdout, '--one-pass'
    refute_includes stdout, '--quick'
    refute_includes stdout, '--find-main'
    refute_includes stdout, '--file'
    refute_includes stdout, '--lualatex'
    refute_match(/--xelatex(?!-preview)/, stdout)
    refute_includes stdout, '--update-on-diff'
    refute_includes stdout, '--diff'
    refute_includes stdout, '--test'
    refute_includes stdout, '--env-free'
    refute_includes stdout, '--envfree'
  end
end
