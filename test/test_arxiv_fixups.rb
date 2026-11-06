#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'json'
require 'minitest/autorun'
require 'tmpdir'

load File.expand_path('../tools/test_arxiv', __dir__)

class TestArxivFixups < Minitest::Test
  def test_matching_source_fixup_is_cataloged
    path = File.expand_path('../examples/arxiv/2501.02798v1/metadata.json', __dir__)
    skip 'examples/arxiv fixture not present' unless File.exist?(path)

    metadata = JSON.parse(File.read(path))
    fixup = ArxivPaperTest.fixup_for(metadata)
    refute_nil fixup
    assert_equal '2501.02798v1', fixup['arxiv_id']
    assert_includes fixup['files'], 'System.eps'
  end

  def test_changed_source_checksum_does_not_match
    metadata = { 'id' => '2501.02798v1', 'source_sha256' => '0' * 64 }
    assert_nil ArxivPaperTest.fixup_for(metadata)
  end

  def test_report_describes_automatic_engine_selection
    Dir.mktmpdir('arxiv-report-') do |sample|
      report = ArxivPaperTest::Runner.new(sample: sample, engine: nil).send(:markdown)
      assert_includes report, 'Engine: `automatic`'
    end
  end
end
