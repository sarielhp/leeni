# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require 'fileutils'

require_relative '../lib/leeni/utils'
require_relative '../lib/leeni/builder'
require_relative '../lib/leeni/bib_extractor'
load File.expand_path('../leeni', __dir__) unless defined?(LatexCLI)

class TestBibExtractor < Minitest::Test
  def setup
    @bin_path = File.expand_path('../leeni', __dir__)
  end

  def test_count_bib_stats
    dummy_builder = Struct.new(:filename, :bfilename, :bdir, :options).new('test.tex', 'test', '.', {})
    extractor = LaTeXBibExtractor.new(dummy_builder)

    bib_text = <<~'BIB'
      @string{ieee = "IEEE"}
      @string{tc = ieee # " Trans. Comp."}
      @comment{Some notes}
      @preamble{"% Created by bibtool"}

      @article{knuth1984,
        author = {Knuth, Donald E.},
        title = {Literate Programming},
        journal = tc,
        year = {1984}
      }

      @inproceedings{focs2020,
        author = {Alice},
        title = {Fast Algo},
        crossref = {proc2020}
      }
    BIB

    stats = extractor.send(:count_bib_stats, bib_text)
    assert_equal 2, stats[:strings]
    assert_equal 2, stats[:entries]
  end

  def test_refuse_writing_to_global_bib_dir
    Dir.mktmpdir('global_bib_safety') do |dir|
      global_dir = File.join(dir, 'global_bibs')
      project_dir = File.join(dir, 'paper')
      FileUtils.mkdir_p(global_dir)
      FileUtils.mkdir_p(project_dir)

      dummy_builder = Struct.new(:filename, :bfilename, :bdir, :options).new(
        'paper.tex', 'paper', project_dir, { bib_dirs: [global_dir] }
      )
      unsafe_out = File.join(global_dir, 'master.bib')
      extractor = LaTeXBibExtractor.new(dummy_builder, unsafe_out)

      safe = extractor.send(:validate_target_safety!, File.expand_path(unsafe_out))
      refute safe, 'Expected validate_target_safety! to reject writing to global_dir'
    end
  end

  def test_backup_logic_preserves_previous_file
    Dir.mktmpdir('backup_test') do |dir|
      dummy_builder = Struct.new(:filename, :bfilename, :bdir, :options).new('paper.tex', 'paper', dir, {})
      extractor = LaTeXBibExtractor.new(dummy_builder)

      target = File.join(dir, 'paper.bib')
      File.write(target, "old content\n")

      Dir.chdir(dir) do
        extractor.send(:backup_existing_target!, 'paper.bib')
        assert File.file?(File.join(dir, 'paper.bib.bak'))
        assert_equal "old content\n", File.read(File.join(dir, 'paper.bib.bak'))

        File.write(target, "new content\n")
        extractor.send(:backup_existing_target!, 'paper.bib')
        bak_files = Dir.glob(File.join(dir, 'paper.bib.*.bak'))
        assert_equal 1, bak_files.size
      end
    end
  end

  def test_end_to_end_bib_extraction
    skip 'bibtool not available' unless LaTeXUtils.command_available?('bibtool')

    Dir.mktmpdir('bib_extract_e2e') do |dir|
      tex_content = <<~'TEX'
        \documentclass{article}
        \begin{document}
        Citing \cite{used1} and \cite{used2}.
        \bibliographystyle{plain}
        \bibliography{all}
        \end{document}
      TEX

      bib_content = <<~'BIB'
        @string{ieee = "IEEE"}
        @string{tc = ieee # " Trans. Comp."}
        @string{unused_string = "Unused"}

        @article{used1,
          author = {Euler, Leonhard},
          title = {Number Theory},
          journal = tc,
          year = {1750}
        }

        @inproceedings{used2,
          author = {Gauss, Carl F.},
          title = {Disquisitiones},
          crossref = {proc2020}
        }

        @proceedings{proc2020,
          title = {Proc. 2020 Conf},
          booktitle = {Proc. 2020 Conf},
          year = {2020}
        }

        @article{unused_entry,
          author = {Nobody},
          title = {Ignored},
          year = {1999}
        }
      BIB

      File.write(File.join(dir, 'paper.tex'), tex_content)
      File.write(File.join(dir, 'all.bib'), bib_content)

      out, status = Open3.capture2e(@bin_path, '-B', 'paper.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected l -B to exit 0. Output:\n#{out}"

      local_bib = File.join(dir, 'paper.bib')
      assert File.file?(local_bib), "Expected #{local_bib} to exist"

      extracted = File.read(local_bib)
      assert_includes extracted, 'used1'
      assert_includes extracted, 'used2'
      assert_includes extracted, 'proc2020'
      assert_includes extracted, 'ieee'
      refute_includes extracted, 'unused_entry'
      refute_includes extracted, 'unused_string'

      # Second extraction creates backup
      out2, status2 = Open3.capture2e(@bin_path, '-B', 'paper.tex', chdir: dir)
      assert_equal 0, status2.exitstatus, "Expected second run to succeed. Output:\n#{out2}"
      assert File.file?(File.join(dir, 'paper.bib.bak')), 'Expected paper.bib.bak to be created'
    end
  end

  def test_custom_bib_name_and_hint
    skip 'bibtool not available' unless LaTeXUtils.command_available?('bibtool')

    Dir.mktmpdir('bib_extract_custom') do |dir|
      tex_content = <<~'TEX'
        \documentclass{article}
        \begin{document}
        Citing \cite{k84}.
        \bibliographystyle{plain}
        \bibliography{global_refs}
        \end{document}
      TEX

      bib_content = <<~'BIB'
        @article{k84,
          author = {Knuth, Donald},
          title = {Literate Programming},
          journal = {CJ},
          year = {1984}
        }
      BIB

      File.write(File.join(dir, 'doc.tex'), tex_content)
      File.write(File.join(dir, 'global_refs.bib'), bib_content)

      # Test custom .bib name passed positionally after -B
      out, status = Open3.capture2e(@bin_path, '-B', 'custom.bib', 'doc.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected custom.bib extraction to succeed. Output:\n#{out}"
      assert File.file?(File.join(dir, 'custom.bib'))
      assert_includes out, 'Update doc.tex to \bibliography{custom}'
    end
  end

  def test_arg_normalization
    args = ['-B', 'paper.tex']
    LatexCLI.normalize_bib_extract_args!(args)
    assert_equal ['-B', 'paper.tex'], args

    args = ['-B', 'custom.bib', 'paper.tex']
    LatexCLI.normalize_bib_extract_args!(args)
    assert_equal ['--bib-extract', '--bib-name', 'custom.bib', 'paper.tex'], args

    args = ['--bib-extract=foo.bib', 'paper.tex']
    LatexCLI.normalize_bib_extract_args!(args)
    assert_equal ['--bib-extract', '--bib-name', 'foo.bib', 'paper.tex'], args
  end

  def test_is_biblatex_detection_with_attributes
    Dir.mktmpdir('bcf_detect_test') do |dir|
      junk_dir = File.join(dir, 'junk')
      FileUtils.mkdir_p(junk_dir)

      bcf_content = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <bcf:controlfile xmlns:bcf="https://sourceforge.net/projects/biblatex">
          <bcf:citekey order="1" intorder="1">clrs-ia-01</bcf:citekey>
        </bcf:controlfile>
      XML
      File.write(File.join(junk_dir, 'paper.bcf'), bcf_content)

      dummy_builder = Struct.new(:filename, :bfilename, :bdir, :options).new('paper.tex', 'paper', dir, {})
      extractor = LaTeXBibExtractor.new(dummy_builder)

      Dir.chdir(dir) do
        assert extractor.send(:is_biblatex?)
      end
    end
  end
end
