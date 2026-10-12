#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tooling'

Tooling.entry do
  abort 'Usage: tools/bump [major|minor|patch|--resume]' unless ARGV.length <= 1 && (ARGV.empty? || %w[major minor patch
                                                                                                       --resume].include?(ARGV.first))
  ARGV.first == '--resume' ? Tooling.resume : Tooling.bump(ARGV.first || 'patch')
end
