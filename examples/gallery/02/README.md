# 2. Unclosed Curly Brace Pinpointing

## Description
A macro argument or group opened with `{` is left unclosed across a paragraph or EOF.

## What Happens with Standard Tools (latexmk / pdflatex)
Standard TeX parsers only complain when they encounter `\par` or EOF (`Runaway argument?`, `! File ended while scanning use of \textbf`). The terminal fills with 70+ lines of internal macro call traces and rule checks, but completely obscures where the `{` was actually typed.

## How leeni Diagnoses It
Runs an AST-aware lexical brace scanner with environment scoping that identifies the exact line (`line 3`), column (`col 34`), and enclosing environment (`document`) where the unclosed brace started, along with an actionable remediation hint.

## How to Run
```bash
l paper.tex
```
