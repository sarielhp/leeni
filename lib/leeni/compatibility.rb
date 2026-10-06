# frozen_string_literal: true

# ==============================================================================
# lib/leeni/compatibility.rb
#
# Vendor compatibility environment injection (REVTeX 4.0 fallback).
# ==============================================================================

module LaTeXCompatibility
  REPO_TEXMF = File.expand_path('../../vendor/revtex4', __dir__).freeze
  INSTALLED_TEXMF = File.expand_path('~/.local/share/leeni/texmf').freeze
  LEGACY_INSTALLED_TEXMF = File.expand_path('~/.local/share/latex_it/texmf').freeze

  def self.source_needs_revtex4?(path_or_content)
    return false if path_or_content.nil?

    raw = if !path_or_content.include?("\n") && File.file?(path_or_content.to_s)
            LaTeXUtils.safe_read(path_or_content)
          else
            path_or_content
          end
    content = LaTeXUtils.strip_latex_comments(raw)
    content.match?(/\\documentclass\s*(?:\[[^\]]*\])?\s*\{\s*revtex4\s*\}/)
  end

  def self.candidate_texmf_dirs(options = {})
    return [] if (ENV['LEENI_DISABLE_BUNDLED_REVTeX'] || ENV['LATEX_IT_DISABLE_BUNDLED_REVTeX']) == '1'

    cfg = options[:revtex4].is_a?(Hash) ? options[:revtex4] : {}
    return [] if cfg['enabled'] == false

    configured = Array(cfg['texmf_dirs']).map { |path| File.expand_path(path.to_s) }
    candidates = [INSTALLED_TEXMF, REPO_TEXMF, LEGACY_INSTALLED_TEXMF] + configured
    candidates.select { |path| File.directory?(path) }.uniq
  end

  def self.texmf_dirs(options = {}, target_file = nil)
    candidates = candidate_texmf_dirs(options)
    return [] if candidates.empty?

    cfg = options[:revtex4].is_a?(Hash) ? options[:revtex4] : {}
    return candidates if cfg['enabled'] == true
    return [] if target_file.nil? || !source_needs_revtex4?(target_file)

    candidates
  end

  def self.compiler_environment(options, base = ENV.to_h, target_file = nil)
    dirs = texmf_dirs(options, target_file)
    return base if dirs.empty?

    input = dirs.map { |dir| File.join(dir, 'tex', 'latex', 'revtex4') }
    old = base['TEXINPUTS'].to_s
    input << old unless old.empty?
    env = base.dup
    env['TEXINPUTS'] = input.join(File::PATH_SEPARATOR) + File::PATH_SEPARATOR
    env
  end

  def self.files_used_by_fls(fls_path, options)
    dirs = candidate_texmf_dirs(options)
    return [] unless File.file?(fls_path) && !dirs.empty?

    roots = dirs.map { |dir| File.expand_path(dir) }
    File.read(fls_path).each_line.filter_map do |line|
      next unless line.start_with?('INPUT ')

      path = File.expand_path(line.delete_prefix('INPUT ').strip)
      roots.any? { |root| path.start_with?(root + File::SEPARATOR) } ? path : nil
    end.uniq
  rescue StandardError
    []
  end
end
