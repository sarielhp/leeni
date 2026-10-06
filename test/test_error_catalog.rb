#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
load File.expand_path('../leeni', __dir__)

class TestErrorCatalog < Minitest::Test
  def test_classify_misplaced_alignment_tab
    text = "./main.tex:10: Misplaced alignment tab character &.\nl.10 x = 1 &"
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :misplaced_alignment_tab, item[:id]
    assert_includes item[:hint], '&'
    assert_equal '01_misplaced_alignment_tab', item[:doc_slug]
  end

  def test_classify_misplaced_alignment_tab_in_equation_star
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.tex')
      File.write(file, "\\documentclass{article}\n\\begin{document}\n\\begin{equation*}\n  x = 1 & y = 2\n\\end{equation*}\n\\end{document}\n")
      text = "#{file}:4: Misplaced alignment tab character &.\nl.4   x = 1 &"
      item = LaTeXErrorCatalog.classify(text, text.lines, file: file, line: 4)
      assert item
      assert_equal :misplaced_alignment_tab, item[:id]
      assert_equal 'equation*', item[:token]
      assert_includes item[:hint], "Misplaced '&' in 'equation*'; switch to 'align*'"
    end
  end

  def test_classify_misplaced_alignment_tab_in_text
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.tex')
      File.write(file, "\\documentclass{article}\n\\begin{document}\nHello AT&T world\n\\end{document}\n")
      text = "#{file}:3: Misplaced alignment tab character &.\nl.3 Hello AT&"
      item = LaTeXErrorCatalog.classify(text, text.lines, file: file, line: 3)
      assert item
      assert_equal :misplaced_alignment_tab, item[:id]
      assert_equal 'document', item[:token]
      assert_equal "Unescaped '&' in text; escape as '\\&'", item[:hint]
    end
  end

  def test_classify_misplaced_alignment_tab_in_displaymath
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.tex')
      File.write(file, "\\documentclass{article}\n\\begin{document}\n\\[\n  x = 1 & y = 2\n\\]\n\\end{document}\n")
      text = "#{file}:4: Misplaced alignment tab character &.\nl.4   x = 1 &"
      item = LaTeXErrorCatalog.classify(text, text.lines, file: file, line: 4)
      assert item
      assert_equal :misplaced_alignment_tab, item[:id]
      assert_equal '\\[ ... \\]', item[:token]
      assert_includes item[:hint], "Misplaced '&' in '\\[ ... \\]'; switch to 'align*'"
    end
  end

  def test_classify_misplaced_alignment_tab_in_tabular
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.tex')
      File.write(file, "\\documentclass{article}\n\\begin{document}\n\\begin{tabular}{c}\n  a & b \\\\\n\\end{tabular}\n\\end{document}\n")
      text = "#{file}:4: Misplaced alignment tab character &.\nl.4   a &"
      item = LaTeXErrorCatalog.classify(text, text.lines, file: file, line: 4)
      assert item
      assert_equal :misplaced_alignment_tab, item[:id]
      assert_equal 'tabular', item[:token]
      assert_includes item[:hint], "Extra '&' in 'tabular'; too many columns"
    end
  end

  def test_classify_undefined_control_sequence_extracts_token
    text = "./main.tex:5: Undefined control sequence.\nl.5 \\badcommand{foo}"
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :undefined_control_sequence, item[:id]
    assert_equal '\\badcommand', item[:token]
    assert_includes item[:hint], "Undefined command '\\badcommand'"
  end

  def test_classify_undefined_control_sequence_suggests_package
    text = "./main.tex:5: Undefined control sequence.\nl.5 \\toprule"
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :undefined_control_sequence, item[:id]
    assert_includes item[:hint], "Command '\\toprule' requires \\usepackage{booktabs}"
  end

  def test_classify_undefined_control_sequence_fuzzy_matches_typo
    text = "./main.tex:5: Undefined control sequence.\nl.5 \\alpa"
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :undefined_control_sequence, item[:id]
    assert_includes item[:hint], "Did you mean '\\alpha'?"
  end

  def test_classify_undefined_control_sequence_fuzzy_matches_lodts_to_ldots
    text = "./main.tex:5: Undefined control sequence.\nl.5 \\lodts"
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :undefined_control_sequence, item[:id]
    assert_equal '\\lodts', item[:token]
    assert_includes item[:hint], "Did you mean '\\ldots'?"
  end

  def test_classify_undefined_control_sequence_fuzzy_matches_package_macro
    text = "./main.tex:5: Undefined control sequence.\nl.5 \\includegrahics{fig.pdf}"
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :undefined_control_sequence, item[:id]
    assert_includes item[:hint], "Did you mean '\\includegraphics'? (requires \\usepackage{graphicx})"
  end

  def test_classify_undefined_control_sequence_in_macro_expansion
    err_lines = [
      "./t_cover.tex:208: Undefined control sequence.",
      "\\DotProd #1#2->\\permut ",
      "                       {{#1},{#2}}",
      "l.208 \\end{align*}"
    ]
    item = LaTeXErrorCatalog.classify(err_lines.join("\n"), err_lines)
    assert item
    assert_equal :undefined_control_sequence, item[:id]
    assert_equal '\\permut', item[:token]
    assert_includes item[:hint], "Undefined command '\\permut' (in expansion of '\\DotProd')"
    assert_includes item[:why], "encountered while expanding '\\DotProd'"
    assert_includes item[:fix], "Check definition of '\\DotProd'"
    refute_includes item[:hint], 'Did you mean'
  end

  def test_classify_undefined_control_sequence_root_location_in_align_environment
    Dir.mktmpdir('test_align_macro') do |dir|
      file = File.join(dir, 'doc.tex')
      File.write(file, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\begin{align*}
          x &= 1 \\\\
          \\DotProd{a}{b} \\\\
          y &= 2
        \\end{align*}
        \\end{document}
      TEX

      err_lines = [
        "#{file}:8: Undefined control sequence.",
        "\\DotProd #1#2->\\permut ",
        "                       {{#1},{#2}}",
        "l.8 \\end{align*}"
      ]
      item = LaTeXErrorCatalog.classify(err_lines.join("\n"), err_lines, file: file, line: 8)
      assert item
      assert_equal :undefined_control_sequence, item[:id]
      assert_equal '\\permut', item[:token]
      assert_equal 5, item[:root_line], "Expected root_line to point to line 5 containing \\DotProd"
      assert_equal 3, item[:root_col], "Expected root_col to point to \\DotProd"
    end
  end

  def test_classify_undefined_control_sequence_in_argument
    err_lines = [
      "! Undefined control sequence.",
      "<argument>  x &= 1 \\\\ y &= \\unknownMacro ",
      "                                         \\\\ z &= 2 ",
      "l.8 \\end{align*}"
    ]
    item = LaTeXErrorCatalog.classify(err_lines.join("\n"), err_lines)
    assert item
    assert_equal :undefined_control_sequence, item[:id]
    assert_equal '\\unknownMacro', item[:token]
    assert_includes item[:hint], "Undefined command '\\unknownMacro'"
  end

  def test_score_command_candidates_does_not_suggest_identical_command
    assert_nil LaTeXErrorCatalog.find_closest_command('end', [])
    assert_nil LaTeXErrorCatalog.find_closest_command('begin', [])
    hint = LaTeXErrorCatalog.suggest_command('end')
    refute_includes hint, "Did you mean '\\end'?"
  end

  def test_classify_missing_item
    text = "./main.tex:4: LaTeX Error: Something's wrong--perhaps a missing \\item."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :missing_item, item[:id]
    assert_includes item[:hint], '\\item'
  end

  def test_classify_missing_dollar
    text = "./main.tex:8: Missing $ inserted."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :missing_dollar, item[:id]
    assert_includes item[:hint], '$'
  end

  def test_classify_missing_dollar_subscript_in_text
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.tex')
      File.write(file, "\\documentclass{article}\n\\begin{document}\nVariable x_1 is here.\n\\end{document}\n")
      text = "#{file}:3: Missing $ inserted.\nl.3 Variable x_\n               1 is here."
      item = LaTeXErrorCatalog.classify(text, text.lines, file: file, line: 3)
      assert item
      assert_equal :missing_dollar, item[:id]
      assert_includes item[:hint], "Subscript '_' outside math mode"
    end
  end

  def test_classify_missing_dollar_unclosed_single
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.tex')
      File.write(file, "\\documentclass{article}\n\\begin{document}\nHere is an unclosed $x + y = z formula.\n\nNext paragraph.\n\\end{document}\n")
      text = "#{file}:4: Missing $ inserted.\nl.4"
      item = LaTeXErrorCatalog.classify(text, text.lines, file: file, line: 4)
      assert item
      assert_equal :missing_dollar, item[:id]
      assert_includes item[:hint], "Unclosed '$' opened on line 3"
    end
  end

  def test_classify_missing_dollar_unclosed_propagation
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.tex')
      content = [
        "\\documentclass{article}",
        "\\begin{document}",
        "Let $x be an arbitrary variable.",
        "We can compute $y = f(x)$ easily.",
        "Finally, we see that $z > 0$ holds.",
        "",
        "\\end{document}"
      ].join("\n")
      File.write(file, content)
      text = "#{file}:6: Missing $ inserted.\nl.6"
      item = LaTeXErrorCatalog.classify(text, text.lines, file: file, line: 6)
      assert item
      assert_equal :missing_dollar, item[:id]
      assert_includes item[:hint], "Unclosed '$' opened on line 3"
    end
  end

  def test_classify_missing_dollar_currency
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.tex')
      File.write(file, "\\documentclass{article}\n\\begin{document}\nThe ticket costs $50 each.\n\nNext paragraph.\n\\end{document}\n")
      text = "#{file}:4: Missing $ inserted.\nl.4"
      item = LaTeXErrorCatalog.classify(text, text.lines, file: file, line: 4)
      assert item
      assert_equal :missing_dollar, item[:id]
      assert_includes item[:hint], "Literal '$' in '$50'; escape as '\\$'"
    end
  end

  def test_classify_extra_closing_brace
    text = "./main.tex:12: Too many }'s."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :extra_closing_brace, item[:id]

    text2 = "./main.tex:12: Extra }, or forgotten $."
    item2 = LaTeXErrorCatalog.classify(text2, text2.lines)
    assert item2
    assert_equal :extra_closing_brace, item2[:id]
  end

  def test_classify_paragraph_ended_before_complete
    text = "Runaway argument?\n{some unclosed brace\nParagraph ended before \\foo was complete."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :paragraph_ended_before_complete, item[:id]
  end

  def test_classify_environment_undefined_extracts_token
    text = "./main.tex:3: LaTeX Error: Environment myenv undefined."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :environment_undefined, item[:id]
    assert_equal 'myenv', item[:token]
    assert_includes item[:hint], "Undefined environment 'myenv'"
  end

  def test_classify_no_line_here_to_end
    text = "./main.tex:6: LaTeX Error: There's no line here to end."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :no_line_here_to_end, item[:id]
  end

  def test_classify_file_not_found_extracts_token
    text = "./main.tex:2: LaTeX Error: File `myheader.sty' not found."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :file_not_found, item[:id]
    assert_equal 'myheader.sty', item[:token]
    assert_includes item[:hint], "File 'myheader.sty' not found"
  end

  def test_classify_command_already_defined_extracts_token
    text = "./main.tex:2: LaTeX Error: Command \\foo already defined."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :command_already_defined, item[:id]
    assert_equal '\\foo', item[:token]
    assert_includes item[:hint], "Command '\\foo' already defined"
  end

  def test_classify_extra_alignment_tab
    text = "./main.tex:4: Extra alignment tab has been changed to \\cr."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :extra_alignment_tab, item[:id]
  end

  def test_classify_missing_number_treated_as_zero
    text = "./main.tex:3: Missing number, treated as zero."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :missing_number_treated_as_zero, item[:id]
  end

  def test_classify_illegal_unit_of_measure
    text = "./main.tex:3: Illegal unit of measure (pt inserted)."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :illegal_unit_of_measure, item[:id]
  end

  def test_classify_double_subscript
    text = "./main.tex:3: Double subscript."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :double_subscript, item[:id]
  end

  def test_classify_double_superscript
    text = "./main.tex:3: Double superscript."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :double_superscript, item[:id]
  end

  def test_classify_option_clash_for_package_extracts_token
    text = "./main.tex:3: LaTeX Error: Option clash for package geometry."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :option_clash_for_package, item[:id]
    assert_equal 'geometry', item[:token]
    assert_includes item[:hint], "package 'geometry'"
  end

  def test_classify_lonely_item
    text = "./main.tex:3: LaTeX Error: Lonely \\item--perhaps a missing list environment."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :lonely_item, item[:id]
  end

  def test_classify_cannot_determine_size_of_graphic_extracts_token
    text = "./main.tex:3: LaTeX Error: Cannot determine size of graphic in mypic.xyz (no BoundingBox)."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :cannot_determine_size_of_graphic, item[:id]
    assert_equal 'mypic.xyz', item[:token]
  end

  def test_classify_not_in_outer_par_mode
    text = "./main.tex:3: LaTeX Error: Not in outer par mode."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :not_in_outer_par_mode, item[:id]
  end

  def test_classify_missing_delimiter
    text = "./main.tex:3: Missing delimiter (. inserted)."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :missing_delimiter, item[:id]
  end

  def test_classify_only_in_preamble
    text = "./main.tex:3: LaTeX Error: Can be used only in preamble."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :only_in_preamble, item[:id]
  end

  def test_classify_extra_right
    text = "./main.tex:3: Extra \\right."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :extra_right, item[:id]
  end

  def test_classify_missing_begin_document
    text = "./main.tex:3: LaTeX Error: Missing \\begin{document}."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :missing_begin_document, item[:id]
  end

  def test_classify_dimension_too_large
    text = "./main.tex:3: Dimension too large."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :dimension_too_large, item[:id]
  end

  def test_classify_misplaced_noalign
    text = "./main.tex:3: Misplaced \\noalign."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :misplaced_noalign, item[:id]
  end

  def test_classify_bad_math_environment_delimiter
    text = "./main.tex:3: LaTeX Error: Bad math environment delimiter."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :bad_math_environment_delimiter, item[:id]
  end

  def test_classify_counter_too_large
    text = "./main.tex:3: LaTeX Error: Counter too large."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :counter_too_large, item[:id]
  end

  def test_classify_amsmath_multiple_tag
    text = "./main.tex:3: Package amsmath Error: Multiple \\tag."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :amsmath_multiple_tag, item[:id]
  end

  def test_classify_undefined_color_extracts_token
    text = "./main.tex:3: Package xcolor Error: Undefined color `mycolor'."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :undefined_color, item[:id]
    assert_equal 'mycolor', item[:token]
    assert_includes item[:hint], "color 'mycolor'"
  end

  def test_classify_mismatched_environment_extracts_token
    text = "./main.tex:3: LaTeX Error: \\begin{itemize} on input line 3 ended by \\end{enumerate}."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :mismatched_environment, item[:id]
    assert_equal 'itemize vs enumerate', item[:token]
    assert_includes item[:hint], 'itemize vs enumerate'
  end

  def test_classify_missing_closing_brace
    text = "./main.tex:3: Missing } inserted."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :missing_closing_brace, item[:id]
  end

  def test_classify_missing_endcsname
    text = "./main.tex:3: Missing \\endcsname inserted."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :missing_endcsname, item[:id]
  end

  def test_classify_cant_use_hrule_here
    text = "./main.tex:3: You can't use `\\hrule' here except with leaders."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :cant_use_hrule_here, item[:id]
  end

  def test_classify_cant_use_spacefactor
    text = "./main.tex:3: You can't use `\\spacefactor' in vertical mode."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :cant_use_spacefactor, item[:id]
  end

  def test_classify_illegal_parameter_number
    text = "./main.tex:3: Illegal parameter number in definition of \\foo."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :illegal_parameter_number, item[:id]
  end

  def test_classify_two_documentclass_commands
    text = "./main.tex:3: LaTeX Error: Two \\documentclass or \\documentstyle commands."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :two_documentclass_commands, item[:id]
  end

  def test_classify_verb_illegal_in_argument
    text = "./main.tex:3: LaTeX Error: \\verb illegal in argument."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :verb_illegal_in_argument, item[:id]
  end

  def test_classify_caption_outside_float
    text = "./main.tex:3: LaTeX Error: \\caption outside float."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :caption_outside_float, item[:id]
  end

  def test_classify_use_of_doesnt_match_definition
    text = "./main.tex:3: Use of \\foo doesn't match its definition."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :use_of_doesnt_match_definition, item[:id]
  end

  def test_classify_ambiguous_math_fractions
    text = "./main.tex:3: Ambiguous; you need another { and }."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :ambiguous_math_fractions, item[:id]
  end

  def test_classify_cant_use_eqno_in_math
    text = "./main.tex:3: You can't use `\\eqno' in math mode."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :cant_use_eqno_in_math, item[:id]
  end

  def test_classify_package_babel_unknown_language
    text = "./main.tex:3: Package babel Error: Unknown option 'unknownlangxyz'."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :package_babel_unknown_language, item[:id]
    assert_equal 'unknownlangxyz', item[:token]
  end

  def test_classify_bad_register_code
    text = "./main.tex:3: Bad register code (-1)."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :bad_register_code, item[:id]
  end

  def test_classify_nested_include
    text = "./main.tex:3: LaTeX Error: \\include cannot be nested."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :nested_include, item[:id]
  end

  def test_classify_no_counter_defined
    text = "./main.tex:3: LaTeX Error: No counter 'mycounter' defined."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :no_counter_defined, item[:id]
    assert_equal 'mycounter', item[:token]
  end

  def test_classify_command_undefined
    text = "./main.tex:3: LaTeX Error: Command \\foo undefined."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :command_undefined, item[:id]
  end

  def test_classify_file_ended_while_scanning
    text = "! File ended while scanning use of \\foo."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :file_ended_while_scanning, item[:id]
    assert_equal '\\foo', item[:token]
  end

  def test_classify_package_amsmath_split_wont_work
    text = "./main.tex:3: Package amsmath Error: \\begin{split} won't work here."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :package_amsmath_split_wont_work, item[:id]
  end

  def test_classify_package_amsmath_invalid_intertext
    text = "./main.tex:3: Package amsmath Error: Invalid use of \\intertext."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :package_amsmath_invalid_intertext, item[:id]
  end

  def test_classify_unknown_float_option
    text = "./main.tex:3: LaTeX Error: Unknown float option 'H'."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :unknown_float_option, item[:id]
    assert_equal 'H', item[:token]
    assert_includes item[:hint], 'usepackage{float}'
  end

  def test_classify_package_tikz_missing_semicolon
    text = "./main.tex:3: Package tikz Error: Giving up on this path. Did you forget a semicolon?"
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :package_tikz_missing_semicolon, item[:id]
  end

  def test_classify_package_pgfkeys_unknown_key
    text = "./main.tex:3: Package pgfkeys Error: I do not know the key '/tikz/badkey', to which you passed '1'."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :package_pgfkeys_unknown_key, item[:id]
    assert_equal '/tikz/badkey', item[:token]
  end

  def test_classify_not_allowed_in_lr_mode
    text = "./main.tex:3: LaTeX Error: Not allowed in LR mode."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :not_allowed_in_lr_mode, item[:id]
  end

  def test_classify_package_enumitem_key_undefined
    text = "./main.tex:3: Package enumitem Error: badkey undefined."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :package_enumitem_key_undefined, item[:id]
    assert_equal 'badkey', item[:token]
  end

  def test_classify_package_kvsetkeys_undefined_key
    text = "./main.tex:3: Package kvsetkeys Error: Undefined key `mybadkey'."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :package_kvsetkeys_undefined_key, item[:id]
    assert_equal 'mybadkey', item[:token]
  end

  def test_classify_unknown_error_returns_nil
    text = "./main.tex:10: Some totally unheard of exotic error message."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert_nil item
  end

  def test_find_by_id
    entry = LaTeXErrorCatalog.find_by_id(:misplaced_alignment_tab)
    assert entry
    assert_equal 'Misplaced Alignment Tab Character (&)', entry[:title]

    assert_nil LaTeXErrorCatalog.find_by_id(:nonexistent_error_id)
  end

  def test_extract_errors_populates_catalog_id
    log_content = <<~LOG
      ./main.tex:5: Undefined control sequence.
      l.5 \\nonexistentmacro
    LOG

    builder = LatexBuilder.new('main.tex', {})
    errors = builder.send(:extract_errors, log_content)
    assert_equal 1, errors.size
    assert_equal :undefined_control_sequence, errors.first[:catalog_id]
    assert errors.first[:catalog]
    assert_equal '\\nonexistentmacro', errors.first[:catalog][:token]
  end
end
