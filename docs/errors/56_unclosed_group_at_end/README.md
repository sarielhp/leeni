# \end{document} reached inside an unclosed group

## TeX Output
```text
(\end occurred inside a group at level 1)

### simple group (level 1) entered at line 3 ({)
### bottom level
```

## Explanation
A brace group (`{`), `\begingroup`, math shift (`$`), or `\if...` conditional was opened and never closed, so the entire rest of the document was typeset inside it. TeX notices this only when it executes `\end`, mentions it as a parenthetical note in the log, and still exits with status 0 and writes the PDF.

The source is malformed all the same: local assignments leak, `\end{document}` closes nothing, and later edits trigger hard-to-trace errors far from the real cause.

## `leeni` Detection
`leeni` rewrites the note into a synthetic compiler error carrying the line number TeX recorded, so the build fails with a non-zero status and the error is reported like any other:

```text
! [leeni] \end{document} reached inside an unclosed simple group opened by '{' on line 3 (TeX only warns about this; leeni flags it as an error).
```

The same promotion applies to `(\end occurred when \ifx on line N was incomplete)`.

## How to Fix
Close the group or conditional on the reported line. The usual culprits are a stray `{` or `$` in the preamble, or a macro definition missing its final `}`.
