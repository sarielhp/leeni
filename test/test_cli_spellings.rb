# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'

load File.expand_path('../leeni', __dir__)

class TestCLISpellings < Minitest::Test
  BIN = File.expand_path('../leeni', __dir__)

  def test_long_option_prefixes_and_omitted_dashes
    canonical = %w[zip-alone single-pass no-env no-styles-inject update-if-changed arxiv-visual-verify config-show errors-only]
    canonical.each do |name|
      %w[- --].each do |prefix|
        [name, name.delete('-')].each do |spelling|
          argv = ["#{prefix}#{spelling}"]
          LatexCLI.normalize_argv!(argv)
          assert_equal ["--#{name}"], argv
        end
      end
    end
    %w[-no-stylesinject --nostyles-inject -arxivvisual-verify --arxiv-visualverify].each do |flag|
      argv = [flag]
      LatexCLI.normalize_argv!(argv)
      expected = flag.include?('styles') ? '--no-styles-inject' : '--arxiv-visual-verify'
      assert_equal [expected], argv
    end
  end

  def test_parser_applies_positive_negative_and_value_options
    options = LatexCLI.build_default_options({}, 'l', [])
    argv = %w[-singlepass --nostylesinject -nocolor -alert-hbox=30 --junkdir build --noarxivvisualverify]
    LatexCLI.normalize_argv!(argv)
    LatexCLI.build_option_parser(options).parse!(argv)
    assert_empty argv
    assert_equal true, options[:single_pass]
    assert_equal false, options[:inject_styles]
    assert_equal false, options[:color]
    assert_equal 30.0, options[:alert_overfull_pt]
    assert_equal 'build', options[:junk_dir]
    assert_equal false, options[:arxiv_visual_verify]
  end

  def test_values_and_operands_keep_their_spelling
    argv = %w[-zipname --noenv --theme -cc -context -3 -junkdir=-no-env -- -zipalone --noenv -B refs.bib]
    LatexCLI.normalize_argv!(argv)
    assert_equal %w[--zip-name --noenv --theme -cc --context -3 --junk-dir=-no-env -- -zipalone --noenv -B refs.bib], argv
    argv = %w[-fn 3 -e -noenv -zt -cc -llm -3]
    LatexCLI.normalize_argv!(argv)
    assert_equal %w[-fn 3 -e -noenv -zt --compile --llm --context=3], argv
    argv = %w[--zipname -B refs.bib]
    LatexCLI.normalize_argv!(argv)
    assert_equal %w[--zip-name -B refs.bib], argv
    argv = %w[-- paper.tex -zipalone]
    assert_empty LatexCLI.extract_extra_cli_files(argv)
    assert_equal %w[-- paper.tex -zipalone], argv
    argv = %w[-theme -zipalone -- paper.tex]
    assert_empty LatexCLI.extract_extra_cli_files(argv)
    assert_equal %w[-theme -zipalone -- paper.tex], argv
  end

  def test_grouped_short_flags_still_parse
    options = LatexCLI.build_default_options({}, 'l', [])
    argv = %w[-zt -fn 3]
    LatexCLI.normalize_argv!(argv)
    LatexCLI.build_option_parser(options).parse!(argv)
    assert_empty argv
    %i[zip verify force].each { |key| assert_equal true, options[key] }
    assert_equal 3, options[:passes]
  end

  def test_errors_only_overrides_configured_werror_and_all
    options = LatexCLI.build_default_options({ 'werror' => true }, 'l', [])
    LatexCLI.build_option_parser(options).parse!(%w[--all --errors-only])
    %i[suppress_alerts suppress_warnings suppress_whatevers].each do |key|
      assert_equal true, options[key]
    end
    assert_equal false, options[:all]
    assert_equal false, options[:werror]
    assert_equal true, options[:errors_only]

    LatexCLI.build_option_parser(options).parse!(%w[--all --werror])
    %i[suppress_alerts suppress_warnings suppress_whatevers].each do |key|
      assert_equal false, options[key]
    end
    assert_equal true, options[:werror]
    assert_equal false, options[:errors_only]
  end

  def test_packaging_spelling_variants_harvest_extra_files
    %w[-zipalone --zipalone -zip-alone --zip-alone -zipflat -arxivname=upload.zip].each do |flag|
      argv = [flag, 'paper.tex', '--', '-noenv']
      assert_equal ['-noenv'], LatexCLI.extract_extra_cli_files(argv), flag
      assert_equal [flag, 'paper.tex'], argv
    end
  end

  def test_bibliography_name_normalization_works_with_compact_flags
    argv = %w[-bibextract=refs.bib paper.tex]
    LatexCLI.normalize_argv!(argv)
    assert_equal %w[--bib-extract --bib-name refs.bib paper.tex], argv
  end

  def test_unknown_options_are_not_rewritten
    argv = %w[--notarealoption -zt --one-pass --envfree]
    LatexCLI.normalize_argv!(argv)
    assert_equal %w[--notarealoption -zt --one-pass --envfree], argv
  end

  def test_cli_accepts_single_dash_compact_and_partial_spellings
    %w[-helpall --helpall -help-all].each do |flag|
      output, status = Open3.capture2e(BIN, flag)
      assert status.success?, output
      assert_includes output, '--zip-alone'
    end
    output, status = Open3.capture2e(BIN, '-version')
    assert status.success?, output
  end
end
