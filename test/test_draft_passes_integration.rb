#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require 'fileutils'

require_relative '../lib/leeni/utils'

# Real builds: a fresh biblatex document drafts the pass before biber and ends
# with regular passes; a document without a bibliography never drafts. Either
# way the PDF matches a build with draft passes turned off.
class TestDraftPassesIntegration < Minitest::Test
  LEENI = File.expand_path('../leeni', __dir__)
  BIB_DOC = <<~'TEX'
    \documentclass{article}
    \usepackage[backend=biber]{biblatex}
    \addbibresource{refs.bib}
    \begin{document}
    \section{Intro}\label{s}
    See \cite{knuth} and Section~\ref{s}.
    \printbibliography
    \end{document}
  TEX
  PLAIN_DOC = <<~'TEX'
    \documentclass{article}
    \begin{document}
    \section{Intro}\label{s}
    See Section~\ref{s}.
    \end{document}
  TEX

  def setup
    skip 'lualatex and biber required' unless %w[lualatex biber pdftotext pdfinfo].all? { |cmd| LaTeXUtils.command_available?(cmd) }
  end

  # Builds a fresh copy of TEX; returns [leeni output, PDF text, page count].
  def build(tex, *flags)
    Dir.mktmpdir('leeni_draft_it') do |dir|
      File.write(File.join(dir, 'paper.tex'), tex)
      File.write(File.join(dir, 'refs.bib'), "@book{knuth, author={Donald Knuth}, title={TAOCP}, year={1968}, publisher={AW}}\n")
      out, status = Open3.capture2e({ 'SOURCE_DATE_EPOCH' => '1700000000' }, LEENI, '-e', 'lualatex', '--junk-dir', 'junk',
                                    *flags, 'paper.tex', chdir: dir)
      assert status.success?, out
      pdf = File.join(dir, 'paper.pdf')
      assert File.size?(pdf), "no PDF:\n#{out}"
      text, = Open3.capture2('pdftotext', '-layout', pdf, '-')
      info, = Open3.capture2('pdfinfo', pdf)
      [out, text, info[/^Pages:\s+(\d+)/, 1]]
    end
  end

  def test_fresh_bibliography_build_drafts_the_pass_before_biber
    out, text, pages = build(BIB_DOC)
    assert_match(/lualatex \(1, draft\).*biber.*lualatex \(2\)/m, out)
    refute_match(/\(\d+, draft\)\s*\z/, out.lines.grep(/lualatex/).last.to_s.strip, 'the last pass must be regular')
    plain_out, plain_text, plain_pages = build(BIB_DOC, '--no-draft-passes')
    refute_includes plain_out, 'draft'
    assert_includes text, 'Knuth'
    assert_equal plain_text, text
    assert_equal plain_pages, pages
  end

  def test_document_without_bibliography_has_no_draft_pass
    out, text, pages = build(PLAIN_DOC)
    refute_includes out, 'draft'
    _plain_out, plain_text, plain_pages = build(PLAIN_DOC, '--no-draft-passes')
    assert_equal plain_text, text
    assert_equal plain_pages, pages
  end
end
