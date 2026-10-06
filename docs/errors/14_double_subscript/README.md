# Double subscript

## Description
Two consecutive subscript characters `_` were applied to the same math symbol without grouping braces.

## Remediation
Group the subscripts with curly braces: `$x_{a_b}$` or `$x_{a,b}$`.

> [!NOTE]
> If this error occurs during `\printbibliography` or `\bibliography`, consecutive unescaped underscores (e.g. `journal = {NORDIC_J_COMP}`) exist inside a `.bib` database field. See [Troubleshooting Bibliography Errors](../../troubleshooting_bibliography_errors.md) for automated diagnosis with `leeni`.
