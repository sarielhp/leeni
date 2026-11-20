#!/usr/bin/env ruby
# frozen_string_literal: true

# Incremental builds must agree with fresh ones. Each scenario builds a small
# document with a bibliography, applies one edit (a citation added or removed,
# a .bib entry changed, a .bib restored with an older timestamp, a database
# renamed, the style or the bibliography system switched), rebuilds, and
# compares the PDF text with a fresh build of the edited sources in a new
# directory with an empty cache. Both builds read the same sources, so any
# difference is a stale bibliography the incremental build kept.
require_relative 'test_env'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestBibEditMatrix < Minitest::Test
  # The tier runner already runs test files in parallel; a few threads here keep
  # these builds from oversubscribing the machine and starving timing tests.
  Minitest.parallel_executor = Minitest::Parallel::Executor.new(4)
  parallelize_me!

  BIN = File.expand_path('../leeni', __dir__)

  BIB = <<~BIB
    @book{knuth, author = {Donald Knuth}, title = {The TeXbook}, publisher = {AW}, year = {1984}}
    @book{lamport, author = {Leslie Lamport}, title = {LaTeX Manual}, publisher = {AW}, year = {1994}}
    @book{goossens, author = {Michel Goossens}, title = {The LaTeX Companion}, publisher = {AW}, year = {1993}}
  BIB

  SYSTEMS = {
    bibtex: { preamble: '', cite: '\\cite', print: "\\bibliographystyle{plain}\n\\bibliography{refs}" },
    biblatex: { preamble: "\\usepackage[backend=biber]{biblatex}\n\\addbibresource{refs.bib}",
                cite: '\\cite', print: '\\printbibliography' }
  }.freeze

  def self.document(system, keys: %w[knuth lamport], bib_name: 'refs', style: 'plain')
    spec = SYSTEMS.fetch(system)
    cites = keys.map { |key| "#{spec[:cite]}{#{key}}" }.join(' and ')
    print = spec[:print].sub('{refs}', "{#{bib_name}}").sub('{plain}', "{#{style}}")
    preamble = spec[:preamble].sub('{refs.bib}', "{#{bib_name}.bib}")
    "\\documentclass{article}\n#{preamble}\n\\begin{document}\nSee #{cites}.\n#{print}\n\\end{document}\n"
  end

  # name => edit; it receives the bibliography system and the project directory.
  EDITS = {
    add_citation: ->(sys, dir) { File.write(File.join(dir, 'main.tex'), document(sys, keys: %w[knuth lamport goossens])) },
    remove_citation: ->(sys, dir) { File.write(File.join(dir, 'main.tex'), document(sys, keys: %w[knuth])) },
    edit_entry: ->(_sys, dir) { File.write(File.join(dir, 'refs.bib'), BIB.sub('The TeXbook', 'The TeXbook, Revised')) },
    restore_older_bib: lambda do |_sys, dir|
      stamp = File.mtime(File.join(dir, 'refs.bib')) - 3600
      File.write(File.join(dir, 'refs.bib'), BIB.sub('LaTeX Manual', 'LaTeX: A Document Preparation System'))
      File.utime(stamp, stamp, File.join(dir, 'refs.bib'))
    end,
    rename_database: lambda do |sys, dir|
      File.write(File.join(dir, 'other.bib'), BIB.sub('The TeXbook', 'The TeXbook (renamed database)'))
      File.write(File.join(dir, 'main.tex'), document(sys, bib_name: 'other'))
    end,
    cite_missing_then_add: lambda do |sys, dir|
      File.write(File.join(dir, 'main.tex'), document(sys, keys: %w[knuth lamport newkey]))
      entry = "@book{newkey, author = {New Author}, title = {Fresh Entry}, publisher = {X}, year = {2020}}\n"
      File.write(File.join(dir, 'refs.bib'), BIB + entry)
    end,
    switch_system: ->(sys, dir) { File.write(File.join(dir, 'main.tex'), document(sys == :bibtex ? :biblatex : :bibtex)) }
  }.freeze
  BIBTEX_ONLY = { change_style: ->(_sys, dir) { File.write(File.join(dir, 'main.tex'), document(:bibtex, style: 'alpha')) } }.freeze

  SYSTEMS.each_key do |system|
    EDITS.merge(system == :bibtex ? BIBTEX_ONLY : {}).each do |name, edit|
      define_method("test_#{system}_#{name}") { check_scenario(system, edit) }
    end
  end

  private

  def check_scenario(system, edit)
    Dir.mktmpdir('bibmatrix') do |tmp|
      project = File.join(tmp, 'project')
      FileUtils.mkdir_p(project)
      File.write(File.join(project, 'main.tex'), self.class.document(system))
      File.write(File.join(project, 'refs.bib'), BIB)
      build!(project)
      sleep 1.1 # the edit must not share the build's one-second timestamp
      edit.call(system, project)
      incremental = build!(project)

      fresh_dir = File.join(tmp, 'fresh')
      FileUtils.mkdir_p(fresh_dir)
      %w[main.tex refs.bib other.bib].each do |f|
        FileUtils.cp(File.join(project, f), fresh_dir) if File.file?(File.join(project, f))
      end
      fresh = build!(fresh_dir, cache: File.join(tmp, 'fresh-cache'))
      assert_equal fresh, incremental, 'incremental rebuild disagrees with a fresh build of the same sources'
    end
  end

  # Builds main.tex and returns the PDF text, whitespace-normalised.
  def build!(dir, cache: nil)
    env = cache ? { 'XDG_CACHE_HOME' => cache } : {}
    out, status = Open3.capture2e(env, BIN, '--no-lock', '-e', 'x', 'main.tex', chdir: dir)
    assert status.success?, "build failed in #{dir}:\n#{out}"
    text, = Open3.capture2('pdftotext', File.join(dir, 'main.pdf'), '-')
    text.split.join(' ')
  end
end
