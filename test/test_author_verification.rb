#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'

class TestAuthorVerification < Minitest::Test
  BIN = File.expand_path('../leeni', __dir__)
  load BIN

  def setup
    @packager = LatexArxivPackager.allocate
  end

  def test_extract_author_names_keeps_comma_joined_name_together
    tex = '\\author{Jane Doe, John Doe \\and José Dupont}'

    assert_equal ['Jane Doe, John Doe', 'José Dupont'], LaTeXMetaExtractor.extract_author_names(tex)
  end

  def test_author_matching_normalizes_unicode_case_punctuation_and_line_breaks
    pdf_text = "JOSÉ\nDUPONT\n"

    assert @packager.send(:arxiv_author_in_text?, "Jose Dupont", pdf_text)
    assert @packager.send(:arxiv_author_in_text?, "Jos\u00e9 Dupont", pdf_text)
  end

  def test_author_matching_removes_diacritics_without_accepting_near_match
    assert @packager.send(:arxiv_author_in_text?, 'Müller', "Muller\n")
    refute @packager.send(:arxiv_author_in_text?, 'Müller', 'Mueller')
    assert_equal 'mueller', @packager.send(:arxiv_author_suggestion, 'Müller', 'Mueller')
  end

  def test_author_matching_respects_name_token_boundaries
    refute @packager.send(:arxiv_author_in_text?, 'Ann', 'Joanne Smith')
    assert @packager.send(:arxiv_author_in_text?, 'Ann', 'Ann Smith')
    assert @packager.send(:arxiv_author_in_text?, 'M. I. Katsnelson', 'M. I. Katsnelson2')
  end

  def test_placeholder_authors_are_rejected
    %w[Unknown Anonymous].each do |name|
      assert @packager.send(:arxiv_placeholder_author?, name)
    end
    refute @packager.send(:arxiv_placeholder_author?, 'Anonymous Person')
  end

  def with_source(source)
    Dir.mktmpdir('leeni_authors_') do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, source)
      @packager.instance_variable_set(:@filename, path)
      yield
    end
  end

  def test_missing_and_placeholder_authors_fail_before_pdf_extraction
    ['', '\\author{}', '\\author{Unknown}', '\\author{Anonymous Authors}'].each do |source|
      with_source(source) do
        Open3.stub(:capture3, ->(*) { flunk 'Unusable authors must fail before PDF extraction' }) do
          _out, err = capture_io { refute @packager.send(:verify_arxiv_authors_match, 'paper.pdf') }
          assert_includes err, '[FAIL]'
        end
      end
    end
  end

  def test_first_page_extraction_failure_fails_verification
    with_source('\\author{Jane Doe}') do
      status = Struct.new(:success?).new(false)
      command = lambda do |*args|
        assert_equal ['pdftotext', '-f', '1', '-l', '1', '-layout', 'paper.pdf', '-'], args
        ['', 'damaged PDF', status]
      end
      Open3.stub(:capture3, command) do
        _out, err = capture_io { refute @packager.send(:verify_arxiv_authors_match, 'paper.pdf') }
        assert_includes err, 'damaged PDF'
        assert_includes err, 'first page'
      end
    end
  end

  def test_near_match_diagnostic_does_not_accept_missing_author
    with_source('\\author{Jörg Müller}') do
      status = Struct.new(:success?).new(true)
      Open3.stub(:capture3, ["Jorg Mueller\n", '', status]) do
        _out, err = capture_io { refute @packager.send(:verify_arxiv_authors_match, 'paper.pdf') }
        assert_includes err, 'near match: jorg mueller'
      end
    end
  end

  def test_edit_distance_suggestions_are_bounded
    assert_nil @packager.send(:arxiv_author_suggestion, '', 'Jane Doe')
    assert_nil @packager.send(:arxiv_author_suggestion, 'Ann', 'Anne')
    assert_nil @packager.send(:arxiv_author_suggestion, 'Alexander Smith', 'Alexandra Smythe')
  end
end
