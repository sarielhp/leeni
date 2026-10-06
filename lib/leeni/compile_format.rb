# frozen_string_literal: true

# ==============================================================================
# lib/leeni/compile_format.rb
#
# GNU Coding Standards compliant diagnostic formatter for compiler runners
# (Emacs compilation-mode, Vim/Neovim, VS Code, CI log matchers).
# ==============================================================================

require 'uri'

module LaTeXCompileFormat
  module_function

  SEVERITY = {
    'errors'    => { label: 'error',            style: :error },
    'alerts'    => { label: 'warning: [alert]', style: :alert },
    'warnings'  => { label: 'warning',          style: :warning },
    'whatevers' => { label: 'note',             style: :note }
  }.freeze

  WARNING_HEADER_PATTERN = /^(?:LaTeX|Class|Package|\*)(?:\s+[-\w.@*]+)*\s+[Ww]arning:\s*/.freeze

  def render(record, color: true, link: false)
    loc = format_location(record[:file], record[:line], record[:col], color: color, link: link)
    sev = format_severity(record[:tier], color: color)
    msg = format_message(record, color: color)

    "#{loc} #{sev} #{msg}"
  end

  def format_location(file, line, col, color: true, link: false)
    active_line = (line && line.to_i.positive?) ? line.to_i : 1
    active_col = (col && col.to_i.positive?) ? col.to_i : nil

    loc_str = active_col ? "#{active_line}:#{active_col}" : active_line.to_s
    raw_loc = "#{file}:#{loc_str}:"

    if link
      loc_text = color ? Rainbow(raw_loc).cyan.bold.to_s : raw_loc
      abs_path = ::URI::DEFAULT_PARSER.escape(File.expand_path(file.to_s))
      uri = "file://#{abs_path}##{loc_str}"
      "\e]8;;#{uri}\e\\#{loc_text}\e]8;;\e\\"
    elsif color
      file_str = Rainbow(file.to_s).bold.to_s
      coords_str = Rainbow(loc_str).cyan.bright.to_s
      "#{file_str}:#{coords_str}:"
    else
      raw_loc
    end
  end

  def format_severity(tier, color: true)
    t = tier.to_s
    case t
    when 'errors'
      color ? Rainbow('error:').red.bright.bold.to_s : 'error:'
    when 'alerts'
      if color
        "#{Rainbow('warning:').magenta.bright.bold} #{Rainbow('[alert]').magenta.bright}"
      else
        'warning: [alert]'
      end
    when 'whatevers'
      color ? Rainbow('note:').cyan.bright.bold.to_s : 'note:'
    else
      color ? Rainbow('warning:').yellow.bright.bold.to_s : 'warning:'
    end
  end

  def format_message(record, color: true)
    base_msg = clean_message(record[:message])

    # Append token if relevant and missing
    token = record[:token] || record.dig(:catalog, :token)
    if token && !token.to_s.empty?
      clean_token = token.to_s.strip
      clean_token = "\\#{clean_token}" if clean_token =~ /\A[a-zA-Z@]+\z/ && !clean_token.start_with?('\\')
      base_msg = "#{base_msg} #{clean_token}" unless base_msg.include?(clean_token)
    end

    # Append hint if present and missing
    hint = record[:hint] || record.dig(:catalog, :hint)
    if hint && !hint.to_s.empty?
      hint_text = strip_trailing_period(hint.to_s.strip)
      hint_suffix = color ? Rainbow(" (hint: #{hint_text})").green.bright.to_s : " (hint: #{hint_text})"
      base_msg = "#{base_msg}#{hint_suffix}" unless base_msg.include?(hint_text)
    end

    base_msg
  end

  def clean_message(raw_text)
    str = raw_text.to_s.gsub(/\s+/, ' ').strip
    str = str.gsub(/not available\s*\(Font\)\s*/i, 'not available, ')
    str = str.gsub(/\(Font\)\s*/i, ' ')
    str = strip_warning_header(str)
    str = str.sub(/(?:,\s*)?on input line \d+(?:,\s*|\s+(?=[a-zA-Z]))/i, ' ')
    str = strip_trailing_location(str)
    str = strip_trailing_period(str)
    str = str.gsub(/\s+/, ' ').strip
    downcase_first_word(str)
  end

  def strip_warning_header(text)
    if text =~ /\A(?:Package|Class)\s+([-\w.@*]+)\s+[Ww]arning:\s*(.*)\z/
      pkg = Regexp.last_match(1)
      rest = Regexp.last_match(2)
      "[#{pkg}] #{rest}"
    elsif text =~ /\ALaTeX\s+([-\w.@*]+)\s+[Ww]arning:\s*(.*)\z/i
      subsystem = Regexp.last_match(1).downcase
      rest = Regexp.last_match(2)
      "[#{subsystem}] #{rest}"
    elsif text =~ WARNING_HEADER_PATTERN
      text.sub(WARNING_HEADER_PATTERN, '')
    elsif text =~ /\A(?:Alert|Warning|Note|Error):\s*(.*)\z/i
      Regexp.last_match(1)
    else
      text
    end
  end

  def strip_trailing_location(text)
    text.sub(/(?:,\s*)?\b(?:on input line \d+(?:--\d+)?|at lines? \d+(?:--\d+)?)\.?\s*\z/i, '')
  end

  def strip_trailing_period(text)
    text.sub(/(?<!\.\.)\.\z/, '')
  end

  def downcase_first_word(text)
    return text if text.empty?
    return text if text.start_with?('\\', '[', '`', "'", '"')

    # If first token is all-caps or CamelCase (e.g. LaTeX, URL, Overfull, Underfull), handle carefully:
    # Overfull and Underfull should be downcased to overfull / underfull:
    if text =~ /\A(Overfull|Underfull)\b/
      return text.sub(/\A\w+/, &:downcase)
    end

    # Don't lowercase words with multiple uppercase letters (LaTeX, BibTeX, PDFDocEncoding, etc.)
    first_word = text.split(/\s+/, 2).first
    if first_word =~ /\A[A-Z][a-z0-9_\-]*\z/
      text.sub(/\A[A-Z]/, &:downcase)
    else
      text
    end
  end
end
