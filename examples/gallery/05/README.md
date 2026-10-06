# 5. Missing Package Macro (\toprule)

## Description
Using standard publication-quality table markup (`\toprule`) without importing the prerequisite package.

## What Happens with Standard Tools (latexmk / pdflatex)
Reports `! Undefined control sequence. <recently read> \toprule`. Standard tools do not associate macro names with external CTAN packages, leaving the author to manually look up what package supplies the command.

## How leeni Diagnoses It
Looks up the command signature in its package index and reports: `Command '\toprule' requires \usepackage{booktabs}`.

## How to Run
```bash
l paper.tex
```
