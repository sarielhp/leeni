#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class LeeniTestBase < Minitest::Test
  # Several tests flip the process-global Rainbow.enabled; without this the value
  # leaks into whichever test file runs next and makes results order-dependent.
  def setup
    @saved_rainbow_enabled = Rainbow.enabled
  end

  def teardown
    Rainbow.enabled = @saved_rainbow_enabled
  end

  BIN = File.expand_path('../leeni', __dir__)
  load BIN

  def legacy_builder(target, options = {})
    LatexBuilder.new(target, { junk_dir: 'junk' }.merge(options))
  end

  def strip_ansi(str)
    str.to_s.gsub(/\e\[[0-9;]*m/, '')
  end
end
