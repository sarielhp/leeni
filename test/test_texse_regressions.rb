#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'open3'

require_relative '../lib/leeni/utils'

# Real pdflatex builds of faults found in TeX Stack Exchange documents whose
# diagnostics leeni got wrong.
class TestTexseRegressions < Minitest::Test
  LEENI = File.expand_path('../leeni', __dir__)

  def setup
    skip 'pdflatex required' unless LaTeXUtils.command_available?('pdflatex')
  end

  # Builds TEX fresh; returns [success, error lines of -llm].
  def build(tex)
    Dir.mktmpdir('leeni_texse_it') do |dir|
      File.write(File.join(dir, 'main.tex'), tex)
      out, status = Open3.capture2e(LEENI, '--no-lock', '-e', 'p', '--junk-dir', 'junk', '-llm', 'main.tex', chdir: dir)
      [status.success?, out.lines.grep(/: error: /)]
    end
  end

  # TeX.SE 360474: a node drawn only once the .aux holds data (there, a
  # balloon over a listing) is unknown in the first pass and found in the
  # second, as when TeX is run twice by hand.
  def test_node_that_needs_the_aux_is_resolved_by_the_next_pass
    ok, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{tikz}
      \begin{document}
      \section{A}\label{sec}
      \makeatletter\@ifundefined{r@sec}{}{\tikz \node (n) {a};}\makeatother
      \tikz \draw (n) -- (0,1);
      \end{document}
    TEX
    assert ok, errors.join
    assert_empty errors
  end

  def test_unknown_node_is_still_an_error_after_the_extra_pass
    ok, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{tikz}
      \begin{document}
      \tikz \draw (nowhere) -- (0,1);
      \end{document}
    TEX
    refute ok
    assert_match(/main\.tex:4: error: .*No shape named `nowhere'/, errors.first.to_s)
  end

  # TeX.SE 491706: one dropped character is placed where it stands alone in
  # the body, not inside \documentclass{beamer} (here \usepackage{bm}).
  def test_one_dropped_character_is_found_in_the_body
    _, errors = build(<<~'TEX')
      \documentclass{article}
      \usepackage{bm}
      \usepackage{tikz}
      \begin{document}
      \begin{tikzpicture}
      \node {a}; b
      \end{tikzpicture}
      \end{document}
    TEX
    dropped = errors.grep(/dropped from the PDF: 'b'/)
    refute_empty dropped, errors.join
    assert_match(/\Amain\.tex:6: /, dropped.first)
  end
end
