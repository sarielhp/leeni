# Font not loadable under XeTeX/LuaTeX

## TeX Output
```text
./example.tex:5: Package fontspec Error: 
(fontspec)                The font "NoSuchFontXyz" cannot be found; this may
(fontspec)                be but usually is not a fontspec bug. Either there
...
l.5 \begin
          {document}
...
./example.tex:5: Font TU/NoSuchFontXyz(0)/m/n/10=NoSuchFontXyz at 10.0pt not lo
adable: Metric (TFM) file or installed font not found.
<to be read again> 
                   relax 
l.5 \begin
          {document}
I wasn't able to read the size data for this font,
so I will ignore the font specification.
...
Missing character: There is no T ("54) in font nullfont!
Missing character: There is no e ("65) in font nullfont!
...
```

## Explanation
Under `xelatex` (and `lualatex`) fonts are looked up by name in the installed system and TeX font directories, not by file name. `\setmainfont{NoSuchFontXyz}` names a font that is not installed, so when the font is first used — at `\begin{document}`, where fontspec selects it — the engine cannot read it and prints `Font ... not loadable: Metric (TFM) file or installed font not found`. fontspec reports the same missing font as `Package fontspec Error` at the same line, and because no font was ever set up, the body is typeset in `nullfont`, so every character is dropped with `Missing character: ... in font nullfont!` — not an error of its own, but the consequence of the first one.

`leeni` classifies the `not loadable` line as `font_not_loadable`, extracts the font name, and hints that the font is not installed (install it, or give `\setmainfont` a font this system has, listed by `fc-list`). The fontspec error that names the same font is folded into the repeat, and the dropped text is placed at its line in the body.

## How to Fix
1. Install the named font so the engine can find it (`fc-list : family` lists the fonts that are available), or
2. Give `\setmainfont` a font that is installed — the TeX Gyre families ship with TeX Live: `\setmainfont{TeX Gyre Termes}` for Times, `\setmainfont{TeX Gyre Heros}` for Helvetica.
