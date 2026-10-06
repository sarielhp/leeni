# Troubleshooting Bibliography Errors in LaTeX (`\printbibliography` & `\bibliography`)

A comprehensive guide to diagnosing, understanding, and fixing cryptic compilation errors in BibLaTeX and BibTeX using [`leeni`](../README.md).

---

## 1. The Mystery: Why Does LaTeX Blame `\printbibliography`?

One of the most frustrating experiences in LaTeX occurs when compilation abruptly halts with a fatal error pointing directly at `\printbibliography` (or `\bibliography`):

```text
! Double subscript.
<argument> NORDIC_J_
                    COMP
l.336 \printbibliography
```

The error log insists that line 336 of `main.tex` is broken. Yet line 336 contains nothing more than `\printbibliography` or `\ChapterEnd`. It gives **no hint** about which citation key failed, which `.bib` file it came from, or what field is invalid.

### Why TeX Decouples the Error from the `.bib` File

To understand why this happens, consider how the LaTeX bibliography pipeline actually works:

```
┌──────────────┐     biber /      ┌──────────────┐      pdflatex /     ┌──────────────┐
│  refs.bib    │ ───────────────> │   junk.bbl   │ ──────────────────> │  output.pdf  │
│ (.bib source)│     bibtex       │ (TeX macros) │      xelatex        │              │
└──────────────┘                  └──────────────┘         ▲           └──────────────┘
                                                           │
                                                  CRASH HAPPENS HERE!
                                                  (TeX only knows .bbl / main.tex,
                                                   completely blind to refs.bib)
```

1. **Phase 1 (Data Extraction):** The TeX engine reads `main.tex` and outputs citation requests to `.aux` or `.bcf`.
2. **Phase 2 (Formatting):** `biber` or `bibtex` reads your `.bib` databases, sorts entries, applies formatting rules, and writes a `.bbl` file containing raw, expanded TeX code.
3. **Phase 3 (Typesetting):** On the next TeX pass, `\printbibliography` opens and expands the `.bbl` file as raw TeX macros.

If your `.bib` file contains an unescaped character (like an underscore `_` in a journal abbreviation or an unescaped `&` in a publisher), `biber` does not validate the TeX syntax—it blindly copies the string into the `.bbl`. 

When the TeX engine encounters the offending token during `\printbibliography`, **TeX has no memory of the original `.bib` file**. It only sees the macro expanding inside `main.tex`.

---

## 2. Common Cryptic Error Symptoms

The table below lists the most common error signatures produced by bibliography syntax errors:

| Error Signature | Real Culprit in `.bib` File | Typical Example |
| :--- | :--- | :--- |
| `! Missing $ inserted.` | Unescaped underscore (`_`) in `journal`, `title`, or `doi`. | `journal = {IEEE_ACM_TRANS}` |
| `! Double subscript.` | Multiple underscores in a single field. | `journal = {NORDIC_J_COMP}` |
| `! Misplaced alignment tab character &.` | Unescaped ampersand (`&`) in publisher or author list. | `publisher = {Barnes & Noble}` |
| `! File ended while scanning use of \field.` | Unbalanced curly braces (`{` or `}`) in abstract or note. | `note = {Missing closing brace` |
| `Paragraph ended before \field was complete.` | Blank line inside an entry's field in the `.bib` file. | Blank line inside `abstract = {...}` |
| `LaTeX Error: Something's wrong--perhaps a missing \item` | Corrupted `.bbl` or empty bibliography printed. | Calling `\printbibliography` with no citations |

---

## 3. The Traditional Troubleshooting Agony

Before `leeni`, authors faced two painful, time-consuming manual options:

### Method A: The Binary Search (20–45 minutes)
1. Comment out half the `\cite{...}` commands or entries in your `.bib` file.
2. Run `biber` and recompile.
3. If it compiles, the offending citation is in the commented half; if it fails, it is in the active half.
4. Repeat this divide-and-conquer process over 10–15 iterations until the single corrupt citation key is found.

