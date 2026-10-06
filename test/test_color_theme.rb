# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

require_relative '../lib/leeni/color'
require_relative '../lib/leeni/config'

class TestColorTheme < Minitest::Test
  def setup
    @original_theme = LatexColor.active_theme
  end

  def teardown
    LatexColor.active_theme = @original_theme
  end

  def test_built_in_themes_defined
    assert_includes LatexColor::ORDERED_THEMES, 'blush'
    assert_includes LatexColor::ORDERED_THEMES, 'catppuccin'
    assert_includes LatexColor::ORDERED_THEMES, 'tokyo-night'
    assert_includes LatexColor::ORDERED_THEMES, 'dracula'
    assert_includes LatexColor::ORDERED_THEMES, 'nord'
    assert_includes LatexColor::ORDERED_THEMES, 'ansi'

    assert_equal '#ffcccc', LatexColor::THEMES.dig('blush', :red)
    assert_equal '#f38ba8', LatexColor::THEMES.dig('catppuccin', :red)
    assert_nil LatexColor::THEMES.dig('ansi', :red)
  end

  def test_theme_normalization_and_custom_hex
    assert_equal 'blush', LatexColor.normalize_theme('blush')
    assert_equal 'catppuccin', LatexColor.normalize_theme('CATPPUCCIN')
    assert_equal '#ff8888', LatexColor.normalize_theme('#ff8888')
    assert_equal 'aabbcc', LatexColor.normalize_theme('aabbcc')
    assert_equal 'blush', LatexColor.normalize_theme('nonexistent_theme')
    assert_equal 'blush', LatexColor.normalize_theme(nil)
  end

  def test_theme_cycling
    assert_equal 'catppuccin', LatexColor.cycle_theme('blush', 1)
    assert_equal 'tokyo-night', LatexColor.cycle_theme('catppuccin', 1)
    assert_equal 'ansi', LatexColor.cycle_theme('nord', 1)
    assert_equal 'blush', LatexColor.cycle_theme('ansi', 1) # wraps around

    assert_equal 'ansi', LatexColor.cycle_theme('blush', -1) # backward wrap
    assert_equal 'tokyo-night', LatexColor.cycle_theme('blush', 2)
  end

  def test_theme_colors_lookup
    LatexColor.active_theme = 'blush'
    assert_equal '#ffcccc', LatexColor.theme_colors[:red]

    LatexColor.active_theme = 'tokyo-night'
    assert_equal '#f7768e', LatexColor.theme_colors[:red]

    LatexColor.active_theme = '#123456'
    assert_equal '#123456', LatexColor.theme_colors[:red]
  end

  def test_format_theme_list
    LatexColor.active_theme = 'blush'
    output = LatexColor.format_theme_list
    assert_match(/\* blush/, output)
    assert_match(/catppuccin/, output)
    assert_match(/\[current\]/, output)
    assert_match(/l --theme \+1/, output)
  end

  def test_save_global_theme_preserves_comments
    Dir.mktmpdir('theme_test') do |dir|
      conf_file = File.join(dir, 'config.jsonc')
      initial_content = <<~JSONC
        {
          // User comment above
          "color": true,
          // Comment on theme
          "theme": "blush",
          "engine": "xelatex"
        }
      JSONC
      File.write(conf_file, initial_content)

      LaTeXConfig.save_global_theme!('tokyo-night', conf_file)
      updated = File.read(conf_file)

      assert_match(/"theme": "tokyo-night"/, updated)
      assert_match(%r{// User comment above}, updated)
      assert_match(%r{// Comment on theme}, updated)
    end
  end

  def test_cli_list_themes_flag
    bin = File.expand_path('../leeni', __dir__)
    out, status = Open3.capture2e(bin, '--theme-list')
    assert status.success?
    assert_match(/Available diagnostic color themes:/, out)
    assert_match(/blush/, out)
    assert_match(/catppuccin/, out)
  end

  def test_terminal_capability_detection
    truecolor_env = { 'COLORTERM' => 'truecolor', 'TERM' => 'xterm-256color' }
    assert LatexColor.true_color_supported?(truecolor_env)
    assert_equal 'blush', LatexColor.default_theme(truecolor_env)

    xterm_env = { 'COLORTERM' => '', 'TERM' => 'xterm' }
    refute LatexColor.true_color_supported?(xterm_env)
    refute LatexColor.color_256_supported?(xterm_env)
    assert_equal 'ansi', LatexColor.default_theme(xterm_env)

    console_env = { 'COLORTERM' => '', 'TERM' => 'linux' }
    refute LatexColor.true_color_supported?(console_env)
    refute LatexColor.color_256_supported?(console_env)
    assert_equal 'ansi', LatexColor.default_theme(console_env)

    emacs_env = { 'COLORTERM' => '', 'TERM' => 'eterm-color' }
    refute LatexColor.true_color_supported?(emacs_env)
    refute LatexColor.color_256_supported?(emacs_env)
    assert_equal 'ansi', LatexColor.default_theme(emacs_env)

    c256_env = { 'COLORTERM' => '', 'TERM' => 'xterm-256color' }
    refute LatexColor.true_color_supported?(c256_env)
    assert LatexColor.color_256_supported?(c256_env)
  end

  def test_rgb_to_ansi16_mapping
    assert_equal 91, LatexColor.rgb_to_ansi16(255, 0, 0)
    assert_equal 101, LatexColor.rgb_to_ansi16(255, 0, 0, :background)
    assert_equal 92, LatexColor.rgb_to_ansi16(0, 255, 0)
    assert_equal 96, LatexColor.rgb_to_ansi16(0, 255, 255)
  end

  def test_determine_color_enabled
    load File.expand_path('../leeni', __dir__)

    # Explicit options override environment
    assert LatexCLI.determine_color_enabled(color: true)
    refute LatexCLI.determine_color_enabled(color: false)

    # Emacs mode disables color by default
    refute LatexCLI.determine_color_enabled(emacs: true, color: nil)

    # NO_COLOR environment variable disables color
    orig_no_color = ENV['NO_COLOR']
    begin
      ENV['NO_COLOR'] = '1'
      refute LatexCLI.determine_color_enabled(color: nil)
    ensure
      ENV['NO_COLOR'] = orig_no_color
    end

    # Dumb terminal disables color
    orig_term = ENV['TERM']
    begin
      ENV['TERM'] = 'dumb'
      refute LatexCLI.determine_color_enabled(color: nil)
    ensure
      ENV['TERM'] = orig_term
    end
  end

  def test_show_config_cli
    bin = File.expand_path('../leeni', __dir__)
    out, status = Open3.capture2e(bin, '--config-show')
    assert status.success?
    assert_match(/Active leeni Configuration/, out)
    assert_match(/"theme":/, out)
  end

  def test_help_all_short_flag
    bin = File.expand_path('../leeni', __dir__)
    out, status = Open3.capture2e(bin, '-H')
    assert status.success?
    assert_match(/Usage: l \[options\]/, out)
    assert_match(/Compilation Options:/, out)
    assert_match(/General Options:/, out)
  end
end
