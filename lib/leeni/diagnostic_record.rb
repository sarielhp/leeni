# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostic_record.rb
#
# Canonical structured diagnostic data models.
# ==============================================================================

require 'json'

module Leeni
  DiagnosticRecord = Struct.new(
    :file,
    :line,
    :col,
    :tier,
    :category,
    :message,
    :token,
    :root_cause,
    :did_you_mean,
    :hint,
    :why,
    :fix,
    :doc_slug,
    :index,
    :repeat_count,
    keyword_init: true
  ) do
    def to_h
      super.compact
    end

    def error?
      t = tier.to_s
      %w[error errors].include?(t)
    end

    def alert?
      t = tier.to_s
      %w[alert alerts].include?(t)
    end

    def warning?
      t = tier.to_s
      %w[warning warnings].include?(t)
    end

    def whatever?
      t = tier.to_s
      %w[whatever whatevers].include?(t)
    end
  end

  DiagnosticResult = Struct.new(
    :success,
    :exit_code,
    :pdf_path,
    :records,
    :summary,
    :folded_counts,
    :log_tail,
    :build,
    keyword_init: true
  ) do
    def initialize(*)
      super
      self.records ||= []
      self.summary ||= { errors: 0, alerts: 0, warnings: 0, whatevers: 0 }
      self.folded_counts ||= {}
    end

    def to_h
      {
        success: success,
        exit_code: exit_code,
        pdf_path: pdf_path,
        summary: summary,
        diagnostics: records.map(&:to_h),
        folded_counts: folded_counts,
        log_tail: log_tail,
        build: build
      }.compact
    end

    def to_json(*args)
      JSON.generate(to_h, *args)
    end
  end
end

LaTeXDiagnosticRecord = Leeni::DiagnosticRecord
LaTeXDiagnosticResult = Leeni::DiagnosticResult
