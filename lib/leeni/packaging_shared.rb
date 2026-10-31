# frozen_string_literal: true

require 'fileutils'

module LaTeXPackagingShared
  module_function

  def sandbox_environment(tmpdir)
    home = File.join(tmpdir, 'home')
    texmf_home = File.join(tmpdir, 'texmf-home')
    texmf_var = File.join(tmpdir, 'texmf-var')
    texmf_config = File.join(tmpdir, 'texmf-config')
    texmf_cache = File.join(tmpdir, 'texmf-cache')
    xdg_config = File.join(tmpdir, 'config')
    xdg_cache = File.join(tmpdir, 'cache')
    [home, texmf_home, texmf_var, texmf_config, texmf_cache, xdg_config, xdg_cache].each { |dir| FileUtils.mkdir_p(dir) }
    ENV.to_h.merge(
      'HOME' => home,
      'TEXMFHOME' => texmf_home,
      'TEXMFVAR' => texmf_var,
      'TEXMFCONFIG' => texmf_config,
      'TEXMFCACHE' => texmf_cache,
      'XDG_CONFIG_HOME' => xdg_config,
      'XDG_CACHE_HOME' => xdg_cache,
      'LEENI_DISABLE_BUNDLED_REVTeX' => '1'
    )
  end

  def copy_preserving_path(src, dest_root, recursive: false)
    return unless File.exist?(src)

    cwd = Dir.pwd
    real_cwd = realpath_or(cwd, cwd)
    real_src = realpath_or(src, nil)
    return unless real_src && (real_src == real_cwd || real_src.start_with?(real_cwd + File::SEPARATOR))

    expanded = File.expand_path(src)
    rel_path = if expanded.start_with?(cwd + File::SEPARATOR)
                 expanded.sub(cwd + File::SEPARATOR, '')
               elsif real_src.start_with?(real_cwd + File::SEPARATOR)
                 real_src.sub(real_cwd + File::SEPARATOR, '')
               else
                 return
               end

    dest = File.join(dest_root, rel_path)
    FileUtils.mkdir_p(File.dirname(dest))
    recursive ? FileUtils.cp_r(src, dest) : FileUtils.cp(src, dest)
  end

  # The bibliography pass copies styles/ into the build directory, and TeX
  # reads files from its output directory first, so the recorder lists those
  # copies. Maps such a copy back to the project file it came from.
  def project_twin(path, junk_dir, exts)
    workspace = File.expand_path(junk_dir) + File::SEPARATOR
    expanded = File.expand_path(path)
    return path unless expanded.start_with?(workspace)

    twin = expanded.delete_prefix(workspace)
    exts.include?(File.extname(twin).downcase) && File.file?(twin) ? twin : path
  end

  # Archives never carry other archives: old_ver_*.zip backups, earlier
  # bundles or report zips picked up through a directory or a glob.
  def drop_nested_archives!(stage_dir)
    Dir.glob(File.join(stage_dir, '**', '*.zip'), File::FNM_CASEFOLD).each do |path|
      File.delete(path)
      puts " -- Left out archive #{path.delete_prefix(stage_dir + File::SEPARATOR)}"
    end
  end

  def realpath_or(path, fallback)
    File.realpath(path)
  rescue StandardError
    fallback
  end
end
