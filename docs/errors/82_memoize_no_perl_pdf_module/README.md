# Package memoize Error: No suitable Perl module for PDF processing

## TeX Output
```text
! Package memoize (perl-based extraction) Error: No suitable Perl module for PD
F processing was found, options are PDF::API2, PDF::Builder.

See the memoize (perl-based extraction) package documentation for explanation.
Type  H <return>  for immediate help.
 ...                                              
                                                  
l.3 ...instructions is section 1.1 of the manual?}
```

## Explanation
This case is simulated: memoize raises the error only when the machine lacks an installed Perl PDF module, so `example.tex` reproduces the exact message with a `\PackageError` on the `\usepackage{memoize}` line. In a real run the error is written to the extraction log `main.mmz.log` and TeX reports it from there, which is why TeX's own position is `main.mmz.log:1`. `leeni` places the error at the `\usepackage{memoize}` line and adds a hint on how to satisfy the dependency.

## How to Fix
1. Install a Perl PDF module: the distribution package (`libpdf-api2-perl`) or `cpan PDF::API2`.
2. Or let memoize extract with Python instead: `\usepackage[extract=python]{memoize}`, with `pypdf` installed.
