# PDF driver could not include an image page

## TeX Output
```text
xdvipdfmx:fatal: Image inclusion failed for "./figs/plot.pdf" (page=3).

No output PDF file written.
```

## Explanation
XeTeX does not write the PDF itself: it streams its pages through a pipe to the driver `xdvipdfmx`. When `\includegraphics[page=N]` asks for a page past the end of a PDF (or the file is damaged), the driver stops. Its message goes to the terminal only, never to the `.log` file. In a short document XeTeX then reports a bare `Error 256 (driver return code)`; in a long one it is still writing pages and is killed by SIGPIPE mid-document, which leaves its `.aux`, `.out` and `.toc` cut off in the middle of an entry. Read back on the next run, those produce `Runaway argument?` and `File ended while scanning use of \@newl@bel` at `\begin{document}`, errors that have nothing to do with the source.

## `leeni` Detection
`leeni` promotes the driver message to an error at the `\includegraphics` that requests the page (preferring the call whose `page=` matches), discards the generated files a killed engine left half-written, and treats a cut-off `.aux` already in the cache as a cache failure (cleaned and rebuilt):

```text
main.tex:4: error: PDF driver could not include page 3 of image 'figs/plot.pdf' (the file has fewer pages, or is damaged), so no PDF was written.
```

## How to Fix
Correct the `page=` option (`pdfinfo figs/plot.pdf` shows the page count), or regenerate the image file.
