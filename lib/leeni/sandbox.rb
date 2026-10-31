# frozen_string_literal: true

# ==============================================================================
# lib/leeni/sandbox.rb
#
# Sandbox check (--sandbox) and the base of --zip-alone. After a normal build,
# every file the paper used is copied into a sandbox kept in the cache
# ($XDG_CACHE_HOME/leeni/sandboxes/<project>/paper), refreshed by content on
# each run, then rebuilt there with --no-env and compared with the paper's PDF.
# Styles from outside the project go to styles/ with \input@path, as in
# --zip-alone, so the sandbox is exactly what such an archive contains.
# ==============================================================================

require 'fileutils'
require 'tmpdir'
require_relative 'build_workspace'
require_relative 'packager'

class LatexSandbox
  attr_reader :root

  def initialize(builder)
    @builder = builder
    @bfilename = builder.bfilename
    @root = LeeniBuildWorkspace.sandbox_dir(builder.bdir)
  end

  def paper_dir
    File.join(@root, 'paper')
  end

  def run!
    Dir.chdir(File.expand_path(@builder.bdir)) do
      reference = reference_pdf
      unless reference
        warn Rainbow("[FAIL] No #{@bfilename}.pdf to compare the sandbox build with.").red.bright
        next false
      end

      puts Rainbow("==> Rebuilding in the sandbox with --no-env: #{paper_dir}").cyan.bright
      next false unless refresh!

      packager.compile_in_sandbox(paper_dir, reference, env_dir)
    end
  end

  private

  # The sandbox build gets its own HOME, TeX trees and leeni cache here, apart
  # from the paper tree that --zip-alone archives.
  def env_dir
    File.join(@root, 'env')
  end

  def packager
    @packager ||= LatexPackager.new(@builder)
  end

  def reference_pdf
    candidates = ["#{@bfilename}.pdf", File.join(@builder.junk_dir, "#{@bfilename}.pdf")]
    found = candidates.find { |path| File.file?(path) }
    found && File.expand_path(found)
  end

  def refresh!
    Dir.mktmpdir('leeni_sandbox_stage_') do |stage|
      next false unless packager.stage_into(stage)

      FileUtils.rm_f(File.join(stage, "#{@bfilename}.pdf"))
      sync(stage)
      true
    end
  end

  # Only changed files are copied, so the sandbox build stays incremental;
  # files the paper no longer uses are deleted.
  def sync(stage)
    FileUtils.mkdir_p([paper_dir, env_dir])
    wanted = relative_files(stage)
    changed = wanted.count { |rel| update_file(File.join(stage, rel), File.join(paper_dir, rel)) }
    stale = relative_files(paper_dir) - wanted - generated_outputs
    stale.each { |rel| File.delete(File.join(paper_dir, rel)) }
    remove_empty_dirs
    puts " -- Sandbox refreshed: #{changed} copied, #{stale.size} removed." if changed.positive? || stale.any?
  end

  def update_file(src, dst)
    return false if File.file?(dst) && !File.symlink?(dst) && FileUtils.compare_file(src, dst)

    FileUtils.mkdir_p(File.dirname(dst))
    FileUtils.rm_f(dst)
    FileUtils.cp(src, dst)
    true
  end

  def relative_files(dir)
    Dir.glob('**/*', File::FNM_DOTMATCH, base: dir).select { |rel| File.file?(File.join(dir, rel)) }
  end

  # Written by the sandbox build itself, not staged from the project.
  def generated_outputs
    %W[#{@bfilename}.pdf #{@bfilename}.synctex.gz #{@bfilename}.bbl.bak]
  end

  def remove_empty_dirs
    dirs = Dir.glob('**/', base: paper_dir).map { |rel| File.join(paper_dir, rel) }
    dirs.sort_by { |dir| -dir.length }.each { |dir| Dir.rmdir(dir) if Dir.empty?(dir) }
  end
end
