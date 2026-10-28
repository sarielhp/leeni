# No pages of output

## TeX Output
```text
No pages of output.
Transcript written on main.log.
```

## Explanation
TeX shipped out no pages, so no PDF was written at all, yet the engine exits 0. The body between `\begin{document}` and `\end{document}` typeset nothing. Usual causes are a missing `\include` target, an `\includeonly` list that excludes everything, a freshly pasted skeleton, or an `\end{document}` that landed in the wrong place while editing.

Without detection the symptom is confusing: the build reports success, no new PDF appears, and any old PDF in the project directory is left untouched and looks current.

## `leeni` Detection
`leeni` promotes the note to an error and fails the build:

```text
main.tex: No pages of output: the document body typeset nothing, so no PDF was written (TeX only notes this; leeni flags it as an error).
```

## How to Fix
Make sure the document body contains typeset material and that every `\include` target exists.
