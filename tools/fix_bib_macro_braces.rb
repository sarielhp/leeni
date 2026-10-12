#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# tools/fix_bib_macro_braces.rb
#
# Scans a .bib file (e.g. geometry.bib) against a macro definition file
# (e.g. shortcuts.bib). Whenever a known @string macro name is wrapped in
# curly braces inside target fields (default: booktitle, journal):
#
#     booktitle = {SODA_1990},  -->  booktitle = SODA_1990,
#     journal   = {DCG},        -->  journal   = DCG,
#
# it strips the braces so BibTeX/Biber can expand the @string macro into
# its full string value and prevent TeX syntax crashes on underscores.
# ==============================================================================

require 'fileutils'
require 'optparse'

module BibMacroFixer
  DEFAULT_SHORTCUTS = File.expand_path('/home/sariel/papers/bib/shortcuts.bib')
  DEFAULT_GEOMETRY  = File.expand_path('/home/sariel/papers/bib/geometry.bib')

  def self.run(argv = ARGV)
    options = {
      shortcuts: DEFAULT_SHORTCUTS,
      fields: %w[booktitle journal],
      dry_run: true,
      backup: true
    }

    parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{$PROGRAM_NAME} [options] [target.bib]"

      opts.on('-s', '--shortcuts FILE', "Path to shortcuts.bib (default: #{options[:shortcuts]})") do |v|
        options[:shortcuts] = File.expand_path(v)
      end

      opts.on('-f', '--fields LIST', "Comma-separated target fields (default: #{options[:fields].join(',')})") do |v|
        options[:fields] = v.split(',').map { |f| f.strip.downcase }.reject(&:empty?)
      end

      opts.on('--all-fields', 'Include all applicable fields (booktitle, journal, series, publisher, acceptrate, organization, note, title)') do
        options[:fields] = %w[booktitle journal series publisher acceptrate organization note title]
      end

      opts.on('-i', '--in-place', 'Apply modifications in place (creates .bak backup)') do
        options[:dry_run] = false
      end

      opts.on('-n', '--dry-run', 'Preview changes without modifying the file (default)') do
        options[:dry_run] = true
      end

      opts.on('--no-backup', 'Do not create .bak backup file when modifying in place') do
        options[:backup] = false
      end

      opts.on('-h', '--help', 'Show this help message') do
        puts opts
        exit 0
      end
    end

    parser.parse!(argv)
    target_bib = argv.first ? File.expand_path(argv.first) : DEFAULT_GEOMETRY

    validate_paths!(options[:shortcuts], target_bib)
    macro_map = load_macros(options[:shortcuts])
    process_bib_file(target_bib, macro_map, options)
  end

  def self.validate_paths!(shortcuts_file, target_file)
    unless File.file?(shortcuts_file)
      warn "❌ Error: Shortcuts file not found: #{shortcuts_file}"
      exit 1
    end

    return if File.file?(target_file)

    warn "❌ Error: Target bibliography file not found: #{target_file}"
    exit 1
  end

  def self.load_macros(shortcuts_file)
    macros = {}
    content = File.read(shortcuts_file)
    content.scan(/@string\s*\{\s*([a-zA-Z0-9_]+)\s*=/im) do |m|
      canonical = m.first.strip
      macros[canonical.downcase] = canonical
    end
    macros
  end

  def self.process_bib_file(target_bib, macro_map, options)
    fields_pattern = Regexp.union(options[:fields])
    field_regex = /^(\s*)(#{fields_pattern})(\s*=\s*)\{([a-zA-Z0-9_]+)\}(\s*,?\s*)$/i

    lines = File.readlines(target_bib)
    replacements = []
    new_lines = []

    lines.each_with_index do |line, idx|
      if (m = line.match(field_regex))
        indent = m[1]
        field = m[2]
        eq = m[3]
        val = m[4]
        tail = m[5]
        canonical = macro_map[val.downcase]
        if canonical
          new_line = "#{indent}#{field}#{eq}#{canonical}#{tail}"
          replacements << { line_no: idx + 1, old: line.chomp, new: new_line.chomp, field: field, macro: canonical }
          new_lines << new_line
          next
        end
      end
      new_lines << line
    end

    report_and_apply(target_bib, replacements, new_lines, options)
  end

  def self.report_and_apply(target_bib, replacements, new_lines, options)
    puts "Loaded #{new_lines.size} lines from #{target_bib}"
    puts "Target fields: #{options[:fields].join(', ')}"
    puts "Identified #{replacements.size} macro references wrapped in braces."

    if replacements.empty?
      puts '✔ File is clean. No changes needed.'
      return
    end

    puts "\n--- Sample Changes (first 10) ---"
    replacements.first(10).each do |r|
      puts "  Line #{r[:line_no]}: #{r[:old].strip}"
      puts "       -->  #{r[:new].strip}"
    end
    puts "  ... and #{replacements.size - 10} more." if replacements.size > 10

    if options[:dry_run]
      puts "\n[DRY RUN] Run with -i / --in-place to apply these #{replacements.size} fixes."
    else
      apply_changes(target_bib, new_lines, options[:backup])
      puts "\n✔ Successfully applied #{replacements.size} fixes to #{target_bib}!"
    end
  end

  def self.apply_changes(target_bib, new_lines, create_backup)
    if create_backup
      backup_file = "#{target_bib}.bak.#{Time.now.strftime('%Y%m%d_%H%M%S')}"
      FileUtils.cp(target_bib, backup_file)
      puts "Backed up original to: #{backup_file}"
    end

    File.write(target_bib, new_lines.join)
  end
end

BibMacroFixer.run if $PROGRAM_NAME == __FILE__
