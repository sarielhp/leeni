# frozen_string_literal: true

# ==============================================================================
# lib/leeni/error_catalog_lookup.rb
#
# Lookup tables of LaTeXErrorCatalog: the package each command needs
# (PACKAGE_COMMANDS), commands every LaTeX knows (COMMON_COMMANDS), and the
# explanations of warnings and alerts (WARNING_EXPLANATIONS).
# Loaded by lib/leeni/error_catalog.rb.
# ==============================================================================

module LaTeXErrorCatalog
  PACKAGE_COMMANDS = {
    'toprule' => 'booktabs',
    'midrule' => 'booktabs',
    'bottomrule' => 'booktabs',
    'cmidrule' => 'booktabs',
    'specialrule' => 'booktabs',
    'mathbb' => 'amssymb',
    'mathfrak' => 'amssymb',
    'checkmark' => 'amssymb',
    'triangleq' => 'amssymb',
    'coloneqq' => 'mathtools',
    'DeclarePairedDelimiter' => 'mathtools',
    'bm' => 'bm',
    'url' => 'hyperref or url',
    'nolinkurl' => 'hyperref or url',
    'href' => 'hyperref',
    'hypersetup' => 'hyperref',
    'includegraphics' => 'graphicx',
    'graphicspath' => 'graphicx',
    'rotatebox' => 'graphicx',
    'resizebox' => 'graphicx',
    'color' => 'xcolor',
    'textcolor' => 'xcolor',
    'colorbox' => 'xcolor',
    'definecolor' => 'xcolor',
    'subcaption' => 'subcaption',
    'subfloat' => 'subcaption',
    'cancel' => 'cancel',
    'sout' => 'ulem',
    'hl' => 'soul',
    'lstinline' => 'listings',
    'lstinputlisting' => 'listings',
    'tikz' => 'tikz',
    'node' => 'tikz',
    'coordinate' => 'tikz',
    'microtypesetup' => 'microtype',
    'text' => 'amsmath',
    'eqref' => 'amsmath',
    'DeclareMathOperator' => 'amsmath',
    'boldsymbol' => 'amsmath',
    'intertext' => 'amsmath'
  }.freeze

  COMMON_COMMANDS = %w[
    acute addcontentsline alpha appendix appendixname approx arabic atop
    author bar begin beginend beta bfseries bibitem bibliography
    bibliographystyle bigcap bigcup Bigg bigg Biggl biggl Bigl
    bigl bigskip boldmath breve cap caption cdot cdots
    centering chapter chaptermark chaptername check chi circ cite
    citep citet citeyear cleardoublepage clearpage cline columnwidth contentsline
    contentsname cos cup date ddot ddots Delta delta
    det displaystyle div documentclass dot dots emph end
    enlargethispage ensuremath epsilon equiv eta exists exp fbox
    figurename flushbottom fontencoding fontfamily fontseries fontshape fontsize footnote
    footnotemark footnotesize footnotetext footref forall fpeval frac frame
    framebox Gamma gamma ge geq glossary glossaryentry grave
    hat hline hlinefill hrule hspace Huge huge i
    iff iint IJ ij implies in include includegraphics
    includeonly index indexname indexspace inf infty input inputlineno
    int inteval iota item itshape kappa kill label
    Lambda lambda LARGE Large large LaTeX LaTeXe ldots
    le left Leftarrow leftarrow lefteqn Leftrightarrow leq lim
    linebreak linespread linethickness linewidth listfigurename listfiles listoffigures listoftables
    listtablename ln log makeatletter makeatother makeglossary makeindex maketitle
    mapsto marginpar markboth markright mathbb mathbf mathcal mathdollar
    mathds mathellipsis mathgroup mathit mathnormal mathparagraph mathring mathrm
    mathscr mathsection mathsf mathsterling mathtt mathunderscore max mbox
    medskip medspace mid min mu multicolumn nabla ne
    neg negmedspace negthickspace neq newcommand newenvironment newlength newline
    newpage newtheorem nocite nofiles noindent nolinebreak nonumber nopagebreak
    normalcolor normalfont normalsize notin nu OE oe oint
    oldstylenums Omega omega onecolumn over overbrace overline pagebreak
    pagename pagenumbering pageref pagestyle paragraph parbox parencite part
    partial partname Phi phi Pi pi pm poptabs
    pounds prime prod protect providecommand Psi psi pushtabs
    r raggedleft raggedright Ref ref refname renewcommand renewenvironment
    rho right Rightarrow rightarrow rightmargin rightmark rmfamily Roman
    roman rule sbox scriptsize scshape section selectfont setlength
    setminus sffamily shortcite shortstack Sigma sigma sim simeq
    sin slshape small smallskip sqrt SS stackrel stepcounter
    stop subitem subparagraph subsection subset subseteq subsubitem subsubsection
    sum sup suppressfloats supset supseteq symbol tablename tableofcontents
    tabularnewline tan tau text textasciicircum textasciitilde textasteriskcentered textbackslash
    textbar textbf textbraceleft textbraceright textbullet textcircled textcite textcommaabove
    textcommabelow textcompwordmark textcopyright textdagger textdaggerdbl textdollar textellipsis textemdash
    textendash textexclamdown textgreater textheight textit textless textmd textnormal
    textparagraph textperiodcentered textquestiondown textquotedblleft textquotedblright textquoteleft textquoteright textregistered
    textrm textsc textsection textsf textsl textsterling textsubscript textsuperscript
    texttrademark texttt textunderscore textup textvisiblespace textwidth thanks Theta
    theta thickspace thispagestyle tilde time times tiny title
    to today ttfamily twocolumn unboldmath underbrace underline upshape
    Upsilon upsilon usepackage varbigtriangledown varbigtriangleup varepsilon varphi varpi
    varrho varsigma vartheta vdots vec vee verb vline
    vspace wedge widehat widetilde width Xi xi zeta
  ].freeze

  WARNING_EXPLANATIONS = {
    multiply_defined_label: {
      title: 'Error: Multiply-Defined Label',
      why: 'Two or more \\label{...} tags share the identical key; every \\ref silently resolves to whichever definition came last. LaTeX only warns, leeni flags it as an error.',
      fix: 'Search your .tex sources for \\label{<key>} and rename or delete one.'
    },
    invalid_in_math_mode: {
      title: 'Alert: Command Invalid in Math Mode',
      why: 'A text font declaration or size switch was used inside math, where LaTeX ignores it, so the formula silently keeps its default look.',
      fix: 'Use the math equivalent (\\mathbf, \\mathit, \\mathsf, \\mathtt, \\mathrm) or wrap the whole formula: {\\large $...$}.'
    },
    duplicate_destination: {
      title: 'Alert: Duplicate Hyperlink Destination',
      why: 'Two anchors in the PDF share a name, so pdfTeX kept the first and every link to that name lands there. Usually page numbering restarted without hyperref knowing, or a \\hypertarget name was reused.',
      fix: 'Give each anchor a unique name; for restarted page numbers use \\pagenumbering with distinct styles or hypersetup{pageanchor=false} for the front matter.'
    },
    mixed_page_sizes: {
      title: 'Alert: Mixed Page Sizes',
      why: 'Not every page of the PDF has the same dimensions, typically because an included PDF figure or an \\includepdf page carries its own page size. Journals and arXiv reject such files.',
      fix: 'Crop or scale the included PDF to the page, or set the paper size explicitly with the geometry package.'
    },
    invisible_character: {
      title: 'Warning: Invisible Character in Source',
      why: 'A zero-width, non-breaking, or bidirectional control character is in the source, usually pasted from a browser or PDF. It compiles but produces odd spacing, forbids line breaks, or corrupts copy and search in the PDF.',
      fix: 'Delete the character at the reported column; an editor that shows invisible characters, or a search for the code point, will find it.'
    },
    draft_leftover: {
      title: 'Alert: Draft Leftover (--final)',
      why: 'A drafting aid is still active in the source: \\includeonly drops chapters, the draft option boxes out figures, and showkeys, todonotes, lineno, draftwatermark or refcheck print marks that do not belong in a submitted document.',
      fix: 'Remove or comment out the construct before packaging; for todonotes, load it with the disable option.'
    },
    unconverged_build: {
      title: 'Alert: Build Did Not Converge',
      why: 'The pass budget ran out while LaTeX still asked for a rerun, so cross-references, page numbers, or the table of contents in the PDF may be stale.',
      fix: 'Raise -n/--passes, or look for a construct that changes on every pass (a \\today in a label, a varying box width, a package warning asking for a rerun).'
    },
    float_too_large: {
      title: 'Alert: Float Too Large for Page',
      why: 'A figure or table is taller than the text height, so LaTeX places it anyway and the overflow is clipped at the page edge.',
      fix: 'Scale the content down (width= or height= in \\includegraphics, \\resizebox, a smaller tabular), or split it across pages.'
    },
    overfull_vbox: {
      title: 'Alert: Severe Overfull \\vbox',
      why: 'A page or box is taller than its allotted height, so the bottom lines run into the margin or off the page.',
      fix: 'Allow a page break (\\allowbreak, \\pagebreak), shorten the unbreakable block, or let the page be ragged with \\raggedbottom.'
    },
    bib_repeated_entry: {
      title: 'Alert: Repeated Bibliography Entry',
      why: 'Two entries in the .bib files share a key; BibTeX keeps the first and silently drops the other, so a corrected entry may never reach the PDF.',
      fix: 'Rename or delete one of the entries at the reported .bib line.'
    },
    unused_global_option: {
      title: 'Alert: Unused Global Option',
      why: 'An option passed to \\documentclass matched nothing in the class or any package, so LaTeX ignored it; a misspelled option silently leaves the default font size or layout in place.',
      fix: 'Fix the option spelling in \\documentclass[...] or remove it.'
    },
    overfull_hbox_alert: {
      title: 'Alert: Severe Overfull \\hbox (≥24pt)',
      why: 'Content spills significantly (≥24pt / ~8.4mm) into the page margin.',
      fix_label: 'Might fix:',
      fix: 'Reword text, insert discretionary hyphens \\-, break equations, or resize figures.'
    },
    overfull_hbox_warning: {
      title: 'Warning: Overfull \\hbox',
      why: 'Line exceeds column width; TeX could not hyphenate within standard tolerances.',
      fix_label: 'Might fix:',
      fix: 'Reword sentence, insert \\-, or wrap code in \\sloppy / \\emergencystretch.'
    },
    overfull_hbox_whatever: {
      title: 'Whatever: Micro Overfull \\hbox (≤2.5pt)',
      why: 'Minor margin protrusion (≤2.5pt / ~0.88mm), often memoir TOC page numbers.',
      fix: 'Harmless typesetting quirk; safely ignored.'
    },
    underfull_hbox: {
      title: 'Note: Underfull \\hbox (Loose Line)',
      why: 'TeX stretched inter-word spacing excessively (badness 10000 = infinite stretch) because there were too few words to fill the line. Typically caused by a trailing \\\\ before an empty line or \\end{...}, double \\\\\\\\, using \\linebreak, or unhyphenated words in narrow columns.',
      fix_label: 'Might fix:',
      fix: 'Remove trailing \\\\ before blank lines or \\end{...}, avoid double \\\\\\\\ (use \\vspace or a blank line), replace \\linebreak with \\newline, or reword text.',
      doc_url: 'https://sarielhp.github.io/leeni/docs/guides/underfull_boxes/'
    },
    underfull_vbox: {
      title: 'Warning: Underfull \\vbox (Vertical Stretch)',
      why: 'TeX could not stretch vertical whitespace enough to fill the column or page height.',
      fix_label: 'Might fix:',
      fix: 'Add \\raggedbottom to preamble, adjust figure/table heights, or balance text across pages.',
      doc_url: 'https://sarielhp.github.io/leeni/docs/guides/underfull_boxes/'
    },
    underfull_box: {
      title: 'Warning: Underfull \\vbox or \\hbox',
      why: 'LaTeX could not stretch whitespace enough to fill the target dimension.',
      fix_label: 'Might fix:',
      fix: 'Add \\raggedbottom to preamble, adjust figure heights, or reword text.',
      doc_url: 'https://sarielhp.github.io/leeni/docs/guides/underfull_boxes/'
    },
    undefined_reference: {
      title: 'Warning: Undefined Reference',
      why: 'A \\ref{...} or \\pageref{...} references a label that does not exist in any .aux.',
      fix: 'Check spelling of the key, ensure target chapter is included, and recompile.'
    },
    undefined_citation: {
      title: 'Warning: Undefined Citation',
      why: 'A \\cite{...} key was not found in the bibliography database (.bib).',
      fix: 'Verify key spelling, check \\bibliography / \\addbibresource, and run BibTeX/Biber.'
    },
    hyperref_token: {
      title: 'Whatever: Hyperref PDF Bookmark Token Sanitization',
      why: 'Math or formatting in a heading was stripped for plain-text PDF bookmarks.',
      fix: 'Harmless. Use \\texorpdfstring{$math$}{text} in headings to clean cleanly.'
    },
    float_specifier: {
      title: 'Whatever: Float Specifier Auto-Adjusted',
      why: "'!h' (strictly here) violated page layout rules, so LaTeX added 't' (top of page).",
      fix: "Harmless. Use '[!htbp]' to give LaTeX standard placement flexibility."
    },
    font_shape: {
      title: 'Whatever: Font Shape Substitution',
      why: 'Requested font weight/style combination was unavailable; fallback substituted.',
      fix: 'Harmless fallback. Check font declarations if unexpected styling appears.'
    },
    summary_warning: {
      title: 'Whatever: Redundant Summary Notice',
      why: 'Document-level summary emitted at end of LaTeX run.',
      fix: 'Harmless recap; individual items are already reported above.'
    },
    etex_allocation: {
      title: 'Whatever: Extended Allocation In Use',
      why: 'Modern LaTeX formats already provide extended allocation; etex.sty code was skipped.',
      fix: 'Harmless notice on modern TeX engines; safely ignored.'
    },
    inverted_label: {
      title: 'Alert: Inverted \\label Before \\caption',
      why: '\\label{...} was placed before \\caption in a float. Cross-references (\\ref) will resolve to the Section number instead of the float number.',
      fix: 'Move \\label{...} after or inside \\caption{...}.'
    },
    unnumbered_label: {
      title: 'Alert: \\label Inside Unnumbered Math',
      why: '\\label was placed inside an unnumbered environment (e.g. equation* or align*). Cross-references will bind to the prior section or theorem.',
      fix: 'Remove \\label or switch to a numbered math environment (equation or align).'
    },
    type3_font: {
      title: 'Type 3 Font in PDF',
      why: 'Type 3 glyphs can be vector or bitmap. Confirmed vector glyphs are a warning; bitmap or unverified glyphs remain an alert. Acceptance depends on the target publisher.',
      fix: 'Install MuPDF with mutool on PATH for automatic inspection. Use scalable fonts: regenerate plots with Matplotlib pdf.fonttype = 42, or use lmodern for LaTeX text. Persist a downgrade with "alert_as_warning": ["type3_font"] in project .l.jsonc or global ~/.config/leeni/config.jsonc.'
    }
  }.freeze
end
