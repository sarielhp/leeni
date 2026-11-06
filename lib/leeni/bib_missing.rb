# frozen_string_literal: true

# ==============================================================================
# lib/leeni/bib_missing.rb
#
# --bib-missing for LatexBuilder: the build runs as usual with its stdout held
# in a buffer. A clean build prints only the cited keys that have no
# bibliography entry, one per line; a failed build replays the held output.
# ==============================================================================

require 'stringio'

module LatexBibMissing
  # --bib-missing prints only the missing keys, so it overrides the output
  # formats (any of which may come from the config) and refuses the options
  # that would build no bibliography or run another target instead.
  CLASHES = { score: '--score', single_pass: '--single-pass', zip: '--zip', verify: '--verify',
              arxiv: '--arxiv', meta_only: '--meta', bib_extract: '--bib-extract', sandbox: '--sandbox',
              make_indep: '--make-indep', deps: '--deps' }.freeze

  def self.validate_options!(options, prog_name)
    return unless options[:bib_missing]

    clashing = CLASHES.select { |key, _| options[key] }.values
    clashing << '--no-bib' if options[:bib] == false
    unless clashing.empty?
      warn "#{prog_name}: error: --bib-missing cannot be combined with #{clashing.join(', ')}"
      exit 2
    end
    options.merge!(compile: false, llm: false, agent: false, json: false, emacs: false, raw: false, trace: false)
  end

  # Cited keys the build directory's .bbl does not provide, plus the keys
  # BibTeX, Biber or biblatex reported as missing, sorted. Works on a cached
  # build too: everything comes from files the last build left behind.
  def missing_bib_keys
    fnbbl = File.join(junk_dir, "#{bfilename}.bbl")
    provided, reported = bib_manager.bbl_coverage(fnbbl)
    cited = bib_manager.current_citation_keys.reject { |k| k == '*' }.to_set
    ((cited - provided) | reported).to_a.sort
  end

  private

  def run_listing_missing_bib_keys
    @orig_stdout = $stdout
    @bib_missing_buffer = StringIO.new
    $stdout = @bib_missing_buffer
    ok = false
    ok = yield
  ensure
    $stdout = @orig_stdout
    revert_bib_missing_output! unless ok
  end

  def report_bib_missing
    missing_bib_keys.each { |key| @orig_stdout.puts key }
  end

  # Restores stdout and replays what the build printed so far, so a failure
  # reads exactly like a run without --bib-missing. Safe to call twice.
  def revert_bib_missing_output!
    return unless @bib_missing_buffer

    $stdout = @orig_stdout
    $stdout.write(@bib_missing_buffer.string)
    @bib_missing_buffer = nil
  end
end
