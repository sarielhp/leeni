# frozen_string_literal: true

# ==============================================================================
# lib/leeni/relatex_synctex.rb
#
# Opt-in word-level SyncTeX from relatex (lualatex only). While leeni builds,
# a detached `relatex synctex` builds the same document with the same pinned
# date (SOURCE_DATE_EPOCH + FORCE_SOURCE_DATE); once leeni's PDF lands in the
# working tree, relatex replaces NAME.synctex.gz only if its own PDF is
# byte-identical. The process outlives leeni; its pid file and log sit in the
# project's build directory, and the next build stops it before starting.
# ==============================================================================

require 'fileutils'

module LeeniRelatexSynctex
  PID_FILE = 'relatex_synctex.pid'
  LOG_FILE = 'relatex_synctex.log'
  COMMAND = 'relatex'
  # Builds that are not a plain export of NAME.pdf into the working tree.
  EXCLUDING_OPTIONS = %i[no_export score deps zip zip_alone verify sandbox arxiv make_indep meta_only bib_extract].freeze
  STATUS_TAIL_LINES = 5

  module_function

  def pid_path(junk_dir) = File.join(junk_dir, PID_FILE)
  def log_path(junk_dir) = File.join(junk_dir, LOG_FILE)

  def wanted?(options, engine)
    options[:relatex_synctex] == true && engine == 'lualatex' &&
      EXCLUDING_OPTIONS.none? { |key| options[key] } && LaTeXUtils.command_available?(COMMAND)
  end

  # Pins one build time for leeni's passes and relatex unless the caller already did.
  def date_environment(env = ENV)
    return {} unless env['SOURCE_DATE_EPOCH'].to_s.empty?

    { 'SOURCE_DATE_EPOCH' => Time.now.to_i.to_s, 'FORCE_SOURCE_DATE' => '1' }
  end

  def spawn(env, junk_dir, main_file)
    pdf = "#{File.basename(main_file, '.*')}.pdf"
    command = ['nice', '-n', '19', COMMAND, 'synctex', '.', '--main', main_file, '--for', pdf]
    pid = Process.spawn(env, *command, in: File::NULL, out: [log_path(junk_dir), 'w'], err: %i[child out],
                                       pgroup: true)
    Process.detach(pid)
    record(junk_dir, pid)
  rescue SystemCallError => e
    warn "leeni: could not start relatex synctex: #{e.message}"
    nil
  end

  def record(junk_dir, pid)
    File.write(pid_path(junk_dir), "#{pid}\n")
    pid
  rescue SystemCallError
    pid
  end

  # Signals only a process that is still a relatex (pids get reused), and its
  # whole process group, which it leads. PID, when known, outranks the pid file.
  def stop(junk_dir, pid = nil)
    file = pid_path(junk_dir)
    pid ||= File.read(file).to_i if File.file?(file)
    FileUtils.rm_f(file)
    return false unless pid&.positive? && relatex_process?(pid)

    Process.kill('TERM', Process.getpgid(pid) == pid ? -pid : pid)
    true
  rescue Errno::ESRCH, Errno::EPERM
    false
  end

  def relatex_process?(pid)
    args = File.binread("/proc/#{pid}/cmdline").split("\0")
    args.any? { |arg| File.basename(arg) == COMMAND } && args.include?('synctex')
  rescue SystemCallError
    false
  end

  def running?(junk_dir)
    file = pid_path(junk_dir)
    File.file?(file) && relatex_process?(File.read(file).to_i)
  end

  def status_lines(junk_dir)
    log = log_path(junk_dir)
    state = running?(junk_dir) ? 'running' : 'not running'
    lines = ["relatex SyncTeX: #{state} (log: #{log})"]
    return lines + ['  no relatex SyncTeX run recorded for this project'] unless File.file?(log)

    lines + File.readlines(log, chomp: true).last(STATUS_TAIL_LINES).map { |line| "  #{line}" }
  end

  # LatexBuilder hooks around the build.
  module Hooks
    # Called once a rebuild is certain: stop the previous run's relatex, pin the
    # date for this build's passes, and start the new one beside them.
    def start_relatex_synctex
      return unless LeeniRelatexSynctex.wanted?(@options, @engine_name)

      LeeniRelatexSynctex.stop(@junk_dir)
      @relatex_env = LeeniRelatexSynctex.date_environment
      @relatex_pid = LeeniRelatexSynctex.spawn(pass_environment, @junk_dir, @filename)
    end

    # A build that did not deliver a PDF leaves relatex nothing to match.
    def finish_relatex_synctex(result)
      return unless @relatex_pid

      if result == 'ok'
        # A cache recovery may have cleaned the build directory, pid file included.
        LeeniRelatexSynctex.record(@junk_dir, @relatex_pid)
        return announce_relatex_synctex
      end

      LeeniRelatexSynctex.stop(@junk_dir, @relatex_pid)
      @relatex_pid = nil
    end

    def announce_relatex_synctex
      return if compile_mode? || @options[:json] || @options[:llm] || @options[:score]

      log = LeeniRelatexSynctex.log_path(@junk_dir)
      puts "      #{Rainbow("relatex SyncTeX running in background (log: #{log})").faint}"
    end

    def relatex_date_environment = @relatex_env || {}
  end
end
