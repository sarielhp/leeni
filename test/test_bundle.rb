# frozen_string_literal: true

require_relative 'test_env'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

load File.expand_path('../tools/bundle', __dir__)

# The installed leeni is the bundle, not the source tree, so a require the
# bundle loses passes every source-tree test and fails only once installed
# (1.0.76: --bib-missing raised NameError on StringIO).
class TestBundle < Minitest::Test
  def bundle = @bundle ||= LatexBundler.bundle

  def header = bundle.split('# lib/leeni/version.rb').first

  def test_header_requires_every_top_level_require_of_the_sources
    sources = Dir[File.join(LatexBundler::LIB_DIR, '*.rb')] + [LatexBundler::ENTRY_FILE]
    required = sources.flat_map { |file| File.read(file).scan(/^require\s+'([^']+)'/).flatten }.uniq
    missing = required.reject { |lib| header.include?("require '#{lib}'\n") }
    assert_empty missing, 'requires the bundle header lacks'
    assert_includes required, 'stringio'
  end

  def test_optional_requires_stay_inside_their_rescue
    %w[rainbow unicode/display_width].each do |lib|
      assert_match(/^begin\n  require '#{Regexp.escape(lib)}'/, bundle)
      refute_includes header, "require '#{lib}'"
    end
  end

  def test_bundled_program_runs
    Dir.mktmpdir('bundle') do |dir|
      path = File.join(dir, 'leeni')
      LatexBundler.write_bundle(path, verbose: false)
      out, status = Open3.capture2e(path, '-V')
      assert status.success?, out
      assert_match(/\Aleeni \d+\.\d+\.\d+/, out)
    end
  end
end
