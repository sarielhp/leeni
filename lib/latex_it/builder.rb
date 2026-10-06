# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/builder.rb
#
# LaTeX compilation lifecycle manager, pass scheduler, junk/ directory isolation,
# bibliography handling, lockfile protection, and artifact staging.
# ==============================================================================

require 'fileutils'
require 'open3'
require 'digest'
require 'json'
require 'tmpdir'
require 'time'

require_relative 'color'
require_relative 'utils'
require_relative 'compatibility'
require_relative 'diagnostics'
require_relative 'brace_checker'
require_relative 'bib_manager'
require_relative 'build_runtime'

class LatexBuilder
  include LaTeXDiagnostics
  include LatexBuildRuntime

  attr_reader :options, :filename, :bfilename, :bdir, :engine_name, :biberr, :input_snapshots, :build_start_time

  CACHE_ENV_KEYS = %w[
    LATEXOPTS LATEXOPTIONS TEXINPUTS PDFTEXINPUTS XETEXINPUTS LUATEXINPUTS
    LUAINPUTS BIBINPUTS BSTINPUTS TEXMFHOME TEXMFCONFIG TEXMFVAR TEXMFCNF
    TEXMF TEXMFDBS TEXMFCACHE
  ].freeze

  DEFAULT_PASS_TIMEOUT = 180

  LATEX_RERUN_PATTERNS = [
    /Label\(s\) may have changed/i, /Rerun to get/i, /Please rerun LaTeX/i,
    /\bRerun\s+LaTeX/i,
    /Package rerunfilecheck Warning: File .* has changed/i, /Package ocgx2 Warning: Rerun/i
  ].freeze

  BIBLATEX_USE = /\\(?:usepackage|RequirePackage)\s*(?:\[[^\]]*\])?\s*\{[^}]*\bbiblatex\b/.freeze
  BIBLATEX_BBL_HEADER = 'biblatex bbl format'
  MAX_BIB_RUNS = 2
  MAX_INDEX_FAILURES = 2
  # TeX error context ("l.12 ...") and the trace header echo document text, which
  # can contain rerun phrases without TeX asking for a rerun.
  ECHOED_SOURCE_LINE = /\A(?:l\.\d+ |\(cd )/.freeze
  # Files whose content shifts with pagination but that never appear in *.aux
  # itself, so an aux-only comparison would miss a change in them.
  SIDE_STATE_EXTS = %w[toc lof lot out nav snm].freeze

  ProcessResultStatus = LaTeXUtils::ProcessResultStatus
  LABEL_HOOK = '\let\lit@orig@pw\protected@write' \
               '\long\def\protected@write#1#2#3{\ifx#1\@auxout\typeout{LIT_LBL:\the\inputlineno:\detokenize{#3}}\fi\lit@orig@pw{#1}{#2}{#3}}'

  BIBLATEX_HOOK = '\AtBeginDocument{\@ifpackageloaded{biblatex}{\AtEveryBibitem{\typeout{BIB_ENTRY: \thefield{entrykey}}}}{}}'

  RUNTIME_HOOK = "\\makeatletter#{LABEL_HOOK}#{BIBLATEX_HOOK}\\makeatother"

  def initialize(target, options)
    @options = options
    @bdir = File.dirname(target)
    @target_base = File.basename(target)
    @bfilename = File.basename(@target_base, '.*')
    @filename = "#{@bfilename}.tex"
    @orig_stdout = $stdout
    @engine_name = LaTeXUtils.normalize_engine(@options[:engine] || @options[:config_engine] || 'xelatex')
    @junk_dir = resolve_junk_dir
    @pdferr = "#{@junk_dir}/err_#{@engine_name}"
    @biberrbase = 'err_bib'
    @biberr = "#{@junk_dir}/#{@biberrbase}"
    @bib_manager = LaTeXBibManager.new(self)
    @explained_categories = {}
  end

  def junk_dir
    @junk_dir ||= resolve_junk_dir
  end

  def resolve_junk_dir
    opts = @options || {}
    configured = (opts[:junk_dir] || opts[:config_junk_dir]).to_s.strip.chomp('/')
    configured = configured.delete_prefix('./')
    return configured unless configured.empty?

    check_dir = @bdir && !@bdir.empty? ? File.expand_path(@bdir) : '.'
    dot_junk = File.join(check_dir, '.junk')
    reg_junk = File.join(check_dir, 'junk')
    return '.junk' if File.directory?(dot_junk) && !File.directory?(reg_junk)

    'junk'
  end

  def interactive_tty?
    $stdout.tty? && ENV['TERM'] != 'dumb' && !@options[:emacs] && !@options[:trace] && !@options[:score] && !@options[:raw] && !llm_mode? && !json_mode?
  end

  def run!
    build_dir = File.expand_path(@bdir)
    if !@options[:score] && build_dir != File.expand_path('.') && (!interactive_tty? || @options[:verbose])
      puts "      cd #{build_dir}"
    end
    Dir.chdir(build_dir) { run_in_current_directory! }
  end

  def run_in_current_directory!
    return compile_target unless @options[:score]

    @orig_stdout = $stdout
    $stdout = File.open(File::NULL, 'w')
    compile_target
  ensure
    if @options[:score]
      $stdout.close rescue nil
      $stdout = @orig_stdout
    end
  end

  private

  def compile_target
    unless File.exist?(@filename)
      warn "Error: File '#{@filename}' not found."
      exit 1
    end

    if @options[:deps]
      export_dependencies
      return true
    end

    with_lock { execute_compile_pipeline } == true
  end

  def execute_compile_pipeline
    setup_environment
    deep_clean if @options[:clean]
    paper_cleanup

    if targets_up_to_date?
      handle_cached_up_to_date_build
      return true
    end

    snapshot_build_inputs!
    FileUtils.rm_f(File.join(@junk_dir, '.build_state.json'))
    clean_pass_logs
    junk_dir_create
    discard_stale_bib_format_files
    total_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) if @options[:time]

    unless run_convergence_loop
      sync_bbl_to_root if @options[:trace]
      LaTeXIndicator.stop(clear: true, enabled: interactive_tty?)
      return false
    end

    interactive_tty? ? LaTeXIndicator.stop(clear: true) : (puts('') unless @options[:compile])
    finalize_build_outputs(total_t0)
    true
  end

  def handle_cached_up_to_date_build
    if @options[:vscode_lw]
      junk_pdf = File.join(@junk_dir, "#{@bfilename}.pdf")
      puts "Output written on #{junk_pdf} (1 page)."
      analyze_output
    elsif json_mode?
      analyze_output
    elsif llm_mode?
      analyze_output if @options[:all] || @options[:werror]
    elsif compile_mode?
      analyze_output if diagnostics_requested?
    else
      puts "      #{Rainbow("All targets (#{@bfilename}.pdf) are up-to-date.").green} (Use 'l -f' to force rebuild)"
      analyze_output if diagnostics_requested?
    end
  end

  def clean_pass_logs
    FileUtils.rm_f([@log, @loga, @biberr, @pdferr] + pass_log_files)
  end

  def finalize_build_outputs(total_t0)
    junk_pdf = File.join(@junk_dir, "#{@bfilename}.pdf")
    junk_bbl = File.join(@junk_dir, "#{@bfilename}.bbl")
    junk_synctex = File.join(@junk_dir, "#{@bfilename}.synctex.gz")

    update_target_file(junk_pdf, "#{@bfilename}.pdf", update_on_diff: @options[:update_on_diff])
    update_target_file(junk_bbl, "#{@bfilename}.bbl") if LaTeXUtils.bbl_has_entries?(junk_bbl)
    update_target_file(junk_synctex, "#{@bfilename}.synctex.gz")

    if @options[:time]
      total_t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      printf("Total Build Time: %s seconds\n", Rainbow(format('%.2f', total_t1 - total_t0)).green.bright)
    end

    puts "Output written on #{junk_pdf} (1 page)." if @options[:vscode_lw]

    analyze_output
    save_build_state!
  end

  # Re-reporting from cached log keeps cache fast and verbose flags honest.
  def diagnostics_requested?
    @options[:all] || @options[:explain] || @options[:verbose] || @options[:emacs] || @options[:compile]
  end

  def targets_up_to_date?
    return false if @options[:clean] || @options[:single_pass] || @options[:force] || @options[:score] || @options[:werror] || @options[:raw]
    return false if @options[:bib] == true

    target_pdf = "#{@bfilename}.pdf"
    return false unless File.exist?(target_pdf) && File.size(target_pdf) > 0

    state_file = File.join(@junk_dir, '.build_state.json')
    return false unless File.exist?(state_file)

    state = JSON.parse(File.read(state_file)) rescue nil
    return false unless state.is_a?(Hash) && state['target'] == target_pdf
    return false unless state['signature'] == build_signature
    return false if @options[:index] == true && index_stale?(state)

    sources = state['sources']
    return false unless sources.is_a?(Hash) && !sources.empty?

    build_time = state['saved_at'] || (File.exist?(state_file) ? File.mtime(state_file).to_i : 0)
    root_files = Dir['*.tex'].select { |f| File.file?(f) } + discover_bib_files
    return false if root_files.any? do |f|
      File.mtime(f).to_i > build_time && (!sources[f] || Digest::SHA256.file(f).hexdigest != sources[f]['sha'])
    end

    sources.all? do |path, meta|
      next false unless File.exist?(path)

      meta['sha'] && Digest::SHA256.file(path).hexdigest == meta['sha']
    end
  end

  def log_activity_start(label, message, suffix: '', first: false)
    return if @options[:compile] && !interactive_tty?

    if interactive_tty?
      LaTeXIndicator.start(message)
    else
      prefix = first ? '      ' : ', '
      print "#{prefix}#{Rainbow(label).bright}#{suffix}"
      $stdout.flush
    end
  end

  def log_pass_start(engine, pass, first: false) = log_activity_start(engine, "Building #{@bfilename}.pdf (#{engine} pass #{pass})...", suffix: " (#{pass})", first: first)
  def log_bib_start(tool, first: false) = log_activity_start(tool, "Running #{tool} on #{@bfilename}...", first: first)

  # The first run is decided by needs_bib_pass?; a repeat only when the last run
  # is provably out of date, so ordinary post-bib "may have changed" warnings
  # cannot trigger it.
  def bib_run_wanted?(bib_tool, bib_runs, pass, curr_aux)
    return false unless bib_tool && bib_runs < MAX_BIB_RUNS
    return needs_bib_pass?(bib_tool, "#{@pdferr}_#{pass}", curr_aux) if bib_runs.zero?

    bib_manager.bib_stale_since_last_run?(bib_tool, curr_aux)
  end

  def check_and_run_bib_pass(bib_tool, bib_runs, pass, curr_aux)
    return [true, false] unless bib_run_wanted?(bib_tool, bib_runs, pass, curr_aux)

    log_bib_start(bib_tool, first: false)
    [run_bib_pass(bib_tool, curr_aux), true]
  end

  def check_and_run_index_pass
    return false unless @options[:index] && needs_index_pass?

    log_index_start(first: false)
    run_index_pass || (needs_index_pass? && run_index_pass)
  end

  # A bib run only helps if another LaTeX pass can follow it, so at the pass cap
  # it is skipped (honouring -n 1) and the build is left uncacheable instead.
  def handle_convergence_bib_step(bib_runs, pass, curr_aux, can_follow)
    bib_tool = detect_bib_tool(curr_aux)
    unless can_follow
      @cacheable_build = false if bib_run_wanted?(bib_tool, bib_runs, pass, curr_aux)
      return [true, false]
    end

    _bib_ok, bib_ran_now = check_and_run_bib_pass(bib_tool, bib_runs, pass, curr_aux)
    return [false, false] if bib_fatal?

    [true, bib_ran_now]
  end

  # Exit check: a bibliography that ran but is still out of date (late-appearing
  # keys, changed .bcf, or biber still asking for a rerun) must not be cached.
  def bib_unsatisfied_at_exit?(bib_runs, pass, curr_aux)
    bib_tool = detect_bib_tool(curr_aux)
    return false unless bib_tool && bib_runs.positive?
    return true if bib_manager.bib_stale_since_last_run?(bib_tool, curr_aux)

    LaTeXUtils.safe_read("#{@pdferr}_#{pass}").match?(/Please \(re\)run Biber/i)
  end

  # junk/ persists, so a .bbl from an earlier build in the other bibliography
  # system kills pass 1 ("Missing 'biblatex' package" / "not created by
  # biblatex"), and report_errors exits before any retry is possible. A .bbl
  # whose format contradicts what the sources load is useless; if a preamble
  # elsewhere disagrees with the scan, the only cost of removing it is one extra
  # bib run.
  def discard_stale_bib_format_files
    return if @options[:bib] == false

    uses_biblatex = sources_use_biblatex?
    stale = stale_bbl_files(uses_biblatex)
    stale += biblatex_leftovers unless uses_biblatex
    FileUtils.rm_f(stale)
  end

  # A .bbl that cannot be regenerated (no bibliography database on disk) is never
  # discarded: the scan for biblatex cannot see a class or .sty loading it, and a
  # supplied .bbl (arXiv-style) would be lost for good.
  def stale_bbl_files(uses_biblatex)
    return [] if bib_files_on_disk.empty?

    [File.join(@junk_dir, "#{@bfilename}.bbl"), "#{@bfilename}.bbl"].select do |f|
      File.file?(f) && File.size(f).positive? && LaTeXUtils.safe_read(f).include?(BIBLATEX_BBL_HEADER) != uses_biblatex
    end
  end

  # Biblatex aux files hold \abx@aux@ commands that are undefined without the
  # package ("Missing \begin{document}"), so they go with the control files. This
  # only runs when no source loads biblatex, and only touches this document's aux
  # tree: other documents sharing junk/ (or \includeonly'd chapters) keep theirs.
  def biblatex_leftovers
    auxes = bib_manager.current_aux_files.select { |f| LaTeXUtils.safe_read(f).include?(LaTeXBibManager::BIBLATEX_AUX_MARKER) }
    return [] if auxes.empty? && !File.file?(File.join(@junk_dir, "#{@bfilename}.bcf"))

    auxes + %w[bcf run.xml].map { |ext| File.join(@junk_dir, "#{@bfilename}.#{ext}") }
  end

  def sources_use_biblatex?
    files = [@filename] + Dir['*.{tex,cls,sty}', '*/*.{tex,cls,sty}']
    files.uniq.any? { |f| File.file?(f) && LaTeXUtils.safe_read(f).gsub(/(?<!\\)%.*$/, '').match?(BIBLATEX_USE) }
  end

  # Digest of the pagination-dependent side files; true when it differs from the
  # previous call (the first call after loop start only records the baseline).
  def side_state_changed?
    files = SIDE_STATE_EXTS.flat_map { |ext| LaTeXUtils.glob_under(@junk_dir, "**/*.#{ext}") }.sort
    digest = Digest::SHA256.hexdigest(files.map { |f| "#{f}\0#{LaTeXUtils.safe_read(f)}" }.join("\0"))
    changed = !@side_state.nil? && digest != @side_state
    @side_state = digest
    changed
  end

  # True when the compilation state (aux plus pagination side files) has returned
  # to an earlier value other than the one just before it: more passes would only
  # repeat the cycle. History is cleared whenever a bib or index run changes the
  # inputs, since the same aux then no longer implies the same next pass.
  def aux_cycle?(seen, aux)
    digest = Digest::SHA256.hexdigest("#{aux}\0#{@side_state}")
    cycle = seen.include?(digest) && seen.last != digest
    seen << digest
    cycle
  end

  # Appends a LaTeX-style warning to the final pass log so the normal
  # diagnostics path shows it and --werror / JSON output count it.
  def report_unconverged(pass, cycling)
    @cacheable_build = false
    why = cycling ? 'the auxiliary files keep cycling between states' : "a rerun is still requested after #{pass} passes"
    msg = "\nLaTeX Warning: latex_it: build did not converge; #{why}. " \
          "References or page numbers may be stale (raise -n/--passes, max #{LaTeXUtils::MAX_PASSES}).\n"
    File.open("#{@pdferr}_#{pass}", 'a') { |f| f.write(msg) }
  end

  def run_convergence_loop
    @cacheable_build = true
    max_passes = @options[:passes] || LaTeXUtils::DEFAULT_PASSES
    pass = 0
    bib_runs = 0
    curr_aux = nil
    aux_before = compute_aux_hash
    @side_state = nil
    side_state_changed?
    seen_aux = [Digest::SHA256.hexdigest("#{aux_before}\0#{@side_state}")]

    loop do
      pass += 1
      log_pass_start(@engine_name, pass, first: pass == 1 && bib_runs.zero?)
      return false unless run_latex_pass("_#{pass}")
      break if @options[:single_pass]

      curr_aux = compute_aux_hash
      status_ok, bib_ran_now = handle_convergence_bib_step(bib_runs, pass, curr_aux, pass < max_passes)
      return false unless status_ok

      if bib_ran_now
        bib_runs += 1
        aux_before = curr_aux
        side_state_changed?
        seen_aux.clear
        next
      end

      index_ran = check_and_run_index_pass
      rerun = needs_latex_rerun?("#{@pdferr}_#{pass}", aux_before, curr_aux, side_changed: side_state_changed?) || index_ran
      aux_before = curr_aux
      seen_aux.clear if index_ran
      cycling = aux_cycle?(seen_aux, curr_aux)
      if rerun && (pass >= max_passes || cycling)
        report_unconverged(pass, cycling)
        break
      end

      break unless rerun
    end
    @cacheable_build = false if !@options[:single_pass] && bib_unsatisfied_at_exit?(bib_runs, pass, curr_aux)
    true
  end

  def log_index_start(first: false) = log_activity_start('makeindex', "Running makeindex on #{@bfilename}...", first: first)

  def needs_index_pass?
    idx = File.join(@junk_dir, "#{@bfilename}.idx")
    return false unless File.file?(idx) && File.size(idx) > 0
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
      printf(" [%s]", Rainbow(format('%.2fs', t1 - t0)).green)
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
    return false unless File.file?(idx) && File.size(idx) > 0

    ind = File.join(@junk_dir, "#{@bfilename}.ind")
    return true unless File.file?(ind)
    return Digest::SHA256.file(idx).hexdigest != state['idx_sha'] if state.is_a?(Hash) && state['idx_sha']

    File.mtime(idx) > File.mtime(ind)
  end

  def bib_files_newer_than_bbl? = bib_manager.bib_files_newer_than_bbl?

  def extract_fls_dependencies(fls_path)
    return [] unless File.exist?(fls_path)

    root_abs = File.expand_path('.')
    deps = []

    File.foreach(fls_path) do |line|
      next unless line.start_with?('INPUT ')

      path = line.sub(/\AINPUT\s+/, '').strip
      next if path.empty?

      abs = File.expand_path(path)
      if abs.start_with?(root_abs) && File.file?(abs)
        rel = abs.sub(%r{\A#{Regexp.escape(root_abs)}/?}, '')
        next if rel.start_with?("#{@junk_dir}/") || rel.start_with?('junk/') || rel.start_with?('.junk/') || rel.empty?

        deps << rel
      end
    end

    deps.uniq
  end

  def snapshot_build_inputs!
    @build_start_time = Time.now
    @input_snapshots = {}
    files = [@filename] + Dir['*.tex'].select { |f| File.file?(f) } + discover_bib_files
    fls_file = File.join(@junk_dir, "#{@bfilename}.fls")
    files.concat(extract_fls_dependencies(fls_file)) if File.exist?(fls_file)
    files.uniq.each do |f|
      next unless File.file?(f)

      @input_snapshots[f] = { mtime: File.mtime(f).to_f, sha: (Digest::SHA256.file(f).hexdigest rescue nil) }
    end
    state = JSON.parse(File.read(File.join(@junk_dir, '.build_state.json'))) rescue nil
    if state.is_a?(Hash)
      bib_manager.last_bib_citations ||= state['citations'] if state['citations'].is_a?(Array)
      bib_manager.last_bib_sources ||= state['sources'] if state['sources'].is_a?(Hash)
      bib_manager.last_bcf_sha ||= state['bcf_sha'] if state['bcf_sha']
    end
  end

  def save_build_state!
    return if @cacheable_build == false
    pdf_file = File.join(@junk_dir, "#{@bfilename}.pdf")
    return unless File.exist?(pdf_file) && File.size(pdf_file) > 0

    deps = collect_active_dependencies
    sources, tainted = inspect_source_snapshots(deps)

    if tainted
      FileUtils.rm_f(File.join(@junk_dir, '.build_state.json'))
      puts "      #{Rainbow('Note: Source files modified during compilation; re-run required.').yellow}" unless @options[:score]
      return
    end

    state = {
      'target' => "#{@bfilename}.pdf",
      'engine' => @engine_name,
      'signature' => build_signature,
      'saved_at' => Time.now.to_i,
      'sources' => sources,
      'citations' => current_citation_keys
    }
    bcf_file = File.join(@junk_dir, "#{@bfilename}.bcf")
    state['bcf_sha'] = Digest::SHA256.file(bcf_file).hexdigest if File.file?(bcf_file)
    idx_file = File.join(@junk_dir, "#{@bfilename}.idx")
    state['idx_sha'] = Digest::SHA256.file(idx_file).hexdigest if File.file?(idx_file)

    File.write(File.join(@junk_dir, '.build_state.json'), JSON.generate(state))
  rescue StandardError => e
    warn "Warning: Could not save build state: #{e.message}" if @options[:verbose]
  end

  def collect_active_dependencies
    fls_path = File.join(@junk_dir, "#{@bfilename}.fls")
    deps = extract_fls_dependencies(fls_path)
    deps << @filename if File.exist?(@filename)
    discover_bib_files.each { |b| deps << b }
    deps.uniq
  end

  def inspect_source_snapshots(deps)
    tainted = false
    sources = {}
    deps.each do |dep|
      next unless File.file?(dep)

      current_sha = Digest::SHA256.file(dep).hexdigest
      current_mtime = File.mtime(dep).to_f

      if @input_snapshots && @input_snapshots[dep]
        snap = @input_snapshots[dep]
        tainted = true if snap[:sha] && snap[:sha] != current_sha
      elsif @build_start_time && current_mtime >= @build_start_time.to_f
        tainted = true
      end

      sources[dep] = { 'mtime' => File.mtime(dep).to_i, 'sha' => current_sha }
    end
    [sources, tainted]
  end

  def build_signature
    values = CACHE_ENV_KEYS.to_h { |key| [key, ENV[key].to_s] }
    payload = {
      engine: @engine_name,
      bib: @options[:bib],
      index: @options[:index] == true,
      passes: @options[:passes],
      single_pass: @options[:single_pass] == true,
      no_env: @options[:no_env] == true,
      environment: values
    }
    Digest::SHA256.hexdigest(JSON.generate(payload))
  end

  def bib_globs = bib_manager.bib_globs
  def bib_files_on_disk = bib_manager.bib_files_on_disk

  def export_dependencies
    deps = []
    state_file = File.join(@junk_dir, '.build_state.json')
    if File.exist?(state_file)
      state = JSON.parse(File.read(state_file)) rescue nil
      deps = state['sources'].keys if state.is_a?(Hash) && state['sources'].is_a?(Hash)
    end

    fls_file = File.join(@junk_dir, "#{@bfilename}.fls")
    deps = extract_fls_dependencies(fls_file) if deps.empty? && File.exist?(fls_file)

    if deps.empty?
      with_lock do
        setup_environment
        junk_dir_create
        run_latex_pass('_1')
        deps = extract_fls_dependencies(fls_file)
      end
    end

    deps << @filename if File.exist?(@filename)
    bib_files_on_disk.each { |b| deps << b }
    deps.uniq!
    deps.sort!

    puts "#{@bfilename}.pdf: #{deps.join(' ')}"
  end

  def bib_manager
    @bib_manager ||= LaTeXBibManager.new(self)
  end

  def bib_fatal? = bib_manager.bib_fatal
  def detect_bib_tool(aux_contents = nil) = bib_manager.detect_bib_tool(aux_contents)
  def discover_bib_files(aux_contents = nil) = bib_manager.discover_bib_files(aux_contents)
  def run_bib_pass(tool, aux_contents = nil) = bib_manager.run_bib_pass(tool, aux_contents)

  def compute_aux_hash = bib_manager.compute_aux_hash

  def current_citation_keys(aux_contents = nil) = bib_manager.current_citation_keys(aux_contents)
  def needs_bib_pass?(tool, loga, aux_contents = nil) = bib_manager.needs_bib_pass?(tool, loga, aux_contents)
  def copy_style_files_for_bibtex = bib_manager.copy_style_files_for_bibtex
  def collect_bib_candidates(bibdata_str, files) = bib_manager.collect_bib_candidates(bibdata_str, files)
  def extract_aux_bib_files(aux_contents = nil) = bib_manager.extract_aux_bib_files(aux_contents)

  def needs_latex_rerun?(loga, prev_aux_hash = nil, curr_aux_hash = nil, side_changed: false)
    return true if side_changed

    curr_aux_hash ||= compute_aux_hash
    return true if prev_aux_hash && !prev_aux_hash.empty? && curr_aux_hash != prev_aux_hash
    return true if prev_aux_hash && prev_aux_hash.empty? && aux_has_cross_references?(curr_aux_hash)

    log_content = LaTeXUtils.safe_read(loga)
    latex_rerun_requested?(log_content)
  end

  def latex_rerun_requested?(log_content)
    filtered = log_content.gsub(/Package biblatex Warning: Please \(re\)run Biber.*?and rerun LaTeX afterwards\./m, '')
    filtered = filtered.lines.reject { |l| l.match?(ECHOED_SOURCE_LINE) }.join
    LATEX_RERUN_PATTERNS.any? { |pat| filtered =~ pat }
  end

  def aux_has_cross_references?(aux_hash)
    aux_hash.match?(/\\(?:newlabel|citation|@writefile)/)
  end

  def check_source_braces
    if File.file?(@filename)
      errs = LaTeXBraceChecker.check_file(@filename)
      return errs unless errs.empty?
    end

    candidates = collect_brace_check_candidates
    candidates.each do |f|
      errs = LaTeXBraceChecker.check_file(f)
      return errs unless errs.empty?
    end

    []
  rescue StandardError => e
    warn "Warning: Brace check failed: #{e.message}" if @options[:verbose]
    []
  end

  def collect_brace_check_candidates
    fls_file = File.join(@junk_dir, "#{@bfilename}.fls")
    candidates = File.exist?(fls_file) ? extract_fls_dependencies(fls_file).select { |f| f.end_with?('.tex') } : []
    candidates.concat(Dir['*.tex', '*/*.tex'].select { |f| File.file?(f) })
    patterns = @options[:exclude_source_tex] || LaTeXUtils::DEFAULT_EXCLUDE_SOURCE_PATTERNS
    candidates.uniq.reject do |f|
      f == @filename || patterns.any? { |pat| File.fnmatch?(pat, f, File::FNM_CASEFOLD | File::FNM_EXTGLOB) }
    end
  end

  def update_target_file(src, dst, update_on_diff: false)
    return unless File.exist?(src)

    if update_on_diff && File.exist?(dst) && dst.end_with?('.pdf') && LaTeXUtils.command_available?('pdftotext')
      return if pdf_text_unchanged?(src, dst)
    end

    atomic_copy(src, dst)
    puts "  Updated target: #{dst}" if update_on_diff
  end

  # The exit status used to be discarded and only the captured output compared,
  # so two failure modes both looked like "no change": a figure-only document
  # has no text layer, making both extractions the empty string, and a
  # pdftotext failure returns the same error text for both. Either one kept the
  # previous PDF in place forever. update_on_diff can be enabled globally in
  # config, so this was not limited to an explicit -d.
  def pdf_text_unchanged?(src, dst)
    txt_src, status_src = trace_or_capture_pdftotext(src)
    txt_dst, status_dst = trace_or_capture_pdftotext(dst)
    return false unless status_src.success? && status_dst.success?

    if txt_src.strip.empty?
      puts "\n  #{Rainbow('No extractable text layer; comparing bytes instead.').yellow}"
      return FileUtils.identical?(src, dst)
    end
    return false unless txt_src == txt_dst

    puts "\n  #{Rainbow(' PDF text content unchanged (skipped target overwrite) ').color(:white).bg(:magenta)}"
    true
  end

  def trace_or_capture_pdftotext(path)
    cmd = ['pdftotext', '-layout', path, '-']
    trace_command(ENV.to_h, cmd) if @options[:trace]
    out, status = Open3.capture2e(*cmd)
    trace_status(status) if @options[:trace]
    [out, status]
  end

  def atomic_copy(src, dst)
    tmp = "#{dst}.tmp.#{Process.pid}"
    FileUtils.cp(src, tmp, preserve: true)
    File.rename(tmp, dst)
  ensure
    FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
  end

  public :capture_pass_output, :update_target_file, :compute_aux_hash,
         :detect_bib_tool, :discover_bib_files, :run_bib_pass,
         :current_citation_keys, :needs_bib_pass?, :bib_files_newer_than_bbl?,
         :bib_files_on_disk, :bib_globs, :bib_fatal?
end
