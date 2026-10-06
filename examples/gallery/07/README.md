# 7. Bibliography Syntax Crash at \printbibliography (Pinpointing the Exact .bib Entry)

## Description
An unescaped underscore (`_`) in a `.bib` database field (such as `journal = {NORDIC_J_COMP}`).

## What Happens with Standard Tools (latexmk / pdflatex)
TeX crashes during `\printbibliography` with `! Missing $ inserted.` or `! Double subscript.` on line 7 of `paper.tex`. It offers zero indication of which citation key failed, which `.bib` file it came from, or what field caused the syntax crash, forcing authors into tedious binary-search debugging.

## How leeni Diagnoses It
Injects an AST hook into BibLaTeX's entry pipeline to capture the active citation key at the instant of failure, locates the entry and line in `refs.bib`, and prints an actionable companion error: `refs.bib:4: [leeni] Bibliography error in entry 'grss95'` with `▸ Hint: Offending token 'NORDIC_J_COMP' found on this line.`.

## How to Run
```bash
l paper.tex
```
