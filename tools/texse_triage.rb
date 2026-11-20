# frozen_string_literal: true

# The triage command of tools/texse_corpus: one LLM agent (opencode) per
# flagged document of a run, several at a time. Each copies the document to a
# scratch directory, runs TeX and leeni on it, reads the source at both lines
# and writes a report with a verdict and, when leeni is wrong, a minimal
# reproducer. The reports are for review: a verdict is checked before
# anything is fixed.
require 'json'
require 'fileutils'
require 'open3'

module TexseTriage
  DEFAULT_MODEL = 'litellm/lumen/deepseek-v4.1-flash-1017'
  VERDICTS = %w[LEENI_RIGHT LEENI_WRONG HARNESS UNSURE].freeze
  AGENT_TIMEOUT = 1500

  PROMPT = <<~TEXT
    You are triaging one flagged document for leeni, a LaTeX build tool whose diagnostics are being checked against TeX. Work in the leeni repository (cwd) but do NOT edit any repository file and do NOT commit; you only investigate and write one report.

    Document: TeX.SE question %<id>s (source in %<paper>s, metadata in %<entry>s with the engine and TeX's errors).
    Harness flag line: %<flag>s
    Flag meanings: differs = leeni's first error location differs from TeX's first error location; leeni_only = leeni reports an error but TeX's log has none in the form the harness reads; lineless = leeni's error has no line (line 0); silent = TeX failed but leeni reported nothing; llm_disagree = the -llm and --json builds disagree; crash/timeout = leeni crashed or timed out.

    Steps:
    1. Copy the paper directory to %<work>s (cp -r %<paper>s %<work>s) and work only there.
    2. In %<work>s, run TeX directly with the engine from entry.json: `<engine> -interaction=nonstopmode main.tex` (run twice if the first pass only complains about aux data); read every '!' error and the 'l.NN' line in main.log (or the file:line: form).
    3. In %<work>s, run `%<leeni>s -f -llm -e <engine> main.tex` and record its full output.
    4. Read the source around TeX's line and around leeni's line. Decide what the real fault in the document is (what the author must change), and on which line it is.
    5. Verdict, exactly one of:
       - LEENI_RIGHT: leeni's location (and category/hint) points at the real fault at least as well as TeX's.
       - LEENI_WRONG: leeni misplaces the error, misses an error TeX reports, reports a spurious error, gives a misleading hint, or reports a cascade of one fault as several errors.
       - HARNESS: the difference is an artifact of the harness or machine (missing system font, package not installed here, shell escape, run-to-run differences), not a leeni bug.
       - UNSURE.
    6. If LEENI_WRONG: say precisely what leeni should report instead, and build a MINIMAL standalone document (%<work>s/min.tex) that reproduces the same leeni misbehaviour; run leeni on it to confirm, and include both min.tex and leeni's output in the report.

    Write the report to %<report>s as markdown. Its first line is exactly "Verdict: X". Then sections: TeX errors (first 3 with lines), leeni output (first 5 lines), Real fault (file:line and one sentence), Reasoning (at most 8 lines), Minimal reproducer (only for LEENI_WRONG, with min.tex inline). Be factual; quote log lines rather than paraphrasing. Then stop.
  TEXT

  module_function

  # Triage every flagged document of a run's results (default: the newest).
  def triage(root, opts)
    results_file = opts[:batch] || Dir.glob(File.join(root, 'run-batch-*.json')).max_by { |f| f[/batch-(\d+)/, 1].to_i }
    abort 'texse_corpus: no run results; run the batch first' unless results_file

    rows = JSON.parse(File.read(results_file)).reject { |row| row['flags'].empty? }
    out = opts[:output] || File.join(root, 'triage', File.basename(results_file, '.json').sub(/\Arun-/, ''))
    FileUtils.mkdir_p(out)
    TexseCorpus.each_parallel(rows, opts[:jobs]) { |row| triage_document(root, row, out, opts) }
    summarize(rows, out)
  end

  def triage_document(root, row, out, opts)
    report = File.join(out, "#{row['id']}.md")
    return if File.file?(report) && verdict(report)

    ProjectTmp.mktmpdir('texse-triage') do |tmp|
      prompt = format(PROMPT, prompt_fields(root, row, File.join(tmp, 'work'), report))
      log, = Open3.capture2e('timeout', '-s', 'TERM', '-k', '30', AGENT_TIMEOUT.to_s,
                             'opencode', 'run', '-m', opts[:model] || DEFAULT_MODEL, prompt)
      File.write(File.join(out, "#{row['id']}.log"), log)
    end
  end

  def prompt_fields(root, row, work, report)
    dir = File.join(TexseCorpus.corpus_dir(root), row['id'])
    tex = row['tex'] ? row['tex'].values_at('file', 'line', 'message').join(':') : 'none read'
    flag = "flags=#{row['flags'].join(',')} tex=#{tex} leeni_first=#{Array(row['leeni']).first&.join(' | ')}"
    { id: row['id'], paper: File.join(dir, 'paper'), entry: File.join(dir, 'entry.json'), flag: flag,
      work: work, report: report, leeni: File.expand_path('../leeni', __dir__) }
  end

  def verdict(report)
    File.read(report)[/Verdict:\W*(#{VERDICTS.join('|')})/, 1]
  end

  def summarize(rows, out)
    verdicts = rows.to_h do |row|
      report = File.join(out, "#{row['id']}.md")
      [row['id'], File.file?(report) ? (verdict(report) || 'NO_VERDICT') : 'NO_REPORT']
    end
    puts "#{rows.size} flagged documents: #{verdicts.values.tally.sort_by { |_, n| -n }.map { |v, n| "#{v}=#{n}" }.join(' ')}"
    verdicts.sort_by { |_, v| v }.each { |id, v| puts "  #{id.ljust(7)} #{v}" }
    puts "Reports: #{out}"
  end
end
