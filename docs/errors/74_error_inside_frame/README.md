# Errors inside a beamer frame reported at \end{frame}

## TeX Output
```text
./example.tex:13: Undefined control sequence.
./example.tex:13: Missing $ inserted.
./example.tex:13: LaTeX Error: \begin{itemize} on input line 13 ended by \end{enumerate}.
```

## Explanation
A beamer frame reads its whole body as an argument before typesetting it, so TeX reports every error inside the frame at its `\end{frame}` line, often with no context. `leeni` places each error inside the frame: an undefined command by the name TeX's elided context still shows, a missing `$` at the first `_` or `^` outside math, and an environment mismatch at the `\end{...}` that closed the wrong environment.

## How to Fix
1. Fix each reported line: define `\undefinedcmd`, write `$x_1$`, and close `itemize` with `\end{itemize}`.
