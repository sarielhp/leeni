# Improper \hyphenation will be flushed

## TeX Output
```text
./example.tex:3: Improper \hyphenation will be flushed.
./example.tex:3: Improper \hyphenation will be flushed.
./example.tex:3: LaTeX Error: Missing \begin{document}.
./example.tex:3: Extra }, or forgotten \endgroup.
...
```

## Explanation
`\hyphenation` accepts only letters of the current font and hyphens. An accent macro (`\"a` with the default OT1 encoding) or a babel shorthand (`"a` with `ngerman`) expands inside the list, and TeX reports one error for each token that is not a letter, followed by others the expansion causes (nineteen in this example). `leeni` reports the first and counts the rest on that line as part of it.

## How to Fix
1. Type the accented letters themselves, with UTF-8 input and `\usepackage[T1]{fontenc}`: `\hyphenation{Anfangs-nä-he-rung}`.
