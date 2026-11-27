# LaTeX Error: Not in outer par mode

## Description
A floating environment (`figure` or `table`) was placed inside a restricted box (`\mbox`) or table cell.

## Remediation
Move floating environments to the main vertical page flow, or use a `minipage` with `\captionof`.

The same applies to a `\marginpar`, written directly or produced by a macro such as `\todo` from todonotes. `\marginnote` (marginnote package) puts text in the margin without making a float, and works inside boxes.

## See Also
- [Float(s) lost](../90_float_lost/): the same mistake when LaTeX does not catch it at the spot (a paragraph inside a box, such as a minipage, a footnote, or a caption that is not measured in a box first). It surfaces only at the next `\clearpage`.
