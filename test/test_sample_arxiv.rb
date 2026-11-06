#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
load File.expand_path('../tools/sample_arxiv', __dir__)

class TestSampleArxiv < Minitest::Test
  def test_parses_atom_metadata
    xml = <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom" xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/">
        <opensearch:totalResults>1</opensearch:totalResults>
        <entry><id>http://arxiv.org/abs/1234.5678v2</id><title> A  Paper </title>
          <author><name>Ada Lovelace</name></author><category term="cs.AI" />
          <summary> API abstract </summary>
        </entry>
      </feed>
    XML
    total, entries = ArxivSampler.parse_entries(xml)
    assert_equal 1, total
    assert_equal '1234.5678v2', entries.first[:id]
    assert_equal 'A Paper', entries.first[:title]
    assert_equal ['Ada Lovelace'], entries.first[:authors]
    assert_equal ['cs.AI'], entries.first[:categories]
    assert_equal 'API abstract', entries.first[:abstract]
    assert_includes entries.first[:arxiv_entry_xml], '<summary>'
  end

  def test_accepts_gzip_tar_with_tex_and_rejects_pdf
    require 'rubygems/package'
    buffer = StringIO.new
    content = '\\documentclass{}'
    Gem::Package::TarWriter.new(buffer) { |writer| writer.add_file_simple('paper.tex', 0o644, content.bytesize) { |io| io.write(content) } }
    buffer.rewind
    gzip = StringIO.new
    Zlib::GzipWriter.wrap(gzip) { |writer| writer.write(buffer.read) }
    assert_equal :tar, ArxivSampler.validate_source!(gzip.string)
    assert_raises(ArxivSampler::Error) { ArxivSampler.validate_source!('%PDF-1.7') }
  end

  def test_plain_gzip_tex_is_accepted
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) { |writer| writer.write("\\documentclass{article}\n\\begin{document}") }
    assert_equal :tex, ArxivSampler.validate_source!(io.string)
  end

  def test_missing_source_retries_and_reports_actionable_error
    client = Class.new do
      def get(_uri)
        raise ArxivSampler::Error, 'source archive is empty'
      end
    end.new
    sampler = ArxivSampler::Sampler.new(client: client, random: Random.new(4))
    error = assert_raises(ArxivSampler::Error) { sampler.run!(output: Dir.mktmpdir, attempts: 2) }
    assert_includes error.message, 'after 2 attempts'
    assert_includes error.message, 'source archive is empty'
  end

  def test_monthly_count_cache_round_trip_and_validation
    Dir.mktmpdir('arxiv-cache-') do |dir|
      cache = ArxivSampler::MonthlyCountCache.new(dir)
      month = Date.new(2024, 2, 1)
      assert_nil cache.fetch(month)
      cache.store(month, 17)
      assert_equal 17, cache.fetch(month)

      File.write(File.join(dir, '2024-02.json'), '{"month":"2024-02","total_results":-1}')
      assert_nil cache.fetch(month)
      File.write(File.join(dir, '2024-02.json'), 'not json')
      _out, err = capture_io { assert_nil cache.fetch(month) }
      assert_includes err, 'ignoring'
    end
  end
end
