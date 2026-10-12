#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tooling'

Tooling.entry do
  abort 'Usage: tools/snapshot [message]' unless ARGV.length <= 1
  Tooling.git('add', '-A')
  Tooling.git('commit', '--no-verify', '-m', ARGV.first || 'chore: checkpoint')
  puts 'Checkpoint committed locally'
end
