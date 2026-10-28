# frozen_string_literal: true

# ==============================================================================
# lib/leeni/doctor.rb
#
# `l --doctor`: one place to look before reporting a problem. Reports which
# engines and helper tools are on the PATH, where the cache lives and how big
# it is, and the quarantined builds that the automatic cache recovery stored.
# ==============================================================================

require 'json'
require_relative 'utils'
require_relative 'build_workspace'
require_relative 'quarantine'
require_relative 'cache_pruner'
require_relative 'version'

module LeeniDoctor
  ENGINES = %w[xelatex lualatex pdflatex].freeze
  HELPERS = %w[biber bibtex makeindex pdftotext pdfinfo pdffonts mutool gh].freeze

  module_function

  # Entry point for the CLI. `target` is true for the overview, a case name
  # to show one quarantined build, "clear" or "prune". Returns the exit status.
  def run(target, options, io: $stdout)
    json = options[:json]
    plain = options[:compile] || options[:color] == false
    case target
    when 'clear'
      count = LeeniQuarantine.cases.size
      LeeniQuarantine.clear!
      io.puts(json ? JSON.generate(cleared: count) : "Removed #{plural(count, 'quarantined build')}.")
      0
    when 'prune'
      summary = LeeniCachePruner.run(days: LeeniCachePruner.days_from(options))
      io.puts(json ? JSON.pretty_generate(summary) : LeeniCachePruner.describe(summary))
      0
    when String
      show_case(target, io: io, json: json)
    else
      data = report(options)
      io.puts(json ? JSON.pretty_generate(data) : render_text(data, plain: plain).join("\n"))
      0
    end
  end

  def report(options = {})
    {
      leeni_version: Leeni::VERSION,
      engines: ENGINES.to_h { |t| [t, LaTeXUtils.command_available?(t)] },
      helpers: HELPERS.to_h { |t| [t, LaTeXUtils.command_available?(t)] },
      cache: cache_summary(LeeniCachePruner.days_from(options)),
      quarantine: LeeniQuarantine.cases.map { |dir, m| case_summary(dir, m) }
    }
  end

  def cache_summary(days = LeeniCachePruner::DEFAULT_DAYS)
    home = File.join(LeeniBuildWorkspace.cache_home, 'leeni')
    projects_dir = File.join(home, 'projects')
    projects = File.directory?(projects_dir) ? Dir.children(projects_dir).size : 0
    statuses = LeeniCachePruner.survey(days: days).group_by { |e| e[:status] }.transform_values(&:size)
    { path: home, projects: projects, size_bytes: tree_size(home), cache_days: days,
      orphaned: statuses.fetch(:orphan, 0), idle: statuses.fetch(:idle, 0) }
  end

  def tree_size(dir)
    return 0 unless File.directory?(dir)

    Dir.glob('**/*', base: dir).sum { |rel| (f = File.join(dir, rel)) && File.file?(f) ? File.size(f) : 0 }
  end

  def case_summary(dir, manifest)
    {
      name: File.basename(dir), path: dir, created_at: manifest['created_at'], project: manifest['project'],
      engine: manifest['engine'], trigger: manifest['trigger'], first_error: manifest['first_error']
    }
  end

  def render_text(data, plain: false)
    lines = ["leeni #{data[:leeni_version]} doctor", '']
    lines << "Engines:  #{availability_line(data[:engines], plain)}"
    lines << "Helpers:  #{availability_line(data[:helpers], plain)}"
    cache = data[:cache]
    lines << "Cache:    #{cache[:path]} (#{cache[:projects]} projects, #{human_size(cache[:size_bytes])})"
    lines << "          #{stale_line(cache)}"
    lines << ''
    lines.concat(render_quarantine(data[:quarantine], plain))
  end

  def availability_line(table, plain)
    table.map do |name, ok|
      mark = ok ? '+' : '-'
      text = "#{mark}#{name}"
      next text if plain

      ok ? Rainbow(text).green : Rainbow(text).red
    end.join('  ')
  end

  def render_quarantine(cases, plain)
    return ['Quarantine: no quarantined builds.'] if cases.empty?

    lines = ["Quarantine: #{plural(cases.size, 'case')} (newest first); " \
             'show one with l --doctor NAME, remove all with l --doctor clear']
    cases.each do |c|
      head = "  #{c[:created_at].to_s[0, 16].tr('T', ' ')}  #{c[:name]}"
      lines << (plain ? head : Rainbow(head).yellow)
      lines << "    project: #{c[:project]}  engine: #{c[:engine]}"
      lines << "    trigger: #{c[:trigger]}"
      lines << "    error:   #{c[:first_error]}" if c[:first_error] && !c[:first_error].empty?
    end
    lines
  end

  def stale_line(cache)
    stale = []
    stale << "#{cache[:orphaned]} of deleted projects" if cache[:orphaned].positive?
    stale << "#{cache[:idle]} idle for more than #{cache[:cache_days]} days" if cache[:idle].positive?
    return 'no stale build directories' if stale.empty?

    "stale: #{stale.join(', ')}; removed daily after a build, or now with l --doctor prune"
  end

  def plural(count, noun)
    suffix = count == 1 ? '' : 's'
    "#{count} #{noun}#{suffix}"
  end

  def human_size(bytes)
    units = %w[B KB MB GB]
    value = bytes.to_f
    unit = units.first
    units.each do |u|
      unit = u
      break if value < 1024

      value /= 1024 unless u == units.last
    end
    format('%<v>.1f %<u>s', v: value, u: unit)
  end

  def show_case(name, io:, json:)
    found = LeeniQuarantine.cases.find { |dir, _| File.basename(dir) == name }
    unless found
      io.puts(json ? JSON.generate(error: "no quarantined build named #{name}") : "No quarantined build named #{name}.")
      return 1
    end

    dir, manifest = found
    block = error_block(dir, manifest)
    if json
      io.puts JSON.pretty_generate(manifest.merge('path' => dir, 'error_block' => block))
    else
      io.puts JSON.pretty_generate(manifest), '', "Case directory: #{dir}", ''
      io.puts(block.empty? ? 'No error block found in the pass log.' : block.join("\n"))
    end
    0
  end

  # The first `!` error block of the stored pass log, through its `l.N` line.
  def error_block(dir, manifest)
    log = File.join(dir, 'build', manifest['pass_log'].to_s)
    return [] unless File.file?(log)

    lines = File.readlines(log, chomp: true)
    start = lines.index { |l| l.start_with?('! ') }
    return [] unless start

    stop = lines[start..].index { |l| l.match?(/\Al\.\d+/) }
    lines[start..(stop ? start + stop : [start + 12, lines.size - 1].min)]
  end
end
