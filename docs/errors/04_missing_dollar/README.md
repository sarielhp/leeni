# Missing $ inserted

## TeX Output
```text
./example.tex:3: Missing $ inserted.
l.3 Variable x_
               1 is not in math mode.
```

## Explanation
TeX encountered a character or macro that is only valid inside math mode while operating in horizontal (text) mode. Common culprits include:
1. Subscripts (`_`) or superscripts (`^`) written outside `$ ... $` (e.g. `file_name.txt` or `10^5`).
2. Greek letters or math symbols like `\alpha`, `\sum`, `\infty` in regular prose.
3. Math operators (`\to`, `\times`, `\le`) without surrounding `$` delimiters.

## How to Fix
- If mathematical: wrap the expression in inline math delimiters `$ ... $`:
  ```latex
  Variable $x_1$ is in math mode.
  ```
- If an underscore is intended in text: escape it with `\_` (or wrap file paths in `\texttt{...}` / `\url{...}`):
  ```latex
  The file name is \texttt{file\_name.txt}.
  ```

> [!NOTE]
> If this error occurs during `\printbibliography` or `\bibliography`, the unescaped underscore or missing dollar sign is inside a `.bib` database field. See [Troubleshooting Bibliography Errors](../../troubleshooting_bibliography_errors.md) for automated diagnosis with `leeni`.
