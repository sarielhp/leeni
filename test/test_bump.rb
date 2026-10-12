#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require_relative '../tools/tooling'

class TestBump < Minitest::Test
  BUMP_BIN = File.expand_path('../tools/bump', __dir__)

  def test_version_levels
    assert_equal '1.0.54', Tooling.next_version('1.0.53', 'patch')
    assert_equal '1.1.0', Tooling.next_version('1.0.53', 'minor')
    assert_equal '2.0.0', Tooling.next_version('1.0.53', 'major')
  end

  def test_unknown_level_rejected
    assert_raises(RuntimeError) { Tooling.next_version('1.0.53', 'other') }
  end

  def test_unknown_argument_rejected_before_release
    out, status = Open3.capture2e(BUMP_BIN, 'other')
    refute status.success?
    assert_includes out, 'Usage: tools/bump [major|minor|patch|--resume]'
  end
end
