# LaTeX Error: Unknown option for package

## TeX Output
```text
/.../xcolor/xcolor.sty:265: LaTeX Error: Unknown option '11names' for package xcolor.
/.../pgf/basiclayer/pgfcore.sty:14: LaTeX Error: Unknown option '11names' for package xcolor.
```

## Explanation
A package accepts only the options it declares; xcolor knows `x11names`, not `11names`. TeX reports the error inside the package file, and again wherever another package loads the same package later (tikz loads xcolor through pgfcore), since LaTeX passes the options on. `leeni` reports one error, at the `\usepackage` line that gave the option.

## How to Fix
1. Correct the option name (`\usepackage[x11names]{xcolor}`), checking the package documentation (`texdoc xcolor`).
2. Or remove the option.
