# frozen_string_literal: true

module LatexCLI
  def self.condensed_help(_prog_name = 'l')
    [
      'Usage: l [options] [document.tex]',
      '',
      'Common Options:',
      '  -f, --force          Force compilation run (bypasses build cache)',
      '  -u, --single-pass    Single pass only (fast draft, skip bib/extra passes)',
      '  -r, --raw            Print raw compiler output (debug mode)',
      '  -c, --clean          Clean temporary build files (preserves .bbl and metadata)',
      '  -x, --explain        Display plain-English explanations for diagnostics',
      '  -B, --bib-extract    Extract cited bib entries into local .bib file',
      '  -e, --engine ENGINE  Compiler engine: x (xelatex), l (lualatex), p (pdflatex)',
      '',
      'Help & Discovery:',
      '  -H, --help-all       Show all available options with full descriptions',
      '  -E, --examples       Show common usage examples and workflows',
      '  -h, --help           Show condensed help summary (this message)'
    ].join("\n")
  end

  def self.terminal_columns
    cols = ENV['COLUMNS']&.to_i
    unless cols&.positive?
      cols = begin
        IO.console&.winsize&.last
      rescue StandardError
        nil
      end
    end
    cols = 80 if cols.nil? || cols <= 0
    cols.clamp(40, 120)
  end

  def self.wrap_words(words, width)
    lines = []
    curr = []
    len = 0
    words.each do |w|
      if curr.empty?
        curr << w
        len = w.length
      elsif len + 1 + w.length <= width
        curr << w
        len += 1 + w.length
      else
        lines << curr.join(' ')
        curr = [w]
        len = w.length
      end
    end
    lines << curr.join(' ') unless curr.empty?
    lines
  end

  def self.wrap_help_line(line, width)
    return [line] if line.length <= width

    if (m = line.match(/^(\s{2,}\S.*?\s{2,})(\S.*)$/))
      leader = m[1]
      desc = m[2]
      avail = width - leader.length
      if avail >= 16
        desc_lines = wrap_words(desc.split, avail)
        indent = ' ' * leader.length
        return [leader + desc_lines[0]] + desc_lines[1..].map { |l| indent + l }
      end
    end

    indent = line[/^\s*/] || ''
    avail = [width - indent.length, 20].max
    wrap_words(line.strip.split, avail).map { |l| indent + l }
  end

  def self.colorize_flags(str)
    str.gsub(/\b[A-Z]{2,}\b/) { |arg| Rainbow(arg).yellow }
       .gsub(/(-[a-zA-Z0-9]+|--(?:\[no-\])?[a-zA-Z0-9\-_]+)/) { |flag| Rainbow(flag).green.bold }
  end

  def self.colorize_help_line(line)
    return line unless Rainbow.enabled

    if (m = line.match(/^(\s*)(Usage:)(\s+)(\S+)(.*)$/))
      lead = m[1]
      usage = m[2]
      sp = m[3]
      prog = m[4]
      rest = m[5]
      colored_rest = rest.gsub(/(\[[^\]]+\])/) { |b| Rainbow(b).cyan }
      "#{lead}#{Rainbow(usage).cyan.bold}#{sp}#{Rainbow(prog).bold}#{colored_rest}"
    elsif (m = line.match(%r{^(\s*)([A-Za-z0-9\s&,/\-.]+:)$}))
      "#{m[1]}#{Rainbow(m[2]).cyan.bold}"
    elsif (m = line.match(/^(\s{2,})((?:-[a-zA-Z0-9]+,?\s*|--(?:\[no-\])?[a-zA-Z0-9\-_]+(?:\s+[A-Z]+)?(?:,\s*)?)+)( {2,})(\S.*)$/))
      lead = m[1]
      flags = m[2]
      sp = m[3]
      desc = m[4]
      "#{lead}#{colorize_flags(flags)}#{sp}#{desc}"
    elsif (m = line.match(/^(\s{2,})(-[a-zA-Z0-9\-_].*)$/))
      lead = m[1]
      flags = m[2]
      "#{lead}#{colorize_flags(flags)}"
    elsif (m = line.match(/(run:\s+)(\S+\s+-E)/))
      line.gsub(m[2], Rainbow(m[2]).bold.cyan)
    else
      line
    end
  end

  def self.divider_character
    ENV['TERM'] == 'dumb' || ENV['LC_ALL'] == 'C' || ENV['LANG'] == 'C' ? '-' : '─'
  end

  def self.build_help_divider(width)
    char = divider_character
    raw = '  ' + (char * [width - 4, 10].max)
    Rainbow.enabled ? Rainbow(raw).faint.to_s : raw
  end

  def self.insert_help_dividers(lines, width)
    divider = build_help_divider(width)
    result = []
    in_group = false
    seen_option = false

    lines.each do |line|
      plain = line.gsub(/\e\[[0-9;]*m/, '')
      if plain =~ %r{^(\s*)([A-Za-z0-9\s&,/\-.]+:)$}
        in_group = true
        seen_option = false
      elsif plain =~ /^[A-Z]/ && !plain.start_with?('  ')
        in_group = false
        seen_option = false
      elsif in_group && plain =~ /^\s{2,}(-[a-zA-Z0-9]+|--(?:\[no-\])?[a-zA-Z0-9\-_]+)/
        result << divider if seen_option
        seen_option = true
      end
      result << line
    end
    result
  end

  def self.wrap_help(text, width = terminal_columns, help_style = 'plain')
    wrapped_lines = text.to_s.lines.map(&:chomp)
                        .flat_map { |line| wrap_help_line(line, width) }
                        .map { |line| colorize_help_line(line) }

    lines = help_style == 'lines' ? insert_help_dividers(wrapped_lines, width) : wrapped_lines
    lines.join("\n")
  end

  def self.handle_help_and_examples(parser, options, prog_name, argv = [])
    options[:color] = determine_color_enabled(options) if options[:color].nil?
    Rainbow.enabled = options[:color]

    if options[:list_themes]
      base_theme = ENV['LEENI_THEME'] || ENV['L_THEME'] || ENV['COLOR_THEME'] ||
                   ENV['BASE16_THEME'] || options[:theme] || LatexColor.default_theme
      LatexColor.active_theme = base_theme
      puts LatexColor.format_theme_list
      exit 0
    end

    if options[:show_config]
      puts LaTeXConfig.format_active_config('.', scope: options[:config_scope])
      exit 0
    end

    # Help is checked first so that it wins over every action, destructive ones
    # included: `l -C -h` used to clean the directory and exit 0 without ever
    # printing the usage the user asked for.
    print_help_or_examples(parser, options, prog_name)

    if options[:show_main]
      puts LaTeXUtils.find_main_latex_file(directory_argument_or_abort(argv[0], prog_name), options[:exclude_main_tex])
      exit 0
    elsif options[:clean_only]
      target = directory_argument_or_abort(argv[0], prog_name)
      config = LaTeXConfig.load_merged_config(target)
      configured = options[:junk_dir] || config['junk_dir']
      workspace = LeeniBuildWorkspace.resolve(target, configured)
      LaTeXUtils.clean_directory(target, true, workspace_dir: workspace)
      exit 0
    end
  end

  def self.help_output_text(parser, options, prog_name)
    manual = options[:show_help_all] ? LaTeXHelpManual.render(prog_name) : condensed_help(prog_name)
    if (options[:show_help_all] || options[:show_help]) && options[:show_examples]
      "#{manual}\n\n#{LaTeXUtils.detailed_examples}"
    elsif options[:show_help_all] || options[:show_help]
      manual
    elsif options[:show_examples]
      LaTeXUtils.detailed_examples(parser.banner)
    end
  end

  def self.print_help_or_examples(parser, options, prog_name)
    output = help_output_text(parser, options, prog_name)
    return unless output

    puts wrap_help(output, terminal_columns, options[:help_style])
    exit 0
  end
end
