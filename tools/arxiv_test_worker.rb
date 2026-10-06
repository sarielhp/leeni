#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'time'

# Internal worker for test_arxiv. Runs only in the workspace staged by bws_run.
module ArxivTestWorker
  class CheckError < StandardError; end

  COMMAND_TIMEOUT = 900 # seconds; per external command
  ALL_CHECKS = %w[environment fresh_build unchanged_rerun fast_rerun single_pass
                  settle_after_single_pass pdf_diff settle_before_dependency
                  dependency_change dependency_rerun invalid_tex recovery
                  metadata portable_archive arxiv_archive].freeze

  class Runner
    def initialize(root)
      ENV['LANG'] = ENV['LC_ALL'] = 'C.UTF-8'
      Encoding.default_external = Encoding::UTF_8 unless Encoding.default_external == Encoding::UTF_8
      @root = root
      cfg_path = File.join(root, 'test-config.json')
      raise CheckError, "#{cfg_path}: config file not found" unless File.file?(cfg_path)

      @config = JSON.parse(File.read(cfg_path))
      main_entry = @config['main'] or
        raise CheckError, %(#{cfg_path}: missing required key "main" (path to the entry .tex, relative to paper/))

      @engine = @config['engine']
      @main = File.join(root, 'paper', main_entry)
      @project = File.dirname(@main)
      @pdf = @main.sub(/\.tex\z/i, '.pdf')
      @latex = File.join(root, 'leeni')
      raise CheckError, "#{@latex}: leeni was not staged into the workspace" unless File.file?(@latex)

      @logs = File.join(root, 'test-logs')
      @counter = File.join(@logs, 'engine-invocations.jsonl')
      FileUtils.mkdir_p(@logs)
      @restores = {}
      install_signal_traps
      @report = { status: 'RUNNING', completed: false, main: main_entry, engine: @engine || 'automatic',
                  leeni_sha256: Digest::SHA256.file(@latex).hexdigest, locale: 'C.UTF-8', checks: [] }
      save
    end

    def install_signal_traps
      return unless Thread.current == Thread.main

      %w[INT TERM HUP].each do |sig|
        Signal.trap(sig) do
          restore_all
          exit!(130)
        end
      rescue ArgumentError
        nil
      end
    end

    def with_original(path)
      @restores[path] = [File.binread(path), File.stat(path)]
      yield
    ensure
      restore_one(path)
    end

    def restore_one(path)
      entry = @restores.delete(path)
      return unless entry

      body, stat = entry
      File.binwrite(path, body)
      File.utime(stat.atime, stat.mtime, path)
    end

    def restore_all
      @restores.keys.each do |p|
        restore_one(p)
      rescue SystemCallError
        nil
      end
    end

    def read_text(path)
      File.binread(path).force_encoding(Encoding::UTF_8).scrub('?')
    end

    def run
      ready = check('environment') { prepare }
      built = ready && check('fresh_build') do
        FileUtils.rm_f(@pdf)
        result = compile
        require_success(result)
        assert(result[:passes].positive?, 'fresh build did not invoke the compiler')
        assert(File.file?(@pdf) && File.binread(@pdf, 5) == '%PDF-', 'build did not produce a PDF')
        text = command(['pdftotext', '-layout', @pdf, File.join(@logs, 'reference.txt')])
        require_success(text)
        { detail: 'Fresh compilation produced a readable PDF.', **result }
      end
      if built
        exercise_build
        check('metadata') { metadata }
        check('portable_archive') { package('--zip', '--verify') }
        check('arxiv_archive') { package('--arxiv', '--arxiv-verify', '--arxiv-visual-verify') }
      else
        executed = @report[:checks].map { |c| c[:name] }
        (ALL_CHECKS - executed).each do |name|
          record(name, 'SKIP', detail: 'Requires a successful fresh build.')
        end
      end
      @report[:completed] = true
      @report[:status] = @report[:checks].all? { |c| c[:status] == 'PASS' } ? 'PASS' : 'FAIL'
      save
      @report[:status] == 'PASS' ? 0 : 1
    rescue Exception => e # ruby-audit: allow-rescue-exception (re-raises SignalException after recording report)
      @report[:status] = 'ERROR'
      @report[:completed] = true
      @report[:error] = "#{e.class}: #{e.message}"
      @report[:backtrace] = e.backtrace&.first(15)
      save
      warn "#{e.class}: #{e.message}"
      raise if e.is_a?(SignalException)

      2
    end

    def prepare
      candidates = @engine ? [@engine] : %w[xelatex lualatex pdflatex]
      real_engine = candidates.lazy.map { |e| executable(e) }.find(&:itself)
      assert(real_engine,
             "No LaTeX engine found on PATH (looked for #{candidates.join(', ')}); " \
             'install TeX Live or set "engine" in test-config.json.')
      required = %w[pdftotext pdftoppm zip unzip]
      missing = required.reject { |name| executable(name) }
      assert(missing.empty?, "Missing tools: #{missing.join(', ')} (poppler-utils / zip provide these)")

      engine_out, engine_st = Open3.capture2e(real_engine, '--version')
      assert(engine_st.success?,
             "#{real_engine} --version failed (exit #{engine_st.exitstatus}): #{engine_out.lines.first}")
      @report[:engine_version] = engine_out.lines.first.to_s.strip

      latex_out, latex_st = Open3.capture2e(RbConfig.ruby, @latex, '--version')
      assert(latex_st.success?,
             "#{@latex} --version failed (exit #{latex_st.exitstatus}): #{latex_out.lines.first(3).join}")
      @report[:leeni_version] = latex_out.strip

      install_engine_wrappers(candidates)
      { detail: 'Required tools available; compiler invocations recorded independently.' }
    end

    def install_engine_wrappers(candidates)
      wrappers = File.join(@root, 'test-engine-bin')
      FileUtils.mkdir_p(wrappers)
      candidates.each do |engine|
        real_engine = executable(engine)
        next unless real_engine

        wrapper = "#!/usr/bin/env ruby\nrequire 'json'\n" \
                  "File.open(#{@counter.dump}, 'a') { |f| f.puts(JSON.generate(ARGV)) }\n" \
                  "exec(#{real_engine.dump}, *ARGV)\n"
        path = File.join(wrappers, engine)
        File.write(path, wrapper)
        File.chmod(0o755, path)
      end
      ENV['PATH'] = "#{wrappers}:#{ENV.fetch('PATH')}"
    end

    def executable(name)
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
         .find { |path| File.file?(path) && File.executable?(path) }
    end

    def exercise_build
      check('unchanged_rerun') { unchanged }
      check('fast_rerun') { unchanged('--fast') }
      check('single_pass') do
        result = compile('--single-pass')
        require_success(result)
        assert(result[:passes] == 1, "Expected exactly one compiler pass; got #{result[:passes]}")
        result
      end
      check('settle_after_single_pass') { require_success(compile) }
      check('pdf_diff') { diff }
      change_dependency
      failure_recovery
    end

    def unchanged(*flags)
      before = pdf_state
      result = compile(*flags)
      require_success(result)
      assert(result[:passes].zero?, "Unchanged input caused #{result[:passes]} compiler passes")
      assert(before == pdf_state, 'Unchanged rerun replaced the PDF')
      result.merge(detail: 'Zero compiler passes; PDF hash and modification time unchanged.')
    end

    def diff
      before = pdf_state
      result = compile('--single-pass', '--update-if-changed')
      require_success(result)
      assert(result[:passes] == 1, 'Diff test did not perform its forced compiler pass')
      assert(before == pdf_state, 'Text-identical forced build replaced the PDF')
      result.merge(detail: 'Forced rebuild preserved PDF hash and modification time.')
    end

    def dependency
      recorder = File.join(@project, 'junk', File.basename(@main, File.extname(@main)) + '.fls')
      paths = if File.file?(recorder)
                read_text(recorder).each_line.grep(/^INPUT /).map do |line|
                  line.delete_prefix('INPUT ').strip
                end
              else
                []
              end
      paths.map { |path| File.expand_path(path, @project) }.find do |path|
        path != @main && path.start_with?(File.join(@root, 'paper') + '/') &&
          !path.include?('/junk/') && path.end_with?('.tex') && File.file?(path)
      end || @main
    end

    def change_dependency
      settled = check('settle_before_dependency') { require_success(compile) }
      return record('dependency_change', 'SKIP', detail: 'Could not establish baseline.') unless settled

      path = dependency
      with_original(path) do
        stat = @restores[path][1]
        check('dependency_change') do
          original = @restores[path][0]
          probe = "\n% leeni dependency probe\n% %%leeni-probe\n"
          File.binwrite(path, original + probe)
          File.utime(stat.atime, stat.mtime, path)
          result = compile
          require_success(result)
          assert(result[:passes].positive?, 'Changed source with preserved mtime was incorrectly cached')
          result.merge(detail: "Rebuilt after changing #{path.delete_prefix(@root + '/')} with its mtime preserved.")
        end
        check('dependency_rerun') { unchanged }
      end
    end

    def failure_recovery
      with_original(@main) do
        check('invalid_tex') do
          original = @restores[@main][0]
          probe = "\\latexItDeliberatelyUndefinedProbe\n% %%leeni-probe\n"
          File.binwrite(@main, probe + original)
          result = compile
          assert(result[:passes].positive?, 'Invalid-input check never invoked the compiler')
          assert(result[:exit_status].positive? && result[:exit_status] < 128,
                 "Expected a clean nonzero exit; got #{result[:exit_status]} " \
                 "(signal death or crash) — see #{result[:log]}")
          if result[:log] && File.file?(result[:log])
            assert(read_text(result[:log]).include?('latexItDeliberatelyUndefinedProbe'),
                   "Compiler failed for a reason unrelated to the probe; see #{result[:log]}")
          end
          result.merge(detail: 'Deliberately invalid TeX correctly returned a nonzero exit status.')
        end
        restore_one(@main)
        check('recovery') do
          result = compile
          require_success(result)
          assert(result[:passes].positive?, 'Recovery incorrectly reused the failed build cache')
          result
        end
      end
    end

    def metadata
      load File.join(@root, 'tools', 'check_arxiv_metadata')
      reference = ArxivMetadataReport.reference_metadata(JSON.parse(File.read(File.join(@root, 'metadata.json'))))
      content = ArxivMetadataReport.utf8(File.binread(@main))
      extracted = { title: LaTeXMetaExtractor.extract_title(content),
                    authors: LaTeXMetaExtractor.extract_author_names(content),
                    abstract: LaTeXMetaExtractor.extract_abstract(content) }
      comparisons = ArxivMetadataReport.compare_metadata(reference, extracted)
      pdf = ArxivMetadataReport.check_pdf(@pdf, reference[:authors])
      details = { comparisons: comparisons, pdf: pdf }
      File.write(File.join(@logs, 'metadata.json'), JSON.pretty_generate(details) + "\n")
      matched = %i[title authors].all? { |key| comparisons[key][:status] == 'match' } && pdf[:status] == 'match'
      assert(matched,
             'arXiv title/authors or PDF page-one authors differ; see test-logs/metadata.json. Source metadata can legitimately differ.')
      { detail: 'Extracted title/authors match arXiv metadata; reference authors appear on PDF page one.',
        metadata: details }
    end

    def package(*flags)
      result = compile(*flags)
      require_success(result)
      output = read_text(result[:log])
      assert(output.include?('[VERIFIED]'), 'Command succeeded without confirming archive verification')
      if flags.include?('--arxiv')
        assert(output.match?(/visual|pixel|rendered/i) && !output.match?(/visual.*skip/i),
               'arXiv visual verification did not run')
      end
      result.merge(detail: if flags.include?('--arxiv')
                             'arXiv rebuild, text, author and rendered-page checks passed.'
                           else
                             'Portable archive rebuilt and passed PDF text comparison.'
                           end)
    end

    def pdf_state
      [Digest::SHA256.file(@pdf).hexdigest, File.stat(@pdf).mtime.to_r.to_s]
    end

    def compile(*flags)
      args = [RbConfig.ruby, @latex, '--emacs']
      args += ['--engine', @engine] if @engine
      command([*args, *flags, File.basename(@main)])
    end

    def command(argv, timeout: COMMAND_TIMEOUT)
      before = File.file?(@counter) ? File.foreach(@counter).count : 0
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @command_index = (@command_index || 0) + 1
      log = File.join(@logs, format('%02d-%s.log', @command_index, @active_check))
      @last_command = { command: argv, log: log }
      pid = Process.spawn(*argv, chdir: @project, in: File::NULL,
                          out: log, err: %i[child out], pgroup: true)
      status = wait_bounded(pid, timeout, log)
      after = File.file?(@counter) ? File.foreach(@counter).count : 0
      @last_command.merge!(exit_status: status.exitstatus || (128 + status.termsig),
                           elapsed: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
                           passes: after - before)
      @last_command.dup
    end

    def wait_bounded(pid, timeout, log)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        _, status = Process.waitpid2(pid, Process::WNOHANG)
        return status if status

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          reap(pid)
          raise CheckError, "timed out after #{timeout}s; see #{log}"
        end
        sleep 0.05
      end
    rescue Exception # ruby-audit: allow-rescue-exception (reaps child process before re-raising)
      reap(pid)
      raise
    end

    def reap(pid)
      Process.kill('TERM', -pid)
      20.times do
        return if Process.waitpid(pid, Process::WNOHANG)

        sleep 0.1
      end
      Process.kill('KILL', -pid)
      Process.waitpid(pid)
    rescue Errno::ESRCH, Errno::ECHILD, Errno::EPERM
      nil
    end

    def require_success(result)
      assert(result[:exit_status].zero?, "Command exited #{result[:exit_status]}; see #{result[:log]}")
      result
    end

    def assert(condition, message)
      raise CheckError, message unless condition
    end

    def check(name)
      @active_check = name
      @last_command = {}
      @report[:running_check] = name
      save
      result = yield
      record(name, 'PASS', **(result || {}))
      true
    rescue StandardError, ScriptError => e
      record(name, 'FAIL', **@last_command, detail: "#{e.class}: #{e.message}")
      false
    end

    def record(name, status, **details)
      @report[:checks] << details.merge(name: name, status: status)
      @report.delete(:running_check)
      save
      puts "#{status}: #{name}#{details[:detail] ? ' — ' + details[:detail] : ''}"
      $stdout.flush
    end

    def save
      @report[:updated_at] = Time.now.utc.iso8601
      path = File.join(@root, 'test-worker-report.json')
      tmp = "#{path}.tmp"
      File.write(tmp, JSON.pretty_generate(@report) + "\n")
      File.rename(tmp, path)
    rescue SystemCallError => e
      FileUtils.rm_f(tmp) rescue nil
      warn "arxiv_test_worker: could not persist report: #{e.message}"
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    exit ArxivTestWorker::Runner.new(Dir.pwd).run
  rescue StandardError, ScriptError => e
    report_path = File.join(Dir.pwd, 'test-worker-report.json')
    File.write(report_path,
               JSON.pretty_generate(status: 'ERROR', completed: true,
                                    error: "#{e.class}: #{e.message}",
                                    backtrace: e.backtrace&.first(10),
                                    updated_at: Time.now.utc.iso8601) + "\n")
    warn "arxiv_test_worker: #{e.class}: #{e.message}"
    exit 2
  end
end
