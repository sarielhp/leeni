#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tooling'

HELP = <<~TEXT
  Usage: tools/bump [major|minor|patch|--resume|--abandon]

  Release the committed tree. The working tree must be clean.

    1. Raise the version (patch by default) and run VERSION_UPDATE.
    2. Run the full gate, commit "chore: bump version to X.Y.Z", and push the
       branch and, when RELEASE_TAG is set, the vX.Y.Z tag atomically,
       verified.

  This changes the remote repository. Nothing is installed.

  Options:
    major, minor, patch  Which part of the version to raise.
    --resume    Finish a bump that stopped partway, without bumping the
                version again.
    --abandon   Drop a stopped bump that published nothing: remove its
                unpushed commit and tag, or restore the version file.
    -h, --help  Show this help; nothing is run.
TEXT

Tooling.entry(HELP) do
  usage = 'Usage: tools/bump [major|minor|patch|--resume|--abandon]'
  abort usage unless ARGV.length <= 1 && (ARGV.empty? || %w[major minor patch --resume --abandon].include?(ARGV.first))
  case ARGV.first
  when '--resume' then Tooling.resume
  when '--abandon' then Tooling.abandon
  else Tooling.bump(ARGV.first || 'patch')
  end
end
