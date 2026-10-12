#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'json'
require 'digest'
require 'open3'
require 'rubygems/package'
require 'stringio'

class TestMetadataReportReview < Minitest::Test
  BIN = File.expand_path('../tools/check_arxiv_metadata', __dir__)

  def sample(source, title: 'Sample Title', authors: ['Ada Lovelace'], filename: 'source.tex')
    Dir.mktmpdir('metadata-review-') do |dir|
      File.binwrite(File.join(dir, filename), source)
      metadata = { id: '1510.00949v1', title: title, authors: authors,
                   source_filename: filename, source_sha256: Digest::SHA256.hexdigest(source) }
      File.write(File.join(dir, 'metadata.json'), JSON.generate(metadata))
      yield dir
    end
  end

  def document(title = 'Sample Title', authors = 'Ada Lovelace')
    "\\documentclass{article}\n\\title{#{title}}\n\\author{#{authors}}\n" \
      "\\begin{document}\\maketitle Example.\\end{document}\n"
  end

  def run_report(dir, *)
    Open3.capture2e('ruby', BIN, dir, *)
  end

  def test_source_checksum_mismatch_fails_without_report
    sample(document) do |dir|
      File.write(File.join(dir, 'source.tex'), document('Changed'))
      output, status = run_report(dir)
      refute status.success?, output
      assert_match(/checksum|sha256/i, output)
      refute File.exist?(File.join(dir, 'metadata-report.json'))
    end
  end

  def test_missing_reference_authors_is_not_a_vacuous_match
    sample(document, authors: []) do |dir|
      output, status = run_report(dir)
      refute status.success?, output
      assert_match(/author/i, output)
    end
  end

  def tar(files)
    buffer = StringIO.new(''.b)
    Gem::Package::TarWriter.new(buffer) do |writer|
      files.each do |name, bytes|
        writer.add_file_simple(name, 0o644, bytes.bytesize) { |io| io.write(bytes) }
      end
    end
    buffer.string
  end

  def test_ambiguous_main_requires_explicit_selection
    sample(tar('first.tex' => document, 'second.tex' => document), filename: 'source.tar') do |dir|
      output, status = run_report(dir)
      refute status.success?, output
      assert_match(/main|ambiguous/i, output)
      output, status = run_report(dir, '--main', 'second.tex')
      assert status.success?, output
      report = JSON.parse(File.read(File.join(dir, 'metadata-report.json')))
      assert_includes report.to_json, 'second.tex'
    end
  end

  def test_archive_traversal_is_rejected
    sample(tar('../escape.tex' => document), filename: 'source.tar') do |dir|
      output, status = run_report(dir)
      refute status.success?, output
      assert_match(/unsafe|path|traversal/i, output)
    end
  end

  def read_report(dir)
    output, status = run_report(dir)
    assert status.success?, output
    JSON.parse(File.read(File.join(dir, 'metadata-report.json')))
  end

  def test_normalization_preserves_raw_values_and_math_operators
    sample(document('\\bf Sample $x+y$', "Jos\\'{e} Garc\\'{i}a"),
           title: 'Sample $x+y$', authors: ['José García']) do |dir|
      report = read_report(dir)
      assert_equal 'match', report.dig('comparisons', 'title', 'status')
      assert_equal 'match', report.dig('comparisons', 'authors', 'status')
      assert_includes report.dig('extracted', 'title'), '\\bf'
    end
    sample(document('Sample $x-y$'), title: 'Sample $x+y$') do |dir|
      report = read_report(dir)
      assert_equal 'mismatch', report.dig('comparisons', 'title', 'status')
    end
  end

  def test_abstract_comparison_is_review_only_and_keeps_extracted_text
    source = document.sub('Example.', "\\begin{abstract}A TeX abstract with different wording.\\end{abstract}\nExample.")
    sample(source) do |dir|
      metadata = JSON.parse(File.read(File.join(dir, 'metadata.json')))
      metadata['abstract'] = 'The API summary uses other wording.'
      File.write(File.join(dir, 'metadata.json'), JSON.generate(metadata))
      report = read_report(dir)
      assert_equal 'review', report.dig('comparisons', 'abstract', 'status')
      assert_equal 'The API summary uses other wording.', report.dig('reference', 'abstract')
      assert_includes report.dig('extracted', 'abstract'), 'A TeX abstract'
    end
  end

  def test_low_abstract_similarity_is_a_warning_only
    source = document.sub('Example.', <<~TEX)
      \\begin{abstract}
      Alpha bravo charlie delta echo foxtrot golf hotel india juliet.
      \\end{abstract}
      Example.
    TEX
    sample(source) do |dir|
      metadata = JSON.parse(File.read(File.join(dir, 'metadata.json')))
      metadata['abstract'] = 'Kilo lima mike november oscar papa quebec romeo sierra tango.'
      File.write(File.join(dir, 'metadata.json'), JSON.generate(metadata))
      output, status = run_report(dir)
      assert status.success?, output
      report = JSON.parse(File.read(File.join(dir, 'metadata-report.json')))
      abstract = report.dig('comparisons', 'abstract')
      assert_equal 'review', abstract['status']
      assert_equal 'available', abstract['availability']
      assert_equal 'low_similarity', abstract.dig('warning', 'code')
      assert(report['warnings'].any? { |warning| warning.include?('very little text') })
    end
  end

  def test_missing_source_abstract_is_reported_as_unavailable
    sample(document) do |dir|
      report = read_report(dir)
      abstract = report.dig('comparisons', 'abstract')
      assert_equal 'unavailable', abstract['availability']
      assert_nil abstract['warning']
    end
  end

  def test_author_multiplicity_and_order_are_checked
    sample(document('Sample Title', 'Ada Lovelace'), authors: ['Ada Lovelace', 'Ada Lovelace']) do |dir|
      report = read_report(dir)
      assert_equal 'mismatch', report.dig('comparisons', 'authors', 'status')
      assert_equal 1, report.dig('comparisons', 'authors', 'missing').size
    end
    sample(document('Sample Title', 'Grace Hopper \\and Ada Lovelace'),
           authors: ['Ada Lovelace', 'Grace Hopper']) do |dir|
      report = read_report(dir)
      assert_equal true, report.dig('comparisons', 'authors', 'order_mismatch')
    end
  end

  def test_near_name_suggestions_do_not_pass
    sample(document('Sample Title', 'Jorg Mueller'), authors: ['Jörg Müller']) do |dir|
      report = read_report(dir)
      assert_equal 'mismatch', report.dig('comparisons', 'authors', 'status')
      refute_empty report.dig('comparisons', 'authors', 'suggestions')
    end
  end

  def test_pdf_check_uses_arxiv_authors_when_extraction_misses_them
    available = %w[pdflatex pdftotext].all? do |bin|
      ENV.fetch('PATH').split(File::PATH_SEPARATOR).any? { |p| File.executable?(File.join(p, bin)) }
    end
    skip 'pdflatex and pdftotext required' unless available
    sample(document.sub('\\author{Ada Lovelace}', ''), authors: ['Ada Lovelace', 'Grace Hopper']) do |dir|
      File.write(File.join(dir, 'visible.tex'),
                 "\\documentclass{article}\\begin{document}Ada Lovelace\\end{document}\n")
      output, status = Open3.capture2e('pdflatex', '-no-shell-escape', '-interaction=nonstopmode',
                                       '-halt-on-error', 'visible.tex', chdir: dir)
      assert status.success?, output
      output, status = run_report(dir, '--pdf', File.join(dir, 'visible.pdf'))
      assert status.success?, output
      report = JSON.parse(File.read(File.join(dir, 'metadata-report.json')))
      assert_equal [], report.dig('extracted', 'authors')
      assert_equal 'mismatch', report.dig('pdf', 'status')
      assert_equal ['grace hopper'], report.dig('pdf', 'missing')
    end
  end
end
