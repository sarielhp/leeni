# 1. Unclosed Dollar Sign ($) Inversion & Pinpointing

## Description
An unclosed `$` on line 4 propagates across five lines of dense mathematical prose, inverting text and math across multiple formulas until TeX crashes far downstream.

## What Happens with Standard Tools (latexmk / pdflatex)
TeX halts on line 8 (`$1 + \epsilon$`) with `! Missing $ inserted.`, blaming an innocent, well-formed formula for missing a dollar sign and completely concealing that math mode was opened four lines earlier on line 4.

## How leeni Diagnoses It
Performs candidate pair scoring across the paragraph, recognizes that downstream formulas are valid, and pinpoints the true culprit: `Unclosed '$' opened on line 4 (col 5); insert closing '$'`.

## How to Run
```bash
l paper.tex
```
