# Package fontenc Error: Encoding file `...enc.def' not found

## TeX Output
```text
! Package fontenc Error: Encoding file `xq9enc.def' not found.
(fontenc)                You might have misspelled the name of the encoding 
(fontenc)                or a required support package (e.g., cyrillic) is 
(fontenc)                missing in your installation.
...
! LaTeX Error: Encoding scheme `XQ9' unknown.
...
! LaTeX Error: Encoding scheme `XQ9' unknown.
```

## Explanation
`\usepackage[XQ9]{fontenc}` asks LaTeX to load the encoding file `xq9enc.def`, which holds the declared encoding. When the package providing that file is not installed the load fails, and every later attempt to select the encoding — at the `\usepackage` line and at each font change such as `\textbf` — fails again with `Encoding scheme 'XQ9' unknown`. All of these come from one missing file. `leeni` reports a single `file_not_found` error at the `\usepackage` line, with a hint naming the package to install.

## How to Fix
1. Install the package that provides the encoding file (`tlmgr search --global --file xq9enc.def`, then `tlmgr install <package>`).
2. Or remove `XQ9` from `\usepackage[...]{fontenc}` and use an encoding shipped with LaTeX (e.g. `T1`).
