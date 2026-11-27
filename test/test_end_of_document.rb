#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'

load File.expand_path('../leeni', __dir__)

# An error TeX raises while running \end{document} (\AtEndDocument code, the
# last float flush or page) lands on that line, which is only where TeX
# noticed. The hint says so, names the end-of-document code it can find, and
# gives the bisection recipe; errors whose cause is placed there are left alone.
class TestEndOfDocument < Minitest::Test
  MAIN = <<~TEX
    \\documentclass{article}
    \\begin{document}
    Text.
    \\AtEndDocument{\\finalcheck} % registered here
    More text.
    \\end{document}
  TEX

  def errors_for(log)
    b = LatexBuilder.new('main.tex', { color: false })
    b.send(:flag_end_of_document_errors!, b.send(:extract_errors, log))
  end

  def in_project(&)
    Dir.mktmpdir('leeni_end_doc') do |dir|
      Dir.chdir(dir) do
        File.write('main.tex', MAIN)
        yield
      end
    end
  end

  def error_log(message, line)
    "(./main.tex\n./main.tex:#{line}: #{message}\n\nl.#{line} \\end{document}\n\n"
  end

  def test_unexplained_error_at_end_document_gets_the_recipe_and_the_hook_site
    in_project do
      err = errors_for(error_log('LaTeX Error: Unfinished review notes remain.', 6)).first
      hint = err[:catalog][:hint]
      assert_match(/while running \\end\{document\}/, hint)
      assert_includes hint, 'main.tex:4'
      assert_match(/move \\end\{document\} halfway up/, hint)
    end
  end

  def test_catalogued_hint_is_kept_and_extended
    in_project do
      err = errors_for(error_log("LaTeX Error: No counter 'nosuchcounter' defined.", 6)).first
      assert_match(/\ACounter 'nosuchcounter' does not exist.*; TeX raised this/, err[:catalog][:hint])
    end
  end

  def test_errors_on_other_lines_are_left_alone
    in_project do
      err = errors_for(error_log('LaTeX Error: Unfinished review notes remain.', 5)).first
      refute_match(/end\{document\}/, err[:catalog].to_h[:hint].to_s)
    end
  end

  def test_paragraph_closed_by_end_document_is_left_alone
    in_project do
      err = errors_for(error_log('Missing $ inserted.', 6)).first
      assert_equal :missing_dollar, err[:catalog_id]
      refute_match(/while running/, err[:catalog][:hint].to_s)
    end
  end
end
