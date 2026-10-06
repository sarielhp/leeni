#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestPathologicalLatex < Minitest::Test
  BIN = File.expand_path('../latex_it', __dir__)

  def test_missing_package_reports_nested_preamble_location
    with_project('missing_package') do |dir|
      write(dir, 'main.tex', "\\documentclass{article}\n\\input{config}\n\\begin{document}Text.\\end{document}\n")
      write(dir, 'config.tex', "\\usepackage{latex-it-definitely-missing-package}\n")

      out, status = compile(dir, 'main.tex')

      assert_equal 1, status.exitstatus, out
      assert_match(/^config\.tex:1(?::\d+)?: error: .*latex-it-definitely-missing-package\.sty.*not found/i, out)
      assert_match(/check file path or spelling/i, out)
    end
  end

  def test_missing_graphic_reports_nested_request_location
    with_project('missing_graphic') do |dir|
      write(dir, 'main.tex', "\\documentclass{article}\n\\usepackage{graphicx}\n\\begin{document}\n\\input{child}\n\\end{document}\n")
      write(dir, 'child.tex', "\\includegraphics{assets/definitely-missing-image}\n")

      out, status = compile(dir, 'main.tex')

      assert_equal 1, status.exitstatus, out
      assert_match(/^child\.tex:1(?::\d+)?: error: .*assets\/definitely-missing-image.*not found/i, out)
      refute_match(/^main\.tex:.*error:/, out)
    end
  end

  def test_missing_bibliography_database_names_the_resource
    with_project('missing_bibliography') do |dir|
      write(dir, 'main.tex', bibliography_document)

      out, status = compile(dir, '-e', 'pdflatex', 'main.tex')

      assert_equal 1, status.exitstatus, out
      assert_match(/definitely-missing-database\.bib/i, out)
      refute_match(/compilation failed; see log for details/i, out)
    end
  end

  def test_deep_error_followed_by_ancestor_error_keeps_both_locations
    with_project('ancestor_after_child') do |dir|
      write(dir, 'main.tex', document('\\input{level1}'))
      write(dir, 'level1.tex', "\\input{level2}\n\\ancestorTypodCommand\n")
      write(dir, 'level2.tex', "\\deepTypodCommand\n")

      out, status = compile(dir, 'main.tex')

      assert_equal 1, status.exitstatus, out
      assert_match(/^level2\.tex:1:1: error: undefined control sequence \\deepTypodCommand/, out)
      assert_match(/^level1\.tex:2:1: error: undefined control sequence \\ancestorTypodCommand/, out)
      refute_match(/^main\.tex:.*error:/, out)
    end
  end

  def test_real_input_cycle_fails_without_hanging_or_publishing_pdf
    with_project('input_cycle') do |dir|
      write(dir, 'main.tex', document('\\input{a}'))
      write(dir, 'a.tex', "\\input{b}\n")
      write(dir, 'b.tex', "\\input{a}\n")

      out, status = compile(dir, '--timeout', '5', 'main.tex')

      assert_equal 1, status.exitstatus, out
      assert_match(/capacity exceeded|input stack|recursive|compilation timed out/i, out)
      refute File.exist?(File.join(dir, 'main.pdf'))
      refute_match(/Traceback|SystemStackError/, out)
    end
  end

  def test_includeonly_does_not_diagnose_skipped_file
    with_project('includeonly') do |dir|
      write(dir, 'main.tex', includeonly_document)
      write(dir, 'included.tex', "Included text.\n")
      write(dir, 'skipped.tex', "\\skippedTypodCommand\n")

      out, status = compile(dir, 'main.tex')

      assert_equal 0, status.exitstatus, out
      assert_includes out, 'Compilation succeeded.'
      refute_includes out, 'skippedTypodCommand'
    end
  end

  def test_repeated_conditional_input_reports_only_failing_invocation
    with_project('conditional_repeat') do |dir|
      write(dir, 'main.tex', conditional_repeat_document)
      write(dir, 'shared.tex', "Shared text.\n\\ifshowerror\\conditionalTypodCommand\\fi\n")

      out, status = compile(dir, 'main.tex')

      assert_equal 1, status.exitstatus, out
      matches = out.scan(/^shared\.tex:2:\d+: error: undefined control sequence \\conditionalTypodCommand/)
      assert_equal 1, matches.size, out
      refute_match(/^main\.tex:.*error:/, out)
    end
  end

  def test_bom_crlf_and_missing_final_newline_preserve_child_location
    with_project('damaged_newlines') do |dir|
      write(dir, 'main.tex', "\uFEFF#{document('\\input{child}').gsub("\n", "\r\n")}")
      write(dir, 'child.tex', "Child text.\r\n\\newlineTypodCommand")

      out, status = compile(dir, 'main.tex')

      assert_equal 1, status.exitstatus, out
      assert_match(/^child\.tex:2:1: error: undefined control sequence \\newlineTypodCommand/, out)
      refute_match(/invalid byte sequence|Traceback/, out)
    end
  end

  def test_invalid_utf8_source_never_crashes_diagnostic_reader
    with_project('invalid_utf8') do |dir|
      write(dir, 'main.tex', document('\\input{child}'))
      write(dir, 'child.tex', "Bad byte: \xFF\n\\byteTypodCommand\n".b, binary: true)

      out, status = compile(dir, '-e', 'pdflatex', 'main.tex')

      assert_equal 1, status.exitstatus, out
      refute_match(/invalid byte sequence|Encoding::|Traceback/, out)
      assert_match(/child\.tex|invalid.*character|byteTypodCommand/i, out)
    end
  end

  def test_nested_error_attribution_is_consistent_across_available_engines
    engines = %w[pdflatex xelatex lualatex].select { |engine| executable?(engine) }
    refute_empty engines

    engines.each do |engine|
      with_project("engine_#{engine}") do |dir|
        write(dir, 'main.tex', document('\\input{child}'))
        write(dir, 'child.tex', "\\engineTypodCommand\n")
        out, status = compile(dir, '-e', engine, 'main.tex')

        assert_equal 1, status.exitstatus, "#{engine}: #{out}"
        assert_match(/^child\.tex:1:1: error: undefined control sequence \\engineTypodCommand/, out)
      end
    end
  end

  def test_custom_junk_directory_with_spaces_preserves_diagnostics
    with_project('spaced_junk') do |dir|
      write(dir, 'main.tex', document('\\input{child}'))
      write(dir, 'child.tex', "\\junkPathTypodCommand\n")

      out, status = compile(dir, '--junk-dir', 'build artifacts (temporary)', 'main.tex')

      assert_equal 1, status.exitstatus, out
      assert_match(/^child\.tex:1:1: error: undefined control sequence \\junkPathTypodCommand/, out)
      assert File.file?(File.join(dir, 'build artifacts (temporary)', 'main.log'))
    end
  end

  def test_failed_rebuild_does_not_replace_previous_pdf_or_claim_success
    with_project('stale_pdf') do |dir|
      write(dir, 'main.tex', document('First successful version.'))
      first_out, first_status = compile(dir, 'main.tex')
      pdf = File.join(dir, 'main.pdf')
      original_pdf = File.binread(pdf)
      write(dir, 'child.tex', "\\stalePdfTypodCommand\n")
      write(dir, 'main.tex', document('\\input{child}'))

      out, status = compile(dir, 'main.tex')

      assert_equal 0, first_status.exitstatus, first_out
      assert_equal 1, status.exitstatus, out
      assert_equal original_pdf, File.binread(pdf)
      refute_includes out, 'Compilation succeeded.'
      assert_match(/^child\.tex:1:1: error: undefined control sequence/, out)
    end
  end

  def test_inert_input_syntax_does_not_create_missing_file_errors
    with_project('inert_inputs') do |dir|
      write(dir, 'main.tex', inert_input_document)

      out, status = compile(dir, 'main.tex')

      assert_equal 0, status.exitstatus, out
      assert_includes out, 'Compilation succeeded.'
      refute_match(/not found|missing-commented|missing-verbatim|missing-unused/i, out)
    end
  end

  def test_same_basename_in_different_directories_keeps_full_paths
    with_project('duplicate_basenames') do |dir|
      write(dir, 'main.tex', document("\\input{chapters/a/shared}\n\\input{chapters/b/shared}"))
      write(dir, 'chapters/a/shared.tex', "\\firstSharedTypodCommand\n")
      write(dir, 'chapters/b/shared.tex', "\\secondSharedTypodCommand\n")

      out, status = compile(dir, 'main.tex')

      assert_equal 1, status.exitstatus, out
      assert_match(%r{^chapters/a/shared\.tex:1:1: error:.*\\firstSharedTypodCommand}, out)
      assert_match(%r{^chapters/b/shared\.tex:1:1: error:.*\\secondSharedTypodCommand}, out)
    end
  end

  def test_errors_inside_local_class_and_package_name_implementation_files
    with_project('class_and_package_errors') do |dir|
      write(dir, 'main.tex', class_and_package_document)
      write(dir, 'localbroken.cls', local_broken_class)
      write(dir, 'localbroken.sty', local_broken_package)

      out, status = compile(dir, 'main.tex')

      assert_equal 1, status.exitstatus, out
      assert_match(/^localbroken\.cls:4:1: error: undefined control sequence \\classTypodCommand/, out)
      assert_match(/^localbroken\.sty:3:1: error: undefined control sequence \\packageTypodCommand/, out)
      refute_match(/^main\.tex:.*error:/, out)
    end
  end

  def test_legal_cross_file_groups_conditionals_and_environments_compile
    with_project('cross_file_state') do |dir|
      write(dir, 'main.tex', cross_file_state_document)
      write(dir, 'open.tex', "{\\iftrue\\begin{quote}\nCross-file state.\n")
      write(dir, 'close.tex', "\\end{quote}\\fi}\n")

      out, status = compile(dir, 'main.tex')

      assert_equal 0, status.exitstatus, out
      assert_includes out, 'Compilation succeeded.'
      refute_match(/unclosed|ended by|extra/i, out)
    end
  end

  def test_malformed_cross_file_environment_reports_closing_file
    with_project('cross_file_mismatch') do |dir|
      write(dir, 'main.tex', cross_file_mismatch_document)
      write(dir, 'open.tex', "\\begin{itemize}\n\\item Entry\n")
      write(dir, 'close.tex', "\\end{enumerate}\n")

      out, status = compile(dir, 'main.tex')

      assert_equal 1, status.exitstatus, out
      assert_match(/^close\.tex:1(?::\d+)?: error: .*itemize.*ended by.*enumerate/i, out)
      refute_match(/^main\.tex:.*error:/, out)
    end
  end

  def test_repeated_failing_input_is_declustered_with_repeat_count
    with_project('repeated_failure') do |dir|
      write(dir, 'main.tex', document("\\input{shared}\n\\input{shared}"))
      write(dir, 'shared.tex', "\\repeatedTypodCommand\n")

      out, status = compile(dir, 'main.tex')

      assert_equal 1, status.exitstatus, out
      assert_equal 1, out.scan(/^shared\.tex:1:1: error:/).size, out
      assert_match(/repeated 2 times/i, out)
    end
  end

  def test_echoed_source_that_resembles_diagnostics_is_not_an_error
    with_project('diagnostic_prose') do |dir|
      write(dir, 'main.tex', diagnostic_prose_document)

      out, status = compile(dir, '-u', 'main.tex')

      logs = Dir[File.join(dir, 'junk', 'err_*')].map { |path| File.read(path) }.join("\n")
      assert_equal 0, status.exitstatus, "#{out}\n#{logs}"
      assert_includes out, 'Compilation succeeded.'
      refute_match(/error:|ghost\.sty.*not found|undefined control sequence/i, out)
    end
  end

  def test_bibliography_macro_error_maps_back_to_bib_field
    skip 'biber is unavailable' unless executable?('biber')

    with_project('bib_field_error') do |dir|
      write(dir, 'main.tex', biblatex_error_document)
      write(dir, 'refs.bib', broken_bibliography)

      out, status = compile(dir, 'main.tex')

      assert_equal 1, status.exitstatus, out
      assert_match(/refs\.bib:3:.*bibliography error in entry 'broken-entry'/i, out)
      assert_match(/\\UndefinedBibliographyMacro/, out)
    end
  end

  def test_endinput_ignores_invalid_trailing_source
    with_project('endinput') do |dir|
      write(dir, 'main.tex', document('\\input{child}'))
      write(dir, 'child.tex', "Visible text.\n\\endinput\n\\ignoredTypodCommand\n")

      out, status = compile(dir, 'main.tex')

      assert_equal 0, status.exitstatus, out
      assert_includes out, 'Compilation succeeded.'
      refute_includes out, 'ignoredTypodCommand'
    end
  end

  private

  def with_project(name)
    Dir.mktmpdir(name) { |dir| yield dir }
  end

  def write(dir, relative, content, binary: false)
    path = File.join(dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    binary ? File.binwrite(path, content) : File.write(path, content)
  end

  def compile(dir, *args)
    Open3.capture2e(BIN, '--compile', '--all', '--no-color', *args, chdir: dir)
  end

  def document(body)
    "\\documentclass{article}\n\\begin{document}\n#{body}\n\\end{document}\n"
  end

  def includeonly_document
    <<~TEX
      \\documentclass{article}
      \\includeonly{included}
      \\begin{document}
      \\include{included}
      \\include{skipped}
      \\end{document}
    TEX
  end

  def conditional_repeat_document
    <<~TEX
      \\documentclass{article}
      \\newif\\ifshowerror
      \\begin{document}
      \\showerrorfalse\\input{shared}
      \\showerrortrue\\input{shared}
      \\end{document}
    TEX
  end

  def inert_input_document
    <<~'TEX'
      \documentclass{article}
      \newcommand{\unused}{\input{missing-unused}}
      \begin{document}
      % \input{missing-commented}
      \begin{verbatim}
      \input{missing-verbatim}
      \end{verbatim}
      \IfFileExists{missing-probed.tex}{\input{missing-probed}}{Fallback text.}
      \end{document}
    TEX
  end

  def bibliography_document
    <<~TEX
      \\documentclass{article}
      \\begin{document}
      Missing citation: \\cite{missing-key}.
      \\bibliographystyle{plain}
      \\bibliography{definitely-missing-database}
      \\end{document}
    TEX
  end

  def class_and_package_document
    <<~TEX
      \\documentclass{localbroken}
      \\usepackage{localbroken}
      \\begin{document}Text.\\end{document}
    TEX
  end

  def local_broken_class
    <<~TEX
      \\NeedsTeXFormat{LaTeX2e}
      \\ProvidesClass{localbroken}
      \\LoadClass{article}
      \\classTypodCommand
    TEX
  end

  def local_broken_package
    <<~TEX
      \\NeedsTeXFormat{LaTeX2e}
      \\ProvidesPackage{localbroken}
      \\packageTypodCommand
    TEX
  end

  def cross_file_state_document
    <<~TEX
      \\documentclass{article}
      \\begin{document}
      \\input{open}
      \\input{close}
      \\end{document}
    TEX
  end

  def cross_file_mismatch_document
    <<~TEX
      \\documentclass{article}
      \\begin{document}
      \\input{open}
      \\input{close}
      \\end{itemize}
      \\end{document}
    TEX
  end

  def diagnostic_prose_document
    <<~'TEX'
      \documentclass{article}
      \begin{document}
      \hbox to 1pt{! LaTeX Error: File `ghost.sty' not found.}
      \hbox to 1pt{ghost.tex:12: Undefined control sequence.}
      \end{document}
    TEX
  end

  def biblatex_error_document
    <<~TEX
      \\documentclass{article}
      \\usepackage{biblatex}
      \\addbibresource{refs.bib}
      \\begin{document}
      \\nocite{*}
      \\printbibliography
      \\end{document}
    TEX
  end

  def broken_bibliography
    <<~BIB
      @article{broken-entry,
        author = {Example, Alice},
        title = {\\UndefinedBibliographyMacro},
        year = {2026}
      }
    BIB
  end

  def executable?(name)
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
      File.executable?(File.join(dir, name))
    end
  end
end
