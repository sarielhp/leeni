# LaTeX Error: File '....cls' not found

## TeX Output
```text
! LaTeX Error: File `nonexistent_journal_class.cls' not found.
./example.tex:2: Emergency stop.
```

## Explanation
`\documentclass{...}` names a class that is neither in the project nor in the TeX distribution, typically a journal or conference class (`JHEP3.cls`, `PoS.cls`, an old LIPIcs class) shipped with the original submission but not with this copy of the sources. TeX cannot continue without a class, so it stops at once. `leeni` reports the error at the `\documentclass` line.

## How to Fix
1. Copy the class file (`.cls`, with any `.bst` or logo files it needs) into the project directory.
2. Install it from CTAN when it is published there (`tlmgr install <package>`).
3. To read the document without the original layout, switch temporarily to a standard class such as `article`.
