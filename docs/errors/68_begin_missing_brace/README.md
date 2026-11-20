# Paragraph ended before \begin was complete

## TeX Output
```text
./example.tex:6: Paragraph ended before \begin was complete.
./example.tex:8: LaTeX Error: \begin{document} ended by \end{proof}.
./example.tex:8: Extra \endgroup.
```

## Explanation
`\begin{proof` lost its closing brace, so the environment name runs on into the text until the blank line ends the paragraph. The environment is never opened, and its `\end{proof}` then closes the wrong one. TeX names the blank line and the `\end`; the fault is the `\begin`. `leeni` reports the unclosed brace first, at its line and column, then the mismatch it caused.

## How to Fix
1. Close the brace: `\begin{proof}`.
2. The mismatch at `\end{proof}` disappears with it.
