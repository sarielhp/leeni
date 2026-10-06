#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require 'fileutils'

class TestVisualVerification < Minitest::Test
  load File.expand_path('../leeni', __dir__)
  Status = Struct.new(:exitstatus) do
    def success?
      exitstatus == 0
    end
  end

  def with_packager
    Dir.mktmpdir('leeni_visual_test_') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('paper.tex', 'Source')
        File.write('paper.pdf', 'original')
        File.write('rebuilt.pdf', 'rebuilt')
        yield LatexArxivPackager.new(LatexBuilder.new('paper.tex', {}))
      end
    end
  end

  def render_stub(page_counts, contents = {})
    lambda do |*args|
      prefix = args[-1]
      pdf = File.basename(args[-2])
      count = page_counts.fetch(pdf, 1)
      count.times do |index|
        value = contents.fetch([pdf, index + 1], "P6\n2 1\n255\npage:#{index + 1}")
        File.write("#{prefix}-#{index + 1}.ppm", value)
      end
      ['', Status.new(0)]
    end
  end

  def visual_result(packager, command, available: true)
    LaTeXUtils.stub(:command_available?, available) do
      Open3.stub(:capture2e, command) do
        return yield if block_given?

        packager.send(:verify_arxiv_pdf_visual_match, 'paper.pdf', 'rebuilt.pdf')
      end
    end
  end

  def test_missing_renderer_fails_closed
    with_packager do |packager|
      _out, err = capture_io do
        refute visual_result(packager, nil, available: false)
      end
      assert_includes err, "requires 'pdftoppm'"
    end
  end

  def test_renderer_failure_fails_closed
    with_packager do |packager|
      _out, err = capture_io do
        refute visual_result(packager, ['renderer failed', Status.new(2)])
      end
      assert_includes err, 'could not render'
    end
  end

  def test_no_rendered_pages_fails_closed
    with_packager do |packager|
      _out, err = capture_io do
        refute visual_result(packager, ['', Status.new(0)])
      end
      assert_includes err, 'rendered no pages'
    end
  end

  def test_empty_rendered_page_fails_closed
    with_packager do |packager|
      command = lambda do |*args|
        FileUtils.mkdir_p(File.dirname(args[-1]))
        File.write("#{args[-1]}-1.ppm", '')
        ['', Status.new(0)]
      end
      _out, err = capture_io { refute visual_result(packager, command) }
      assert_includes err, 'rendered no pages'
    end
  end

  def test_empty_late_page_fails_closed
    with_packager do |packager|
      command = lambda do |*args|
        prefix = args[-1]
        File.write("#{prefix}-1.ppm", "P6\n2 1\n255\npage")
        File.write("#{prefix}-2.ppm", '')
        ['', Status.new(0)]
      end
      _out, err = capture_io { refute visual_result(packager, command) }
      assert_includes err, 'rendered no pages'
    end
  end

  def test_page_count_difference_fails_with_count_diagnostic
    with_packager do |packager|
      command = render_stub({ 'paper.pdf' => 1, 'rebuilt.pdf' => 2 })
      _out, err = capture_io { refute visual_result(packager, command) }
      assert_includes err, 'page count differs'
    end
  end

  def test_ppm_header_difference_is_detected
    with_packager do |packager|
      contents = {
        ['paper.pdf', 1] => "P6\n2 1\n255\nabc",
        ['rebuilt.pdf', 1] => "P6\n3 1\n255\nabc"
      }
      command = render_stub({ 'paper.pdf' => 1, 'rebuilt.pdf' => 1 }, contents)
      _out, err = capture_io { refute visual_result(packager, command) }
      assert_includes err, 'page 1'
    end
  end

  def test_late_page_difference_reports_that_page
    with_packager do |packager|
      contents = { ['rebuilt.pdf', 2] => "P6\n2 1\n255\ndifferent" }
      command = render_stub({ 'paper.pdf' => 2, 'rebuilt.pdf' => 2 }, contents)
      _out, err = capture_io { refute visual_result(packager, command) }
      assert_includes err, 'page 2'
    end
  end

  def test_tenth_page_is_compared_in_numeric_order
    with_packager do |packager|
      contents = { ['rebuilt.pdf', 10] => "P6\n2 1\n255\ndifferent" }
      command = render_stub({ 'paper.pdf' => 10, 'rebuilt.pdf' => 10 }, contents)
      _out, err = capture_io { refute visual_result(packager, command) }
      assert_includes err, 'page 10'
    end
  end

  def test_matching_pages_pass
    with_packager do |packager|
      command = render_stub({ 'paper.pdf' => 2, 'rebuilt.pdf' => 2 })
      assert visual_result(packager, command)
    end
  end

  def test_visual_check_is_not_called_when_text_check_fails
    with_packager do |packager|
      zip = File.join(Dir.pwd, 'archive.zip')
      File.write(zip, 'archive')
      compile = build_short_circuit_compile
      visual = lambda { flunk 'visual check should be short-circuited' }
      run_short_circuit_verification(packager, zip, compile, visual)
    end
  end

  def build_short_circuit_compile
    calls = 0
    lambda do |*args|
      calls += 1
      next ['', Status.new(0)] if calls == 1

      kwargs = args.last.is_a?(Hash) ? args.last : {}
      File.write(File.join(kwargs[:chdir], 'paper.pdf'), 'rebuilt')
      ['', Status.new(0)]
    end
  end

  def run_short_circuit_verification(packager, zip, compile, visual)
    packager.stub(:verify_arxiv_pdf_match, false) do
      packager.stub(:verify_arxiv_pdf_visual_match, visual) do
        LaTeXUtils.stub(:command_available?, true) do
          Open3.stub(:capture2e, compile) do
            refute packager.send(:verify_arxiv_sandbox!, zip, File.join(Dir.pwd, 'paper.pdf'))
          end
        end
      end
    end
  end
end
