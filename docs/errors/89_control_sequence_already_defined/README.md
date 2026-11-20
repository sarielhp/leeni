# LaTeX Error: Control sequence already defined

## TeX Output
```text
(TEXMFDIST/latex/unicode-math/unicode-math-table.tex
)

! LaTeX Error: Control sequence \not= already defined.

For immediate help type H <return>.
 ...                                              
                                                  
l.3854 \NewNegationCommand { = }    { \neq   }
                                              

! LaTeX Error: Control sequence \not< already defined.

For immediate help type H <return>.
 ...                                              
                                                  
l.3855 \NewNegationCommand { < }    { \nless }
                                              

! LaTeX Error: Control sequence \not> already defined.

For immediate help type H <return>.
 ...                                              
                                                  
l.3856 \NewNegationCommand { > }    { \ngtr  }
                                              
))
```

## Explanation
`unicode-math` builds `\not=`, `\not<`, `\not>` (and the other negated relations) itself, with `\NewDocumentCommand`-style definitions that refuse to replace an existing command. When a legacy math setup has already defined those control sequences — `amssymb` and a math-font package such as `stix2` both declare `\not=`, `\not<`, `\not>` — loading `unicode-math` stops at the first clash with `Control sequence \not= already defined` and repeats it for each of the symbols, at the `\usepackage{unicode-math}` line that triggered the definitions.

`unicode-math` replaces `amssymb` rather than stacking on top of it: it provides the same symbols from an OpenType math font. On current TeX Live it silently overrides the plain `amssymb` definitions, but a math-font package that keeps the legacy `\not` commands (here `stix2`) is not undone, so the clash surfaces. The document cannot be typeset until one side is dropped.

`leeni` classifies each `Control sequence ... already defined` line as `control_sequence_already_defined`, extracts the offending command (`\not=`), and hints that two loaded packages define it, naming `unicode-math` against `amssymb` and the math-font packages. All three messages come from the one `\usepackage` line, so all three are reported there.

## How to Fix
1. Load only one math setup. With `unicode-math` in use, drop `amssymb`, `amsfonts` and the legacy math-font packages (`stix2`, `txfonts`, `newpxmath`, …); `unicode-math` supplies the symbols from the OpenType math font you choose with `\setmathfont`.
2. If a legacy package is required, drop `unicode-math` and its OpenType math font instead, and keep `amssymb` with the math-font package.
