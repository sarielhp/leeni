#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'leeni_test_support'

# A .bib edit that removes a macro the old .bbl uses (the fix for an
# "Undefined control sequence" in the bibliography) must not be blocked by that
# old .bbl failing the first pass before biber can regenerate it.
class TestStaleBbl < LeeniTestBase
  MAIN = <<~TEX
    \\documentclass{article}
    \\usepackage[backend=biber]{biblatex}
    \\addbibresource{refs.bib}
    \\begin{document}
    \\cite{k}
    \\printbibliography
    \\end{document}
  TEX
  BIB = "@article{k, author={A. Author}, title={Title}, journal={J}, year=2000}\n"

  def options(extra = {})
    { engine: 'pdflatex', passes: 4, lock: false, force: true }.merge(extra)
  end

  def with_project
    Dir.mktmpdir('leeni_stale_bbl') do |dir|
      cache = File.join(dir, 'cache')
      project = File.join(dir, 'paper')
      FileUtils.mkdir_p([cache, project])
      saved = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = cache
      Dir.chdir(project) do
        File.write('main.tex', MAIN)
        File.write('refs.bib', BIB)
        capture_io { assert LatexBuilder.new('main.tex', options).run!, 'initial build failed' }
        yield LeeniBuildWorkspace.cache_dir('.')
      end
    ensure
      saved ? ENV['XDG_CACHE_HOME'] = saved : ENV.delete('XDG_CACHE_HOME')
    end
  end

  # Both copies of the .bbl use a macro nobody defines and predate the .bib.
  def poison_bbl(junk_dir)
    old = Time.now - 3600
    [File.join(junk_dir, 'main.bbl'), 'main.bbl'].each do |bbl|
      next unless File.file?(bbl)

      File.write(bbl, File.read(bbl).sub('{Title}', '{Title\\GoneMacro}'))
      File.utime(old, old, bbl)
    end
  end

  def test_stale_bbl_failing_the_first_pass_is_regenerated
    skip 'biber not installed' unless system('biber --version', out: File::NULL, err: File::NULL)
    with_project do |junk_dir|
      poison_bbl(junk_dir)
      out, err = capture_io { assert LatexBuilder.new('main.tex', options).run!, 'stale .bbl blocked the build' }
      refute_includes strip_ansi(out + err), 'GoneMacro'
      refute_includes File.read(File.join(junk_dir, 'main.bbl')), 'GoneMacro'
    end
  end

  def test_biber_error_names_the_bib_file_not_its_temporary_copy
    output = <<~LOG
      INFO - Found BibTeX data source '/home/u/paper/guarding.bib'
      ERROR - BibTeX subsystem: /tmp/biber_tmp_MwUb/66b2_2502359.utf8, line 37, syntax error: found "@article"
    LOG
    detail = LaTeXBibManager.allocate.send(:bibliography_failure_detail, output)
    assert_includes detail, 'BibTeX subsystem: guarding.bib, line 37'
    refute_includes detail, 'biber_tmp'
  end
end
