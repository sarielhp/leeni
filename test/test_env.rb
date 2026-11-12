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

require 'etc'

# Timing-sensitive tests (short timeouts, elapsed-time bounds, sleeps that a
# background thread must outlast) stretch their waits by this factor: the
# one-minute load average per CPU, at least 1 and at most 10. On a quiet
# machine the tests stay as strict as written; on a loaded one a child that
# merely starts slowly no longer fails them.
module LeeniTestLoad
  module_function

  def factor
    load1 = File.read('/proc/loadavg').split.first.to_f
    (load1 / Etc.nprocessors).clamp(1.0, 10.0)
  rescue SystemCallError
    1.0
  end

  def scale(seconds, factor = self.factor)
    (seconds * factor).round(3)
  end
end
