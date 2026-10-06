# arXiv Submission Preparation & Verification

`leeni` provides automated packaging and verification for uploading papers to [arXiv.org](https://arxiv.org). A single command produces a clean, self-contained submission archive while stripping private comments and verifying that the output compiles identically.

---

## 1. Quick Start

To generate an arXiv submission package:

```bash
# Package the detected main document
l --arxiv

# Package a specific document
l --arxiv paper.tex

# Package and extract metadata (title, authors, abstract)
l --arxiv --meta paper.tex
```

This creates:
- `arxiv_<document>.zip`: Sanitized, flattened archive ready for arXiv upload.
- `arxiv_<document>_meta.txt`: Formatted metadata (when `--meta` is used).

> [!NOTE]
> For preparing publisher/journal archives (IEEE, Springer, Elsevier) that require flat `.tex` files without stripping comments or applying arXiv-specific constraints, use `-Z` / `--zip-flat`. See [Packaging Modes Comparison](advanced_topics.md#packaging-modes-comparison).

---

## 2. Packaging Pipeline (`--arxiv`)

When `--arxiv` is invoked, `leeni` performs the following steps:

### Monolithic TeX Flattening
arXiv prefers a single `.tex` file or a shallow hierarchy. The flattener (`LaTeXFlattener`):
- Inlines all subfiles referenced via `\input{...}` and `\include{...}` into a single `<document>.tex`.
- Recursively traverses nested inputs while detecting and reporting any circular input references.
- Preserves standard verbatim/listing environments (`verbatim`, `lstlisting`, `minted`) and inline `\verb` macros verbatim without expanding nested text.

### Comment & Macro Sanitization
- Strips private `%` comments to prevent leaking editorial notes, draft remarks, or internal comments.
- Preserves escaped percent signs (`\%`), URLs with percent encoding, and TeX magic comments (`% !TEX ...`).
- Retains empty `%` line-continuation markers where needed to preserve TeX whitespace semantics.
- Strips local development macro definitions and draft-mode packages.

### Active Figure Discovery
- Queries the LaTeX compiler recorder (`.fls`) to identify graphics files actually loaded during compilation.
- Packages only the necessary `.pdf`, `.png`, or `.jpg` figures.
- Strictly excludes raw figure sources (`.fig`, `.ipe`, `.svg`, `.asy`, `.gp`, `.gnuplot`, `.py`, `.R`) and backup copies (`*.bak`, `figs/bak/`).

### BibLaTeX Version Shielding
arXiv's TeX Live environment may run a different version of `biblatex` than your local machine, leading to `wrong format version` errors. When `biblatex` is detected, `leeni`:
- Bundles local distribution files (`biblatex.sty`, `biblatex.cfg`, `*.bbx`, `*.cbx`, `*.lbx`) directly into the archive.
- Can be disabled with `--no-biblatex-shield` if a standard system build is preferred.

---

## 3. Automated Verification

Before finalizing the package, `leeni` tests the generated zip inside an isolated `/tmp` sandbox:

1. **Sandbox Compilation**: Unpacks the archive and compiles it using `leeni --no-env` to ensure no ambient environment variables (`TEXINPUTS`, `BIBINPUTS`) are required.
2. **Text Layout Verification**: Uses `pdftotext -layout` to compare the rebuilt PDF against the original local PDF. Any text divergence triggers a verification failure.
3. **Visual Page Rendering (pdftoppm)**: Renders every page at 150 DPI and compares pixel output between builds.
   - Requires `pdftoppm` (from `poppler-utils`).
   - Use `--no-arxiv-visual-verify` to fall back to text-only verification if `pdftoppm` is not installed.
   - Use `--no-arxiv-verify` to skip sandbox verification entirely.
4. **Author Verification**: Parses expected author names from the TeX source and verifies that each author appears on the first page of the generated PDF. Normalizes accents, umlauts, whitespace, and punctuation. Identifies near-match misspellings via edit distance.

---

## 4. Metadata Extraction (`--meta`)

The `--meta` option extracts paper metadata and formats it for arXiv's web submission form:

```bash
l --meta paper.tex
```

Output is saved to `arxiv_<document>_meta.txt` and contains:
- **Title**: Clean plaintext title with TeX formatting stripped.
- **Authors**: Comma-separated author list.
- **Abstract**: ASCII-compatible, comment-free abstract. Standard MathJax inline TeX (`$...$`) is preserved, and paragraph breaks are formatted to match arXiv's required indentation.
- **Submission Comments**: Automatically calculated page count and figure count (e.g. `12 pages, 6 figures`).

---

## 5. Testing & Sampling Tooling

The repository includes tools for sampling and testing real-world arXiv papers:

### Sampling Papers (`tools/sample_arxiv`)
Downloads random source packages from arXiv for testing:

```bash
tools/sample_arxiv --output examples/arxiv --attempts 10
```

- Chooses completed calendar months uniformly from April 2007 onward.
- Downloads source archives (`source.tar.gz`, `source.tex`) and records API metadata in `metadata.json`.
- Caches monthly query counts in `~/.cache/leeni/arxiv`.

### Inspecting Metadata (`tools/check_arxiv_metadata`)
Verifies that the metadata extractor accurately matches arXiv's API records:

```bash
tools/check_arxiv_metadata examples/arxiv/1510.00949v1
tools/check_arxiv_metadata examples/arxiv/1510.00949v1 --main paper.tex --pdf paper.pdf
```

### Full Sandbox Testing (`tools/test_arxiv`)
Runs an end-to-end audit of a downloaded paper inside a disposable Bubblewrap sandbox:

```bash
tools/test_arxiv examples/arxiv/1510.00949v1
```

Tests include clean builds, incremental caching (`--fast`), single-pass builds, PDF diffing, portable zip packaging, and arXiv visual verification.

### Automated Test Cycle (`tools/arxiv_test_cycle`)
Combines sampling and testing into a single command:

```bash
tools/arxiv_test_cycle --output examples/arxiv
```
