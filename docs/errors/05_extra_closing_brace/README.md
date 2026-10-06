# Too many }'s / Extra closing brace '}'

## TeX Output
```text
./example.tex:3: Too many }'s.
l.3 Some text with an extra closing brace}
                                         .
```

## Explanation
TeX encountered a closing curly brace `}` at a time when no matching open curly brace `{` was active.

## `leeni` Pre-Flight Detection
Before TeX even starts, `leeni` runs `LaTeXBraceChecker` across `.tex` source files. If an unmatched brace is present, `leeni` surfaces an instant static alert pointing directly to the offending column and line number.

## How to Fix
Remove the superfluous closing brace `}`, or ensure its matching opening brace `{` was not accidentally omitted or mistyped as `[` or `(`.
