# Illegal parameter number in a beamer frame

## TeX Output
```text
./example.tex:11: Illegal parameter number in definition of \iterate.
./example.tex:11: Illegal parameter number in definition of \iterate.
./example.tex:11: Illegal parameter number in definition of \beamer@doifinframe.
...
```

## Explanation
A beamer frame reads its body as the argument of a macro, so a `#1` written in it (here in a TikZ style, `long/.style={shorten >=-#1}`) is taken as a parameter of beamer's own macros, which have none. TeX reports it at `\end{frame}` (or at the end of the `\only{...}` that holds it, in a fragile frame) and names beamer's internal macros. `leeni` reports one error, at the nearest `#1` above in the frame, with the fix.

## How to Fix
1. Double the `#` inside the frame: `long/.style={shorten >=-##1}`.
2. Or define the style outside the frame, with `\tikzset` in the preamble.
