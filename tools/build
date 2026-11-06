#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tooling'

HELP = <<~TEXT
  Usage: tools/build

  Check that each artifact is executable Ruby, and syntax-check every source
  (ruby -cw). Nothing is installed.

  Options:
    -h, --help  Show this help; nothing is run.
TEXT

Tooling.entry(HELP) do
  abort 'Usage: tools/build' unless ARGV.empty?
  Language.build
end
