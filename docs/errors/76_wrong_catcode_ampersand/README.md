# Package pgf Error: Single ampersand used with wrong catcode

## TeX Output
```text
./example.tex:8: Undefined control sequence.
./example.tex:8: Undefined control sequence.
Missing character: There is no b in font nullfont!
./example.tex:8: Package pgf Error: Single ampersand used with wrong catcode.
...
```

## Explanation
A TikZ `matrix of nodes` (and `tikz-cd`) makes `&` active to separate the cells. Text read as an argument, such as the body of `\only{...}` or `\uncover{...}`, a beamer frame or a macro, has its catcodes fixed before TikZ can change them, so `&` arrives as an ordinary alignment character. pgf then reaches for its internal cell macros (the undefined control sequence) and typesets the cells as loose text in `nullfont`. TeX reports all of this at `\end{frame}`; `leeni` reports one error, at the first `&` in the frame.

## How to Fix
1. Add `ampersand replacement=\&` to the matrix (or `tikzcd`) options and write `\&` between cells.
2. Or keep the matrix out of the argument: `\begin{onlyenv}<1> ... \end{onlyenv}` instead of `\only<1>{...}`.
