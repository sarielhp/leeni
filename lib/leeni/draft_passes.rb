# frozen_string_literal: true

# ==============================================================================
# lib/leeni/draft_passes.rb
#
# Draft LaTeX passes (pdfTeX/LuaTeX -draftmode, XeTeX -no-pdf): the engine
# typesets and writes the aux files and the log but no PDF, which saves the
# PDF output time. A pass is a draft only when leeni knows before running it
# that another LaTeX pass will follow: a bibliography or index tool is certain
# to run after it, and the pass budget leaves room for the next pass. "Labels
# may have changed" reruns depend on the pass's own output, so those passes
# stay regular. When a draft pass turns out to be the last one (the predicted
# tool did not run, failed, or the loop stopped), one regular pass follows at
# once, so the last pass always writes the PDF.
# ==============================================================================

require 'fileutils'

module LatexDraftPasses
  DRAFT_FLAGS = { 'pdflatex' => '-draftmode', 'lualatex' => '-draftmode', 'xelatex' => '-no-pdf' }.freeze

  # The engines announce draft mode in their output; it is not a document warning.
  DRAFT_NOTICE = /^(?:pdfTeX warning: \\pdf|warning\s+\(pdf backend\): )draftmode enabled, not changing output pdf[ \t]*\n?/

  CITE_USE = /\\(?:[a-zA-Z]*cite[a-zA-Z]*\*?|nocite)\s*(?:\[[^\]]*\]\s*)*\{/
  BIB_DATABASE_USE = /\\(?:bibliography|addbibresource|addglobalbib|addsectionbib)\s*(?:\[[^\]]*\]\s*)?\{/
  BIBLIOGRAPHY_AUX = /\\bibdata\{|\\abx@aux@/
  CITATION_AUX = /\\citation\{|\\abx@aux@cite\{/
  INDEX_USE = /\\makeindex\b/
  INDEX_ENTRY = /\\index\s*\{/
  INPUT_USE = /\\(?:input|include|subfile)\s*\{([^}]+)\}/
  MAX_SCANNED_SOURCES = 200

  private

  def draft_passes_enabled?
    @options[:draft_passes] != false && !@options[:single_pass] && !@options[:raw] && DRAFT_FLAGS.key?(@engine_name)
  end

  # Why pass PASS may be a draft (:bib or :index), or nil when it must be regular.
  # Each reason is used once per loop, so a wrong prediction costs one pass at most.
  def draft_reason(pass, max_passes)
    return nil unless pass < max_passes && draft_passes_enabled?
    return :bib if pass == 1 && bib_run_certain_after_first_pass?
    return :index if !@draft_reasons_used.to_a.include?(:index) && index_run_certain_after_pass?

    nil
  end

  # The first bibliography run is decided by needs_bib_pass? after pass 1. Of its
  # reasons, three are known from the inputs alone while the sources cite from a
  # database: no bibliography yet; biblatex without an aux from an earlier pass
  # (it then always asks for Biber); or a database newer than the last run.
  def bib_run_certain_after_first_pass?
    return false if @options[:bib] == false
    return true if @options[:bib] == true
    return sources_cite_a_bib_database? if fresh_bibliography?

    previous_aux = compute_aux_hash
    previous_aux_names_bibliography?(previous_aux) && bib_manager.bib_database_changed?(previous_aux)
  end

  def fresh_bibliography?
    # Like needs_bib_pass?: a missing or empty .bbl always means a run; one
    # without entries can still cover the citations (all of them missing).
    return true unless File.size?(File.join(@junk_dir, "#{@bfilename}.bbl"))

    !File.file?(File.join(@junk_dir, "#{@bfilename}.aux")) && sources_use_biblatex?
  end

  def previous_aux_names_bibliography?(aux) = aux.match?(BIBLIOGRAPHY_AUX) && aux.match?(CITATION_AUX)

  def sources_cite_a_bib_database?
    texts = draft_source_texts
    texts.any? { |text| text.match?(BIB_DATABASE_USE) } && texts.any? { |text| text.match?(CITE_USE) }
  end

  # makeindex runs after any pass that leaves a non-empty .idx with no .ind yet.
  def index_run_certain_after_pass?
    return false unless @options[:index] && @last_idx_hash.nil? && @index_failures.to_i.zero?
    return false if File.file?(File.join(@junk_dir, "#{@bfilename}.ind"))

    texts = draft_source_texts
    texts.any? { |text| text.match?(INDEX_USE) } && texts.any? { |text| text.match?(INDEX_ENTRY) }
  end

  # The document's own sources: what the last build read (.fls), plus what the
  # main file reaches through \input, \include and \subfile. Comments are dropped.
  def draft_source_texts
    @draft_source_texts ||= draft_source_files.map { |file| LaTeXUtils.safe_read(file).gsub(/(?<!\\)%.*$/, '') }
  end

  def draft_source_files
    fls = File.join(@junk_dir, "#{@bfilename}.fls")
    recorded = File.file?(fls) ? extract_fls_dependencies(fls).select { |file| file.end_with?('.tex') } : []
    (reachable_tex_files(@filename) + recorded).uniq.select { |file| File.file?(file) }
  end

  def reachable_tex_files(main)
    queue = [main]
    found = []
    until queue.empty? || found.size >= MAX_SCANNED_SOURCES
      file = queue.shift
      next if found.include?(file) || !File.file?(file)

      found << file
      LaTeXUtils.safe_read(file).gsub(/(?<!\\)%.*$/, '').scan(INPUT_USE) { |m| queue << tex_input_path(m.first) }
    end
    found
  end

  def tex_input_path(name)
    name = name.strip
    File.extname(name).empty? ? "#{name}.tex" : name
  end

  # Runs convergence pass PASS, as a draft when the next pass is certain.
  def run_convergence_pass(pass, max_passes, first:)
    reason = draft_reason(pass, max_passes)
    @draft_reasons_used = @draft_reasons_used.to_a + [reason] if reason
    @last_pass_draft = !reason.nil?
    log_pass_start(@engine_name, pass, first: first, draft: @last_pass_draft)
    run_pass_as(pass, draft: @last_pass_draft)
  end

  # A draft pass writes no PDF, so the previous build's PDF is removed first:
  # a build that stops after a draft never leaves an old PDF looking current.
  def run_pass_as(pass, draft:)
    @draft_pass = draft
    if draft
      @draft_passes = @draft_passes.to_i + 1
      FileUtils.rm_f(File.join(@junk_dir, "#{@bfilename}.pdf"))
    end
    run_latex_pass("_#{pass}")
  ensure
    @draft_pass = false
  end

  # Returns the number of the last pass, or nil when the regular pass that a
  # draft ending the loop needs fails.
  def regular_pass_after_draft(pass)
    return pass unless @last_pass_draft

    @last_pass_draft = false
    pass += 1
    log_pass_start(@engine_name, pass)
    run_pass_as(pass, draft: false) ? pass : nil
  end

  # The build fails (a bibliography tool died), but the PDF still matches the
  # sources as far as they went, like a build without draft passes.
  def abandon_after_draft(pass)
    regular_pass_after_draft(pass)
    false
  end

  def draft_pass_flags = @draft_pass ? [DRAFT_FLAGS.fetch(@engine_name)] : []
  def strip_draft_notice(output) = @draft_pass ? output.gsub(DRAFT_NOTICE, '') : output
end
