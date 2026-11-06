# frozen_string_literal: true

require 'date'
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require_relative 'settings'
require_relative 'tmp_space'
require_relative 'language'

# Copy beside the entry points. This helper never loads the live standards checkout.
module Tooling
  SEMVER = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/

  HELP_FLAGS = %w[-h --help].freeze

  module_function

  def setup
    Dir.chdir(File.realpath(File.expand_path('..', __dir__)))
    ENV['PATH'] = search_paths.join(File::PATH_SEPARATOR)
    ProjectTmp.project = project_name
    Language.setup
  end

  # ToolSettings::PROJECT_NAME, or the repository directory's name.
  def project_name
    name = ToolSettings.const_defined?(:PROJECT_NAME) ? ToolSettings::PROJECT_NAME : nil
    name || File.basename(Dir.pwd)
  end

  # Ruby programs in tools/; settings.rb is configuration (install
  # destinations, tool paths) and creates nothing.
  def tool_scripts
    Dir.glob('tools/*').select do |path|
      next false if path == 'tools/settings.rb'

      File.file?(path) && (path.end_with?('.rb') || File.open(path, &:gets).to_s.match?(/\A#!.*ruby/))
    end
  end

  # Temporary files go under <tmpdir>/<user>/<project>/ through ProjectTmp;
  # tests may use the language's own calls, since tools/test points TMPDIR
  # into that tree, but no literal /tmp path.
  def check_temporary_files
    found = ProjectTmp.offenders(tool_scripts, ProjectTmp::RUBY_CALLS, comment: /#.*/) +
            ProjectTmp.offenders(Language.temp_policy_files, Language::TEMP_CALLS, comment: Language::COMMENT,
                                                                                   test_file: Language.method(:test_file?))
    return if found.empty?

    raise "temporary files outside <tmpdir>/<user>/#{ProjectTmp.project}/ (use ProjectTmp, " \
          "or mark the line `tmp-exempt: <reason>`):\n#{found.uniq.join("\n")}"
  end

  def search_paths
    (ENV.fetch('PATH', '').split(File::PATH_SEPARATOR) + Language.tool_paths).uniq
  end

  def find_tool(name)
    return ToolSettings::TOOLS.fetch(name) if ToolSettings::TOOLS.key?(name)

    search_paths.map { |dir| File.join(dir, name) }.find { |path| File.file?(path) && File.executable?(path) }
  end

  def executable(name)
    path = find_tool(name)
    raise "required tool missing: #{name}; bootstrap separately with authorization" unless path &&
                                                                                           File.file?(path) && File.executable?(path)

    File.expand_path(path)
  end

  def capture(*args)
    Open3.capture3([args.first, args.first], *args.drop(1))
  rescue SystemCallError => e
    raise "cannot execute #{args.first}: #{e.message}"
  end

  def run(*args)
    out, err, status = capture(*args)
    $stdout.write(out)
    $stderr.write(err)
    raise "command failed (#{status.exitstatus || status.termsig}): #{args.inspect}" unless status.success?

    out
  end

  def git(*args)
    out, err, status = capture(executable('git'), *args)
    raise "git #{args.first} failed: #{out}#{err}" unless status.success?

    out
  end

  def query(*args)
    out, err, status = capture(*args)
    raise "query failed: #{args.inspect}\n#{out}#{err}" unless status.success?

    out
  end

  def script(name, *)
    path = File.join(Dir.pwd, 'tools', name)
    raise "required entry point missing or not executable: tools/#{name}" unless File.file?(path) && File.executable?(path)

    run(path, *)
  end

  def contained_path(path)
    root = Dir.pwd
    target = File.expand_path(path)
    raise "path must stay inside repository: #{path}" unless target.start_with?("#{root}/")

    ancestor = target
    ancestor = File.dirname(ancestor) until File.exist?(ancestor) || File.symlink?(ancestor)
    resolved = File.realpath(ancestor)
    raise "symlink escapes repository: #{path}" unless resolved == root || resolved.start_with?("#{root}/")
    raise "path cannot target Git metadata: #{path}" if target == File.join(root, '.git') || target.start_with?("#{root}/.git/")
    raise "target cannot be a symlink: #{path}" if File.symlink?(target)

    target
  end

  def state_path(name)
    git('rev-parse', '--git-path', "tooling-#{name}.json").strip
  end

  def head
    git('rev-parse', 'HEAD').strip
  end

  def file_input(path)
    return "#{path}\0missing\0" unless File.exist?(path)

    resolved = File.symlink?(path) ? File.realpath(path) : path
    "#{path}\0#{resolved}\0#{File.binread(path)}\0#{File.stat(path).mode & 0o777}\0"
  end

  def input_digest
    files = git('ls-files', '-c', '-o', '--exclude-standard', '-z').split("\0")
    files.select! { |path| File.exist?(path) || File.symlink?(path) }
    files.concat(Dir.glob('tools/**/*', File::FNM_DOTMATCH).select { |path| File.file?(path) })
    files.concat(Language.required_inputs)
    files.concat(ToolSettings::VERIFICATION_INPUTS.flat_map { |pattern| Dir.glob(pattern, File::FNM_DOTMATCH) })
    digest = Digest::SHA256.new
    files.uniq.sort.each { |path| digest << file_input(path) }
    tools = Language.verification_tools.map do |name|
      path = find_tool(name)
      [name, path, path && File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil]
    end
    digest << JSON.generate([tools, Language.environment])
    digest.hexdigest
  end

  def record(level)
    File.write(state_path('verification'), JSON.generate(head: head, level: level, inputs: input_digest))
  end

  def verified?(full)
    path = state_path('verification')
    return false unless File.file?(path)

    data = JSON.parse(File.read(path), symbolize_names: true)
    return false unless data.is_a?(Hash)

    levels = full ? ['full'] : %w[fast full]
    data[:head] == head && levels.include?(data[:level]) && data[:inputs] == input_digest
  rescue JSON::ParserError
    false
  end

  def gate(tier)
    full = tier == :full
    Language.preflight(full)
    checked = input_digest
    Language.gate_start
    script('lint')
    check_temporary_files
    ToolSettings::FAST_CHECKS.each { |args| run(*args) }
    script('test', "--#{tier}")
    if full
      Language.deep_review
      ToolSettings::FULL_CHECKS.each { |args| run(*args) }
    end
    Language.gate_finish
    raise 'gate changed source or verification inputs; inspect and rerun' unless checked == input_digest

    puts "#{tier.to_s.capitalize} gate passed"
  end

  def commit(message, full)
    script('gate', *('--full' if full)) unless verified?(full)
    checked = input_digest
    git('add', '-A')
    git('commit', '-m', message)
    unless checked == input_digest && git('status', '--porcelain').empty?
      raise 'commit hook changed checked inputs or committed tree; inspect and recheck'
    end

    record(full ? 'full' : 'fast')
    puts "Committed locally: #{message}"
  end

  def upstream
    branch = git('symbolic-ref', '--short', 'HEAD').strip
    remote = git('config', '--get', "branch.#{branch}.remote").strip
    ref = git('config', '--get', "branch.#{branch}.merge").strip
    raise 'release requires a remote branch upstream' if remote.empty? || remote == '.' || !ref.start_with?('refs/heads/')

    git('check-ref-format', ref)
    destinations = git('remote', 'get-url', '--push', '--all', remote).lines.map(&:strip)
    raise 'release requires one upstream push destination' unless destinations.length == 1

    [destinations.first, ref]
  end

  def version
    path, value = Language.version
    contained_path(path)
    raise "invalid semantic version: #{value.inspect}" unless SEMVER.match?(value)

    [path, value]
  end

  def next_version(current, level)
    parts = current.split('.').map(&:to_i)
    index = %w[major minor patch].index(level)
    raise "unsupported bump level: #{level}" unless index

    parts[index] += 1
    ((index + 1)..2).each { |position| parts[position] = 0 }
    parts.join('.')
  end

  def release_tag_absent(tag, destination)
    _, err, status = capture(executable('git'), 'show-ref', '--verify', '--quiet', "refs/tags/#{tag}")
    raise "cannot check local release tag: #{err}" unless [0, 1].include?(status.exitstatus)
    raise "release tag already exists locally: #{tag}" if status.success?
    raise "release tag already exists remotely: #{tag}" unless git('ls-remote', destination, "refs/tags/#{tag}").empty?
  end

  def bump(level = 'patch')
    if File.exist?(state_path('release'))
      raise 'unfinished release; inspect local state and use tools/bump --resume, or --abandon if nothing was published'
    end

    destination, ref = upstream
    _, current = version
    raise 'bump requires a clean working tree' unless git('status', '--porcelain').empty?

    updated = next_version(current, level)
    tag = ToolSettings::RELEASE_TAG ? "v#{updated}" : nil
    release_tag_absent(tag, destination) if tag
    data = { base: head, version: updated, destination: destination, ref: ref, tag: tag }
    data[:milestone] = Language.next_milestone
    File.write(state_path('release'), JSON.generate(data))
    Language.update_version(updated)
    ToolSettings::VERSION_UPDATE.each { |args| run(*args) }
    Language.synchronize_version
    Language.prepare_milestone(data.fetch(:milestone))
    finish_pending_commit(data)
    publish(data)
  rescue StandardError => e
    raise "#{e.message}\nLocal state retained. Inspect and use tools/bump --resume; it never bumps again. " \
          'If nothing was published, tools/bump --abandon drops it.'
  end

  def finish_pending_commit(data)
    raise 'HEAD changed before pending release commit' unless head == data.fetch(:base)
    raise 'pending version changed; inspect local files' unless version.last == data.fetch(:version)

    checked = input_digest
    script('gate', '--full')
    Language.milestone_checks(data.fetch(:milestone))
    raise 'milestone checks changed source or checked inputs; inspect and rerun' unless checked == input_digest

    git('add', '-A')
    git('commit', '-m', "chore: bump version to #{data.fetch(:version)}")
    unless checked == input_digest && git('status', '--porcelain').empty?
      raise 'commit hook changed checked release inputs or committed tree; inspect and recheck'
    end

    data[:commit] = head
    data[:inputs] = input_digest
    File.write(state_path('release'), JSON.generate(data))
  end

  def resume
    path = state_path('release')
    raise 'no interrupted release to resume' unless File.file?(path)

    data = JSON.parse(File.read(path), symbolize_names: true)
    unless data[:commit]
      unless head == data.fetch(:base) && version.last == data.fetch(:version)
        raise 'HEAD or version changed; inspect, then drop the pending release with tools/bump --abandon'
      end

      ToolSettings::VERSION_UPDATE.each { |args| run(*args) }
      Language.synchronize_version
      Language.prepare_milestone(data.fetch(:milestone))
      finish_pending_commit(data)
    end
    unchanged = head == data.fetch(:commit) && git('status', '--porcelain').empty? && input_digest == data.fetch(:inputs)
    raise 'HEAD, working tree, or checked inputs changed since release commit' unless unchanged

    publish(data)
  end

  # Drops a pending release that never reached the remote, so a bump that can
  # no longer resume (HEAD moved, the fix needed a commit) does not need its
  # state file deleted by hand. The bump commit and its local tag go only while
  # HEAD is still that commit; an uncommitted pending version is restored.
  # Other files the bump touched are listed, not reverted.
  def abandon
    path = state_path('release')
    raise 'no interrupted release to abandon' unless File.file?(path)

    data = JSON.parse(File.read(path), symbolize_names: true)
    refuse_published_release(data)
    data[:commit] ? drop_release_commit(data) : restore_pending_version(data)
    FileUtils.rm_f(path)
    puts "Abandoned release #{data.fetch(:version)}; nothing was published"
    left = git('status', '--porcelain')
    puts "Left for inspection:\n#{left}" unless left.empty?
  end

  def refuse_published_release(data)
    destination = data.fetch(:destination)
    published = data[:commit] && git('ls-remote', destination, data.fetch(:ref)).split.first == data[:commit]
    published ||= data[:tag] && !git('ls-remote', destination, "refs/tags/#{data[:tag]}").empty?
    raise 'the release already reached the remote; finish it with tools/bump --resume' if published
  end

  def drop_release_commit(data)
    commit = data.fetch(:commit)
    raise 'HEAD is no longer the release commit; inspect and remove it by hand' unless head == commit
    raise 'abandon requires a clean working tree' unless git('status', '--porcelain').empty?

    delete_release_tag(data[:tag], commit) if data[:tag]
    git('reset', '--keep', "#{commit}^")
  end

  def delete_release_tag(tag, commit)
    ref = "refs/tags/#{tag}"
    _, _, status = capture(executable('git'), 'show-ref', '--verify', '--quiet', ref)
    git('tag', '-d', tag) if status.success? && git('rev-parse', "#{ref}^{}").strip == commit
  end

  def restore_pending_version(data)
    file, value = version
    git('checkout', 'HEAD', '--', file) if value == data.fetch(:version)
  end

  def ensure_release_tag(data)
    return unless data[:tag]

    ref = "refs/tags/#{data.fetch(:tag)}"
    _, err, status = capture(executable('git'), 'show-ref', '--verify', '--quiet', ref)
    raise "cannot check release tag: #{err}" unless [0, 1].include?(status.exitstatus)

    unless status.success?
      git('tag', '-a', data.fetch(:tag), data.fetch(:commit), '-m', "Release #{data.fetch(:version)}")
      return
    end
    raise 'existing release tag points to another commit' unless git('rev-parse', "#{ref}^{}").strip == data.fetch(:commit)
  end

  def publish(data)
    ensure_release_tag(data)
    refs = ["#{data.fetch(:commit)}:#{data.fetch(:ref)}"]
    refs << "refs/tags/#{data[:tag]}:refs/tags/#{data[:tag]}" if data[:tag]
    git('push', '--atomic', data.fetch(:destination), *refs)
    actual = git('ls-remote', '--exit-code', data.fetch(:destination), data.fetch(:ref)).split.first
    raise "remote branch mismatch: #{actual.inspect}" unless actual == data.fetch(:commit)

    if data[:tag]
      actual = git('ls-remote', '--exit-code', data.fetch(:destination), "refs/tags/#{data[:tag]}^{}").split.first
      raise "remote tag mismatch: #{actual.inspect}" unless actual == data.fetch(:commit)
    end
    FileUtils.rm_f(state_path('verification'))
    FileUtils.rm_f(state_path('release'))
    puts "Released #{data.fetch(:version)}: branch and requested tag pushed and verified"
  end

  def install(link: false, names: [])
    raise 'link installation is only supported for interpreted Ruby artifacts' if link && Language.name != 'Ruby'

    targets = ToolSettings::INSTALL_TARGETS
    raise 'installation unsupported: declare INSTALL_TARGETS' if targets.empty?

    selected = names.empty? ? targets : targets.select { |source, _| names.include?(File.basename(source)) }
    missing = names - selected.keys.map { |source| File.basename(source) }
    raise "undeclared installation names: #{missing.inspect}" unless missing.empty?

    selected.each do |source, destination|
      contained_path(source)
      raise "installation source is not declared: #{source}" unless Language.artifacts.include?(source)
      raise "installation target must be absolute: #{destination}" unless destination.start_with?('/')
      raise "installation target is a directory: #{destination}" if File.directory?(destination)

      if File.symlink?(destination)
        valid_link = link && File.realpath(destination) == File.expand_path(source)
        raise "installation target is an unrelated symlink: #{destination}" unless valid_link
      end
    end
    script('build')
    selected.each { |source, destination| install_artifact(source, destination, link) }
    puts 'Installation verified'
  end

  # True when destination already holds built's bytes and permissions.
  def installed?(built, destination)
    File.file?(destination) && !File.symlink?(destination) &&
      Digest::SHA256.file(built) == Digest::SHA256.file(destination) &&
      File.stat(built).mode == File.stat(destination).mode
  end

  # Copies built beside destination and renames it into place, so a running
  # program is replaced rather than overwritten ("Text file busy") and no
  # reader ever sees a partial file.
  def replace_file(built, destination)
    temporary = File.join(File.dirname(destination), ".#{File.basename(destination)}.#{Process.pid}.tmp")
    FileUtils.cp(built, temporary, preserve: true)
    File.rename(temporary, destination)
  ensure
    FileUtils.rm_f(temporary) if temporary
  end

  def install_artifact(source, destination, link)
    built = contained_path(source)
    raise "installation source is not executable: #{source}" unless File.file?(built) && File.executable?(built)

    expected = Digest::SHA256.file(built).hexdigest
    FileUtils.mkdir_p(File.dirname(destination))
    if link
      FileUtils.rm_f(destination)
      FileUtils.ln_s(built, destination)
      raise "installed link mismatch: #{destination}" unless File.realpath(destination) == built
    end
    unless link
      return puts("#{destination} is already up to date") if installed?(built, destination)

      replace_file(built, destination)
    end
    raise "installed artifact mismatch: #{destination}" unless expected == Digest::SHA256.file(destination).hexdigest
    raise "installed permissions mismatch: #{destination}" unless File.stat(built).mode == File.stat(destination).mode
  end

  # True when HEAD is the bump commit of the current version and the upstream
  # branch already points at it: there is nothing new to bump or push. A bump
  # commit the upstream lacks is an interrupted or diverged release, which
  # needs inspection rather than a second bump.
  def released?
    current = version.last
    return false unless git('log', '-1', '--format=%s').strip == "chore: bump version to #{current}"

    destination, ref = upstream
    actual = git('ls-remote', destination, ref).split.first
    return true if actual == head

    raise "HEAD is the #{current} release commit, but #{ref} at #{destination} is #{actual.inspect}; " \
          'inspect, then use tools/bump --resume or push it'
  end

  def release(message, install: true)
    published = false
    upstream
    version
    if git('status', '--porcelain').empty?
      puts 'Nothing to commit; continuing with the bump.'
    else
      script('commit', message)
    end
    if released?
      puts "Nothing new since release #{version.last}; skipping the bump."
    else
      script('bump')
    end
    published = true
    return puts('--no-install: installation skipped.') unless install
    return puts('No INSTALL_TARGETS declared; installation skipped.') if ToolSettings::INSTALL_TARGETS.empty?

    script('install')
  rescue StandardError => e
    state = if published
              'Release published and verified; installation failed. Retry tools/install separately.'
            else
              'Release failed before verified publication; inspect pending/local state before resuming.'
            end
    raise "#{e.message}\n#{state}"
  end

  # A script's help is printed, and nothing else happens, whenever -h or
  # --help is among its arguments. The scripts took any lone argument as their
  # commit message, so `tools/release --help` committed pending work as
  # "--help", bumped the version and published the release.
  def entry(help = nil)
    if ARGV.intersect?(HELP_FLAGS)
      puts help || "#{File.basename($PROGRAM_NAME)}: no help written for this script"
      exit
    end
    setup
    yield
  rescue StandardError => e
    abort e.message
  end

  # A commit message is what the commit is called for good once it is pushed,
  # so one that looks like an option -- a mistyped --ful, a --dry-run the
  # script does not have -- is refused rather than committed.
  def commit_message(text)
    raise 'the commit message is empty' if text.strip.empty?
    raise "refusing a commit message that looks like an option: #{text}" if text.start_with?('-')

    text
  end
end
