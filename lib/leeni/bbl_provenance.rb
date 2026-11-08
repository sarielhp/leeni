# frozen_string_literal: true

# ==============================================================================
# lib/leeni/bbl_provenance.rb
#
# The files the last bibliography run read (.bib databases, the .bst style),
# taken from its .blg log, with their content hashes, recorded next to the
# .bbl it wrote. Unlike modification times, the hashes survive copies,
# restores and checkouts, and they cover the .bst, which the document's own
# \bibdata and .bcf never name.
# ==============================================================================

require 'digest'
require 'fileutils'
require 'json'
require 'open3'

require_relative 'utils'

module LeeniBblProvenance
  RECORD = '.bbl_inputs.json'
  BIBER_SOURCE = /INFO - Found \S+ data source '([^']+)'/
  BIBTEX_INPUT = /^(?:The style file|Database file #\d+): (.+)$/
  REMOTE = %r{\A[a-z][a-z0-9+.-]*://}i

  module_function

  # Absolute paths of the files the run's log names. BibTeX logs names, not
  # paths: they are resolved from the build directory with the search
  # environment the run had, as BibTeX itself found them.
  def logged_inputs(tool, blg, dir, env)
    log = LaTeXUtils.safe_read(blg)
    return log.scan(BIBER_SOURCE).flatten.grep_v(REMOTE).map { |p| File.expand_path(p, dir) } if tool == :biber

    log.scan(BIBTEX_INPUT).flatten.filter_map { |name| resolve(name.strip, dir, env) }
  end

  def resolve(name, dir, env)
    local = File.expand_path(name, dir)
    return local if File.file?(local)

    out, status = Open3.capture2(env, 'kpsewhich', name, chdir: dir)
    path = out.lines.first.to_s.strip
    status.success? && !path.empty? ? File.expand_path(path, dir) : nil
  rescue SystemCallError
    nil
  end

  # An empty list (no log, or nothing recognised) leaves no record, so the
  # caller falls back to modification times.
  def record(dir, bbl, inputs)
    file = File.join(dir, RECORD)
    return FileUtils.rm_f(file) if inputs.empty?

    data = { 'bbl' => sha(bbl), 'inputs' => inputs.uniq.to_h { |path| [path, sha(path)] } }
    File.write(file, JSON.generate(data))
  end

  # nil when there is no record for this exact .bbl (none written, or the
  # .bbl came from elsewhere); otherwise whether a recorded input changed or
  # disappeared.
  def stale_verdict(dir, bbl)
    data = JSON.parse(File.read(File.join(dir, RECORD)))
    inputs = data['inputs']
    return nil unless inputs.is_a?(Hash) && !inputs.empty? && data['bbl'] && data['bbl'] == sha(bbl)

    inputs.any? { |path, digest| sha(path) != digest }
  rescue StandardError
    nil
  end

  def sha(path)
    File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil
  end
end
