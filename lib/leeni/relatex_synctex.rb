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
#
# With xelatex_preview (--xelatex-preview) leeni's own passes run XeLaTeX, whose
# SyncTeX names the right files at once, and relatex runs with --replace-pdf:
# it installs its LuaLaTeX PDF with its word-level SyncTeX in place of
# XeLaTeX's pair, only while the PDF is still the one it waited for.
# ==============================================================================

require 'fileutils'

module LeeniRelatexSynctex
  PID_FILE = 'relatex_synctex.pid'
  LOG_FILE = 'relatex_synctex.log'
  COMMAND = 'relatex'
  # Builds that are not a plain export of NAME.pdf into the working tree.
  EXCLUDING_OPTIONS = %i[no_export score bib_missing deps zip zip_alone verify sandbox arxiv make_indep meta_only bib_extract].freeze
  STATUS_TAIL_LINES = 5
  # The engine relatex builds with, and the one a preview's passes run instead.
  RELATEX_ENGINE = 'lualatex'
  PREVIEW_ENGINE = 'xelatex'
  LOG_HEADER = 'leeni: '
  MODES = {
    true => 'mode: XeLaTeX preview; relatex replaces it with its LuaLaTeX PDF and word-level SyncTeX',
    false => 'mode: relatex installs its word-level SyncTeX if its PDF is byte-identical'
  }.freeze

  module_function

  def pid_path(junk_dir) = File.join(junk_dir, PID_FILE)
  def log_path(junk_dir) = File.join(junk_dir, LOG_FILE)

  def wanted?(options, engine)
    options[:relatex_synctex] == true && engine == RELATEX_ENGINE &&
      EXCLUDING_OPTIONS.none? { |key| options[key] } && LaTeXUtils.command_available?(COMMAND)
  end

  # A preview: leeni's passes run XeLaTeX and relatex replaces their PDF.
  def preview?(options, engine) = options[:xelatex_preview] == true && wanted?(options, engine)

  # Pins one build time for leeni's passes and relatex unless the caller already did.
  def date_environment(env = ENV)
    return {} unless env['SOURCE_DATE_EPOCH'].to_s.empty?

    { 'SOURCE_DATE_EPOCH' => Time.now.to_i.to_s, 'FORCE_SOURCE_DATE' => '1' }
  end

  # The log's first line is the command, so --synctex-status can tell the mode.
  def spawn(env, junk_dir, main_file, replace_pdf: false)
    pdf = "#{File.basename(main_file, '.*')}.pdf"
    command = ['nice', '-n', '19', COMMAND, 'synctex', '.', '--main', main_file, '--for', pdf]
    command << '--replace-pdf' if replace_pdf
    File.write(log_path(junk_dir), "#{LOG_HEADER}#{command.join(' ')}\n")
    pid = Process.spawn(env, *command, in: File::NULL, out: [log_path(junk_dir), 'a'], err: %i[child out],
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

    log_lines = File.readlines(log, chomp: true)
    lines << "  #{MODES.fetch(replacing?(log_lines.first))}"
    lines + log_lines.last(STATUS_TAIL_LINES).map { |line| "  #{line}" }
  end

  def replacing?(header) = header.to_s.start_with?(LOG_HEADER) && header.split.include?('--replace-pdf')

  # LatexBuilder hooks around the build.
  module Hooks
    # Called once a rebuild is certain: stop the previous run's relatex, pin the
    # date for this build's passes, and start the new one beside them. A preview
    # pins no date: nothing is compared byte for byte, and with FORCE_SOURCE_DATE
    # XeTeX dates \today in UTC where LuaTeX uses local time (the evening's
    # preview would say tomorrow until relatex's PDF replaced it).
    def start_relatex_synctex
      engine = @relatex_document_engine || @engine_name
      return unless LeeniRelatexSynctex.wanted?(@options, engine)

      LeeniRelatexSynctex.stop(@junk_dir)
      preview = LeeniRelatexSynctex.preview?(@options, engine)
      @relatex_env = preview ? {} : LeeniRelatexSynctex.date_environment
      @relatex_pid = LeeniRelatexSynctex.spawn(pass_environment, @junk_dir, @filename, replace_pdf: preview)
    end

    # The engine leeni's passes run: XeLaTeX for a preview of a lualatex document
    # whose PDF relatex replaces; the document's engine otherwise.
    def preview_engine(engine)
      @relatex_document_engine = engine
      LeeniRelatexSynctex.preview?(@options, engine) ? PREVIEW_ENGINE : engine
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
      preview = @relatex_document_engine && @relatex_document_engine != @engine_name ? ', replaces the XeLaTeX preview' : ''
      puts "      #{Rainbow("relatex SyncTeX running in background#{preview} (log: #{log})").faint}"
    end

    def relatex_date_environment = @relatex_env || {}
  end
end
