# Package xltxtra Error: XeTeX is required

## TeX Output
```text
/.../xltxtra/xltxtra.sty (loaded by example.tex)
 ********************************************
 * XeTeX is required to compile this document.
 * Sorry!
 ********************************************

/.../xltxtra/xltxtra.sty:43: Emergency stop.
<read *>
         
l.43 \RequireXeTeX
```

## Explanation
`xltxtra` is a XeLaTeX package: it calls `\RequireXeTeX`, which stops the run when the engine is pdfTeX or LuaTeX. TeX prints its banner, then an `Emergency stop` inside `xltxtra.sty`; the message itself (`XeTeX is required to compile this document`) carries no file or line, so the log alone never says which line of the document to fix. `leeni` reports one error, at the `\usepackage{xltxtra}` line in example.tex, with a hint naming the engine to build with.

## How to Fix
1. Build with XeLaTeX (`-e xelatex`).
2. Or drop the package: for font selection, `fontspec` replaces it.
