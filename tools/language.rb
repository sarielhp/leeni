# frozen_string_literal: true

require 'rbconfig'

module Language
  VERSION_ASSIGNMENT = /^\s*(?:[A-Z]\w*::)*VERSION\s*=\s*(?<quote>['"])(?<value>[^'"\n]+)\k<quote>/
  TEST_LOADER = 'ARGV.each { |path| require File.expand_path(path) }'
  FLAY_SCORE = /^Total score \(lower is better\) = (\d+)$/

  module_function

  def name
    'Ruby'
  end

  def setup
    raise 'PROFILE must be :project or :script' unless %i[project script].include?(ToolSettings::PROFILE)
    raise 'VERSION_STYLE must be :constant or :text' unless %i[constant text].include?(ToolSettings::VERSION_STYLE)
    raise 'no Ruby sources; configure SOURCE_GLOBS' if source_files.empty?
  end

  def tool_paths
    [Gem.bindir, File.join(Gem.user_dir, 'bin'), File.expand_path('~/bin')]
  end

  def required_inputs
    ['Gemfile', 'Gemfile.lock', ToolSettings::VERSION_FILE].compact
  end

  def verification_tools
    %w[ruby bundle ruby-audit rubocop bundle-audit flay]
  end

  def environment
    gems = Gem::Specification.map { |spec| [spec.name, spec.version.to_s, spec.full_gem_path] }.sort
    [RUBY_DESCRIPTION, RbConfig.ruby, gems, ENV.to_h.select { |key, _| key.start_with?('RUBY', 'GEM', 'BUNDLE', 'RUBOCOP') }]
  end

  def ruby_source?(path)
    return false unless File.file?(path)
    return true if %w[.rb .gemspec].include?(File.extname(path)) || File.basename(path) == 'Rakefile'

    File.open(path, &:gets).to_s.match?(/\A#!.*ruby/)
  end

  def source_files
    paths = ToolSettings::SOURCE_GLOBS.flat_map { |pattern| Dir.glob(pattern) }
    paths << File.basename(Dir.pwd)
    paths.uniq.sort.select { |path| ruby_source?(path) }
  end

  def project_profile?
    return true if ToolSettings::PROFILE == :project || File.file?('Gemfile.lock')

    files = source_files.reject { |path| path.start_with?('tools/') }
    files.length > 1 || files.any? { |path| File.foreach(path).count > 150 }
  end

  def preflight(full)
    tools = %w[ruby ruby-audit]
    tools << 'rubocop' if project_profile?
    tools << 'bundle' if File.file?('Gemfile')
    tools << 'bundle-audit' if full && File.file?('Gemfile.lock')
    tools << 'flay' if full && project_profile?
    tools.each { |tool| Tooling.executable(tool) }
    raise 'projects require a local .rubocop.yml; copy and adapt the standards baseline' if project_profile? && !File.file?('.rubocop.yml')
  end

  def ruby_command(*args)
    command = [Tooling.executable('ruby'), *args]
    command = [Tooling.executable('bundle'), 'exec', *command] if File.file?('Gemfile')
    command
  end

  def build
    Tooling.run('tools/bundle', '-o', 'build/leeni')
    outputs = artifacts.map { |path| Tooling.contained_path(path) }
    outputs.each do |path|
      raise "artifact must be an executable Ruby source: #{path}" unless ruby_source?(path) && File.executable?(path)
    end
    (source_files + outputs).uniq.each do |path|
      out, err, status = Tooling.capture(*ruby_command('-cw', path))
      raise "syntax check failed: #{path}\n#{out}#{err}" unless status.success? && err.strip.empty?
    end
    puts 'Build/syntax check passed'
  end

  def artifacts
    return ToolSettings::ARTIFACTS unless ToolSettings::ARTIFACTS.nil?

    Dir.glob('bin/*').select { |path| ruby_source?(path) && File.executable?(path) }
  end

  def lint
    preflight(false)
    Tooling.run(Tooling.executable('ruby-audit'), '--strict', '--include-tests', *source_files)
    return puts('Script audit passed') unless project_profile?

    Tooling.run(Tooling.executable('rubocop'), '--format', 'progress', *source_files)
    puts 'Lint passed'
  end

  def test
    if ToolSettings::TEST_COMMAND
      Tooling.run(*ToolSettings::TEST_COMMAND)
      return
    end
    files = ToolSettings::TEST_GLOBS.flat_map { |pattern| Dir.glob(pattern) }.uniq.sort
    return puts('No test files configured') if files.empty?

    Tooling.run(*ruby_command('-Ilib:test', '-e', TEST_LOADER, '--', *files))
  end

  def gate_start
    Tooling.script('build')
  end

  def gate_finish; end

  def deep_review
    Tooling.run(Tooling.executable('bundle-audit'), 'check') if File.file?('Gemfile.lock')
    return unless project_profile?

    files = source_files.reject { |path| path.start_with?('tools/') }
    return if files.empty?

    # Review duplicated behavior; unrelated declarative lookup tables can resemble each other structurally.
    out, err, status = Tooling.capture(Tooling.executable('flay'), '-o', 'defn', '-m', ToolSettings::FLAY_MASS.to_s, *files)
    score = out[FLAY_SCORE, 1]
    raise "Flay execution/report failure:\n#{out}#{err}" unless status.success? && err.empty? && score
    raise "Flay clone findings:\n#{out}" unless out.lines.all? { |line| line.strip.empty? || line.match?(FLAY_SCORE) }
  end

  def version_file
    return ToolSettings::VERSION_FILE if ToolSettings::VERSION_FILE

    candidates = Dir.glob('lib/**/version.rb') + Dir.glob('version.rb') + Dir.glob('bin/*').select { |path| ruby_source?(path) }
    matching = candidates.select { |path| File.read(path).match?(VERSION_ASSIGNMENT) }
    raise 'release requires exactly one VERSION definition; configure VERSION_FILE' unless matching.length == 1

    matching.first
  end

  def version
    path = version_file
    Tooling.contained_path(path)
    raise "version file missing: #{path}" unless File.file?(path)
    return [path, File.read(path).strip] if ToolSettings::VERSION_STYLE == :text

    matches = File.read(path).scan(VERSION_ASSIGNMENT)
    raise 'version file must contain exactly one literal VERSION constant' unless matches.length == 1

    [path, File.read(path).match(VERSION_ASSIGNMENT)[:value]]
  end

  def update_version(updated)
    path, = version
    return File.write(path, "#{updated}\n") if ToolSettings::VERSION_STYLE == :text

    content = File.read(path)
    match = content.match(VERSION_ASSIGNMENT)
    content[match.begin(:value), match[:value].length] = updated
    File.write(path, content)
  end

  def synchronize_version; end

  def next_milestone
    0
  end

  def prepare_milestone(_count); end

  def milestone_checks(_count); end
end
