# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'

class TestConfigSave < Minitest::Test
  BIN = File.expand_path('../leeni', __dir__)

  def test_config_save_local_default
    Dir.mktmpdir('leeni_save_local') do |dir|
      out, stderr, status = Open3.capture3(BIN, '-I', '--config-save', chdir: dir)
      assert status.success?, "CLI failed with: #{stderr}"
      assert_includes out, 'Saved index to local configuration'

      local_cfg = File.join(dir, '.l.jsonc')
      assert File.file?(local_cfg), "Expected #{local_cfg} to exist"
      content = File.read(local_cfg)
      assert_match(/"index"\s*:\s*true/, content)
    end
  end

  def test_config_save_local_toggle_no_index
    Dir.mktmpdir('leeni_toggle_index') do |dir|
      # First enable
      _out, stderr, status = Open3.capture3(BIN, '-I', '--config-save', chdir: dir)
      assert status.success?, "CLI failed with: #{stderr}"

      # Then disable
      out, stderr, status = Open3.capture3(BIN, '--no-index', '--config-save', '--local', chdir: dir)
      assert status.success?, "CLI failed with: #{stderr}"
      assert_includes out, 'Saved index to local configuration'

      local_cfg = File.join(dir, '.l.jsonc')
      content = File.read(local_cfg)
      assert_match(/"index"\s*:\s*false/, content)
    end
  end

  def test_config_save_global
    Dir.mktmpdir('leeni_save_global') do |home_dir|
      env = { 'HOME' => home_dir }
      out, stderr, status = Open3.capture3(env, BIN, '-I', '--config-save', '--global', chdir: home_dir)
      assert status.success?, "CLI failed with: #{stderr}"
      assert_includes out, 'Saved index to global configuration'

      global_cfg = File.join(home_dir, '.config', 'leeni', 'config.jsonc')
      assert File.file?(global_cfg), "Expected #{global_cfg} to exist"
      content = File.read(global_cfg)
      assert_match(/"index"\s*:\s*true/, content)
    end
  end

  def test_config_save_preserves_comments_and_structure
    Dir.mktmpdir('leeni_preserve_comments') do |dir|
      local_cfg = File.join(dir, '.l.jsonc')
      initial = <<~JSONC
        {
          // Custom header comment
          "fast": false,
          // Index comment
          "index": false
        }
      JSONC
      File.write(local_cfg, initial)

      out, stderr, status = Open3.capture3(BIN, '-I', '-e', 'pdflatex', '--config-save', chdir: dir)
      assert status.success?, "CLI failed with: #{stderr}"
      assert_includes out, 'Saved index, engine to local configuration'

      updated = File.read(local_cfg)
      assert_includes updated, '// Custom header comment'
      assert_includes updated, '// Index comment'
      assert_match(/"index"\s*:\s*true/, updated)
      assert_match(/"engine"\s*:\s*"pdflatex"/, updated)
    end
  end

  def test_config_show_scoped_views
    Dir.mktmpdir('leeni_show_scope') do |dir|
      local_cfg = File.join(dir, '.l.jsonc')
      File.write(local_cfg, "{\n  \"index\": true\n}\n")

      # Local show
      out_local, status_local = Open3.capture2(BIN, '--config-show', '--local', chdir: dir)
      assert status_local.success?
      assert_includes out_local, '# Local leeni Configuration'
      assert_includes out_local, '"index": true'

      # Global show
      out_global, status_global = Open3.capture2(BIN, '--config-show', '--global', chdir: dir)
      assert status_global.success?
      assert_includes out_global, '# Global leeni Configuration'

      # Merged show
      out_merged, status_merged = Open3.capture2(BIN, '--config-show', chdir: dir)
      assert status_merged.success?
      assert_includes out_merged, '# Active leeni Configuration'
      assert_includes out_merged, '"index": true'
    end
  end
end
