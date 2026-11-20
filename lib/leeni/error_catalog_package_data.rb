# frozen_string_literal: true

# ==============================================================================
# lib/leeni/error_catalog_package_data.rb
#
# Entries of LaTeXErrorCatalog::CATALOG for package errors without a hint of
# their own in TeX (siunitx, memoize) and for runs that stop with no error
# message (another engine required, a \read from the terminal, a verbatim
# environment that swallowed the rest of the file). CATALOG splices them in
# at their place in the matching order.
# Loaded by lib/leeni/error_catalog.rb before lib/leeni/error_catalog_data.rb.
# ==============================================================================

module LaTeXErrorCatalog
  SILENT_AND_PACKAGE_CATALOG = [
    {
      id: :siunitx_incompatible_package,
      pattern: /Package siunitx Error: Package [`']([^']+)' incompatible/,
      title: 'Package siunitx Error: Package incompatible',
      token_extractor: ->(match, _block) { match[1] },
      hint: lambda { |tok|
        "siunitx cannot be used with the #{tok} package (both define the same commands, e.g. \\unit); " \
          "remove \\usepackage{#{tok}} and use siunitx's \\unit and \\qty instead"
      },
      why: 'siunitx refuses to load next to a package that defines the commands it provides (units and its \\unit, \\unitfrac). ' \
           'The clash also shows as "Command \\unit already defined" at the same \\usepackage, and siunitx repeats its error at \\begin{document}.',
      fix: 'Remove the other package and write its commands with siunitx (\\unit{\\metre\\per\\second}, \\qty{3}{\\metre}).',
      doc_slug: '83_siunitx_incompatible_package'
    },
    {
      id: :verbatim_environment_unclosed,
      pattern: /The file ended inside environment \{([^}]+)\}, which reads its body verbatim until \\end\{([^}]+)\}/,
      title: 'The file ended inside a verbatim environment',
      # A part of the message, so it is not appended to it again.
      token_extractor: ->(match, _block) { match[0][/\{.*/] },
      hint: lambda { |tok|
        name, stop = tok.to_s.scan(/\{([^}]+)\}/).flatten
        if name == stop
          "\\end{#{name}} was not recognised, so the rest of the file was read as its body: a comment-package " \
            "environment needs \\end{#{name}} alone at the start of a line (no indentation)"
        else
          "The begin code of \\lstnewenvironment{#{name}} opens {#{stop}}, so listings looks for \\end{#{stop}}; " \
            'do not open an environment in the begin code (use \\center ... \\endcenter or a box instead)'
        end
      },
      why: 'Verbatim-like environments (verbatim, listings, the comment package) read their body line by line until they find their own \\end. When that \\end is not recognised the whole rest of the file, \\end{document} included, is swallowed and TeX stops with no legal \\end.',
      fix: 'Write the \\end of the environment exactly as the package expects: alone, unindented for comment-package environments, and with no other environment opened in a \\lstnewenvironment begin code.',
      doc_slug: '86_verbatim_environment_unclosed'
    },
    {
      id: :control_sequence_already_defined,
      pattern: /LaTeX Error: Control sequence (\\\S+?) already defined/,
      title: 'LaTeX Error: Control sequence already defined',
      token_extractor: ->(match, _block) { match[1] },
      hint: lambda { |tok|
        "Two loaded packages both define #{tok}; load only one of them (unicode-math clashes with legacy " \
          'math-font packages such as newtxmath or stix2; fontawesome5 with the fontawesome6 that moderncv loads)'
      },
      why: 'A package defined a command with \\NewDocumentCommand or the expl3 equivalent that another package had already defined. unicode-math raises it for \\not= and similar when a legacy math-font package (newtxmath, stix2) is also loaded.',
      fix: 'Remove one of the clashing packages; with unicode-math, drop the legacy math-font packages.',
      doc_slug: '89_control_sequence_already_defined'
    },
    {
      id: :unbalanced_write,
      pattern: /Unbalanced write command/,
      title: 'Unbalanced write command',
      hint: 'A moving argument (\\caption, \\section) written to the .aux or .toc expanded to unbalanced braces: ' \
            'an active character (a babel shorthand such as french ; or :) or a fragile command; ' \
            'protect it (\\string; or \\protect), or load listings and similar packages after babel',
      why: 'Text that goes to the table of contents or the .aux is written at shipout. When it expands to unbalanced braces (an active character of a babel language redefined meanwhile, a fragile command), TeX cannot finish the \\write and stops with an Emergency stop at whatever line it was reading.',
      fix: 'Protect the offending character or command in the moving argument (\\string;, \\protect\\cmd), give a short optional argument for the entry, or load the package that changes catcodes after babel.',
      doc_slug: '87_unbalanced_write'
    },
    {
      id: :read_from_terminal,
      pattern: /\\read from a stream that is not open \(cannot \\read from terminal in nonstop modes\)/,
      title: 'cannot \\read from terminal in nonstop modes',
      hint: '\\read or \\readline used a stream that is not open, usually because the file given to \\openin does not exist; ' \
            'check the file name, and test \\ifeof right after \\openin before reading',
      why: 'A \\read from a closed stream asks the terminal for a line. In nonstop mode there is no terminal, so TeX stops with an Emergency stop at the line that read and prints no error message.',
      fix: 'Make sure the file opened with \\openin exists (it is looked up like \\input), and guard the reading loop with \\ifeof so a missing or finished file is not read.',
      doc_slug: '85_read_from_terminal'
    },
    {
      id: :engine_required,
      pattern: /Package (\S+) Error: ((?:XeTeX|LuaTeX)(?: or (?:XeTeX|LuaTeX))?) is required to compile this document/,
      title: 'XeTeX or LuaTeX is required to compile this document',
      hint: 'The package works only with the engine the message names: build with -e xelatex (XeTeX) or ' \
            '-e lualatex (LuaTeX), or remove the package (fontspec replaces xltxtra)',
      why: 'Packages such as xltxtra and xunicode (XeTeX) call \\RequireXeTeX or \\RequireLuaTeX, which print a banner and stop the run with an Emergency stop inside the package when another engine runs.',
      fix: 'Compile with the engine the package needs (l -e xelatex), or remove the package: fontspec covers xltxtra on XeLaTeX and LuaLaTeX.',
      doc_slug: '84_engine_required'
    },
    {
      id: :memoize_no_perl_pdf_module,
      pattern: /Package memoize \(perl-based extraction\) Error: No suitable Perl module for PDF processing/,
      title: 'Package memoize Error: No suitable Perl module for PDF processing',
      hint: 'memoize extracts externs with a Perl script that needs PDF::API2 or PDF::Builder: install one ' \
            '(libpdf-api2-perl, or cpan PDF::API2), or load memoize with [extract=python] (needs pypdf)',
      why: 'memoize writes each memoized picture to the PDF and cuts it out afterwards with an extraction script. ' \
           'The default script is in Perl and reads the PDF through PDF::API2 or PDF::Builder; with neither ' \
           'installed nothing is extracted, and the error is reported from the .mmz.log at the \\usepackage of memoize.',
      fix: 'Install the Perl module PDF::API2 (Debian/Ubuntu: libpdf-api2-perl), or use \\usepackage[extract=python]{memoize} with the Python module pypdf installed.',
      doc_slug: '82_memoize_no_perl_pdf_module'
    }
  ].freeze
end
