# frozen_string_literal: true

# Load first in every test file, before minitest (whose at_exit runs the
# tests). tools/test already points TMPDIR and XDG_CACHE_HOME into
# <tmpdir>/<user>/leeni/test-run/ and sets LEENI_TEST_ENV; a test file run on
# its own (ruby test/test_x.rb) gets the same here, so no test writes to the
# system temporary directory or to the user's real cache.
unless ENV['LEENI_TEST_ENV']
  require 'fileutils'
  require_relative '../lib/leeni/tmp_space'

  leeni_test_run = LeeniTmp.mktmpdir('test-run')
  ENV['TMPDIR'] = File.join(leeni_test_run, 'tmp')
  ENV['XDG_CACHE_HOME'] = File.join(leeni_test_run, 'cache')
  ENV['LEENI_TEST_ENV'] = '1'
  FileUtils.mkdir_p([ENV.fetch('TMPDIR'), ENV.fetch('XDG_CACHE_HOME')], mode: 0o700)
  at_exit { FileUtils.rm_rf(leeni_test_run) }
end
