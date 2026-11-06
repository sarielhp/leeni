#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tooling'

HELP = <<~TEXT
  Usage: tools/lint

  Static feedback only: ruby-audit --strict on every Ruby file, and RuboCop
  for a project. No tests.

  Options:
    -h, --help  Show this help; nothing is run.
TEXT

Tooling.entry(HELP) do
  abort 'Usage: tools/lint' unless ARGV.empty?
  Language.lint
end
