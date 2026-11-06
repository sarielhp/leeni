# frozen_string_literal: true

# ==============================================================================
# lib/leeni/cli_options.rb
#
# The OptionParser declarations of the leeni CLI, one method per help group;
# LatexCLI.build_option_parser (in the leeni executable) calls them in order.
# Kept apart from the executable so that file stays within its size limit.
# ==============================================================================

require 'optparse'

module LatexCLI
  def self.add_compilation_options_pass(opts, options)
    opts.separator ''
    opts.separator '  Pass Control & Compilation:'
    opts.on('-f', '--force', 'Force an initial compilation run unconditionally (bypasses build cache)') { options[:force] = true }
    opts.on('--force-file', 'Force using specified .tex file even if it matches exclude_main_tex') do
      options[:force_file] = true
    end
    opts.on('-u', '--single-pass', 'Execute a single LaTeX pass only (no BibTeX/Biber or convergence passes)') do
      options[:single_pass] = true
      options[:passes] = 1
      options[:bib] = false
    end
    opts.on('-n', '--passes NUM', Integer, "Maximum number of compilation passes (1-#{LaTeXUtils::MAX_PASSES}, default: #{LaTeXUtils::DEFAULT_PASSES})") do |v|
      options[:passes] = v.clamp(1, LaTeXUtils::MAX_PASSES)
      options[:explicit_passes] = true
    end
    opts.on('-b', '--[no-]bib', 'Explicitly enable or skip bibliography pass (default: auto-detect)') { |v| options[:bib] = v }
    opts.on('--[no-]index', 'Run makeindex pass when .idx changes (default: false or config)') do |v|
      options[:index] = v
      options[:explicit_index] = true
    end
    opts.on('--[no-]draft-passes', 'Skip PDF output on passes certain to be followed by another (default: on)') do |v|
      options[:draft_passes] = v
    end
    opts.on('-i') { raise OptionParser::InvalidOption }
    opts.on('-e', '--engine ENGINE', 'Compiler engine: x (xelatex), l (lualatex), or p (pdflatex)') do |v|
      options[:engine] = LaTeXUtils.normalize_engine(v)
      options[:engine_explicit] = true
    end
    opts.on('--timeout SECONDS', Integer, 'Maximum execution timeout allowed per pass in seconds') { |v| options[:timeout] = v }
    opts.on('-T', '--time', 'Show execution wall-clock time breakdown per compilation pass') do
      options[:time] = true
      options[:explicit_time] = true
    end
  end

  def self.add_compilation_options_target(opts, options)
    opts.separator ''
    opts.separator '  Output Management & Cleaning:'
    opts.on('-c', '--clean', 'Clean build cache and regenerable root artifacts before compilation') { options[:clean] = true }
    opts.on('-C', '--clean-only', 'Clean auxiliary files in directory and exit without building') { options[:clean_only] = true }
    opts.on('--junk-dir DIR', 'Directory for build artifacts (default: $XDG_CACHE_HOME/leeni/projects)') do |v|
      options[:junk_dir] = v
      options[:explicit_junk_dir] = true
    end
    opts.on('--no-export', 'Leave the working tree untouched: outputs stay in the build directory') do
      options[:no_export] = true
    end
    opts.on('--update-if-changed', 'Only replace target PDF if extracted text changed (prevents viewer reloads)') do
      options[:update_on_diff] = true
      options[:explicit_update_on_diff] = true
    end
    opts.on('--[no-]relatex-synctex', 'With lualatex, let a background relatex replace the SyncTeX with a word-level one') do |v|
      options[:relatex_synctex] = v
      options[:explicit_relatex_synctex] = true
    end
    opts.on('--[no-]xelatex-preview', 'With --relatex-synctex, build a XeLaTeX preview that relatex replaces with its LuaLaTeX PDF') do |v|
      options[:xelatex_preview] = v
      options[:explicit_xelatex_preview] = true
    end
    opts.on('--synctex-status', 'Show whether the background relatex SyncTeX run is alive, with its log tail, and exit') do
      options[:synctex_status] = true
    end
    opts.on('--[no-]mirror-subdirs', 'Mirror project subdirectories into build directory (default: false)') do |v|
      options[:auto_mirror_subdirs] = v
    end
    opts.on('--[no-]copy-subdirs', 'Alias for --[no-]mirror-subdirs') do |v|
      options[:auto_mirror_subdirs] = v
    end
  end

  def self.add_compilation_options_diag(opts, options)
    opts.separator ''
    opts.separator '  Diagnostics & Error Filtering:'
    opts.on('-r', '--raw', 'Print raw compiler stdout/stderr during compilation passes') do
      options[:raw] = true
      options[:explicit_raw] = true
    end
    opts.on('-x', '--explain', 'Display boxed plain-English explanations and fixes for diagnostics on first occurrence') { options[:explain] = true }
    opts.on('-a', '--all', 'Show all diagnostics across all tiers (including Whatevers and Warnings)') do
      options[:all] = true
      options[:suppress_whatevers] = false
      options[:suppress_warnings] = false
      options[:suppress_alerts] = false
      options[:errors_only] = false
    end
    opts.on('--[no-]badges', 'Display visual severity badges/emojis for all diagnostics (default: on)') do |v|
      options[:badges] = v
    end
    opts.on('-W', '--werror', 'Treat compilation warnings as fatal errors and exit with non-zero status') do
      options[:werror] = true
      options[:explicit_werror] = true
    end
    opts.on('--final', 'Final-build profile: undefined references and citations, stale builds and oversized floats are errors; draft leftovers are alerts (implied by -z and --arxiv)') do
      options[:final] = true
    end
    opts.on('--errors-only', 'Suppress alerts, warnings and Whatevers; only errors cause diagnostic failure') do
      options.merge!(suppress_alerts: true, suppress_warnings: true, suppress_whatevers: true,
                     all: false, errors_only: true, werror: false, explicit_werror: true)
    end
    opts.on('-s', '--score', 'Quiet mode: suppress stdout and print only numeric error/alert/warning counts') { options[:score] = true }
    opts.on('-v', '--verbose', 'Verbose output mode (show raw overfull hbox snippet text and resolution steps)') { options[:verbose] = true }
    opts.on('--trace', 'Print exact external subprocess commands, working directory, and environment overrides') do
      options[:trace] = true
      options[:explicit_trace] = true
    end
    opts.on('--alert-hbox PT', Float, 'Overfull hbox threshold in points to classify as Alert (default: 24.0)') { |v| options[:alert_overfull_pt] = v.to_f }
    opts.on('--whatever-pt PT', Float, 'Overfull hbox threshold in points to classify as Whatever (default: 2.5)') { |v| options[:whatever_overfull_pt] = v.to_f }
    opts.on('--context NUM', Integer, 'Show NUM lines of surrounding source context for diagnostics') do |v|
      options[:context_lines] = v.to_i
      options[:explicit_context_lines] = true
    end
  end

  def self.add_compilation_options_bundle(opts, options)
    opts.separator ''
    opts.separator '  Paper Bundling, Bibliography & Portability:'
    opts.on('-z', '--zip', 'Create a self-contained portable zip archive of paper, styles, and figures') { options[:zip] = true }
    opts.on('--zip-alone', 'Bundle styles and verify an isolated rebuild with no errors or alerts and matching PDF') do
      options.merge!(zip_alone: true, zip: true, inject_styles: true, verify: true, force: true)
    end
    opts.on('--sandbox', 'After building, rebuild from an isolated copy with --no-env (kept in the cache) and compare the PDFs') do
      options[:sandbox] = true
      options[:inject_styles] = true
    end
    opts.on('-Z', '--zip-flat', 'Create a self-contained portable zip archive with inlined/flattened .tex') do
      options[:zip] = true
      options[:zip_flat] = true
    end
    opts.on('-t', '--verify', 'Check the zip contents in the cache sandbox with --no-env before zipping them') do
      options[:verify] = true
      options[:zip] = true
    end
    opts.on('--zip-name NAME', 'Specify custom output filename for generated zip archive') do |v|
      options[:zip] = true
      options[:zip_name] = v
    end
    opts.on('-B', '--bib-extract', 'Extract cited bibliography entries into local .bib file (default: <doc>.bib)') { options[:bib_extract] = true }
    opts.on('--bib-name NAME', 'Specify custom output filename for extracted bibliography') do |v|
      options[:bib_extract] = true
      options[:bib_extract_name] = v
    end
    opts.on('--bib-fix', 'Build; add missing entries and @string macros to the local .bib from bib_fix_sources and BIBINPUTS') do
      options[:bib_fix] = true
    end
    opts.on('--bib-missing', 'Build; print only the keys of cited entries missing from the bibliography (regular output on errors)') { options[:bib_missing] = true }
    opts.on('-I', '--make-indep', 'Convert the paper in place to compile with --no-env: copy external styles to styles/, extract cited entries to <doc>.bib; originals saved in old_ver_yy_mm_dd_hh_mm.zip') do
      options[:make_indep] = true
    end
    opts.on('--dry-run', 'With -I or --bib-fix: show the changes without making them') do
      options[:dry_run] = true
    end
    opts.on('--[no-]styles-inject', 'Enable or disable isolating harvested styles into styles/ and injecting \input@path') do |v|
      options[:inject_styles] = v
      options[:explicit_styles_inject] = true
    end
  end

  def self.add_compilation_options_env(opts, options)
    opts.separator ''
    opts.separator '  Environment, Theming & Configuration:'
    opts.on('--[no-]color', 'Enable or disable colored terminal output (default: auto)') { |v| options[:color] = v }
    opts.on('--[no-]link', 'Enable or disable clickable terminal hyperlinks (default: auto-detect)') do |v|
      options[:link] = v
    end
    opts.on('--theme THEME', 'Set diagnostic color theme (e.g. blush, catppuccin, or "+1" to cycle)') { |v| options[:theme_arg] = v }
    opts.on('--theme-list', 'List available diagnostic color themes with previews and exit') { options[:list_themes] = true }
    opts.on('--[no-]lock', 'Enable or disable lockfile concurrency protection (default: enabled)') { |v| options[:lock] = v }
    opts.on('--no-env', 'Reset environment variables used by LaTeX/BibTeX/Biber') { options[:no_env] = true }
    opts.on('--emacs', 'Format warnings/errors for Emacs AUCTeX integration (suppress line prefixes)') do
      options[:emacs] = true
      options[:emacs_explicit] = true
      options[:explicit_emacs] = true
    end
    sw = OptionParser::Switch::NoArgument.new(
      nil,
      proc { options[:compile] = true },
      ['-cc'],
      ['--compile'],
      nil,
      ['Format diagnostics in GNU standard compiler format (file:line:col: severity: message)']
    )
    opts.top.append(sw, [], ['compile'])
    opts.on('--llm', '--agent', 'Format diagnostics for LLMs and AI agents (plaintext, folded warnings, silent success)') do
      options[:llm] = true
      options[:compile] = true
      options[:color] = false
      options[:link] = false
    end
    opts.on('--json', 'Output structured compilation and diagnostic results as JSON') do
      options[:json] = true
      options[:compile] = true
      options[:color] = false
      options[:link] = false
    end
    opts.on('--config-init', 'Create a local .l.jsonc configuration template in the current directory and exit') do
      LaTeXConfig.create_local_template!('.')
      exit 0
    end
    opts.on('--set-main-file FILE', 'Set main LaTeX document in local .l.jsonc configuration and exit') do |file|
      options[:set_main_file] = file
    end
    opts.on('--report [LEVEL]', 'Write a problem-report bundle for the document (diagnostics, build logs, environment; LEVEL "full" adds the sources) and exit') do |v|
      options[:report] = v || 'basic'
    end
    opts.on('--doctor [TARGET]', 'Report engines, helper tools, cache state and quarantined builds and exit; TARGET names a case to show, "clear" removes the cases, "prune" removes stale build directories') do |v|
      options[:doctor] = v || true
    end
    opts.on('--config-show', 'Show active configuration sources and resolved settings and exit') { options[:show_config] = true }
    opts.on('--config-save', 'Save specified CLI option choices to configuration file (default: local .l.jsonc)') do
      options[:config_save] = true
    end
    opts.on('--config-unset KEY', 'Remove a saved setting from local or global configuration and exit') do |key|
      options[:config_unset] = key
    end
    opts.on('--global', 'Target global configuration (~/.config/leeni/config.jsonc) for config operations') do
      options[:config_scope] = :global
    end
    opts.on('--local', 'Target local configuration (./.l.jsonc) for config operations (default)') do
      options[:config_scope] = :local
    end
    opts.on('--vscode-init', 'Create VS Code tasks.json and settings.json in .vscode/ and exit') do
      LaTeXConfig.create_vscode_template!('.')
      exit 0
    end
    opts.on('--vscode-lw', 'Format diagnostics for VS Code LaTeX Workshop extension') do
      options[:compile] = true
      options[:vscode_lw] = true
      options[:color] = false
    end
    opts.on('--gitignore-init', 'Create or add standard LaTeX and junk/ ignore rules to .gitignore and exit') do
      LaTeXConfig.init_gitignore!('.')
      exit 0
    end
  end

  def self.add_arxiv_options(opts, options)
    opts.on('--arxiv', 'Prepare sanitized, flattened, submission-ready arXiv zip package') { options[:arxiv] = true }
    opts.on('--arxiv-name NAME', 'Specify custom output name for arXiv zip package') do |v|
      options[:arxiv] = true
      options[:arxiv_name] = v
    end
    opts.on('--meta', 'Extract and display sanitized paper metadata and write arxiv_<file>_meta.txt') { options[:meta_only] = true }
    opts.on('--[no-]arxiv-verify', 'Enable/disable sandbox compile plus exact PDF text verification (default: true)') { |v| options[:arxiv_verify] = v }
    opts.on('--[no-]arxiv-visual-verify', 'Enable/disable rendered PDF page verification (default: true; requires pdftoppm)') { |v| options[:arxiv_visual_verify] = v }
    opts.on('--[no-]biblatex-shield', 'Enable or disable bundling local biblatex distribution files (default: true)') { |v| options[:biblatex_shield] = v }
  end

  def self.add_general_options(opts, options)
    opts.separator ''
    opts.separator 'General Options:'
    opts.on('-m', '--main', 'Print the detected main LaTeX root file and exit without compiling') { options[:show_main] = true }
    opts.on('-M', '--deps', 'Print Makefile dependency rule for the document and exit') { options[:deps] = true }
    opts.on('-V', '--version', 'Show version and exit') do
      puts "leeni #{Leeni::VERSION}"
      exit 0
    end
    opts.on('-E', '--examples', 'Show detailed usage examples and common workflows') { options[:show_examples] = true }
    opts.on('-h', '--help', 'Show condensed help summary (see -H for all options)') { options[:show_help] = true }
    opts.on('-H', '--help-all', 'Show comprehensive manual of all options with detailed descriptions and examples') { options[:show_help_all] = true }
    opts.on('--help-style STYLE', %w[plain lines], 'Help display style: plain (default) or lines (subdued dividers)') { |v| options[:help_style] = v }
  end
end
