# Bibliography run failed: I found no \bibstyle command

## Tool Output
```text
I found no \bibstyle command---while reading file example.aux
(There was 1 error message)
```

## Explanation
The document has `\bibliography{...}` but no active `\bibliographystyle{...}` (here it is commented out), so BibTeX does not know how to format the entries and writes no bibliography. TeX reports nothing; every citation stays undefined. A copy of the sources that ships its `.bbl` hides the fault until the `.bbl` is regenerated. `leeni` reports an error at the `\bibliography` line. The same holds for `I found no \bibdata command`, a `\bibliographystyle` with no `\bibliography`.

## How to Fix
1. Add `\bibliographystyle{plain}` (or the style the venue asks for) before `\bibliography{...}`.
2. If the style lives in a class or package, check that it is loaded.
