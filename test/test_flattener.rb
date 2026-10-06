#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/leeni/utils'
require_relative '../lib/leeni/flattener'

# The flattener's output is the .tex that ships inside arxiv_<base>.zip, so
# anything it gets wrong is published. Brace balance is the invariant that
# matters most: unbalanced output is not LaTeX at all.
class TestFlattener < Minitest::Test
  def assert_balanced(text, label)
    assert_equal text.count('{'), text.count('}'),
                 "#{label} produced unbalanced braces: #{text.inspect}"
  end

  def test_host_conditionals_are_removed_without_breaking_braces
    {
      'nested \\input in the true branch' =>
        '\IfFileExists{local.tex}{\input{local.tex}}{}',
      'nested \\usepackage and a false branch' =>
        '\IfFileExists{mycomputer.cfg}{\usepackage{x}}{\relax}',
      'two-argument form with a nested group' =>
        '\IfFileExists{local.tex}{\typeout{hi}}',
      'flat arguments' =>
        '\IfFileExists{local.tex}{AAA}{BBB}',
      'deeply nested branch' =>
        '\IfFileExists{private.sty}{\def\x{\y{z}}}{\relax}'
    }.each do |label, src|
      cleaned = LaTeXFlattener.clean_host_specific(src)
      assert_balanced(cleaned, label)
      refute_match(/IfFileExists/, cleaned, "#{label}: the conditional was not removed")
    end
  end

  def test_surrounding_content_survives
    src = "BEFORE\n\\IfFileExists{local.tex}{\\input{local.tex}}{}\nAFTER\n"
    cleaned = LaTeXFlattener.clean_host_specific(src)

    assert_includes cleaned, 'BEFORE'
    assert_includes cleaned, 'AFTER'
    assert_balanced(cleaned, 'surrounding content')
  end

  def test_unrelated_conditionals_are_left_untouched
    src = '\IfFileExists{figures.cfg}{\input{figures.cfg}}{\relax}'
    assert_equal src, LaTeXFlattener.clean_host_specific(src),
                 'a conditional not matching any host pattern must be preserved verbatim'
  end

  def test_custom_patterns_only_strip_their_own_matches
    src = "\\IfFileExists{secret.tex}{\\input{secret}}{}\n\\IfFileExists{computer.tex}{\\input{computer}}{}\nKeep this"
    cleaned = LaTeXFlattener.clean_host_specific(src, ['secret'])

    refute_includes cleaned, 'secret.tex'
    assert_includes cleaned, 'computer.tex'
    assert_includes cleaned, 'Keep this'
    assert_balanced(cleaned, 'custom patterns')
  end

  def test_malformed_conditional_is_left_alone
    src = '\IfFileExists{local.tex}{unterminated'
    assert_equal src, LaTeXFlattener.clean_host_specific(src),
                 'an unbalanced conditional must be preserved rather than half-deleted'
  end

  def test_verbatim_content_is_protected
    src = "\\begin{verbatim}\n\\IfFileExists{local.tex}{a}{b}\n\\end{verbatim}\n"
    assert_equal src, LaTeXFlattener.clean_host_specific(src),
                 'a conditional inside verbatim must be shown, not stripped'
  end

  def test_strip_comments_is_configurable
    Dir.mktmpdir('leeni_flatten_test') do |dir|
      main = File.join(dir, 'main.tex')
      File.write(main, "TEXT % a private note\nMORE\n")

      stripped = LaTeXFlattener.flatten(main, dir)
      refute_includes stripped, 'a private note'

      kept = LaTeXFlattener.flatten(main, dir, nil, strip_comments: false)
      assert_includes kept, 'a private note',
                      'arxiv.strip_comments: false was advertised but had no effect'
    end
  end

  def test_macros_beginning_with_verb_are_not_inline_verbatim
    Dir.mktmpdir('leeni_verb_test') do |dir|
      File.write(File.join(dir, 'a.tex'), "INCLUDED\n")
      main = File.join(dir, 'main.tex')
      File.write(main, "\\verbatiminput{v.txt}\nsome text\n\\input{a}\nmore a text\n")

      out = LaTeXFlattener.flatten(main, dir)
      assert_includes out, 'INCLUDED',
                      '\\verbatiminput was read as \\verb and swallowed the following \\input'
      refute_includes out, '\\input{a}'
    end
  end

  def test_real_inline_verbatim_is_still_protected
    Dir.mktmpdir('leeni_verb_test') do |dir|
      File.write(File.join(dir, 'a.tex'), "INCLUDED\n")
      main = File.join(dir, 'main.tex')
      File.write(main, "\\verb|\\input{a}| stays literal\n")

      out = LaTeXFlattener.flatten(main, dir)
      assert_includes out, '\\verb|\\input{a}|',
                       'a real \\verb span must not be rewritten'
      refute_includes out, 'INCLUDED'
    end
  end

  def test_inline_verbatim_does_not_span_lines
    src = "\\verb+x+\nTEXT % a comment\n\\verb+y+\n"
    out = LaTeXFlattener.strip_comments(src)
    refute_includes out, 'a comment',
                    'a \\verb span crossed a newline and protected a real comment'
  end

  def test_out_of_tree_input_is_not_inlined
    Dir.mktmpdir('leeni_containment_test') do |root|
      outside = File.join(root, 'outside.tex')
      File.write(outside, "SECRET_OUTSIDE_DATA\n")

      proj = File.join(root, 'proj')
      FileUtils.mkdir_p(proj)
      main = File.join(proj, 'main.tex')
      File.write(main, "DOCUMENT_START\n\\input{../outside.tex}\nDOCUMENT_END\n")

      out = LaTeXFlattener.flatten(main, proj)
      refute_includes out, 'SECRET_OUTSIDE_DATA', 'out-of-tree input was inlined across project boundary'
      assert_includes out, '\\input{../outside.tex}'
    end
  end

  def test_symlink_pointing_out_of_tree_is_not_inlined
    Dir.mktmpdir('leeni_symlink_test') do |root|
      outside = File.join(root, 'outside.tex')
      File.write(outside, "SECRET_SYMLINK_TARGET\n")

      proj = File.join(root, 'proj')
      FileUtils.mkdir_p(proj)
      link = File.join(proj, 'link.tex')
      File.symlink(outside, link)

      main = File.join(proj, 'main.tex')
      File.write(main, "DOCUMENT_START\n\\input{link.tex}\nDOCUMENT_END\n")

      out = LaTeXFlattener.flatten(main, proj)
      refute_includes out, 'SECRET_SYMLINK_TARGET', 'symlink pointing outside tree was inlined'
      assert_includes out, '\\input{link.tex}'
    end
  end

  def test_in_tree_nested_subfolder_input_is_inlined
    Dir.mktmpdir('leeni_nested_test') do |proj|
      FileUtils.mkdir_p(File.join(proj, 'chapters'))
      File.write(File.join(proj, 'chapters', 'ch1.tex'), "CHAPTER_ONE_DATA\n")

      main = File.join(proj, 'main.tex')
      File.write(main, "START\n\\input{chapters/ch1}\nEND\n")

      out = LaTeXFlattener.flatten(main, proj)
      assert_includes out, 'CHAPTER_ONE_DATA'
      refute_includes out, '\\input{chapters/ch1}'
    end
  end

  def test_multiple_inputs_on_single_line_are_all_inlined
    Dir.mktmpdir('leeni_multi_input_test') do |proj|
      File.write(File.join(proj, 'macros.tex'), "\\def\\foo{bar}\n")
      File.write(File.join(proj, 'content.tex'), "SECTION_BODY\n")
      File.write(File.join(proj, 'ignored.tex'), "SHOULD_BE_IGNORED\n")
      File.write(File.join(proj, 'secret.tex'), "CONFIDENTIAL_DATA\n")

      main = File.join(proj, 'main.tex')
      File.write(main, <<~TEX)
        START
        \\input{macros}\\input{content}
        \\input{macros} % \\input{ignored}
        % \\input{secret}
        END
      TEX

      out = LaTeXFlattener.flatten(main, proj)
      assert_includes out, "\\def\\foo{bar}"
      assert_includes out, 'SECTION_BODY'
      refute_includes out, '\\input{macros}'
      refute_includes out, '\\input{content}'
      refute_includes out, 'SHOULD_BE_IGNORED'
      refute_includes out, 'CONFIDENTIAL_DATA'
    end
  end

  def test_inline_comment_index_handles_urls_and_comments
    assert_equal 12, LaTeXFlattener.inline_comment_index('hello world % comment')
    assert_nil LaTeXFlattener.inline_comment_index('hello \\% escaped percent')
    assert_equal 45, LaTeXFlattener.inline_comment_index('\\url{https://arxiv.org/abs/2601.12345%20foo} % comment')
    assert_equal 27, LaTeXFlattener.inline_comment_index('\\href{http://x.org/%20foo} % outside')
    assert_nil LaTeXFlattener.inline_comment_index('no comments here')
    assert_equal 2, LaTeXFlattener.inline_comment_index('\\\\% double escaped')
  end

  def test_inline_comment_index_handles_nolinkurl_and_path
    assert_equal 51, LaTeXFlattener.inline_comment_index('\\nolinkurl{https://arxiv.org/abs/2601.12345%20foo} % comment')
    assert_equal 26, LaTeXFlattener.inline_comment_index('\\path{/tmp/foo%20bar.txt} % outside')
    assert_nil LaTeXFlattener.inline_comment_index('\\nolinkurl{http://site.com/foo%20bar}')
    assert_nil LaTeXFlattener.inline_comment_index('\\path{/a/%20b}')
  end

  def test_strip_comments_preserves_all_url_macros
    src = "\\nolinkurl{http://site.com/foo%20bar} % strip me\n\\path{/a/%20b} % strip me\n"
    res = LaTeXFlattener.strip_comments(src)
    assert_includes res, '\\nolinkurl{http://site.com/foo%20bar}'
    assert_includes res, '\\path{/a/%20b}'
    refute_includes res, 'strip me'
  end
end
