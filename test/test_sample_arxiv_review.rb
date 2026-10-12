#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'open3'
load File.expand_path('../tools/sample_arxiv', __dir__)

class TestSampleArxivReview < Minitest::Test
  class QueueClient
    attr_reader :urls

    def initialize(responses)
      @responses = responses
      @urls = []
    end

    def get(url)
      @urls << url
      raise 'Unexpected extra network request' if @responses.empty?

      @responses.shift
    end
  end

  def feed(id = '1006.0038v3')
    <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom" xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/">
        <opensearch:totalResults>20</opensearch:totalResults>
        <entry><id>http://arxiv.org/abs/#{id}</id><title>Sample paper</title>
          <author><name>Sample Author</name></author><category term="math.CO"/>
          <summary>  An API   abstract with
            normalized whitespace. </summary>
        </entry>
      </feed>
    XML
  end

  def source
    "\\documentclass{article}\n\\begin{document}Example.\\end{document}\n"
  end

  def test_complete_download_preserves_bytes_and_provenance
    client = QueueClient.new([feed, feed, source])
    Dir.mktmpdir('sampler-review-') do |dir|
      sampler = ArxivSampler::Sampler.new(client: client, random: Random.new(42), cache_dir: nil)
      capture_io { sampler.run!(output: dir, attempts: 1) }
      result = File.join(dir, '1006.0038v3')
      metadata = JSON.parse(File.read(File.join(result, 'metadata.json')))
      assert_equal '1006.0038v3', metadata['id']
      assert_equal ['Sample Author'], metadata['authors']
      assert_equal 'An API abstract with normalized whitespace.', metadata['abstract']
      assert_includes metadata['arxiv_entry_xml'], '<summary>'
      assert_equal Digest::SHA256.hexdigest(source), metadata['source_sha256']
      assert_equal source, File.binread(Dir[File.join(result, 'source*')].fetch(0))
      assert_equal 'https://export.arxiv.org/e-print/1006.0038v3', client.urls.last
      query = URI.decode_www_form(URI(client.urls.first).query).to_h
      range = query.fetch('search_query')
      dates = range.scan(/\d{12}/)
      assert_equal dates.first[0, 6], dates.last[0, 6], range
      assert_match(/2359\]\z/, range)
    end
  end

  def test_pdf_only_candidate_is_skipped_before_saving_valid_source
    client = QueueClient.new([feed, feed, '%PDF-1.7', feed('1006.0040v1'), feed('1006.0040v1'), source])
    Dir.mktmpdir('sampler-review-') do |dir|
      sampler = ArxivSampler::Sampler.new(client: client, random: Random.new(42), cache_dir: nil)
      capture_io { sampler.run!(output: dir, attempts: 2) }
      refute File.exist?(File.join(dir, '1006.0038v3'))
      assert File.file?(File.join(dir, '1006.0040v1', 'metadata.json'))
      assert_equal 6, client.urls.length
    end
  end

  def test_existing_paper_is_preserved
    client = QueueClient.new([feed, feed, source])
    Dir.mktmpdir('sampler-review-') do |dir|
      existing = File.join(dir, '1006.0038v3')
      FileUtils.mkdir_p(existing)
      File.write(File.join(existing, 'marker'), 'keep')
      sampler = ArxivSampler::Sampler.new(client: client, random: Random.new(42), cache_dir: nil)
      capture_io do
        assert_raises(ArxivSampler::Error) { sampler.run!(output: dir, attempts: 1) }
      end
      assert_equal ['marker'], Dir.children(existing)
      assert_equal 'keep', File.read(File.join(existing, 'marker'))
    end
  end

  def test_cli_help_and_invalid_options
    bin = File.expand_path('../tools/sample_arxiv', __dir__)
    output, status = Open3.capture2e(bin, '--help')
    assert status.success?, output
    assert_includes output, '--output'
    assert_includes output, '--cache-dir'
    [['--unknown'], ['extra'], ['--attempts', '0']].each do |args|
      output, status = Open3.capture2e(bin, *args)
      refute status.success?, output
      assert_includes output, 'sample_arxiv:'
      refute_includes output, 'in `<main>'
    end
  end

  def test_rejects_html_containing_tex_and_invalid_api_metadata
    assert_raises(ArxivSampler::Error) do
      ArxivSampler.validate_source!("<!DOCTYPE html><html>#{source}</html>")
    end
    assert_raises(ArxivSampler::Error) { ArxivSampler.parse_entries('<feed/>') }
    assert_raises(ArxivSampler::Error) do
      ArxivSampler.parse_entries(feed.sub('>20<', '>oops<'))
    end
  end

  def test_http_streaming_redirects_and_fatal_rate_limit
    redirect = Net::HTTPFound.new('1.1', '302', 'Found')
    redirect['location'] = 'https://arxiv.org/e-print/1006.0038v3'
    success = Net::HTTPOK.new('1.1', '200', 'OK')
    [redirect, success].each do |response|
      response.define_singleton_method(:read_body) { |&block| block.call('source bytes') }
    end
    replies = [redirect, success]
    connection = Object.new
    %i[use_ssl= open_timeout= read_timeout= max_retries=].each do |setter|
      connection.define_singleton_method(setter) { |_value| nil }
    end
    connection.define_singleton_method(:start) { |&block| block.call(connection) }
    connection.define_singleton_method(:request) do |_request, &block|
      replies.shift.tap { |response| block.call(response) }
    end
    transport = Object.new
    transport.define_singleton_method(:new) { |*_args| connection }
    client = ArxivSampler::Client.new(min_interval: 0, http: transport, sleeper: ->(_seconds) {})
    assert_equal 'source bytes', client.get('https://export.arxiv.org/e-print/1006.0038v3')
    assert_empty replies
    rate_limit = Net::HTTPTooManyRequests.new('1.1', '429', 'Too Many Requests')
    rate_limit.define_singleton_method(:read_body) { |&block| block.call('Try later') }
    4.times { replies << rate_limit }
    Dir.mktmpdir do |dir|
      sampler = ArxivSampler::Sampler.new(client: client)
      assert_raises(ArxivSampler::HttpError) { sampler.run!(output: dir, attempts: 10) }
      assert_empty replies
    end
  end

  def test_http_429_retries_with_retry_after_and_bounded_backoff
    responses = [Net::HTTPTooManyRequests.new('1.1', '429', 'Too Many Requests'),
                 Net::HTTPOK.new('1.1', '200', 'OK')]
    responses.first['retry-after'] = '7'
    responses.each { |response| response.define_singleton_method(:read_body) { |&block| block.call('body') } }
    connection = Object.new
    %i[use_ssl= open_timeout= read_timeout= max_retries=].each do |setter|
      connection.define_singleton_method(setter) { |_value| nil }
    end
    connection.define_singleton_method(:start) { |&block| block.call(connection) }
    connection.define_singleton_method(:request) do |_request, &block|
      response = responses.shift
      block.call(response)
      response
    end
    transport = Object.new
    transport.define_singleton_method(:new) { |*_args| connection }
    sleeps = []
    client = ArxivSampler::Client.new(min_interval: 0, http: transport,
                                      sleeper: ->(seconds) { sleeps << seconds })
    assert_equal 'body', client.get('https://export.arxiv.org/api/query')
    assert_equal [7.0], sleeps

    retries = Array.new(4) { Net::HTTPTooManyRequests.new('1.1', '429', 'Too Many Requests') }
    retries.each { |response| response.define_singleton_method(:read_body) { nil } }
    responses.replace(retries)
    assert_raises(ArxivSampler::HttpError) { client.get('https://export.arxiv.org/api/query') }
    assert_equal [7.0, 3, 6, 12], sleeps
  end
end
