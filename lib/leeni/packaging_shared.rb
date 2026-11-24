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

  # A package ships the .bbl the PDF was built with, from the build directory.
  # A successful build exports it to the working tree, but that copy can change
  # afterwards (a checkout, a copy from another version, a failed build, or
  # --no-export), possibly to the other bibliography system's format; it ships
  # only when the build directory has none. Returns the path (nil for none)
  # and any warnings.
  def shipped_bbl(bfilename, junk_dir)
    root = "#{bfilename}.bbl"
    built = File.join(junk_dir, root)
    source = [built, root].find { |f| LaTeXUtils.bbl_has_entries?(f) }
    return [nil, []] unless source

    warnings = []
    if source == built && File.file?(root) && !FileUtils.identical?(root, built)
      warnings << "#{root} in the working tree differs from the bibliography the PDF was built with; " \
                  'shipping the build\'s copy'
    end
    [source, warnings + bbl_format_warnings(source, root, File.join(junk_dir, "#{bfilename}.fls"))]
  end

  BIB_SOURCE_EXTS = %w[.bib .bst].freeze

  # The bibliography databases and BibTeX styles the build read, as existing
  # paths: biblatex datasources from the .bcf, \bibdata and \bibstyle from the
  # .aux files, and the data sources the .blg reports. A copy in the build
  # directory maps back to its project file. Callers decide which paths lie in
  # the project tree (copy_preserving_path ships only those).
  def bibliography_sources(bfilename, junk_dir)
    names = recorded_bcf_datasources(File.join(junk_dir, "#{bfilename}.bcf"))
    aux = Dir.glob(File.join(junk_dir, '**', '*.aux')).map { |f| LaTeXUtils.safe_read(f) }.join("\n")
    names += aux.scan(/\\bibdata\{([^}]+)\}/).flatten.flat_map { |s| s.split(',') }.map { |s| with_ext(s, '.bib') }
    names += aux.scan(/\\bibstyle\{([^}]+)\}/).flatten.map { |s| with_ext(s, '.bst') }
    names += LaTeXUtils.safe_read(File.join(junk_dir, "#{bfilename}.blg"))
                       .scan(/(?:Found BibTeX data source|Looking for bibtex file)\s+'([^']+)'|Database file #\d+:\s*(\S+)/)
                       .flatten.compact
    names.map { |n| project_twin(n, junk_dir, BIB_SOURCE_EXTS) }.uniq.select { |p| File.file?(p) }
  end

  def recorded_bcf_datasources(bcf)
    LaTeXUtils.safe_read(bcf).scan(%r{<bcf:datasource[^>]*>([^<]+)</bcf:datasource>}).flatten.map(&:strip)
  end

  def with_ext(name, ext)
    name = name.strip
    File.extname(name).casecmp?(ext) ? name : "#{name}#{ext}"
  end

  def bbl_format_warnings(source, root, fls)
    loaded = LaTeXUtils.recorded_biblatex_load(fls)
    written_by_biber = LaTeXUtils.biblatex_bbl?(source)
    return [] if loaded.nil? || written_by_biber == loaded

    ["the shipped #{root} was written for #{written_by_biber ? 'biblatex' : 'BibTeX'}, but the document " \
     "#{loaded ? 'loads' : 'does not load'} biblatex; rebuild with l -c before submitting"]
  end

  def realpath_or(path, fallback)
    File.realpath(path)
  rescue StandardError
    fallback
  end
end
