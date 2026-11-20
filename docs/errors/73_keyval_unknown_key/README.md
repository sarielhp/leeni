# Package keyval Error: unknown key

## TeX Output
```text
./example.tex:9: Package keyval Error: widht undefined.
```

## Explanation
A command that takes `key=value` options (`\includegraphics`, many package options, TikZ styles) was given a key it does not define, usually a misspelling. TeX reports the line where it finished reading the command; inside a beamer frame, whose body is read whole, that is the `\end{frame}` line. `leeni` finds the key on the reported line or above it.

A key reported together with its value (`scale=0.5 undefined`) means `=` was not read as a plain character: a babel language such as `turkish` makes it a shorthand. `leeni` says so in its hint.

## How to Fix
1. Correct the key (`width`, not `widht`), or remove an option the command does not support.
2. For a key reported with its value, add `\shorthandoff{=}` or load babel with `shorthands=off`.
