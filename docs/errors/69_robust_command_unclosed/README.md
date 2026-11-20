# File ended while scanning use of \textbf

## TeX Output
```text
! File ended while scanning use of \textbf .
```

## Explanation
The argument of `\textbf{` is never closed, so TeX reads to the end of the file looking for its `}` and stops with no line number. Robust LaTeX commands (`\textbf`, `\emph`, `\eqref`, ...) carry an internal name ending in a space, hence `\textbf .` in the message. `leeni` reports one error, at the brace left open, with TeX's category and hint.

## How to Fix
1. Add the missing `}` where the argument should end: `\textbf{bold}`.
