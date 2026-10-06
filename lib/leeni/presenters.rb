# frozen_string_literal: true

# ==============================================================================
# lib/leeni/presenters.rb
#
# Audience-specific diagnostic presenters:
# - LaTeXCompilerPresenter: GNU compile-mode standard (file:line:col: severity: msg)
# - LaTeXAgentPresenter: Token-optimized plaintext for LLMs & autonomous agents
# - LaTeXJsonPresenter: Machine-readable JSON output for APIs and MCP
# ==============================================================================

require_relative 'compile_format'
require_relative 'diagnostic_record'

module Leeni
  module Presenters
    # Base helper for category normalization
    def self.classify_category(record)
      cat = record[:category]&.to_sym
      return :undefined_citation if cat == :undefined_citation
      return :undefined_reference if cat == :undefined_reference
      return :overfull_box if cat.to_s =~ /overfull/
      return :underfull_box if cat.to_s =~ /underfull/

      msg = record[:message].to_s
      if msg =~ /undefined citation/i
        :undefined_citation
      elsif msg =~ /undefined reference/i
        :undefined_reference
      elsif msg =~ /too wide|overfull \\hbox|overfull \\vbox/i
        :overfull_box
      elsif msg =~ /underfull \\hbox|underfull \\vbox|too narrow/i
        :underfull_box
      elsif record[:tier].to_s == 'errors' || record[:tier].to_s == 'error'
        :compiler_error
      else
        cat || :general_warning
      end
    end

    def self.category_name(cat)
      case cat
      when :undefined_citation then 'undefined citations'
      when :undefined_reference then 'undefined references'
      when :overfull_box then 'overfull box alerts'
      when :underfull_box then 'underfull box notes'
      else 'diagnostics'
      end
    end
  end

  class CompilerPresenter
    def initialize(options = {})
      @options = options
    end

    def render_record(record, io: $stderr)
      color = @options[:color] != false
      link = @options[:link] == true
      line = LaTeXCompileFormat.render(record, color: color, link: link)
      io.puts line
      line
    end

    def render_diagnostics(records, io: $stderr)
      records.each { |r| render_record(r, io: io) }
      records.size
    end
  end

  class AgentPresenter
    DEFAULT_FOLD_THRESHOLD = 2
    MAX_ERRORS_SHOWN = 5

    def initialize(options = {})
      @options = options
      @fold_threshold = options[:fold_threshold] || DEFAULT_FOLD_THRESHOLD
    end

    def render_diagnostics(errors: [], alerts: [], warnings: [], whatevers: [], log_tail: nil, file: nil, io: $stderr)
      # 1. When errors are present, suppress warnings/alerts completely to focus attention
      if errors.any?
        render_errors(errors, file: file, io: io)
        return
      end

      # 2. When compilation failed with 0 parsed errors, output actionable log tail
      if log_tail && !log_tail.empty? && errors.empty?
        render_unparsed_failure(log_tail, file: file, io: io)
        return
      end

      # 3. Suppress all diagnostics if clean (no alerts or warnings)
      active_warnings = alerts + warnings
      return if active_warnings.empty? && (!@options[:all] || whatevers.empty?)

      # 4. Render folded warnings and alerts
      render_folded_tiers(active_warnings, whatevers, show_all: @options[:all] == true, io: io)
    end

    def render_errors(errors, file: nil, io: $stderr)
      primary_errors = errors.first(MAX_ERRORS_SHOWN)
      primary_errors.each do |err|
        io.puts LaTeXCompileFormat.render(err, color: false, link: false)
      end

      remaining = errors.size - primary_errors.size
      if remaining > 0
        primary_file = primary_errors.first[:file] || file || 'document'
        io.puts "leeni: note: #{remaining} more errors in #{primary_file} truncated (resolve initial errors first)"
      end
    end

    def render_unparsed_failure(log_tail, file: nil, io: $stderr)
      target_file = file || 'document.tex'
      io.puts "#{target_file}:1: error: compilation failed with unclassified error"
      io.puts "#{target_file}:1: note: compiler log tail:"
      log_tail.lines.last(8).each do |l|
        clean_l = l.strip
        io.puts "> #{clean_l}" unless clean_l.empty?
      end
    end

    def render_folded_tiers(warnings_and_alerts, whatevers, show_all: false, io: $stderr)
      # Group by category
      groups = warnings_and_alerts.group_by { |rec| Presenters.classify_category(rec) }
      folds = {}

      groups.each do |cat, items|
        if should_fold_category?(cat) && !show_all
          visible = items.first(@fold_threshold)
          remainder = items.size - visible.size
          visible.each { |rec| io.puts LaTeXCompileFormat.render(rec, color: false, link: false) }
          if remainder > 0
            file_name = items.first[:file] || 'document.tex'
            name = Presenters.category_name(cat)
            io.puts "leeni: note: #{remainder} more #{name} in #{file_name} (pass -a to show all)"
            folds[cat] = remainder
          end
        else
          items.each { |rec| io.puts LaTeXCompileFormat.render(rec, color: false, link: false) }
        end
      end

      # Whatevers (underfull boxes) are emitted only if show_all is true
      if show_all
        whatevers.each { |rec| io.puts LaTeXCompileFormat.render(rec, color: false, link: false) }
      end

      folds
    end

    def should_fold_category?(cat)
      %i[undefined_citation undefined_reference overfull_box underfull_box].include?(cat)
    end
  end

  class JsonPresenter
    def initialize(options = {})
      @options = options
    end

    def render_result(result, io: $stdout)
      json = result.is_a?(DiagnosticResult) ? result.to_json : JSON.generate(result)
      io.puts json
      json
    end
  end
end

LaTeXCompilerPresenter = Leeni::CompilerPresenter
LaTeXAgentPresenter = Leeni::AgentPresenter
LaTeXJsonPresenter = Leeni::JsonPresenter
