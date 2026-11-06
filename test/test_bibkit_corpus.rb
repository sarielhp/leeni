# frozen_string_literal: true

# Bibkit's scanner over every .bib file TeX Live ships (full tier only). Each
# file must scan without an exception, and every line that starts an entry
# must yield an entry or a reported problem: nothing is silently lost.

require_relative 'test_env'
require 'minitest/autorun'
require 'open3'
require_relative '../lib/leeni/bibkit_collection'

class TestBibkitCorpus < Minitest::Test
  ENTRY_START = /^[ \t]*@[ \t]*(?!string\b|comment\b|preamble\b)[A-Za-z][\w-]*[ \t]*[{(]/i

  def corpus
    root, status = Open3.capture2('kpsewhich', '-var-value', 'TEXMFDIST')
    root = root.strip
    status.success? && File.directory?(root) ? Dir.glob(File.join(root, 'bibtex', 'bib', '**', '*.bib')) : []
  rescue SystemCallError
    []
  end

  def test_every_entry_is_scanned_or_reported
    files = corpus
    skip 'no TeX Live bibliography files found' if files.empty?

    lost = files.filter_map do |path|
      text = File.binread(path)
      file = Bibkit::BibFile.new(text, path)
      starts = text.scan(ENTRY_START).size
      found = file.entries.size + file.problems.count { |p| p.message.include?(' in @') }
      "#{path}: #{starts} entry starts, #{found} entries or problems" if found < starts
    end
    assert_empty lost
  end
end
