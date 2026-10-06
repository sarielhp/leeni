# 6. Inverted \label Before \caption (Silent Reference Corruption)

## Description
Placing `\label{...}` before `\caption{...}` inside a floating `figure` or `table`.

## What Happens with Standard Tools (latexmk / pdflatex)
Standard compilers are **completely silent** and exit with code 0. However, `\caption` is what increments the float counter; placing `\label` before it causes `\ref{fig:myfig}` to quietly bind to Section 1 instead of Figure 1, producing corrupt citations in published papers.

## How leeni Diagnoses It
Inspects float structure and elevates this silent bug to the **Alert** diagnostic tier: `6: Inverted \label{fig:myfig} before \caption in figure environment. Move \label after or inside \caption.`

## How to Run
```bash
l paper.tex
```
