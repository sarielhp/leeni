#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'

require_relative '../lib/leeni/utils'
require_relative '../lib/leeni/brace_checker'

# The brace checker runs on every failed build and its findings are stamped
# index: -1000, which sorts them ahead of every real TeX error. A false positive
# here is therefore the first thing a user reads when something goes wrong, so
# these tests are mostly about valid LaTeX it must stay silent on.
class TestBraceChecker < Minitest::Test
  def check(source)
    Dir.mktmpdir('leeni_brace_test') do |dir|
      path = File.join(dir, 'doc.tex')
      File.write(path, source)
      LaTeXBraceChecker.check_file(path)
    end
  end

  def assert_silent(source, label)
    errors = check(source)
    assert_empty errors.map { |e| e[:text] }, "false positive on #{label}"
  end

  def test_macro_definitions_containing_environments_are_not_flagged
    {
      'newenvironment' => "\\newenvironment{note}{\\begin{quote}\\itshape}{\\end{quote}}\n",
      'renewenvironment' => "\\renewenvironment{abstract}{\\begin{center}}{\\end{center}}\n",
      'newcommand wrapping begin' => "\\newcommand{\\startbox}{\\begin{center}}\n",
      'def wrapping end' => "\\def\\stopbox{\\end{center}}\n",
      'providecommand' => "\\providecommand{\\x}{\\begin{itemize}}\n",
      'DeclareRobustCommand' => "\\DeclareRobustCommand{\\y}{\\begin{tabular}{ll}}\n"
    }.each { |label, src| assert_silent(src, label) }
  end

  def test_full_preamble_with_newenvironment_is_clean
    source = <<~TEX
      \\documentclass{article}
      \\newenvironment{note}{\\begin{quote}\\itshape}{\\end{quote}}
      \\begin{document}
      \\begin{note}Hello\\end{note}
      \\end{document}
    TEX

    assert_silent(source, 'a document whose preamble defines an environment')
  end

  def test_genuine_unclosed_brace_is_still_reported
    source = <<~TEX
      \\documentclass{article}
      \\begin{document}
      \\begin{theorem}
      \\frac{Y_{i-1}{2}.
      \\end{theorem}
      \\end{document}
    TEX

    errors = check(source)
    refute_empty errors, 'the checker stopped reporting a real unclosed brace'
    assert_match(/Unclosed open brace/, errors.first[:text])
  end

  def test_genuine_extra_closing_brace_is_still_reported
    errors = check("\\documentclass{article}\n\\begin{document}\nx}y\n\\end{document}\n")
    refute_empty errors, 'the checker stopped reporting a real extra closing brace'
    assert_match(/Extra closing brace/, errors.first[:text])
  end

  def test_inline_verbatim_with_any_delimiter_is_not_flagged
    {
      'equals delimiter' => "\\verb=x{y=\n",
      'colon delimiter' => "\\verb:a{b:\n",
      'dash delimiter' => "\\verb-a{b-\n",
      'starred verb' => "\\verb*|a{b|\n",
      'starred verb, equals' => "\\verb*=a{b=\n",
      'lstinline' => "\\lstinline!x{y!\n",
      'lstinline with options' => "\\lstinline[language=C]!x{y!\n",
      'mintinline' => "\\mintinline{c}|x| and \\verb+z{+\n",
      'pipe delimiter (previously ok)' => "\\verb|x{y|\n",
      'plus delimiter (previously ok)' => "\\verb+x{y+\n"
    }.each { |label, src| assert_silent(src, label) }
  end

  def test_percent_inside_url_like_macros_is_not_a_comment
    {
      'url with percent escape' => "\\url{http://x.org/a%7Eb}\n",
      'path with percent' => "\\path{/tmp/a%20b}\n",
      'nolinkurl' => "\\nolinkurl{http://x.org/%7Ejoe}\n",
      'href first argument' => "\\href{http://x.org/a%7Eb}{the link}\n"
    }.each { |label, src| assert_silent(src, label) }
  end

  def test_real_comment_still_ends_the_line
    assert_silent("x % an unbalanced { in a comment\n", 'a brace inside a real comment')
  end

  def test_verbatim_environments_with_braces_are_ignored
    %w[verbatim lstlisting minted filecontents].each do |env|
      src = <<~TEX
        \\documentclass{article}
        \\begin{document}
        \\begin{#{env}}
        def unclosed_brace {
          x = y[0];
        \\end{#{env}}
        \\end{document}
      TEX
      assert_silent(src, "verbatim environment #{env} with unbalanced brace")
    end
  end

  def test_environment_nested_in_braces_does_not_flag_outer_braces
    source = <<~TEX
      \\documentclass{article}
      \\begin{document}
      \\centerline{%
        \\begin{minipage}{0.9\\linewidth}
          Some text inside minipage.
        \\end{minipage}
      }
      \\end{document}
    TEX
    assert_silent(source, 'an environment enclosed inside braces')
  end

  def test_macro_wrapped_begin_and_end_environments_are_not_flagged
    source = <<~TEX
      \\documentclass{article}
      \\newcommand{\\NotCCCMode}[1]{#1}%
      \\begin{document}
      \\NotCCCMode{%
        \\begin{table}[p]%
      }%
      Table content
      \\NotCCCMode{%
        \\end{table}
      }
      \\end{document}
    TEX
    assert_silent(source, 'macros wrapping begin and end environment tokens')
  end

  def test_brace_checker_error_format_is_auctex_compatible
    source = <<~TEX
      \\documentclass{article}
      \\begin{document}
      \\begin{theorem}
      \\frac{Y_{i-1}{2}.
      \\end{theorem}
      \\end{document}
    TEX
    errors = check(source)
    refute_empty errors
    text = errors.first[:text]

    # AUCTeX matches: ^! (.*) followed by ^l.<line> <snippet>
    assert_match(/\A! \[leeni\] /, text, 'must start with ! [leeni] for AUCTeX error matching and attribution')
    assert_match(/^l\.\d+ /, text, 'must include standard TeX l.<line> line for AUCTeX navigation')
  end
end
