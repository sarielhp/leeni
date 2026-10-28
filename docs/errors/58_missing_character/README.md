# Missing character: glyph not in font

## TeX Output
```text
Missing character: There is no 你 (U+4F60) in font [lmroman10-regular]:mapping=tex-text;!
```

## Explanation
The current font has no glyph for a character in the source, so TeX typeset nothing in its place and moved on. The note goes to the log only, the engine exits 0, and the PDF is silently missing the character. Typical causes are CJK or other non-Latin text under a Latin font, Unicode punctuation and arrows pasted from a browser, and symbols typed directly instead of with their LaTeX command.

## `leeni` Detection
`leeni` promotes each distinct glyph-and-font pair to one error, counts repeats, locates the first source line containing the character, and fails the build:

```text
main.tex:3: Missing character: there is no 你 (U+4F60) in font lmroman10-regular, so the glyph was dropped from the PDF (TeX only notes this; leeni flags it as an error).
```

## How to Fix
Load a font that covers the character (`fontspec` with xelatex or lualatex, or a CJK package), use the LaTeX command for the symbol, or remove the character.
