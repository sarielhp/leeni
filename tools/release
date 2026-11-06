#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tooling'

HELP = <<~TEXT
  Usage: tools/release <message>

  Publish a release: commit, bump the patch version, push, and install.

    1. Commit the pending work as <message>, after the fast gate (tools/commit);
       skipped when there is nothing to commit.
    2. Bump the patch version, run the full gate, commit
       "chore: bump version to X.Y.Z", and push the branch and its vX.Y.Z tag
       together, verified (tools/bump);
       skipped when HEAD is already the pushed release commit.
    3. Install the built artifacts to INSTALL_TARGETS (tools/install);
       skipped, with a notice, when no targets are declared;
       a target that already matches the build is left alone.

  Rerunning after a success does nothing but confirm it. Steps 1 and 2 change
  the remote repository and are not undone by rerunning. If a step fails, the
  message says what was published; an interrupted bump is finished with
  tools/bump --resume, or dropped with tools/bump --abandon when
  nothing was published.

  Options:
    --install   Accepted for compatibility; installation always runs.
    -h, --help  Show this help; nothing is run.
TEXT

Tooling.entry(HELP) do
  ARGV.shift if ARGV.first == '--install'
  abort 'Usage: tools/release <message>' unless ARGV.length == 1
  Tooling.release(Tooling.commit_message(ARGV.first))
end
