# 3. Misplaced Alignment Tab (&) inside equation*

## Description
The author used `&` to align multi-part equations, but placed it inside `equation*` instead of `align*`.

## What Happens with Standard Tools (latexmk / pdflatex)
Standard LaTeX emits a generic `! Misplaced alignment tab character &.`, followed by 45 lines of engine state and generic failure boilerplate. It offers zero explanation of *why* the ampersand is invalid or how to structure the math environment.

## How leeni Diagnoses It
Performs backwards AST scope resolution, detects that the tab character resides inside `equation*`, and delivers an immediate, tailored hint: `Misplaced '&' in 'equation*'; switch to 'align*' (or use 'aligned' / 'split')`.

## How to Run
```bash
l paper.tex
```
