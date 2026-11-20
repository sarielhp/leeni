# Error inside a [fragile] beamer frame

## TeX Output
```text
./example.vrb:5: Undefined control sequence.
```

## Explanation
A `[fragile]` frame (needed for `verbatim` and similar) writes its body to `<jobname>.vrb` in the build directory and reads it back, so TeX reports any error in the frame at a line of that generated file. The file is rewritten on every pass, so the error is in the source, not in a stale cache. `leeni` maps the `.vrb` line back to the frame's line in the source, and does not treat the error as a corrupt build directory.

## How to Fix
1. Fix the reported line of the frame; here, define or correct `\undefinedmacro`.
