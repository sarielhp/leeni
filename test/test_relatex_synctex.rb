#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'leeni_test_support'

# The background `relatex synctex` run: started for lualatex builds when enabled
# and relatex is on PATH, left running on success, stopped on failure and by the
# next build. A stub relatex records its arguments and environment and waits.
class TestRelatexSynctex < LeeniTestBase
  STUB = <<~RUBY
    #!/usr/bin/env ruby
    puts "args: \#{ARGV.join(' ')}"
    puts "date: \#{ENV['SOURCE_DATE_EPOCH']} \#{ENV['FORCE_SOURCE_DATE']} tz=\#{ENV['TZ']}"
    $stdout.flush
    Signal.trap('TERM') { puts 'got TERM'; $stdout.flush; exit 0 }
    sleep 30
  RUBY

  def setup
    super
    @saved_env = ENV.to_h.slice('PATH', 'SOURCE_DATE_EPOCH', 'FORCE_SOURCE_DATE', 'TZ')
    @dir = Dir.mktmpdir('leeni-relatex-')
    @bin = File.join(@dir, 'bin')
    FileUtils.mkdir_p([@bin, File.join(@dir, 'paper', 'junk')])
    File.write(File.join(@bin, 'relatex'), STUB)
    File.chmod(0o755, File.join(@bin, 'relatex'))
    File.write(File.join(@dir, 'paper', 'paper.tex'), "\\documentclass{article}\\begin{document}x\\end{document}\n")
    ENV['PATH'] = "#{@bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH', nil)}"
    ENV.delete('SOURCE_DATE_EPOCH')
    ENV.delete('FORCE_SOURCE_DATE')
    @pids = []
  end

  def teardown
    @pids.each { |pid| Process.kill('KILL', -pid) rescue nil } # rubocop:disable Style/RescueModifier
    %w[PATH SOURCE_DATE_EPOCH FORCE_SOURCE_DATE TZ].each { |key| ENV[key] = @saved_env[key] }
    FileUtils.rm_rf(@dir)
    super
  end

  def in_paper(&) = Dir.chdir(File.join(@dir, 'paper'), &)

  def builder(options = {})
    b = legacy_builder('paper.tex', { relatex_synctex: true, engine: 'lualatex' }.merge(options))
    b.instance_variable_set(:@engine_name, b.engine_name)
    b
  end

  def start(builder)
    builder.send(:start_relatex_synctex)
    pid = builder.instance_variable_get(:@relatex_pid)
    @pids << pid if pid
    pid
  end

  def wait_for(timeout = 10)
    deadline = Time.now + timeout
    sleep 0.05 until yield || Time.now > deadline
    yield
  end

  def log_text = LaTeXUtils.safe_read(File.join('junk', LeeniRelatexSynctex::LOG_FILE))
  def alive?(pid) = LeeniRelatexSynctex.relatex_process?(pid)

  def test_success_path_spawns_detached_relatex_and_keeps_it
    in_paper do
      b = builder
      pid = start(b)
      assert pid, 'relatex must be spawned'
      assert_equal Process.getpgid(pid), pid, 'relatex leads its own process group'
      assert(wait_for { log_text.include?('args:') })
      assert_includes log_text, 'args: synctex . --main paper.tex --for paper.pdf'
      out, = capture_io { b.send(:finish_relatex_synctex, 'ok') }
      assert_includes strip_ansi(out), 'relatex SyncTeX running in background (log: junk/relatex_synctex.log)'
      assert alive?(pid)
      assert_equal pid, File.read('junk/relatex_synctex.pid').to_i
      assert_equal 'running', LeeniRelatexSynctex.status_lines('junk').first[/running/]
    end
  end

  def test_failed_build_stops_relatex_and_removes_pid_file
    in_paper do
      b = builder
      pid = start(b)
      assert(wait_for { log_text.include?('args:') })
      b.send(:finish_relatex_synctex, 'failed')
      assert wait_for { !alive?(pid) }, 'relatex must be stopped after a failed build'
      refute File.exist?('junk/relatex_synctex.pid')
      assert(wait_for { log_text.include?('got TERM') })
    end
  end

  def test_next_build_stops_previous_run
    in_paper do
      first = start(builder)
      assert(wait_for { log_text.include?('args:') })
      second = start(builder)
      refute_equal first, second
      assert wait_for { !alive?(first) }, 'the previous relatex must be stopped'
      assert alive?(second)
      assert_equal second, File.read('junk/relatex_synctex.pid').to_i
    end
  end

  def test_stop_leaves_a_reused_pid_that_is_not_relatex_alone
    in_paper do
      other = Process.spawn('sleep', '30', pgroup: true)
      @pids << other
      File.write('junk/relatex_synctex.pid', "#{other}\n")
      refute LeeniRelatexSynctex.stop('junk')
      assert_nil Process.waitpid(other, Process::WNOHANG), 'a non-relatex process must not be signalled'
      refute File.exist?('junk/relatex_synctex.pid')
    end
  end

  def test_shared_date_reaches_passes_and_relatex
    ENV['TZ'] = 'UTC'
    in_paper do
      b = builder
      start(b)
      env = b.send(:pass_environment)
      epoch = env.fetch('SOURCE_DATE_EPOCH')
      assert_equal '1', env['FORCE_SOURCE_DATE']
      assert(wait_for { log_text.include?('date:') })
      assert_includes log_text, "date: #{epoch} 1 tz=UTC"
    end
  end

  def test_existing_source_date_epoch_is_kept
    ENV['SOURCE_DATE_EPOCH'] = '1234567890'
    assert_empty LeeniRelatexSynctex.date_environment
    in_paper do
      b = builder
      start(b)
      assert_equal '1234567890', b.send(:pass_environment)['SOURCE_DATE_EPOCH']
      assert(wait_for { log_text.include?('date:') })
      assert_includes log_text, 'date: 1234567890  tz='
    end
  end

  def test_disabled_cases_spawn_nothing
    in_paper do
      [{ engine: 'xelatex' }, { engine: 'pdflatex' }, { relatex_synctex: false }, { no_export: true },
       { zip: true }, { arxiv: true }].each do |options|
        b = builder(options)
        assert_nil start(b), "no relatex for #{options}"
        assert_empty b.send(:relatex_date_environment)
      end
      refute File.exist?('junk/relatex_synctex.pid')
    end
  end

  def test_disabled_when_relatex_is_not_on_path
    dirs = ENV['PATH'].split(File::PATH_SEPARATOR).reject { |dir| File.executable?(File.join(dir, 'relatex')) }
    ENV['PATH'] = dirs.join(File::PATH_SEPARATOR)
    refute LaTeXUtils.command_available?('relatex')
    in_paper { assert_nil start(builder) }
  end

  def test_cli_flag_and_config_key
    parse = lambda do |cfg, argv|
      options = LatexCLI.build_default_options(cfg, 'l', [])
      LatexCLI.normalize_argv!(argv)
      LatexCLI.build_option_parser(options).parse!(argv)
      options
    end
    refute parse.call({}, [])[:relatex_synctex]
    assert parse.call({ 'relatex_synctex' => true }, [])[:relatex_synctex]
    assert parse.call({}, %w[--relatex-synctex])[:relatex_synctex]
    refute parse.call({ 'relatex_synctex' => true }, %w[--no-relatex-synctex])[:relatex_synctex]
    assert parse.call({}, %w[--synctex-status])[:synctex_status]
  end

  def test_status_without_a_run
    in_paper do
      lines = LeeniRelatexSynctex.status_lines('junk')
      assert_match(/not running/, lines.first)
      assert_match(/no relatex SyncTeX run recorded/, lines.last)
    end
  end

  # --xelatex-preview: the passes run xelatex, relatex gets --replace-pdf, and
  # --synctex-status names the mode.
  def test_xelatex_preview_runs_xelatex_and_lets_relatex_replace_the_pdf
    in_paper do
      b = builder(xelatex_preview: true)
      assert_equal 'xelatex', b.send(:preview_engine, 'lualatex')
      b.instance_variable_set(:@engine_name, 'xelatex')
      start(b)
      assert(wait_for { log_text.include?('args:') })
      assert_includes log_text, 'args: synctex . --main paper.tex --for paper.pdf --replace-pdf'
      assert_empty b.send(:relatex_date_environment), 'a preview pins no date'
      assert_match(/XeLaTeX preview; relatex replaces it/, LeeniRelatexSynctex.status_lines('junk')[1])
      out, = capture_io { b.send(:finish_relatex_synctex, 'ok') }
      assert_includes strip_ansi(out), 'relatex SyncTeX running in background, replaces the XeLaTeX preview'
    end
  end

  def test_identity_mode_is_named_and_passes_keep_lualatex
    in_paper do
      b = builder
      assert_equal 'lualatex', b.send(:preview_engine, 'lualatex')
      start(b)
      assert(wait_for { log_text.include?('args:') })
      refute_includes log_text, '--replace-pdf'
      assert_match(/byte-identical/, LeeniRelatexSynctex.status_lines('junk')[1])
    end
  end

  def test_xelatex_preview_needs_relatex_synctex_and_lualatex
    in_paper do
      [{ relatex_synctex: false }, { engine: 'pdflatex' }].each do |options|
        b = builder(options.merge(xelatex_preview: true))
        assert_equal b.engine_name, b.send(:preview_engine, b.engine_name), "no preview for #{options}"
      end
    end
  end

  def test_xelatex_preview_flag_and_config_key
    parse = lambda do |cfg, argv|
      options = LatexCLI.build_default_options(cfg, 'l', [])
      LatexCLI.normalize_argv!(argv)
      LatexCLI.build_option_parser(options).parse!(argv)
      options
    end
    refute parse.call({}, [])[:xelatex_preview]
    assert parse.call({ 'xelatex_preview' => true }, [])[:xelatex_preview]
    assert parse.call({}, %w[--xelatex-preview])[:xelatex_preview]
    refute parse.call({ 'xelatex_preview' => true }, %w[--no-xelatex-preview])[:xelatex_preview]
  end
end
