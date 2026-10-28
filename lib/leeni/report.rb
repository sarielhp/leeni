# frozen_string_literal: true

# ==============================================================================
# lib/leeni/report.rb
#
# `l --report[=full] doc.tex`: bundle everything needed to look into a problem
# (leeni's own diagnostics, the build logs, the environment, a quarantined
# case if one exists) into a zip under the cache. Sources are included only
# with `full`. Nothing leaves the machine unless the user says yes to the
# GitHub issue offer, and `-llm` / `--json` never ask.
# ==============================================================================

require 'fileutils'
require 'json'
require 'open3'
require 'time'
require 'tmpdir'
require_relative 'utils'
require_relative 'build_workspace'
require_relative 'quarantine'
require_relative 'doctor'
require_relative 'version'

module LeeniReport
  REPO = 'sarielhp/leeni'
  ISSUES_URL = "https://github.com/#{REPO}/issues/new".freeze
  LEVELS = %w[basic full].freeze
  BUILD_FILE_PATTERNS = ['err_*', '*.log', '*.blg', '*.fls', '.build_state.json'].freeze
  MAX_FILE_BYTES = 10 * 1024 * 1024

  module_function

  def root
    File.join(LeeniBuildWorkspace.cache_home, 'leeni', 'reports')
  end

  # Returns the exit status for the CLI.
  def run(target, options, io: $stdout)
    level = options[:report].to_s
    unless LEVELS.include?(level)
      warn "leeni: --report takes 'basic' or 'full', not '#{level}'"
      return 2
    end

    zip = Dir.mktmpdir('leeni_report') do |stage|
      files = stage_bundle(stage, target, options, level)
      archive(stage, target, files)
    end
    announce(zip, level, options, io: io)
    offer_issue(zip, target, options, io: io) unless options[:compile] || options[:json]
    0
  end

  def stage_bundle(stage, target, options, level)
    diagnostics = capture_diagnostics(target, options)
    File.write(File.join(stage, 'diagnostics.json'), diagnostics[:json])
    File.write(File.join(stage, 'diagnostics.txt'), diagnostics[:text])
    build_dir = LeeniBuildWorkspace.resolve('.', options[:junk_dir] || options[:config_junk_dir])
    copy_build_files(build_dir, File.join(stage, 'build'))
    copy_quarantine(File.join(stage, 'quarantine'))
    sources = level == 'full' ? copy_sources(build_dir, target, File.join(stage, 'sources')) : []
    manifest = manifest(target, options, level, diagnostics, sources)
    File.write(File.join(stage, 'manifest.json'), JSON.pretty_generate(manifest))
    Dir.glob('**/*', base: stage).select { |rel| File.file?(File.join(stage, rel)) }.sort
  end

  # leeni's own view of the document, as a user and as an agent would see it.
  def capture_diagnostics(target, options)
    base = [Leeni::EXECUTABLE, '-f', '--no-lock']
    base += ['--engine', options[:engine]] if options[:engine]
    base += ['--junk-dir', options[:junk_dir]] if options[:junk_dir]
    text, text_status = Open3.capture2e(*base, '--no-color', target)
    json, json_status = Open3.capture2e(*base, '--json', target)
    { text: text, text_status: text_status.exitstatus, json: json, json_status: json_status.exitstatus }
  end

  def copy_build_files(build_dir, dest)
    return [] unless File.directory?(build_dir)

    BUILD_FILE_PATTERNS.flat_map { |pat| Dir.glob(pat, File::FNM_DOTMATCH, base: build_dir) }.uniq.sort.each do |rel|
      src = File.join(build_dir, rel)
      next unless File.file?(src) && File.size(src) <= MAX_FILE_BYTES

      FileUtils.mkdir_p(dest)
      FileUtils.cp(src, File.join(dest, rel))
    end
  end

  def copy_quarantine(dest)
    project = File.expand_path('.')
    found = LeeniQuarantine.cases.find { |_, m| m['project'] == project }
    return unless found

    FileUtils.mkdir_p(dest)
    FileUtils.cp_r(found.first, dest)
  end

  # Project-local inputs recorded by -recorder, relative to the project root.
  def project_inputs(build_dir, target)
    root = File.expand_path('.')
    fls = File.join(build_dir, "#{File.basename(target, '.tex')}.fls")
    rels = [target]
    if File.file?(fls)
      File.foreach(fls) do |line|
        next unless line.start_with?('INPUT ')

        abs = File.expand_path(line.sub(/\AINPUT\s+/, '').strip)
        next unless abs.start_with?("#{root}/") && File.file?(abs)
        next if abs.start_with?("#{File.expand_path(build_dir)}/")

        rels << abs.delete_prefix("#{root}/")
      end
    end
    rels.uniq
  end

  def copy_sources(build_dir, target, dest)
    project_inputs(build_dir, target).each do |rel|
      next if File.size(rel) > MAX_FILE_BYTES

      FileUtils.mkdir_p(File.dirname(File.join(dest, rel)))
      FileUtils.cp(rel, File.join(dest, rel))
    end
  end

  def manifest(target, options, level, diagnostics, sources)
    doctor = LeeniDoctor.report
    {
      leeni_version: Leeni::VERSION, created_at: Time.now.iso8601, level: level,
      project: File.expand_path('.'), main_file: target, engine: options[:engine],
      engine_version: engine_version(options[:engine]), platform: RUBY_PLATFORM, ruby: RUBY_VERSION,
      exit_status: { text: diagnostics[:text_status], json: diagnostics[:json_status] },
      engines: doctor[:engines], helpers: doctor[:helpers], sources: sources,
      note: 'Build logs contain fragments of typeset text from box reports; sources are included only at level full.'
    }
  end

  def engine_version(engine)
    return nil unless engine && LaTeXUtils.command_available?(engine)

    out, = Open3.capture2e(engine, '--version')
    out.lines.first.to_s.strip
  rescue StandardError
    nil
  end

  def archive(stage, target, files)
    raise "'zip' command not found; cannot write the report bundle" unless LaTeXUtils.command_available?('zip')

    FileUtils.mkdir_p(root)
    name = "#{File.basename(target, '.tex')}-#{Time.now.strftime('%Y%m%d-%H%M%S')}.zip"
    zip = File.join(root, name)
    out, status = Dir.chdir(stage) { Open3.capture2e('zip', '-q', '-r', zip, *files) }
    raise "zip failed: #{out.strip}" unless status.success?

    zip
  end

  def announce(zip, level, options, io:)
    if options[:json]
      io.puts JSON.generate(report: zip, level: level)
    elsif options[:compile]
      io.puts "leeni: note: report written: #{zip} (#{level})"
    else
      what = level == 'full' ? 'diagnostics, build logs, environment and sources' : 'diagnostics, build logs and environment; no sources'
      io.puts "Report written: #{zip} (#{level}: #{what})"
      io.puts '  Build logs include fragments of typeset text from box reports.'
      io.puts "  To include the sources: l --report=full #{File.basename(zip).sub(/-\d{8}-\d{6}\.zip\z/, '.tex')}" if level == 'basic'
    end
  end

  # Interactive only. The issue body carries the summary, never logs or sources.
  def offer_issue(zip, target, options, io:)
    unless $stdin.tty? && LaTeXUtils.command_available?('gh')
      io.puts "  To report it: open #{ISSUES_URL} and attach the zip."
      return
    end

    io.print "  Open a GitHub issue on #{REPO} with the summary (you attach the zip yourself)? [y/N] "
    answer = $stdin.gets.to_s.strip.downcase
    return io.puts("  Not sent. Open #{ISSUES_URL} when ready and attach the zip.") unless answer.start_with?('y')

    title = "leeni #{Leeni::VERSION}: problem report for #{File.basename(target)}"
    body = issue_body(zip, options)
    out, status = Open3.capture2e('gh', 'issue', 'create', '--repo', REPO, '--title', title, '--body', body)
    io.puts(status.success? ? "  Issue opened: #{out.strip}. Attach #{zip} to it." : "  gh failed: #{out.strip}")
  end

  def issue_body(zip, options)
    [
      "leeni #{Leeni::VERSION}, engine #{options[:engine]}, #{RUBY_PLATFORM}.",
      '', 'What happened:', '', '(describe the problem here)', '',
      "Report bundle to attach: `#{File.basename(zip)}` (written by `l --report`)."
    ].join("\n")
  end
end
