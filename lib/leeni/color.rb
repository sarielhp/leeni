# frozen_string_literal: true

require 'strscan'

# ==============================================================================
# lib/leeni/color.rb
#
# Terminal color output abstraction, TrueColor support, and theme presets.
# ==============================================================================

module LatexColor
  THEMES = {
    'blush' => {
      name: 'Soft Blush',
      red: '#ffcccc',
      yellow: '#ffe0b2',
      cyan: '#b3e5fc',
      green: '#c8e6c9',
      magenta: '#f8bbd0',
      blue: '#90caf9',
      desc: 'Soft pastel blush with high luminance'
    },
    'catppuccin' => {
      name: 'Catppuccin Mocha',
      red: '#f38ba8',
      yellow: '#fab387',
      cyan: '#89dceb',
      green: '#a6e3a1',
      magenta: '#f5c2e7',
      blue: '#89b4fa',
      desc: 'Warm soothing pastels'
    },
    'tokyo-night' => {
      name: 'Tokyo Night',
      red: '#f7768e',
      yellow: '#ff9e64',
      cyan: '#7dcfff',
      green: '#9ece6a',
      magenta: '#bb9af7',
      blue: '#7aa2f7',
      desc: 'Cyberpunk rose pastel'
    },
    'dracula' => {
      name: 'Dracula',
      red: '#ff5555',
      yellow: '#ffb86c',
      cyan: '#8be9fd',
      green: '#50fa7b',
      magenta: '#ff79c6',
      blue: '#8be9fd',
      desc: 'High-contrast vibrant coral'
    },
    'nord' => {
      name: 'Nord',
      red: '#bf616a',
      yellow: '#d08770',
      cyan: '#88c0d0',
      green: '#a3be8c',
      magenta: '#b48ead',
      blue: '#81a1c1',
      desc: 'Calm arctic muted brick'
    },
    'ansi' => {
      name: 'ANSI 16-Color',
      red: nil,
      yellow: nil,
      cyan: nil,
      green: nil,
      magenta: nil,
      blue: nil,
      desc: 'Classic terminal 16-color ANSI'
    }
  }.freeze

  ANSI_16_PALETTE = {
    30 => [0, 0, 0],
    31 => [205, 0, 0],
    32 => [0, 205, 0],
    33 => [205, 205, 0],
    34 => [0, 0, 238],
    35 => [205, 0, 205],
    36 => [0, 205, 205],
    37 => [229, 229, 229],
    90 => [127, 127, 127],
    91 => [255, 0, 0],
    92 => [0, 255, 0],
    93 => [255, 255, 0],
    94 => [92, 92, 255],
    95 => [255, 0, 255],
    96 => [0, 255, 255],
    97 => [255, 255, 255]
  }.freeze

  ORDERED_THEMES = %w[blush catppuccin tokyo-night dracula nord ansi].freeze
  DEFAULT_THEME = 'blush'

  @active_theme = nil

  class << self
    def active_theme
      @active_theme || default_theme
    end

    def active_theme=(theme_name)
      @active_theme = normalize_theme(theme_name)
    end

    def true_color_supported?(env = ENV)
      colorterm = env['COLORTERM'].to_s.downcase
      return true if %w[truecolor 24bit].include?(colorterm)

      term = env['TERM'].to_s.downcase
      return true if term.include?('direct')

      return true if env['KITTY_PID'] || env['WT_SESSION'] || env['VSCODE_PID'] || env['ITERM_SESSION_ID']

      false
    end

    def color_256_supported?(env = ENV)
      term = env['TERM'].to_s.downcase
      term.include?('256color') || term.include?('256')
    end

    def default_theme(env = ENV)
      true_color_supported?(env) ? 'blush' : 'ansi'
    end

    def highlight_latex(line, color_enabled: true)
      return line.to_s unless color_enabled

      s = StringScanner.new(line.to_s)
      out = String.new(capacity: line.bytesize * 2)

      until s.eos?
        if s.scan(/(?<!\\)%.*$/)
          out << Rainbow(s.matched).faint.to_s
        elsif s.scan(/\\(?:begin|end)\b/)
          out << Rainbow(s.matched).magenta.bright.to_s
        elsif s.scan(/\\[a-zA-Z@]+|\\[^a-zA-Z@\s]/)
          out << Rainbow(s.matched).cyan.to_s
        elsif s.scan(/\$\$|\$|\\\(|\\\)|\\[\[\]]/)
          out << Rainbow(s.matched).yellow.to_s
        elsif s.scan(/[^\\%$]+/)
          out << s.matched
        else
          out << s.getch
        end
      end
      out
    end

    def rgb_to_ansi16(r, g, b, ground = :foreground)
      best_code = 37
      min_dist = Float::INFINITY
      ANSI_16_PALETTE.each do |code, (pr, pg, pb)|
        dist = ((r - pr)**2) + ((g - pg)**2) + ((b - pb)**2)
        if dist < min_dist
          min_dist = dist
          best_code = code
        end
      end
      ground == :background ? (best_code + 10) : best_code
    end

    def custom_hex?(str)
      !str.nil? && (str =~ /^#?[0-9a-f]{6}$/i)
    end

    def normalize_theme(name)
      return DEFAULT_THEME if name.nil? || name.to_s.strip.empty?

      str = name.to_s.strip.downcase
      return str if THEMES.key?(str) || custom_hex?(str)

      DEFAULT_THEME
    end

    def theme_colors
      curr = active_theme
      if custom_hex?(curr)
        hex = curr.start_with?('#') ? curr : "##{curr}"
        return { red: hex }
      end
      THEMES[curr] || THEMES[DEFAULT_THEME]
    end

    def theme_description(name)
      norm = normalize_theme(name)
      THEMES.dig(norm, :desc) || "Custom hex (#{norm})"
    end

    def cycle_theme(current_name, step = 1)
      norm = normalize_theme(current_name)
      idx = ORDERED_THEMES.index(norm) || 0
      next_idx = (idx + step) % ORDERED_THEMES.size
      ORDERED_THEMES[next_idx]
    end

    def format_theme_list
      lines = ["Available diagnostic color themes:\n"]
      curr = active_theme
      ORDERED_THEMES.each do |key|
        meta = THEMES[key]
        marker = (key == curr) ? '* ' : '  '
        swatch = meta[:red] ? " (#{meta[:red]})" : ''
        current_tag = (key == curr) ? '  [current]' : ''
        lines << format('%s%-12s - %-32s%s%s', marker, key, meta[:desc], swatch, current_tag)
      end
      lines << "\nCycle through themes with: l --theme +1"
      lines.join("\n")
    end
  end
end

begin
  require 'rainbow'

  module RainbowRGBOverride
    def codes
      if LatexColor.true_color_supported?
        [ground == :foreground ? 38 : 48, 2, r, g, b]
      elsif LatexColor.color_256_supported?
        super + [5, code_from_rgb]
      else
        [LatexColor.rgb_to_ansi16(r, g, b, ground)]
      end
    end
  end
  Rainbow::Color::RGB.prepend(RainbowRGBOverride)

  module RainbowThemeOverride
    def build(ground, values)
      if values.size == 1 && values.first.is_a?(Symbol)
        if !LatexColor.true_color_supported? && !LatexColor.color_256_supported?
          return super
        end

        colors = LatexColor.theme_colors
        hex = colors[values.first]
        return Rainbow::Color::RGB.new(ground, *parse_hex_color(hex)) if hex
      end
      super
    end
  end
  Rainbow::Color.singleton_class.prepend(RainbowThemeOverride)

  # Fallback for ANSI theme: remap standard red (ANSI 31) to bright red (ANSI 91)
  if defined?(Rainbow::Color::Named::NAMES)
    bright_names = Rainbow::Color::Named::NAMES.dup.merge(red: 61)
    Rainbow::Color::Named.send(:remove_const, :NAMES)
    Rainbow::Color::Named.const_set(:NAMES, bright_names.freeze)
  end
rescue LoadError
  module Rainbow
    class NullString < String
      def method_missing(*)
        self
      end

      def respond_to_missing?(*)
        true
      end
    end

    def self.call(obj)
      NullString.new(obj.to_s)
    end

    def self.enabled=(val)
      @enabled = val
    end

    def self.enabled
      false
    end
  end

  def Rainbow(obj)
    Rainbow.call(obj)
  end
end
