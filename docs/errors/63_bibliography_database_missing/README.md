# Bibliography run failed: I couldn't open database file

## Tool Output
```text
I couldn't open database file nonexistent_refs.bib
---line 4 of file example.aux
 : \bibdata{nonexistent_refs
 :                          }
```

## Explanation
BibTeX (or Biber) could not read a database the document names in `\bibliography{...}` or `\addbibresource{...}`, so it wrote no bibliography. TeX itself reports nothing: the document still compiles, with every citation undefined. `leeni` stops the build and reports the failure as an error at the line naming the database (with `-cc`, `-llm` and `--json` as well as in the terminal).

## How to Fix
1. Check the database name: `\bibliography{refs}` reads `refs.bib`. `leeni` suggests a `.bib` file of a similar name when one exists.
2. Check the path: the database is looked up relative to the document and on `BIBINPUTS`.
3. For a shared bibliography outside the project, add its directory to `BIBINPUTS` or to `bib_dirs` in `.l.jsonc`.
