# frozen_string_literal: true

# Temporary files of a project live in one tree, <tmpdir>/<user>/<project>/<purpose>/
# (see the standards README, "Temporary and cached files"); caches, which save
# work across runs, live in $XDG_CACHE_HOME/<project>/ instead (cache_dir). The
# temporary tree keeps the system temporary directory
# holds one entry per user and project instead of one per run. Making a temporary
# directory first removes entries of the tree older than 24 hours, except a lock
# file some process holds, and old-style <tmpdir>/<project>_* entries of the same
# user. Copy unchanged; tools/tooling.rb sets the project name from
# ToolSettings::PROJECT_NAME, and a project's own code sets ProjectTmp.project.
#
# Only this helper may use the system temporary directory directly; the gate
# rejects any other line that does unless it carries `tmp-exempt: <reason>`.

require 'etc'
require 'fileutils'
require 'tmpdir'

module ProjectTmp
  MAX_AGE = 24 * 3600
  MARKER = 'tmp-exempt:'
  LITERAL_TMP = %r{["']/tmp\b}
  # Ruby calls that use the system temporary directory directly.
  RUBY_CALLS = %r{Dir\.mktmpdir|Dir\.tmpdir|\bTempfile\b|["']/tmp\b}

  class << self
    attr_writer :project

    def project
      @project or raise 'ProjectTmp.project is not set'
    end

    # <tmpdir>/<user>/<project>. The user directory must belong to the user and
    # be closed to writes by others; the project directory is private.
    def root
      base = File.join(Dir.tmpdir, user_name) # tmp-exempt: the helper itself
      ensure_dir(base, forbidden: 0o022)
      ensure_dir(File.join(base, project), forbidden: 0o077)
    end

    def user_name
      Etc.getpwuid(Process.uid)&.name || Process.uid.to_s
    rescue ArgumentError
      Process.uid.to_s
    end

    # A long-lived private directory for one purpose, such as locks.
    def dir(purpose)
      ensure_dir(File.join(root, purpose), forbidden: 0o077)
    end

    # Dir.mktmpdir under root/<purpose>/, named by creation time. With a block
    # the directory is removed afterwards; without one the caller keeps it and
    # the 24-hour sweep removes it later.
    def mktmpdir(purpose, &)
      sweep!
      Dir.mktmpdir(Time.now.strftime('%Y%m%d-%H%M%S-'), dir(purpose), &) # tmp-exempt: the helper itself
    end

    # $XDG_CACHE_HOME/<project>/<purpose>/ (default ~/.cache): for files reused
    # across runs to save work. Losing one costs rework only; the project's own
    # policy removes stale entries, not the 24-hour sweep.
    def cache_dir(purpose)
      base = ENV.fetch('XDG_CACHE_HOME', '')
      base = File.join(Dir.home, '.cache') if base.empty?
      path = File.join(base, project, purpose)
      FileUtils.mkdir_p(path, mode: 0o700)
      path
    end

    # Runs the block with TMPDIR and XDG_CACHE_HOME set to fresh directories of
    # the tree (<dir>/tmp, <dir>/cache), so every program it starts (a test
    # runner, a compiler, a test's own files) neither writes to the system
    # temporary directory nor to the user's real cache; all of it goes when the
    # block ends.
    def with_test_env(purpose = 'test-run')
      mktmpdir(purpose) do |dir|
        env = { 'TMPDIR' => File.join(dir, 'tmp'), 'XDG_CACHE_HOME' => File.join(dir, 'cache') }
        FileUtils.mkdir_p(env.values, mode: 0o700)
        saved = env.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
        begin
          ENV.update(env)
          yield dir
        ensure
          ENV.update(saved)
        end
      end
    end

    def sweep!(now: Time.now)
      entries = Dir.glob(File.join(root, '*', '*'), File::FNM_DOTMATCH).reject { |p| %w[. ..].include?(File.basename(p)) }
      entries += Dir.glob(File.join(Dir.tmpdir, "#{project}_*")) # tmp-exempt: old-style entries of this project
      entries.each { |path| remove_if_stale(path, now) }
    rescue SystemCallError
      nil
    end

    def remove_if_stale(path, now)
      stat = File.lstat(path)
      return if stat.uid != Process.uid || now - stat.mtime < MAX_AGE
      return if stat.directory? ? holds_lock?(path) : locked?(path)

      FileUtils.rm_rf(path)
    rescue SystemCallError
      nil
    end

    def holds_lock?(dir)
      Dir.glob(File.join(dir, '*.lock')).any? { |f| locked?(f) }
    end

    def locked?(file)
      File.open(file, File::RDONLY) do |fh|
        return true unless fh.flock(File::LOCK_EX | File::LOCK_NB)

        fh.flock(File::LOCK_UN)
        false
      end
    rescue SystemCallError
      false
    end

    # Lines of `files` that use the system temporary directory directly: a
    # `calls` match in a program file, a literal /tmp path in a test file. A
    # line carrying MARKER is exempt; `comment` strips the language's comments.
    def offenders(files, calls, comment:, test_file: ->(_) { false })
      files.uniq.flat_map do |file|
        pattern = test_file.call(file) ? LITERAL_TMP : calls
        File.foreach(file).with_index(1).filter_map do |line, number|
          next if line.include?(MARKER)

          "#{file}:#{number}: #{line.strip}" if line.sub(comment, '').match?(pattern)
        end
      end
    end

    # Creates `path` (mode 0700) if needed and refuses one that is a symlink,
    # owned by someone else, or open to the `forbidden` permission bits: the
    # names are predictable, and lock files may be opened for writing inside.
    def ensure_dir(path, forbidden:)
      begin
        Dir.mkdir(path, 0o700)
      rescue Errno::EEXIST
        nil
      end
      stat = File.lstat(path)
      return path if stat.directory? && !stat.symlink? && stat.uid == Process.uid && stat.mode.nobits?(forbidden)

      abort "#{project}: refusing to use #{path}: not a directory owned by uid #{Process.uid} and closed to other users"
    end
  end
end
