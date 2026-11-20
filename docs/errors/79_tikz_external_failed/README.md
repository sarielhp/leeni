# Package tikz Error: externalization system call failed

## TeX Output
```text
./example.tex:9: Package tikz Error: Sorry, the system call 'pdflatex -halt-on-error -interaction=batchmode -jobname "example-figure0" "\def\tikzexternalrealjob{example}\input{example}"' did NOT result in a usable output file 'example-figure0' (expected one of .pdf:.jpg:.jpeg:.png:). Please verify that you have enabled system calls. ...
```

## Explanation
With `\tikzexternalize` (or forest's `external` option) every picture is compiled by a separate TeX run that the document starts through `\write18`. Without shell escape the run is refused, no picture file is made, and TikZ reports the picture as failed. In some documents (a forest tree with `external`, on its first build) TeX's recovery reports more errors (`File ended while scanning use of \tikzpicture`, an environment ended by `\end{document}`, an open group); `leeni` reports the failed call alone.

## How to Fix
1. Allow shell escape for the build: `LATEXOPTS="-shell-escape" l example.tex`.
2. Or remove `\tikzexternalize` so the pictures are drawn in the main run.
