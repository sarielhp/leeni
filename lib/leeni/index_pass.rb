# frozen_string_literal: true

# ==============================================================================
# lib/leeni/index_pass.rb
#
# makeindex runs for LatexBuilder (--index): when to run it, running it, and
# whether a cached build's index is stale.
# ==============================================================================

require 'digest'

module LatexIndexPass
  MAX_INDEX_FAILURES = 2

  private

  def check_and_run_index_pass
    return false unless @options[:index] && needs_index_pass?

    log_index_start(first: false)
    run_index_pass || (needs_index_pass? && run_index_pass)
  end

  def log_index_start(first: false) = log_activity_start('makeindex', "Running makeindex on #{@bfilename}...", first: first)

  def needs_index_pass?
    idx = File.join(@junk_dir, "#{@bfilename}.idx")
    return false unless File.file?(idx) && File.size(idx).positive?
    return false if @index_failures.to_i >= MAX_INDEX_FAILURES

    Digest::SHA256.file(idx).hexdigest != @last_idx_hash || !File.file?(File.join(@junk_dir, "#{@bfilename}.ind"))
  end

  def run_index_pass
    puts '' if @options[:trace] || @options[:raw]
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) if @options[:time]
    idx_file = File.join(@junk_dir, "#{@bfilename}.idx")
    return false unless File.file?(idx_file)

    idx_hash = Digest::SHA256.file(idx_file).hexdigest
    cmd = ['makeindex', '-q', "#{@bfilename}.idx"]
    out, status = Dir.chdir(@junk_dir) { capture_pass_output(cmd) }
    File.write(File.join(@junk_dir, "#{@bfilename}.ilg"), out) unless out.empty?

    if @options[:time]
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      printf(' [%s]', Rainbow(format('%.2fs', t1 - t0)).green)
    end
    record_index_result(status.success?, idx_hash)
  end

  # The hash is recorded only on success so a failed makeindex is retried (up to
  # MAX_INDEX_FAILURES) instead of being treated as done, and it is reported.
  def record_index_result(success, idx_hash)
    if success
      @last_idx_hash = idx_hash
      @index_failures = 0
    else
      @index_failures = @index_failures.to_i + 1
      @cacheable_build = false
      warn "\nmakeindex failed; the index may be missing or stale. See #{File.join(@junk_dir, "#{@bfilename}.ilg")}."
    end
    success
  end

  def index_stale?(state = nil)
    idx = File.join(@junk_dir, "#{@bfilename}.idx")
    return false unless File.file?(idx) && File.size(idx).positive?

    ind = File.join(@junk_dir, "#{@bfilename}.ind")
    return true unless File.file?(ind)
    return Digest::SHA256.file(idx).hexdigest != state['idx_sha'] if state.is_a?(Hash) && state['idx_sha']

    File.mtime(idx) > File.mtime(ind)
  end
end
