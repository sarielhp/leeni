# frozen_string_literal: true

# ==============================================================================
# lib/leeni/project_record.rb
#
# `project.json` in every build directory: what leeni knows about a project
# that the build state does not say. Where the sources live, which main file
# and engine were used, when it was first and last built, how the last builds
# went. Written atomically at build start and end, kept by `l -c`, read by
# the cache pruner, --doctor and --report. A missing or damaged record is a
# convenience lost, never a build failure.
# ==============================================================================

require 'fileutils'
require 'json'
require 'time'
require_relative 'version'

module LeeniProjectRecord
  FILE = 'project.json'
  FORMAT = 1
  HISTORY = 5
  SUCCESSES = %w[ok up_to_date].freeze

  module_function

  def path(build_dir)
    File.join(build_dir, FILE)
  end

  def read(build_dir)
    file = path(build_dir)
    return nil unless File.file?(file)

    data = JSON.parse(File.read(file))
    data.is_a?(Hash) ? data : nil
  rescue JSON::ParserError, SystemCallError
    nil
  end

  # Write-then-rename, so a reader never sees a half-written record.
  def write(build_dir, record)
    FileUtils.mkdir_p(build_dir)
    tmp = "#{path(build_dir)}.#{Process.pid}.tmp"
    File.write(tmp, JSON.pretty_generate(record))
    File.rename(tmp, path(build_dir))
    record
  rescue SystemCallError
    FileUtils.rm_f(tmp) if tmp
    nil
  end

  def update(build_dir)
    record = read(build_dir) || {}
    yield record
    write(build_dir, record)
  end

  # Called once the build directory exists and the engine is known.
  def start!(build_dir, project:, main_file:, engine:, now: Time.now)
    update(build_dir) do |r|
      r['format'] = FORMAT
      r['project'] = project
      r['main_file'] = main_file
      r['engine'] = engine
      r['leeni_version'] = Leeni::VERSION
      r['created_at'] ||= now.iso8601
      r['runs'] = r['runs'].to_i + 1
      r['last_build'] = { 'started_at' => now.iso8601, 'result' => 'running' }
    end
  end

  # `result` is ok, up_to_date, failed or interrupted.
  def finish!(build_dir, result:, passes: 0, duration: nil, recovered: false, now: Time.now)
    update(build_dir) do |r|
      last = (r['last_build'] || {}).merge('finished_at' => now.iso8601, 'result' => result, 'passes' => passes)
      last['duration_s'] = duration.round(2) if duration
      last['recovered'] = true if recovered
      r['last_build'] = last
      r['builds'] = r['builds'].to_i + 1 unless result == 'up_to_date'
      r['failures'] = r['failures'].to_i + 1 if result == 'failed'
      r['recoveries'] = r['recoveries'].to_i + 1 if recovered
      r['last_success_at'] = now.iso8601 if SUCCESSES.include?(result)
      r['history'] = (Array(r['history']) << last).last(HISTORY)
    end
  end

  def touch_report!(build_dir, now: Time.now)
    update(build_dir) { |r| r['last_report_at'] = now.iso8601 }
  end

  # The newest timestamp the record carries, or nil for an empty record.
  def last_activity(record)
    stamps = [record.dig('last_build', 'finished_at'), record.dig('last_build', 'started_at'),
              record['last_report_at'], record['created_at']]
    stamps.compact.filter_map { |s| parse_time(s) }.max
  end

  def parse_time(text)
    Time.iso8601(text.to_s)
  rescue ArgumentError
    nil
  end
end
