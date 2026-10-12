#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tooling'

Tooling.entry do
  install_requested = ARGV.first == '--install'
  ARGV.shift if install_requested
  abort 'Usage: tools/release [--install] <message>' unless ARGV.length == 1 && !ARGV.first.strip.empty?
  Tooling.release(ARGV.first, install_requested)
end
