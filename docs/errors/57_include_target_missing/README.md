# \include target not found

## TeX Output
```text
No file chapter_missing.tex.
```

## Explanation
`\include{chapter_missing}` named a file that does not exist. Unlike `\input`, which stops with `File not found`, `\include` only writes `No file chapter_missing.tex.` to the log and carries on. The engine exits 0 and writes a PDF with the chapter missing.

## `leeni` Detection
`leeni` promotes the note to an error, locates the `\include` line in the source, and fails the build:

```text
main.tex:4: \include target 'chapter_missing.tex' not found, so its contents were skipped (TeX only notes this; leeni flags it as an error).
```

Only `.tex` targets are promoted. The `No file main.aux.` and `No file main.bbl.` lines of a first pass are expected and left alone.

## How to Fix
Create the file, correct the name in `\include{...}`, or remove the `\include`.
