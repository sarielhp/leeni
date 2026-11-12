# frozen_string_literal: true

# ==============================================================================
# lib/leeni/error_catalog_data.rb
#
# The compiler error table of LaTeXErrorCatalog: CATALOG, the error patterns
# with their explanations, fixes and extractors.
# Loaded by lib/leeni/error_catalog.rb after the helpers the tables call.
# ==============================================================================

module LaTeXErrorCatalog
  CATALOG = [
    {
      id: :misplaced_alignment_tab,
      pattern: /Misplaced alignment tab character &/i,
      title: 'Misplaced Alignment Tab Character (&)',
      token_extractor: lambda do |_match, err_block, file = nil, line = nil|
        extract_misplaced_tab_env(err_block, file, line)
      end,
      hint: ->(tok) { suggest_alignment_tab(tok) },
      why: "An alignment tab '&' was encountered outside a table or align environment.",
      fix: "Use an environment that supports '&' (e.g., align*, tabular) or write '\\&'.",
      doc_slug: '01_misplaced_alignment_tab'
    },
    {
      id: :undefined_control_sequence,
      pattern: /Undefined control sequence/i,
      title: 'Undefined Control Sequence',
      token_extractor: UNDEFINED_CS_EXTRACTOR,
      hint: lambda do |tok, file = nil, macro = nil, junk_dir = nil|
        suggest_command(tok, file: file, macro: macro, junk_dir: junk_dir)
      end,
      why: 'LaTeX does not recognize this macro or command name.',
      fix: 'Check for typos or include the package defining this macro in preamble.',
      doc_slug: '02_undefined_control_sequence'
    },
    {
      id: :missing_item,
      pattern: /perhaps a missing \\item/i,
      title: "Something's wrong--perhaps a missing \\item",
      hint: 'Text inside list without \\item; add \\item before list entries',
      why: 'Text was typed directly inside an itemize, enumerate, or description environment before any \\item.',
      fix: 'Add \\item before the text or check if \\begin{itemize} is misplaced.',
      doc_slug: '03_missing_item'
    },
    {
      id: :missing_dollar,
      pattern: /Missing \$ inserted/i,
      title: 'Missing $ inserted',
      token_extractor: lambda do |_match, err_block, file = nil, line = nil|
        extract_missing_dollar_info(err_block, file, line)
      end,
      hint: ->(tok) { suggest_missing_dollar(tok) },
      why: "A math-mode token was used in text mode or an unclosed '$' crossed a paragraph break.",
      fix: "Close the open '$' delimiter, enclose math in $...$, or escape literal characters (e.g., '\\_').",
      doc_slug: '04_missing_dollar'
    },
    {
      id: :extra_closing_brace,
      pattern: /(?:Too many }'s|Extra }, or forgotten \$)/i,
      title: "Too many }'s / Extra closing brace",
      hint: "Unmatched closing brace '}'; remove extra '}' or check balance",
      why: "A closing brace '}' was encountered without a matching opening brace '{'.",
      fix: "Remove the stray '}' or check brace nesting with 'leeni --check-braces'.",
      doc_slug: '05_extra_closing_brace'
    },
    {
      id: :paragraph_ended_before_complete,
      pattern: /(?:Paragraph ended before \S+ was complete|Runaway argument\?)/i,
      title: 'Paragraph ended before macro was complete / Runaway argument',
      hint: 'Unclosed brace across paragraph or blank line inside short macro argument',
      why: 'A macro argument containing an unclosed brace encountered a blank line / paragraph break.',
      fix: "Close the unclosed brace '{' or ensure no blank lines are inside macro arguments.",
      doc_slug: '06_paragraph_ended_before_complete'
    },
    {
      id: :environment_undefined,
      pattern: /Environment (\S+) undefined/i,
      title: 'Environment undefined',
      hint: lambda { |tok|
        tok ? "Undefined environment '#{tok}'; check spelling or \\usepackage" : 'Undefined environment; check spelling or \\usepackage'
      },
      why: 'The environment named in \\begin{...} is not defined by any loaded package.',
      fix: 'Check environment name spelling or load the package that provides it.',
      doc_slug: '07_environment_undefined'
    },
    {
      id: :no_line_here_to_end,
      pattern: /There's no line here to end/i,
      title: "There's no line here to end",
      hint: "Line break '\\\\' at start of paragraph or after section/math",
      why: "A line break '\\\\' or '\\newline' was issued when LaTeX was not in horizontal text mode.",
      fix: "Remove '\\\\' and use a blank line for paragraph separation, or \\vspace for vertical space.",
      doc_slug: '08_no_line_here_to_end'
    },
    {
      id: :file_not_found,
      pattern: /File `?([^']+)'? not found/i,
      title: 'File not found',
      hint: ->(tok) { LaTeXErrorCatalog.file_not_found_hint(tok) },
      why: 'An \\input{...}, \\include{...}, or \\usepackage{...} targeted a file that does not exist in TeX search path.',
      fix: 'Verify that the file exists and that the relative path is correct.',
      doc_slug: '09_file_not_found'
    },
    {
      id: :command_already_defined,
      pattern: /Command (\S+) already defined/i,
      title: 'Command already defined',
      hint: lambda { |tok|
        tok ? "Command '#{tok}' already defined; use \\renewcommand or rename" : 'Command already defined; use \\renewcommand or rename'
      },
      why: '\\newcommand tried to define a macro that already exists in LaTeX or a loaded package.',
      fix: 'Use \\renewcommand instead of \\newcommand, or choose a different macro name.',
      doc_slug: '10_command_already_defined'
    },
    {
      id: :extra_alignment_tab,
      pattern: /Extra alignment tab has been changed to \\cr/i,
      title: 'Extra alignment tab has been changed to \\cr',
      hint: "Too many '&' columns in table row; check column specifier",
      why: "A table or matrix row contains more '&' separators than defined in the column specification.",
      fix: 'Add another column to the environment preamble (e.g., {c|c|c}) or remove the extra ampersand.',
      doc_slug: '11_extra_alignment_tab'
    },
    {
      id: :missing_number_treated_as_zero,
      pattern: /Missing number, treated as zero/i,
      title: 'Missing number, treated as zero',
      hint: 'Missing numeric value; provide a number before dimension unit',
      why: 'TeX expected a numeric constant or dimension value but found text or a unit without a leading number.',
      fix: 'Provide a numeric value before the unit (e.g. \\hspace{10pt} instead of \\hspace{pt}).',
      doc_slug: '12_missing_number_treated_as_zero'
    },
    {
      id: :illegal_unit_of_measure,
      pattern: /Illegal unit of measure \(pt inserted\)/i,
      title: 'Illegal unit of measure (pt inserted)',
      hint: 'Missing length unit; append pt, cm, mm, in, or em',
      why: 'A dimension had a numeric value but omitted the measurement unit.',
      fix: 'Specify a valid TeX unit after the number (e.g. \\vspace{10pt} or \\setlength{\\parindent}{1cm}).',
      doc_slug: '13_illegal_unit_of_measure'
    },
    {
      id: :double_subscript,
      pattern: /Double subscript/i,
      title: 'Double subscript',
      hint: "Consecutive '_' subscripts; wrap in braces like 'x_{a_b}'",
      why: "Multiple subscript operators '_' were applied directly to the same base.",
      fix: 'Group the subscripts with curly braces: $x_{a_b}$ or $x_{a,b}$.',
      doc_slug: '14_double_subscript'
    },
    {
      id: :double_superscript,
      pattern: /Double superscript/i,
      title: 'Double superscript',
      hint: "Consecutive '^' superscripts; wrap in braces like 'x^{a^b}'",
      why: "Multiple superscript operators '^' were applied directly to the same base.",
      fix: 'Group the superscripts with curly braces: $x^{a^b}$ or $x^{a,b}$.',
      doc_slug: '15_double_superscript'
    },
    {
      id: :option_clash_for_package,
      pattern: /Option clash for package ([a-zA-Z0-9_-]+)/i,
      title: 'Option clash for package',
      hint: lambda { |tok|
        tok ? "Conflicting options for package '#{tok}'; pass all options in first \\usepackage" : 'Conflicting package options; unify options in first \\usepackage'
      },
      why: 'A package was loaded multiple times with mutually conflicting options.',
      fix: 'Move all required package options to the first \\usepackage call or use \\PassOptionsToPackage.',
      doc_slug: '16_option_clash_for_package'
    },
    {
      id: :lonely_item,
      pattern: /Lonely \\item--perhaps a missing list environment/i,
      title: 'Lonely \\item--perhaps a missing list environment',
      hint: '\\item used outside list; wrap in \\begin{itemize} or \\begin{enumerate}',
      why: 'An \\item command was used outside any list environment.',
      fix: 'Enclose items within \\begin{itemize}...\\end{itemize} or \\begin{enumerate}...\\end{enumerate}.',
      doc_slug: '17_lonely_item'
    },
    {
      id: :cannot_determine_size_of_graphic,
      pattern: /Cannot determine size of graphic in (\S+)/i,
      title: 'Cannot determine size of graphic',
      hint: ->(tok) { tok ? "Invalid image format or missing BoundingBox for '#{tok}'" : 'Invalid image format or missing BoundingBox' },
      why: 'The graphics driver cannot read the image file format or find its bounding box dimensions.',
      fix: 'Ensure the file is a valid PDF, PNG, or JPG, or convert it to a supported format.',
      doc_slug: '18_cannot_determine_size_of_graphic'
    },
    {
      id: :not_in_outer_par_mode,
      pattern: /Not in outer par mode/i,
      title: 'Not in outer par mode',
      hint: 'Float (figure/table) inside a box or minipage; move float outside or use minipage',
      why: 'A floating environment (figure or table) was placed inside a box (\\mbox, \\fbox) or inside another float.',
      fix: 'Move the figure/table outside the box, or use a non-floating minipage with \\captionof.',
      doc_slug: '19_not_in_outer_par_mode'
    },
    {
      id: :missing_delimiter,
      pattern: /Missing delimiter \(\. inserted\)/i,
      title: 'Missing delimiter (. inserted)',
      hint: "\\left or \\right without delimiter; use '.' for empty delimiter (e.g. '\\right.')",
      why: 'A \\left or \\right command was not followed by a valid delimiter character.',
      fix: "Specify a delimiter after \\left or \\right. Use a period '.' if no visible delimiter is desired.",
      doc_slug: '20_missing_delimiter'
    },
    {
      id: :only_in_preamble,
      pattern: /Can be used only in preamble/i,
      title: 'Can be used only in preamble',
      hint: 'Preamble command (like \\usepackage) used after \\begin{document}; move before \\begin{document}',
      why: 'A configuration command that can only run in the document preamble was executed in the document body.',
      fix: 'Move \\usepackage and configuration declarations before \\begin{document}.',
      doc_slug: '21_only_in_preamble'
    },
    {
      id: :extra_right,
      pattern: /Extra \\right\b/i,
      title: 'Extra \\right',
      hint: '\\right without matching \\left; check delimiter balance',
      why: 'A \\right delimiter was closed without a corresponding \\left delimiter earlier in the formula.',
      fix: "Ensure every \\right has a corresponding \\left, or use '\\left.' for an invisible opening delimiter.",
      doc_slug: '22_extra_right'
    },
    {
      id: :missing_begin_document,
      pattern: /Missing \\begin\{document\}/i,
      title: 'Missing \\begin{document}',
      hint: 'Printable text in preamble; move text after \\begin{document}',
      why: 'Text, characters, or typesetting commands appeared in the preamble before \\begin{document}.',
      fix: 'Move body text after \\begin{document} or remove stray characters from preamble.',
      doc_slug: '23_missing_begin_document'
    },
    {
      id: :dimension_too_large,
      pattern: /Dimension too large/i,
      title: 'Dimension too large',
      hint: 'Coordinate or dimension exceeds TeX maximum (~5.75m / 16383pt); check scaling',
      why: "A length, coordinate, or calculation exceeded TeX's arithmetic limit (16383.99999pt).",
      fix: 'Scale down coordinates, font size, or TikZ graph dimensions.',
      doc_slug: '24_dimension_too_large'
    },
    {
      id: :misplaced_noalign,
      pattern: /(?:Misplaced \\noalign|Misplaced \\omit)/i,
      title: 'Misplaced \\noalign / \\omit',
      hint: "\\hline or \\cline placed after content; must follow '\\\\' immediately",
      why: "\\hline or \\cline was placed in a table row after table cells rather than immediately after a newline '\\\\'.",
      fix: "Place \\hline or \\cline directly after '\\\\' with no intervening text.",
      doc_slug: '25_misplaced_noalign'
    },
    {
      id: :bad_math_environment_delimiter,
      pattern: /Bad math environment delimiter/i,
      title: 'Bad math environment delimiter',
      hint: "Mismatched inline/display math delimiters; match '\\(' with '\\)' or '\\[ ' with '\\]'",
      why: 'A LaTeX math delimiter was closed with a mismatched counterpart (e.g. \\( ... \\]).',
      fix: 'Match opening and closing delimiters: \\( ... \\) or \\[ ... \\].',
      doc_slug: '26_bad_math_environment_delimiter'
    },
    {
      id: :counter_too_large,
      pattern: /Counter(?: (\S+))? too large/i,
      title: 'Counter too large',
      hint: lambda { |tok|
        tok ? "Counter '#{tok}' exceeded limit (e.g. fnsymbol pool); reset or switch to numeric" : 'Counter exceeded limit (e.g. fnsymbol pool); reset or switch to numeric'
      },
      why: 'A counter representation (such as \\fnsymbol for footnotes) exceeded its fixed symbol pool.',
      fix: 'Reset the counter per page or switch to arabic numerals.',
      doc_slug: '27_counter_too_large'
    },
    {
      id: :amsmath_multiple_tag,
      pattern: /Multiple \\tag/i,
      title: 'Package amsmath: Multiple \\tag',
      hint: 'Multiple \\tag commands on same equation line; keep only one \\tag',
      why: 'More than one \\tag{...} was specified for a single equation.',
      fix: 'Remove the duplicate \\tag or use \\split / \\align for multi-line formulas.',
      doc_slug: '28_amsmath_multiple_tag'
    },
    {
      id: :undefined_color,
      pattern: /Undefined color `?([^']+)'?/i,
      title: 'Package xcolor: Undefined color',
      hint: lambda { |tok|
        tok ? "Undefined color '#{tok}'; define with \\definecolor or load colornames" : 'Undefined color; define with \\definecolor or load colornames'
      },
      why: 'A color name was passed to \\textcolor or \\colorbox that has not been defined.',
      fix: 'Define the color using \\definecolor or load \\usepackage[dvipsnames]{xcolor}.',
      doc_slug: '29_undefined_color'
    },
    {
      id: :mismatched_environment,
      pattern: /\\begin\{([^}]+)\} (?:on input line \d+ )?ended by \\end\{([^}]+)\}/i,
      title: 'Mismatched \\begin and \\end environments',
      token_extractor: ->(match, _block) { "#{match[1]} vs #{match[2]}" },
      hint: lambda { |tok|
        tok ? "Environment mismatch ('#{tok}'); ensure \\begin{foo} matches \\end{foo}" : 'Environment mismatch; ensure \\begin matches \\end'
      },
      why: 'An environment was opened with \\begin{foo} but closed with \\end{bar}.',
      fix: 'Ensure the environment name in \\end matches the opening \\begin.',
      doc_slug: '30_mismatched_environment'
    },
    {
      id: :missing_closing_brace,
      pattern: /Missing \} inserted/i,
      title: 'Missing } inserted',
      hint: "Unclosed math group or argument; insert matching '}'",
      why: 'A group or macro argument was opened with { but never closed before math mode or the line ended.',
      fix: 'Add the missing closing brace } before ending math or group.',
      doc_slug: '31_missing_closing_brace'
    },
    {
      id: :missing_endcsname,
      pattern: /Missing \\endcsname inserted/i,
      title: 'Missing \\endcsname inserted',
      hint: "Unclosed \\csname; terminate macro name with '\\endcsname'",
      why: 'A \\csname command was evaluated without finding a matching \\endcsname.',
      fix: 'Add \\endcsname to close the dynamic macro name.',
      doc_slug: '32_missing_endcsname'
    },
    {
      id: :cant_use_hrule_here,
      pattern: /You can't use `?\\hrule'? here/i,
      title: "You can't use \\hrule here except with leaders",
      hint: "\\hrule inside \\hbox; use '\\vrule' in horizontal boxes or move \\hrule outside",
      why: 'A horizontal rule \\hrule was placed inside a horizontal box (\\hbox).',
      fix: 'Use \\vrule for vertical rules in \\hbox, or place \\hrule in vertical mode.',
      doc_slug: '33_cant_use_hrule_here'
    },
    {
      id: :cant_use_spacefactor,
      pattern: /You can't use `?\\spacefactor'? in vertical mode/i,
      title: "You can't use \\spacefactor in vertical mode",
      hint: '\\spacefactor in vertical mode; set within paragraph or text mode',
      why: '\\spacefactor controls spacing between words and is only meaningful in horizontal mode.',
      fix: 'Ensure \\spacefactor is used within a paragraph.',
      doc_slug: '34_cant_use_spacefactor'
    },
    {
      id: :illegal_parameter_number,
      pattern: /Illegal parameter number in definition of (\S+)/i,
      title: 'Illegal parameter number in definition',
      hint: lambda { |tok|
        tok ? "Macro '#{tok}' uses parameters (#1) without declaring argument count [n]" : 'Macro uses parameters without declaring argument count'
      },
      why: 'A macro definition referenced #1 or #2 but omitted the parameter count declaration.',
      fix: 'Declare the number of arguments: \\newcommand{\\cmd}[1]{...}.',
      doc_slug: '35_illegal_parameter_number'
    },
    {
      id: :two_documentclass_commands,
      pattern: /Two \\documentclass(?: or \\documentstyle)? commands/i,
      title: 'LaTeX Error: Two \\documentclass commands',
      hint: 'Multiple \\documentclass declarations; keep only one in preamble',
      why: 'A LaTeX document can only have exactly one \\documentclass command.',
      fix: 'Remove the redundant \\documentclass declaration.',
      doc_slug: '36_two_documentclass_commands'
    },
    {
      id: :verb_illegal_in_argument,
      pattern: /\\verb illegal in argument/i,
      title: 'LaTeX Error: \\verb illegal in argument',
      hint: "\\verb inside command argument; use '\\texttt' or 'cprotect' package",
      why: '\\verb changes character category codes and cannot be passed inside command arguments.',
      fix: 'Use \\texttt{...} instead of \\verb, or load the cprotect package.',
      doc_slug: '37_verb_illegal_in_argument'
    },
    {
      id: :caption_outside_float,
      pattern: /\\caption outside float/i,
      title: 'LaTeX Error: \\caption outside float',
      hint: "\\caption outside figure/table; place in float or use '\\captionof' from 'caption' package",
      why: '\\caption was placed in standard text outside a figure or table environment.',
      fix: 'Move inside \\begin{figure} / \\begin{table}, or use \\captionof{figure}{...}.',
      doc_slug: '38_caption_outside_float'
    },
    {
      id: :use_of_doesnt_match_definition,
      pattern: /Use of (\S+) doesn't match its definition/i,
      title: "Use of command doesn't match its definition",
      hint: lambda { |tok|
        tok ? "Argument mismatch for delimited macro '#{tok}'; check delimiter syntax" : 'Argument mismatch for delimited macro; check delimiter syntax'
      },
      why: 'A delimited macro was defined with custom argument syntax but invoked with different delimiters.',
      fix: 'Match the macro delimiter structure (e.g. \\cmd(arg) instead of \\cmd{arg}).',
      doc_slug: '39_use_of_doesnt_match_definition'
    },
    {
      id: :ambiguous_math_fractions,
      pattern: /Ambiguous; you need another \{ and \}/i,
      title: 'Ambiguous; you need another { and }',
      hint: "Multiple '\\over' in same group; add braces or use '\\frac{a}{b}'",
      why: 'Multiple \\over commands in the same math subformula created ambiguity.',
      fix: 'Enclose each fraction in braces: ${{a \\over b} \\over c}$ or use \\frac.',
      doc_slug: '40_ambiguous_math_fractions'
    },
    {
      id: :cant_use_eqno_in_math,
      pattern: /You can't use `?\\eqno'? in math mode/i,
      title: "You can't use \\eqno in math mode",
      hint: "\\eqno used in inline math; use display math '\\[ ... \\]' or '\\tag'",
      why: '\\eqno attaches an equation number and is only valid in display math ($$).',
      fix: 'Switch from inline math ($...$) to display math (\\[ ... \\] or equation).',
      doc_slug: '41_cant_use_eqno_in_math'
    },
    {
      id: :package_babel_unknown_language,
      pattern: /Package babel Error: Unknown (?:language|option) [`']([^`'.]+)['`]/i,
      title: 'Package babel Error: Unknown language',
      hint: lambda { |tok|
        tok ? "Unknown babel language '#{tok}'; check spelling or texlive-lang" : 'Unknown babel language; check spelling or texlive-lang'
      },
      why: 'The language option passed to babel is not defined or installed.',
      fix: 'Verify language spelling (e.g. english, french, german) and install language packs.',
      doc_slug: '42_package_babel_unknown_language'
    },
    {
      id: :bad_register_code,
      pattern: /Bad register code/i,
      title: 'Bad register code',
      hint: 'Register number out of bounds; must be non-negative (use \\newcount)',
      why: 'A TeX register number was negative or exceeded the maximum register index.',
      fix: 'Use non-negative register numbers or allocate with \\newcount / \\newdimen.',
      doc_slug: '43_bad_register_code'
    },
    {
      id: :nested_include,
      pattern: /\\include cannot be nested/i,
      title: 'LaTeX Error: \\include cannot be nested',
      hint: "\\include called inside included file; replace secondary with '\\input'",
      why: '\\include manages page clears and aux files and cannot be called recursively.',
      fix: 'Use \\input{...} instead of \\include{...} inside secondary files.',
      doc_slug: '44_nested_include'
    },
    {
      id: :no_counter_defined,
      pattern: /No counter [`']([^`']+)['`] defined/i,
      title: 'LaTeX Error: No counter defined',
      hint: lambda { |tok|
        tok ? "Counter '#{tok}' does not exist; declare with \\newcounter{#{tok}}" : 'Counter does not exist; declare with \\newcounter'
      },
      why: 'A counter operation was performed on an undeclared counter name.',
      fix: 'Declare the counter with \\newcounter{...} or check spelling.',
      doc_slug: '45_no_counter_defined'
    },
    {
      id: :command_undefined,
      pattern: /Command `?(\\?\S+?)'? undefined/i,
      title: 'LaTeX Error: Command undefined',
      hint: lambda { |tok|
        tok ? "Command '#{tok}' is not defined; use \\newcommand instead of \\renewcommand" : 'Command is not defined; use \\newcommand instead of \\renewcommand'
      },
      why: '\\renewcommand was used on a macro that has not yet been declared.',
      fix: 'Use \\newcommand to define the command or check for typos in the name.',
      doc_slug: '46_command_undefined'
    },
    {
      id: :file_ended_while_scanning,
      pattern: /File ended while scanning (?:use|text) of (\\\S+?|\S+?)\.?$/i,
      title: 'File ended while scanning macro',
      hint: lambda { |tok|
        tok ? "Unclosed brace in argument of '#{tok}'; add missing '}' before EOF" : "Unclosed brace before end of file; add missing '}'"
      },
      why: 'End of file was reached while TeX was still looking for a closing brace.',
      fix: 'Add the missing closing curly brace } to terminate the macro argument.',
      doc_slug: '47_file_ended_while_scanning'
    },
    {
      id: :package_amsmath_split_wont_work,
      pattern: /\\begin\{split\} won't work here/i,
      title: "Package amsmath Error: \\begin{split} won't work here",
      hint: "\\begin{split} outside display math; wrap inside '\\begin{equation}'",
      why: 'split environment is only allowed inside an existing math display (equation, gather).',
      fix: 'Wrap \\begin{split} ... \\end{split} inside \\begin{equation} ... \\end{equation}.',
      doc_slug: '48_package_amsmath_split_wont_work'
    },
    {
      id: :package_amsmath_invalid_intertext,
      pattern: /Invalid use of \\intertext/i,
      title: 'Package amsmath Error: Invalid use of \\intertext',
      hint: "\\intertext inside 'equation'; switch to '\\begin{align}' or move outside",
      why: '\\intertext can only be used inside multi-line alignment environments like align.',
      fix: 'Use align instead of equation, or place text outside the math environment.',
      doc_slug: '49_package_amsmath_invalid_intertext'
    },
    {
      id: :unknown_float_option,
      pattern: /Unknown float option [`']([^`']+)['`]/i,
      title: 'LaTeX Error: Unknown float option',
      hint: ->(tok) { tok == 'H' ? "Float option '[H]' requires '\\usepackage{float}'" : "Invalid float option '#{tok}'; use [!htbp]" },
      why: 'An unrecognized float placement specifier was provided.',
      fix: 'Load \\usepackage{float} for [H] placement, or use standard specifiers [!htbp].',
      doc_slug: '50_unknown_float_option'
    },
    {
      id: :package_tikz_missing_semicolon,
      pattern: /Giving up on this path\. Did you forget a semicolon\?/i,
      title: 'Package tikz Error: Missing semicolon',
      hint: "Missing semicolon ';' at end of TikZ path command; append ';'",
      why: 'A TikZ \\draw, \\node, or \\path command was not terminated with a semicolon.',
      fix: 'Append a semicolon ; to the end of the path statement.',
      doc_slug: '51_package_tikz_missing_semicolon'
    },
    {
      id: :package_pgfkeys_unknown_key,
      pattern: /Package pgfkeys Error: I do not know the key [`']([^`']+)['`]/i,
      title: 'Package pgfkeys Error: Unknown key',
      hint: lambda { |tok|
        tok ? "Unknown pgfkeys option '#{tok}'; check spelling or load library" : 'Unknown pgfkeys option; check spelling or load library'
      },
      why: 'A key passed to a TikZ/PGF command is not recognized.',
      fix: 'Check the key spelling or load the required library (\\usetikzlibrary{...}).',
      doc_slug: '52_package_pgfkeys_unknown_key'
    },
    {
      id: :not_allowed_in_lr_mode,
      pattern: /Not allowed in LR mode/i,
      title: 'LaTeX Error: Not allowed in LR mode',
      hint: 'Block environment in LR mode; provide required arguments (e.g. \\begin{thebibliography}{99})',
      why: 'A paragraph-level or list environment was invoked inside horizontal LR mode.',
      fix: 'Check for missing mandatory arguments to environments or move outside LR box.',
      doc_slug: '53_not_allowed_in_lr_mode'
    },
    {
      id: :package_enumitem_key_undefined,
      pattern: /Package enumitem Error: (\S+) undefined/i,
      title: 'Package enumitem Error: Key undefined',
      hint: lambda { |tok|
        tok ? "Undefined enumitem key '#{tok}'; check documentation (e.g. label, leftmargin)" : 'Undefined enumitem key; check documentation'
      },
      why: 'An invalid option key was passed to an enumitem list environment.',
      fix: 'Use valid enumitem options like label, leftmargin, itemsep, or topsep.',
      doc_slug: '54_package_enumitem_key_undefined'
    },
    {
      id: :package_kvsetkeys_undefined_key,
      pattern: /Package kvsetkeys Error: Undefined key `?([^']+)'?/i,
      title: 'Package kvsetkeys Error: Undefined key',
      hint: ->(tok) { tok ? "Undefined setup key '#{tok}'; check macro setup options" : 'Undefined setup key; check macro setup options' },
      why: 'An unknown key was passed to a package setup command (e.g. \\hypersetup).',
      fix: 'Verify option name spelling in the setup declaration.',
      doc_slug: '55_package_kvsetkeys_undefined_key'
    },
    {
      id: :unclosed_group_at_end,
      pattern: /\\end\{document\} reached inside an (?:unclosed (.+? group) opened by '(.+?)'|unfinished (\\\w+) conditional)/,
      title: '\\end{document} reached inside an unclosed group',
      token_extractor: ->(match, _block) { match[2] || match[3] },
      hint: lambda { |tok|
        tok ? "Unclosed '#{tok}' still open at \\end{document}; close it" : 'Group still open at \\end{document}; close it'
      },
      why: 'A brace group, \\begingroup, math shift, or \\if conditional was opened and never closed, so the rest of the document ran inside it. TeX reports this only as a note and exits 0.',
      fix: 'Close the group or conditional on the reported line (usually a stray { or $ in the preamble, or a macro definition missing its final }).',
      doc_slug: '56_unclosed_group_at_end'
    },
    {
      id: :include_target_missing,
      pattern: /\\include target '(.+?)' not found/,
      title: '\\include target not found',
      token_extractor: ->(match, _block) { match[1] },
      hint: lambda { |tok|
        tok ? "Create '#{tok}' or fix the \\include name; LaTeX skips a missing \\include silently" : 'Fix the \\include name; LaTeX skips a missing \\include silently'
      },
      why: 'An \\include named a file that does not exist. Unlike \\input, \\include only notes "No file" in the log and continues, so the chapter is missing from the PDF.',
      fix: 'Create the file, correct the name in \\include{...}, or remove the \\include.',
      doc_slug: '57_include_target_missing'
    },
    {
      id: :missing_character,
      pattern: /Missing character: there is no (\S+)(?: \([^)]*\))? in font (.+?), so the glyph/,
      title: 'Missing character: glyph not in font',
      token_extractor: ->(match, _block) { match[1] },
      hint: lambda { |tok|
        tok ? "No glyph for '#{tok}' in the current font; switch fonts or replace the character" : 'No glyph in the current font; switch fonts or replace the character'
      },
      why: 'The current font has no glyph for a character in the source, so TeX typeset nothing in its place. TeX only notes this in the log and exits 0.',
      fix: 'Load a font that covers the character (fontspec with xelatex or lualatex), use the LaTeX command for the symbol, or remove the character.',
      doc_slug: '58_missing_character'
    },
    {
      id: :no_pages_of_output,
      pattern: /No pages of output: the document body typeset nothing/,
      title: 'No pages of output',
      hint: 'Document body produced no pages; check \\include targets, \\includeonly, and where \\end{document} sits',
      why: 'TeX shipped out no pages, so no PDF was written. The body between \\begin{document} and \\end{document} typeset nothing, usually because an \\include target is missing, \\includeonly excludes everything, or \\end{document} is misplaced.',
      fix: 'Make sure the document body contains typeset material and that every \\include target exists.',
      doc_slug: '59_no_pages_of_output'
    },
    {
      id: :pdf_driver_image_failed,
      pattern: /PDF driver could not include page (\d+) of image '(.+?)'/,
      title: 'PDF driver could not include an image page',
      token_extractor: ->(match, _block) { match[2] },
      hint: lambda { |tok|
        img = tok ? "'#{File.basename(tok)}'" : 'the image'
        "Image #{img} lacks that page or is unreadable; check the page= option against its page count"
      },
      why: 'XeTeX passes each image to its PDF driver, xdvipdfmx, which failed on it: usually \includegraphics[page=N] asks for a page the PDF does not have, or the file is damaged. The driver message goes only to the terminal; XeTeX itself either reports a bare driver return code or is killed mid-document, leaving truncated auxiliary files.',
      fix: 'Correct the page= option (pdfinfo shows the page count), or regenerate the image file.',
      doc_slug: '61_pdf_driver_image_failed'
    },
    {
      id: :pdf_driver_fatal,
      pattern: /PDF driver xdvipdfmx failed: (.+?), so no PDF was written/,
      title: 'PDF driver xdvipdfmx failed',
      token_extractor: ->(match, _block) { match[1] },
      hint: 'xdvipdfmx, the PDF driver of XeTeX, stopped; the cause is in its message',
      why: 'XeTeX writes its pages to xdvipdfmx, which turns them into the PDF. A fatal driver error ends the run without a PDF, and is printed only to the terminal, never to the .log file.',
      fix: 'Fix the image, font or special the message names; if unclear, try -e lualatex to see whether the input is at fault.',
      doc_slug: '62_pdf_driver_fatal'
    },
    {
      id: :invalid_in_math_mode,
      pattern: /Command (\\[A-Za-z@]+) invalid in math mode/,
      title: 'Command invalid in math mode',
      token_extractor: ->(match, _block) { match[1] },
      hint: ->(tok) { LaTeXErrorCatalog.math_mode_hint(tok) },
      why: 'A text font declaration or size switch was used inside math. Font declarations are rejected; size switches are silently ignored, so the formula keeps its default look.',
      fix: 'Use the math equivalent (\\mathbf, \\mathit, \\mathsf, \\mathtt, \\mathrm) or move the switch outside the formula.',
      doc_slug: '60_invalid_in_math_mode'
    },
    {
      id: :cannot_write_file,
      pattern: /I can't write on file\s+[`"'](?:"?)([^'"`]+?)(?:"?)['"`]/i,
      title: 'Cannot write to file',
      token_extractor: lambda do |match, _err_block, _file = nil, _line = nil|
        match[1]
      end,
      hint: lambda do |tok|
        dir = tok ? File.dirname(tok) : nil
        if dir && dir != '.'
          "Cannot write to '#{tok}'; target directory '#{dir}' does not exist or is not writable"
        else
          "Cannot write to '#{tok}'; target directory does not exist, or file is locked/read-only"
        end
      end,
      why: "TeX attempted to write an auxiliary file ('\\openout'), but the target path cannot be created because the directory does not exist or lacks write permissions.",
      fix: 'Ensure the target directory exists and is writable, or adjust the path in your LaTeX source.',
      doc_slug: '56_cannot_write_file'
    }
  ].freeze
end
