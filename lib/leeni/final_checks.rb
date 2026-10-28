# frozen_string_literal: true

# ==============================================================================
# lib/leeni/final_checks.rb
#
# Source scan for the --final profile: drafting aids that are fine while
# writing and wrong in a submitted document. Each hit is an alert item in the
# same shape as the brace checker's label alerts.
# ==============================================================================

require_relative 'utils'

module LaTeXFinalChecks
  LINE_CHECKS = [
    [/\\includeonly\s*\{/, '\\includeonly restricts the build to the listed chapters'],
    [/\\documentclass\s*\[[^\]]*\bdraft\b[^\]]*\]/, 'documentclass option draft boxes out figures and marks overfull lines'],
    [/\\usepackage\s*\[[^\]]*\bdraft\b[^\]]*\]\s*\{[^}]*\bgraphicx\b/, 'graphicx option draft replaces every figure with a box'],
    [/\\linenumbers\b/, '\\linenumbers numbers every line of the document']
  ].freeze

  DRAFT_PACKAGES = {
    'showkeys' => 'prints every label key in the margin',
    'todonotes' => 'renders pending notes in the margin',
    'draftwatermark' => 'stamps a watermark on every page',
    'refcheck' => 'marks labels and citations in the margin'
  }.freeze

  PACKAGE_PATTERN = /\\(?:usepackage|RequirePackage)\s*(\[[^\]]*\])?\s*\{([^}]*)\}/

  def self.scan(path)
    alerts = []
    LaTeXUtils.safe_read(path).each_line.with_index(1) do |raw, line_no|
      line = LaTeXUtils.strip_latex_comments(raw)
      LINE_CHECKS.each { |pattern, what| alerts << item(path, line_no, what) if line.match?(pattern) }
      alerts.concat(package_alerts(path, line_no, line))
    end
    alerts
  end

  def self.package_alerts(path, line_no, line)
    line.scan(PACKAGE_PATTERN).flat_map do |opts, names|
      names.split(',').map(&:strip).filter_map do |name|
        effect = DRAFT_PACKAGES[name]
        next unless effect
        next if name == 'todonotes' && opts.to_s.include?('disable')

        item(path, line_no, "package #{name} #{effect}")
      end
    end
  end

  def self.item(path, line_no, what)
    {
      file: path, line: line_no, col: 1, line_str: line_no.to_s,
      text: "Draft leftover: #{what}", alert_type: :draft_leftover,
      base_color: :red, index: 60_000 + line_no
    }
  end
end
