# PDF driver xdvipdfmx failed

## TeX Output
```text
xdvipdfmx:fatal: Image inclusion failed. Could not find file: nosuch.pdf

No output PDF file written.
```

## Explanation
XeTeX streams its pages to the driver `xdvipdfmx`, which writes the PDF. A fatal driver error (an image it cannot read, a font it cannot embed, a malformed `\special`) ends the run without a PDF. The message is printed to the terminal only, never to the `.log` file, so a log-based scan sees no error at all.

## `leeni` Detection
`leeni` promotes every `xdvipdfmx:fatal:` line to an error. Image page failures have their own entry, [`61_pdf_driver_image_failed`](../61_pdf_driver_image_failed/), located at the `\includegraphics`.

```text
main.tex: error: PDF driver xdvipdfmx failed: Image inclusion failed. Could not find file: nosuch.pdf, so no PDF was written.
```

## How to Fix
Fix the image, font or special that the message names. If the cause is unclear, building with `-e lualatex` shows whether the input or the driver is at fault.
