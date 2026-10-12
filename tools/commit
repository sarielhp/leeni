#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tooling'

Tooling.entry do
  full = ARGV.first == '--full'
  ARGV.shift if full
  abort 'Usage: tools/commit [--full] <message>' unless ARGV.length == 1 && !ARGV.first.strip.empty?
  Tooling.commit(ARGV.first, full)
end
