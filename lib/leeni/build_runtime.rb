# frozen_string_literal: true

# ==============================================================================
# lib/leeni/build_runtime.rb
#
# Runtime services for LatexBuilder: locking, workspace preparation, compiler
# process execution, timeouts, and individual LaTeX passes.
# ==============================================================================

module LatexBuildRuntime
  private

  def canonical_build_dir
    target_dir = @bdir ? File.expand_path(@bdir) : Dir.pwd
    File.realpath(target_dir)
  rescue StandardError
    target_dir
  end

  def path_hash
    @path_hash ||= Digest::SHA256.hexdigest(canonical_build_dir)[0..15]
  end

  def project_tmp_dir
    @project_tmp_dir ||= begin
      dir = File.join(Dir.tmpdir, "leeni_#{Process.uid}")
      Dir.mkdir(dir, 0o700) unless File.directory?(dir)
      verify_private_dir!(dir)
      dir
    end
  end

  # The lock directory name is predictable. Refuse a directory that another
  # user could control, otherwise a malicious lock-file symlink could redirect
  # the truncating open performed by with_lock.
  def verify_private_dir!(dir)
    stat = File.lstat(dir)
    return if stat.directory? && !stat.symlink? && stat.uid == Process.uid && stat.mode.nobits?(0o077)

    abort "leeni: refusing to use #{dir}: not a private directory owned by uid #{Process.uid}"
  end

  def project_tmp_file(suffix)
    File.join(project_tmp_dir, "#{path_hash}_#{@bfilename}_#{suffix}")
  end

  def with_lock
    return yield unless @options[:lock]

    lock_file = project_tmp_file('build.lock')
    nofollow = defined?(File::NOFOLLOW) ? File::NOFOLLOW : 0
    File.open(lock_file, File::RDWR | File::CREAT | nofollow, 0o600) do |file|
      wait_for_build_lock(file)
      write_lock_metadata(file)
      yield
    ensure
      file.flock(File::LOCK_UN)
    end
  end

  def wait_for_build_lock(file)
    return if file.flock(File::LOCK_EX | File::LOCK_NB)

    unless @options[:score]
      puts "      #{Rainbow("Another leeni process is running for #{@bfilename}. Waiting for it to finish...").yellow}"
    end
    file.flock(File::LOCK_EX)
  end

  def write_lock_metadata(file)
    file.truncate(0)
    file.puts "pid: #{Process.pid}\nstarted: #{Time.now.iso8601}\ntarget: #{File.expand_path(@filename)}"
    file.flush
  end

  def setup_environment
    junk_dir_create
    LaTeXUtils.reset_latex_environment! if @options[:no_env]

    @engine_name = resolve_engine
    LaTeXUtils.check_program(@engine_name)
    @latex_flags = %w[-interaction=nonstopmode -synctex=1 -no-mktex=tfm -recorder] +
                   ["-output-directory=#{@junk_dir}", '-file-line-error']
    @pdferr = "#{@junk_dir}/err_#{@engine_name}"
    @biberr = "#{@junk_dir}/err_bib"
    @log = "#{@junk_dir}/log.txt"
    @loga = "#{@junk_dir}/log.txt.1"
  end

  def resolve_engine
    file_engine = LaTeXUtils.detect_engine_from_file(@filename)
    candidate_engine = @options[:engine] || ENV['PDFBINONLY'] || file_engine ||
                       @options[:config_engine] || ENV['PDFBIN'] || ENV['LATEX_ENGINE'] || 'xelatex'
    requested_engine = LaTeXUtils.normalize_engine(candidate_engine)
    pdflatex_reasons = LaTeXUtils.source_pdflatex_reasons(@filename)
    incompatible = %w[xelatex lualatex].include?(requested_engine) && !pdflatex_reasons.empty?
    return requested_engine unless incompatible

    explain_engine_fallback(requested_engine, pdflatex_reasons.join(' and '))
  end

  def explain_engine_fallback(requested_engine, reason)
    if @options[:engine_explicit]
      puts Rainbow(" -- Source uses #{reason}; #{requested_engine} may fail. Recommended: -e pdflatex").yellow
      return requested_engine
    end

    puts Rainbow(" -- Source uses #{reason}; selecting pdflatex automatically.").cyan
    LaTeXUtils.compatible_engine(requested_engine, @filename)
  end

  # project.json bookkeeping around the pipeline body.
  def record_build_start
    @build_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @build_result = 'interrupted'
    LeeniProjectRecord.start!(@junk_dir, project: File.expand_path('.'), main_file: @filename, engine: @engine_name)
  end

  def record_build_finish
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @build_started
    LeeniProjectRecord.finish!(@junk_dir, result: @build_result, passes: @latex_passes.to_i, duration: duration,
                                          recovered: @recovered == true)
  end

  def junk_dir_create
    dir = junk_dir
    FileUtils.mkdir_p(dir, mode: 0o700)
    FileUtils.mkdir_p(File.join(dir, File.basename(dir)), mode: 0o700) unless dir.start_with?(File::SEPARATOR)
    File.write(File.join(dir, '.leeni_workspace'), LeeniBuildWorkspace.project_root)
    target_subdirs = (@options && @options[:junk_subdirs]) || LaTeXUtils::DEFAULT_JUNK_SUBDIRS
    target_subdirs.each { |subdir| FileUtils.mkdir_p(File.join(dir, subdir), mode: 0o700) }
    mirror_project_subdirs_to_junk if @options && @options[:auto_mirror_subdirs] == true
  end

  def mirror_project_subdirs_to_junk
    dir = junk_dir
    project_root = File.expand_path('.')
    workspace_abs = File.expand_path(dir)
    workspace_child = workspace_abs.delete_prefix(project_root + File::SEPARATOR).split(File::SEPARATOR).first
    Dir.glob('*/').each do |entry|
      clean_dir = entry.chomp('/')
      next if clean_dir == workspace_child || clean_dir.start_with?('junk', '.', 'backup')

      FileUtils.mkdir_p(File.join(dir, clean_dir), mode: 0o700)
    end
  end

  def deep_clean
    LaTeXUtils.clean_directory('.', true, workspace_dir: @junk_dir)
  end

  def paper_cleanup
    copy_root_aux_to_junk
    sync_bbl_before_compile
    return if @options[:no_export]

    remove_root_auxiliary_files

    root_bbl = "#{@bfilename}.bbl"
    FileUtils.rm_f(root_bbl) if File.exist?(root_bbl) && !LaTeXUtils.bbl_has_entries?(root_bbl)
  end

  def copy_root_aux_to_junk
    root_aux = "#{@bfilename}.aux"
    junk_aux = File.join(@junk_dir, root_aux)
    return unless File.exist?(root_aux) && !File.exist?(junk_aux)

    FileUtils.mkdir_p(@junk_dir)
    FileUtils.cp(root_aux, junk_aux, preserve: true)
  end

  def remove_root_auxiliary_files
    extensions = %w[.ps .blg .dvi .thm .aux .idx .ind .ilg .log .out .vtc .bcf .run.xml]
    files = extensions.map { |extension| "#{@bfilename}#{extension}" }
    (files + %w[texput.log missfont.log mfput.log]).each { |file| FileUtils.rm_f(file) }
  end

  def sync_bbl_before_compile
    root_bbl = "#{@bfilename}.bbl"
    junk_bbl = File.join(@junk_dir, root_bbl)
    if File.exist?(root_bbl) && LaTeXUtils.bbl_has_entries?(root_bbl)
      FileUtils.mkdir_p(@junk_dir)
      FileUtils.cp(root_bbl, junk_bbl, preserve: true) if newer_root_bbl?(root_bbl, junk_bbl)
    elsif restore_root_bbl?(root_bbl, junk_bbl)
      FileUtils.cp(junk_bbl, root_bbl, preserve: true)
    end
  end

  def restore_root_bbl?(root_bbl, junk_bbl)
    @options[:trace] && !@options[:no_export] && File.exist?(junk_bbl) && !File.exist?(root_bbl) &&
      LaTeXUtils.bbl_has_entries?(junk_bbl)
  end

  # With --no-export the build directory is leeni's own and the working tree only an input:
  # a root .bbl (one shipped with the sources) seeds a build directory that has none, and
  # never replaces the bibliography a build made. A caller may hand over a fresh copy of
  # the sources each time, newer than every build, so a newer root .bbl means nothing there.
  def newer_root_bbl?(root_bbl, junk_bbl)
    return true unless File.exist?(junk_bbl)

    !@options[:no_export] && File.mtime(root_bbl) > File.mtime(junk_bbl)
  end

  def sync_bbl_to_root
    junk_bbl = File.join(@junk_dir, "#{@bfilename}.bbl")
    root_bbl = "#{@bfilename}.bbl"
    return unless File.exist?(junk_bbl) && LaTeXUtils.bbl_has_entries?(junk_bbl)

    update_target_file(junk_bbl, root_bbl)
  end

  def pass_environment
    env = LaTeXCompatibility.compiler_environment(@options, ENV.to_h, @filename).dup
    env['max_print_line'] ||= '2048'
    env
  end

  def kill_process_group(pid)
    pgid = Process.getpgid(pid)
    Process.kill('-KILL', pgid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  ensure
    terminate_process(pid)
  end

  def terminate_process(pid)
    begin
      Process.kill('KILL', pid)
    rescue Errno::ESRCH
      nil
    end
    begin
      Process.waitpid(pid, Process::WNOHANG)
    rescue Errno::ECHILD
      nil
    end
  end

  def shell_quote(str) = LaTeXUtils.shell_quote(str)
  def format_trace_command(env, cmd, cwd = Dir.pwd) = LaTeXUtils.format_trace_command(env, cmd, cwd)
  def trace_command(env, cmd, cwd = Dir.pwd) = LaTeXUtils.trace_command(env, cmd, cwd)
  def trace_status(status) = LaTeXUtils.trace_status(status)

  def capture_pass_output(cmd_args)
    timeout = (@options[:timeout] || ENV['LEENI_TIMEOUT'] || ENV['LATEX_IT_TIMEOUT'] || self.class::DEFAULT_PASS_TIMEOUT).to_i
    env = pass_environment
    trace_command(env, cmd_args) if @options[:trace]
    out, status = capture_command(env, cmd_args, timeout)
    trace_status(status) if @options[:trace]
    $stdout.puts out if @options[:raw]
    [out, status]
  rescue Errno::ENOENT
    raise
  rescue StandardError => e
    err_status = self.class::ProcessResultStatus.new(1, false, nil, false)
    trace_status(err_status) if @options[:trace]
    ["\n! Process Error: #{e.message}\n", err_status]
  end

  def capture_command(env, cmd_args, timeout)
    return Open3.capture2e(env, *cmd_args) if timeout <= 0

    capture_with_timeout(env, cmd_args, timeout)
  end

  def capture_with_timeout(env, cmd_args, timeout)
    Open3.popen2e(env, *cmd_args, pgroup: true) do |stdin, stdout_err, wait_thread|
      stdin.close
      output = +''
      reader = Thread.new { read_process_output(stdout_err, output) }
      return timeout_result(wait_thread, reader, timeout) unless wait_thread.join(timeout)

      reader.join(2.0) || reader.kill
      [output, wait_thread.value]
    ensure
      kill_process_group(wait_thread.pid) if wait_thread&.alive?
      reader&.kill
    end
  end

  def read_process_output(stream, output)
    loop { output << stream.readpartial(65_536) }
  rescue IOError
    nil
  end

  def timeout_result(wait_thread, reader, timeout)
    kill_process_group(wait_thread.pid)
    reader.kill
    message = "\n! LaTeX Error: Compilation timed out after #{timeout}s (suspected runaway loop).\n"
    [message, self.class::ProcessResultStatus.new(124, false, nil, false)]
  end

  def run_latex_pass(suffix)
    @latex_passes = @latex_passes.to_i + 1
    puts '' if @options[:trace] || @options[:raw]
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC) if @options[:time]
    pass_log = "#{@pdferr}#{suffix}"
    FileUtils.rm_f(pass_log)

    command = build_latex_pass_cmd
    write_pass_header(pass_log, command)
    output, status = capture_pass_output(command)
    exit_status = process_exit_status(status)
    File.open(pass_log, 'a') { |file| file.write(output) }
    report_process_failure(status, exit_status)
    handle_pass_errors(exit_status, pass_log)
    File.open(@log, 'a') { |file| file.write(output) }
    print_pass_time(started) if @options[:time]
    status.success?
  end

  def process_exit_status(status)
    return status.exitstatus if status.exitstatus
    return 128 + status.termsig if status.respond_to?(:termsig) && status.termsig

    1
  end

  def report_process_failure(status, exit_status)
    if status.respond_to?(:signaled?) && status.signaled?
      LaTeXIndicator.stop(clear: true, enabled: interactive_tty?)
      warn "\nLaTeX engine terminated by signal #{status.termsig} (fatal crash).\n"
      return
    end
    return unless exit_status.positive?

    LaTeXIndicator.stop(clear: true, enabled: interactive_tty?)
    return if interactive_tty? || @options[:compile]

    puts ": #{format_compilation_failure(exit_status)}"
    $stdout.flush
  end

  def print_pass_time(started)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    printf(' [%s]', Rainbow(format('%.2fs', elapsed)).green)
  end

  def build_latex_pass_cmd
    latexopts = ENV['LATEXOPTS'] || ''
    latexoptions = ENV['LATEXOPTIONS'] || ''
    prefix = latexoptions.empty? ? latexopts : "#{latexoptions} "
    input = "#{prefix}#{self.class::RUNTIME_HOOK}\\input{#{@filename}}"
    [@engine_name] + @latex_flags + [input]
  end

  def write_pass_header(pass_log, command)
    File.open(pass_log, 'a') do |file|
      file.puts '========================================'
      file.puts format_trace_command(pass_environment, command)
      file.puts '========================================'
      file.puts Time.now.strftime('%a %b %d %H:%M:%S %Z %Y')
      file.puts '========================================'
    end
  end

  def handle_pass_errors(exit_status, pass_log)
    error_count = count_errors_in_log(exit_status, pass_log)
    return unless error_count.positive?

    failure = @recovered ? nil : cache_failure(pass_log)
    raise failure if failure

    announce_detected_failure if exit_status.zero?
    if @options[:score]
      output_score(pass_log, exit_status)
      exit 1
    end
    report_errors(pass_log)
  end

  # The first error of the pass sits in a generated file (.aux, .toc, .bbl,
  # ...): the cache, not the source, is at fault. A .bbl error traced back to
  # a .bib entry is the user's and is excluded.
  def cache_failure(pass_log)
    content = LaTeXUtils.filter_subcommand_noise(LaTeXUtils.safe_read(pass_log))
    first = extract_errors(content).first
    return nil unless first && LeeniQuarantine.generated_file?(first[:file]) && !first[:bib_entry]

    LeeniQuarantine::CacheFailure.new(
      "error inside generated file #{File.basename(first[:file].to_s)}",
      first[:text].to_s.lines.first.to_s.strip, pass_log
    )
  end

  # A failure inside generated files is the cache's fault, not the source's:
  # keep the evidence as a quarantine case, clean, and rebuild once. A second
  # failure in the same run is reported as usual.
  def run_convergence_loop_with_recovery
    run_convergence_loop
  rescue LeeniQuarantine::CacheFailure => e
    @recovered = true
    repeat = LeeniQuarantine.recent_case_for?('.')
    @recovery_case = quarantine_build(e)
    announce_recovery(e, repeat)
    LaTeXUtils.clean_directory('.', false, workspace_dir: @junk_dir)
    junk_dir_create
    discard_stale_bib_format_files
    run_convergence_loop
  end

  def quarantine_build(failure)
    sources = extract_fls_dependencies(File.join(@junk_dir, "#{@bfilename}.fls"))
    sources = [@filename] if sources.empty?
    LeeniQuarantine.store(project_dir: '.', main_file: @filename, junk_dir: @junk_dir, engine: @engine_name,
                          failure: failure, sources: sources)
  rescue StandardError => e
    warn "Warning: could not store the quarantine case: #{e.message}" if @options[:verbose]
    nil
  end

  def announce_recovery(failure, repeat)
    LaTeXIndicator.stop(clear: true, enabled: interactive_tty?)
    return if json_mode?

    msg = "Build failed with an #{failure.trigger}; cleaned the build directory and rebuilt."
    msg += " Case kept at #{@recovery_case}." if @recovery_case
    msg += ' Second recovery for this project within a week; run l --doctor.' if repeat
    if compile_mode?
      warn "leeni: note: #{msg}"
    else
      puts "\n#{Rainbow(msg).yellow}"
    end
  end

  # TeX exits 0 on some malformed input (an unclosed group at \end), so the
  # failure banner is keyed on the detected error count rather than the status.
  def announce_detected_failure
    LaTeXIndicator.stop(clear: true, enabled: interactive_tty?)
    return if interactive_tty? || @options[:compile]

    puts ": #{format_compilation_failure('0, error detected by leeni')}"
    $stdout.flush
  end

  def format_compilation_failure(status)
    message = if @options && @options[:color] == false
                'Latex compilation failed!'
              else
                Rainbow('Latex compilation failed!').red.bright
              end
    "#{message} (Status: #{status})"
  end

  def format_engine_crash(signal)
    message = if @options && @options[:color] == false
                'Latex engine terminated by signal'
              else
                Rainbow('Latex engine terminated by signal').red.bright
              end
    "#{message} #{signal} (fatal crash)"
  end
end
