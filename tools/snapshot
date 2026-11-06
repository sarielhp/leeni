#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tooling'

HELP = <<~TEXT
  Usage: tools/snapshot [message]

  Stage every change (git add -A) and commit it locally, without the gate and
  without commit hooks. Nothing is pushed. The message defaults to
  "chore: checkpoint".

  Options:
    -h, --help  Show this help; nothing is run.
TEXT

Tooling.entry(HELP) do
  abort 'Usage: tools/snapshot [message]' unless ARGV.length <= 1
  message = Tooling.commit_message(ARGV.first || 'chore: checkpoint')
  Tooling.git('add', '-A')
  Tooling.git('commit', '--no-verify', '-m', message)
  puts 'Checkpoint committed locally'
end
