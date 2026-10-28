# Command invalid in math mode

## TeX Output
```text
./example.tex:3: LaTeX Error: Command \bfseries invalid in math mode.
```
and, for `\em` and the size switches, only a warning:
```text
LaTeX Font Warning: Command \em invalid in math mode on input line 3.
```

## Explanation
Text font declarations and size switches do not work inside math. Current LaTeX rejects `\bfseries`, `\itshape`, `\sffamily` and friends with an error, but `\em` and the size commands (`\large`, `\small`, ...) are silently ignored with a Font Warning, so the formula keeps its default look while the engine exits 0.

## `leeni` Detection
The error form gets a catalog hint naming the math equivalent. The warning form is promoted to an **alert**, since it never fixes itself and always marks a source mistake:

```text
main.tex:3: warning: [alert] command \em invalid in math mode; use \mathit{...}
```

## How to Fix
Use the math equivalent (`\mathbf`, `\mathit`, `\mathsf`, `\mathtt`, `\mathrm`), or wrap the whole formula for a size change: `{\large $...$}`.
