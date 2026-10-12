# frozen_string_literal: true

require 'digest'

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

  def cache_dir(dir = '.')
    root = project_root(dir)
    name = File.basename(root).gsub(/[^a-zA-Z0-9._-]/, '_')
    hash = Digest::SHA256.hexdigest(root)[0, 16]
    File.join(cache_home, 'leeni', 'projects', "#{name}-#{hash}")
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
