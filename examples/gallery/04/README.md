# 4. Macro Spelling & Typo Fuzzy Matching (\includegrahics)

## Description
A minor typo in a common macro name (`\includegrahics` instead of `\includegraphics`).

## What Happens with Standard Tools (latexmk / pdflatex)
TeX fails on the unknown macro and attempts to recover by misinterpreting underscores (`_`) in filenames as text-mode subscripts, causing a cascade of misleading secondary errors (`Missing $ inserted`, `Extra }, or forgotten $`).

## How leeni Diagnoses It
Uses Levenshtein edit distance against standard LaTeX commands and package signatures, identifying the intended macro with: `Did you mean '\includegraphics'? (requires \usepackage{graphicx})`.

## How to Run
```bash
l paper.tex
```