### Method B: The `.bbl` File Dissection (10–20 minutes)
1. Navigate into the temporary build folder (`junk/` or the project root).
2. Open `paper.bbl` in a text editor.
3. Search for the line where TeX choked (matching the token printed in `<argument>`).
4. Read upwards in the `.bbl` to locate the surrounding `\entry{citekey}{...}` definition.
5. Manually search your `.bib` files to find the entry and edit the offending field.

---

## 4. How `leeni` Solves It Automatically

`leeni` eliminates this entire manual debugging cycle through automated AST-level entry tracking and multi-database resolution.

### 1. Transparent AST Tracking
When `biblatex` is used, `leeni` automatically injects a non-destructive logging hook:
```latex
\AtBeginDocument{\@ifpackageloaded{biblatex}{\AtEveryBibitem{\typeout{BIB_ENTRY: \thefield{entrykey}}}}{}}
```
During compilation, each bibliography item reports its unique citation key to the log stream as it begins typesetting.

### 2. Failure Interception & Provenance
When the TeX engine crashes inside `\printbibliography`, `leeni` immediately intercepts the failure and extracts:
- The **active citation key** typeset right before the crash.
- The **offending token** from TeX's `<argument>` or error context.

### 3. Automated Source Resolution
`leeni` queries the `.bcf` datasource list, `\bibliography{}` declarations, and `BIBINPUTS` paths across the workspace. It scans the candidate `.bib` files, matches the entry key, and locates the exact line containing the offending token.

### 4. Direct Companion Diagnostic Output
Instead of leaving the author staring at an anonymous error in `main.tex`, `leeni` surfaces both the primary engine error and a **companion error** pointing directly into the `.bib` source:

```text
── main.tex (2 errors) ─────────────────────────────────────────────────────────
./main.tex:336: Missing $ inserted.
       <inserted text> $
       l.336 \printbibliography
       ▸ Hint: Math symbol (like _ or ^) outside math mode; wrap in $...$
./main.tex:336: Double subscript.
       <argument> NORDIC_J_
                           COMP
       l.336 \printbibliography
       ▸ Hint: Consecutive '_' subscripts; wrap in braces like 'x_{a_b}'

── refs/geometry.bib (1 error) ─────────────────────────────────────────────────
refs/geometry.bib:13148: [leeni] Bibliography error in entry 'grss-sracp-95'
       l.13148 journal      = {NORDIC_J_COMP},
       ▸ Hint: Offending token 'NORDIC_J_COMP' found on this line.
```

The author can click directly on `refs/geometry.bib:13148` in their editor and fix the typo instantly.

---

## 5. Prevention & Best Practices

To avoid syntax crashes in `.bib` files:

1. **Escape Reserved TeX Characters:**
   - Underscores: Use `\_` instead of `_` (e.g. `journal = {IEEE\_ACM\_Trans}`).
   - Ampersands: Use `\&` instead of `&` (e.g. `publisher = {John Wiley \& Sons}`).
   - Percent signs: Use `\%` instead of `%` (e.g. `title = {A 100\% Verified System}`).
   - Dollar signs: Use `\$` instead of `$` when referring to currency.

2. **Wrap Math in Math Mode:**
   - If an entry title includes mathematical notation, wrap it in `$ ... $`:
     ```bibtex
     title = {An $O(n \log n)$ Sorting Algorithm}
     ```

3. **Protect DOIs and URLs:**
   - Use dedicated `doi` and `url` fields rather than pasting raw links into `note` or `howpublished`. BibLaTeX's standard styles automatically escape special characters in `doi` and `url` fields.

4. **Protect Capitalization with Braces:**
   - Wrap proper nouns and acronyms in braces to prevent bibtex downcasing:
     ```bibtex
     title = {Analysis of the {VLSI} Architecture for {IEEE} Standards}
     ```
