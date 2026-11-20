# Paragraph ended before \new@command was complete

## TeX Output
```text
./example.tex:5: Paragraph ended before \new@command was complete.
./example.tex:8: Undefined control sequence.
./example.tex:8: Undefined control sequence.
```

## Explanation
A brace is missing in a `\newcommand` in the preamble (`\newcommand{\norm[1]{...}`): the name argument stays open, swallows the next definitions, and runs into the blank line, where TeX reports it. Every macro it swallowed is then undefined in the body. TeX names the blank line and the uses; the fault is the definition. `leeni` reports the unclosed brace first, at its line and column, then the undefined macros it caused.

## How to Fix
1. Close the brace at the reported column: `\newcommand{\norm}[1]{...}`.
2. The undefined-macro errors after it disappear with the fix; check them only if they remain.
