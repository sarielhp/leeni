# frozen_string_literal: true

module ToolSettings
  TOOLS = { 'ruby-audit' => File.expand_path('ruby_audit', __dir__) }.freeze
  PROFILE = :project # :script is for standalone programs <=150 lines without Gemfile.lock.
  SOURCE_GLOBS = ['leeni', 'lib/**/*.rb', 'tools/**/*', 'test/**/*.rb'].freeze
  TEST_GLOBS = ['test/**/test_*.rb', 'test/**/*_test.rb'].freeze
  TEST_COMMAND = ['tools/test'].freeze # Existing test files use isolated processes.
  ARTIFACTS = ['build/leeni'].freeze
  INSTALL_TARGETS = { 'build/leeni' => File.expand_path('~/bin/leeni') }.freeze
  VERSION_FILE = 'lib/leeni/version.rb'
  VERSION_STYLE = :constant # :text supports a standalone VERSION metadata file.
  VERSION_UPDATE = [].freeze
  RELEASE_TAG = true
  FLAY_MASS = 50
  FAST_CHECKS = [['tools/bundle', '--check'].freeze].freeze
  FULL_CHECKS = [].freeze
  VERIFICATION_INPUTS = ['.bundle/config', '.ruby-version', '.tool-versions', '.rubocop*', '.flayignore'].freeze
end
