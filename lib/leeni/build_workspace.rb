# frozen_string_literal: true

require 'digest'
require_relative 'tmp_space'

module LeeniBuildWorkspace
  module_function

  def project_root(dir = '.')
    File.realpath(File.expand_path(dir || '.'))
  end

  def cache_home
    configured = ENV['XDG_CACHE_HOME'].to_s
    return configured if configured.start_with?(File::SEPARATOR)

    File.join(Dir.home, '.cache')
  end

  # A project that itself lives in leeni's temporary tree (a sandbox, an -I
  # check, an arXiv verification) builds there too, in builds/, and goes with
  # the 24-hour sweep; any other project builds in the cache.
  def cache_dir(dir = '.')
    root = project_root(dir)
    name = File.basename(root).gsub(/[^a-zA-Z0-9._-]/, '_')
    hash = Digest::SHA256.hexdigest(root)[0, 16]
    return File.join(LeeniTmp.dir('builds'), "#{name}-#{hash}") if temporary_project?(root)

    File.join(cache_home, 'leeni', 'projects', "#{name}-#{hash}")
  end

  # Inside <tmpdir>/<user>/leeni/, without creating that tree to find out.
  def temporary_project?(root)
    tree = File.join(Dir.tmpdir, LeeniTmp.user_name, 'leeni') # tmp-exempt: compares with the tree, creates nothing
    tree = File.realpath(tree) if File.directory?(tree)
    root.start_with?("#{tree}#{File::SEPARATOR}")
  end

  # --sandbox and --zip-alone keep their sandbox beside the build caches, so
  # the build's own *.aux scans never see the sandbox build's files.
  def sandbox_dir(dir = '.')
    File.join(cache_home, 'leeni', 'sandboxes', File.basename(cache_dir(dir)))
  end

  def resolve(dir = '.', configured = nil)
    dir ||= '.'
    value = configured.to_s.strip
    value = value.delete_suffix('/') while value.length > 1 && value.end_with?('/')
    value = value.delete_prefix('./')
    return cache_dir(dir) if value.empty?

    expanded = File.expand_path(value, dir)
    root = project_root(dir)
    if expanded == File::SEPARATOR || expanded == root || root.start_with?(expanded + File::SEPARATOR)
      abort 'leeni: build directory cannot be the project directory or an ancestor'
    end

    value
  end
end
