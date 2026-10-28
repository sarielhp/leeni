# frozen_string_literal: true

# ==============================================================================
# lib/leeni/cli_targets.rb
#
# Target dispatch and target-specific workflows for the leeni CLI.
# ==============================================================================

module LatexCLITargets
  def execute_targets(argv, options)
    targets = resolve_cli_targets(argv, options)
    targets.each { |target| process_target(target, options) }
  end

  def resolve_cli_targets(argv, options)
    patterns = options[:exclude_main_tex]
    configured = options[:main_file]
    return [LaTeXUtils.find_main_latex_file('.', patterns, configured)] if argv.empty?

    argv.map { |target| resolve_single_target(target, patterns, configured, options[:force_file]) }.uniq
  end

  def resolve_single_target(target, patterns, configured, force_file)
    if !force_file && LaTeXUtils.file_matches_patterns?(target, patterns)
      warn "Warning: '#{target}' matches exclude_main_tex patterns and was ignored. " \
           'Auto-detecting main file instead (use --force-file to override).'
      dir = File.dirname(target)
      dir = '.' if dir.empty?
      LaTeXUtils.find_main_latex_file(dir, patterns, configured)
    else
      target
    end
  end

  def process_target(target, options)
    exit LeeniReport.run(target, options) if options[:report]

    if options[:meta_only]
      process_meta_target(target, options)
    elsif options[:arxiv]
      process_arxiv_target(target, options)
    elsif options[:bib_extract]
      process_bib_extract_target(target, options)
    else
      process_standard_target(target, options)
    end
  end

  def process_bib_extract_target(target, options)
    builder = LatexBuilder.new(target, options)
    exit 1 unless LaTeXBibExtractor.extract!(builder, options[:bib_extract_name])
  end

  def process_meta_target(target, options)
    Dir.chdir(File.expand_path(File.dirname(target))) do
      local_target = File.basename(target)
      builder = LatexBuilder.new(local_target, options)
      write_meta_for(local_target, options, junk_dir: builder.junk_dir)
    end
  end

  def write_meta_for(target, options, junk_dir: 'junk')
    base_name = File.basename(target, '.tex')
    pdf_path = File.file?("#{base_name}.pdf") ? "#{base_name}.pdf" : build_artifact_path(junk_dir, base_name, 'pdf')
    fls_path = build_artifact_path(junk_dir, base_name, 'fls')
    log_path = build_artifact_path(junk_dir, base_name, 'log')

    metadata = LaTeXMetaExtractor.extract(target, pdf_path: pdf_path, fls_path: fls_path, log_path: log_path,
                                                  extra_comments: options[:comments])
    metadata_text = LaTeXMetaExtractor.format_meta_txt(metadata)
    metadata_file = "arxiv_#{base_name}_meta.txt"
    LaTeXMetaExtractor.write_meta_file(metadata_file, metadata_text)
    print_metadata(metadata_text, metadata_file)
  end

  def build_artifact_path(junk_dir, base_name, extension)
    File.join(junk_dir, "#{base_name}.#{extension}")
  end

  def print_metadata(metadata_text, metadata_file)
    puts Rainbow("\n========================= Paper Metadata =========================").cyan.bright
    puts metadata_text
    puts Rainbow('==================================================================').cyan.bright
    puts Rainbow("==> Wrote paper metadata to: #{metadata_file}\n").green.bright
  end

  # Submission staging consumes compiler recorder data and the reference PDF,
  # so it must always build fresh artifacts in the resolved junk directory.
  def arxiv_build_options(options)
    options.merge(force: true, final: true)
  end

  def process_arxiv_target(target, options)
    builder = LatexBuilder.new(target, arxiv_build_options(options))
    exit 1 unless LatexArxivPackager.new(builder).package!
  end

  def process_standard_target(target, options)
    options = options.merge(zip: true, inject_styles: true, verify: true, force: true) if options[:zip_alone]
    options = options.merge(final: true) if options[:zip] || options[:verify]
    builder = LatexBuilder.new(target, options)
    exit 1 unless builder.run!
    return unless options[:zip] || options[:verify]

    packager = LatexPackager.new(builder)
    exit 1 unless packager.package!
  end
end
