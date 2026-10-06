# Advanced Execution, Packaging & Environment Control

`leeni` provides powerful features for publication packaging, cited bibliography harvesting, non-visual diff guarding, sandbox verification, and environment isolation.

This guide covers operational controls and power-user workflows beyond everyday document compilation.

---

## 1. Journal & Publisher Packaging (`-z` and `-Z`)

When submitting to peer-reviewed journals, conferences, or collaborating with co-authors, `leeni` can package your document into a clean, standalone `.zip` archive.

### Standard Portable Archive (`-z` / `--zip`)
Creates a self-contained zip containing the paper, local figures, styles, and compiled bibliography:

```bash
l -z paper.tex
```

The packager:
- Analyzes compiler recorder logs (`.fls`) to bundle only the files your document actually inputs, ignoring system TeX Live packages (`texmf-dist`).
- Preserves the compiled `.bbl` so recipients can compile without needing your `.bib` files or running BibTeX.
- Discovers companion figure source files (`.fig`, `.ipe`, `.svg`, `.asy`, `.gp`, `.gnuplot`, `.py`, `.R`) matching included figure stems.
- Automatically excludes editor backups (`*~`, `*.bak`, `figs/bak/`).

To include arbitrary supplementary datasets or notes:
```bash
l -z paper.tex -- notes.txt data/*.csv
```

### Flattened Single-File Archive (`-Z` / `--zip-flat`)
Many journal portals (such as Springer Nature, IEEE Author Portal, and Elsevier Editorial Manager) require all LaTeX content in a single monolithic `.tex` file without nested `\input` or `\include` directories.

`-Z` (or `--zip-flat`) recursively inlines all subfiles into a single `<document>.tex`, bundles active figures and styles, retains the `.bbl`, and omits subordinate `.tex` files:

```bash
l -Z paper.tex
```

### Style File Organization (`--[no-]styles-inject`)
- **Default (`false`)**: Harvested `.sty` and `.cls` files are placed in the archive root for universal journal submission portal compatibility.
- **Opt-in (`--styles-inject`)**: Harvested styles are placed into a `styles/` subfolder, and `\def\input@path{{styles/}{./}}` is prepended to the packaged `.tex` file.

### Packaging Modes Comparison

| Feature | Standard Zip (`-z`) | Flat Zip (`-Z`) | arXiv Package (`--arxiv`) |
| :--- | :--- | :--- | :--- |
| **TeX Structure** | Multi-file tree preserved | **Inlined single `.tex` file** | Inlined single `.tex` file |
| **Subordinate `.tex`** | Copied into archive | **Omitted** | Omitted |
| **Comments (`%`)** | Preserved | **Preserved** | Stripped by default |
| **Bibliography** | Copies `.bbl` and local `.bib` | Copies `.bbl` and local `.bib` | Copies `.bbl` (shields biblatex) |
| **Figures & Styles** | Preserved | Preserved | Preserved |
| **Figure Sources** | Companion sources bundled (`.fig`, `.ipe`, etc.) | Companion sources bundled | Strictly excluded (PDF/PNG only) |
| **Metadata File** | None | None | Generates `arxiv_*_meta.txt` |
| **Target Output** | `<doc>.zip` | `<doc>.zip` | `arxiv_<doc>.zip` |
| **Primary Use Case** | Co-authors & general archival | Journal submission portals (IEEE, Springer) | Direct submission to arXiv.org |

*(For dedicated arXiv submission instructions, see [docs/arxiv.md](arxiv.md).)*

---

## 2. Cited Bibliography Extraction (`-B` / `--bib-extract`)

Many researchers maintain a single, massive `all.bib` database containing thousands of entries accumulated over decades. When submitting a paper or sharing code, sending a 10MB `.bib` file is cumbersome and leaks unrelated literature.

`-B` extracts **only the references cited in your document** into a minimal, self-contained `.bib` file:

```bash
# Extracts cited references to paper.bib
l -B paper.tex

# Or specify a custom output filename
l -B --bib-name=refs.bib paper.tex
```

How it works:
1. `leeni` runs the compilation pass to generate the `.aux` file.
2. It parses all `\citation{...}` keys in the `.aux`.
3. It extracts matching `@article`, `@book`, and `@inproceedings` entries (including cross-referenced string macros) into the target `.bib` file.

---

## 3. Text-Diff PDF Update Guard (`--update-if-changed`)

When editing LaTeX documents with external PDF viewers (such as Skim, Zathura, or Evince), saving a document causes the viewer to refresh. If you are editing non-visual content (such as comments, internal macros, or formatting whitespace), viewer reloading can cause annoying screen flicker.

The `--update-if-changed` flag compares the extracted text layout of the newly compiled PDF against the existing file using `pdftotext`:

```bash
l --update-if-changed paper.tex
```

If the extracted text content and layout have not changed, `leeni` **skips replacing the target PDF on disk**, preventing the PDF viewer from triggering a reload.

To enable this permanently for a project, set it in `.l.jsonc`:
```jsonc
{
  "update_on_diff": true
}
```

---

## 4. Sandbox Portability Verification (`-t` / `--verify`)

To ensure that your document or packaged `.zip` will compile cleanly on another machine (without relying on uncommitted files or packages only installed on your personal computer), use `-t`:

```bash
l -z -t paper.tex
```

The verification engine:
1. Unpacks the generated `.zip` package into an isolated `/tmp/leeni_verify_XXXX` sandbox.
2. Compiles the document with `l --no-env` (stripping all user environment variables like `TEXINPUTS`).
3. Compares the resulting PDF text against the original build using `pdftotext -layout`.
4. Cleans up the sandbox directory upon verification success.

### Offline Bubblewrap Sandbox (`tools/bws_run`)
For strict offline testing, `tools/bws_run` compiles documents inside an unprivileged [Bubblewrap](https://github.com/containers/bubblewrap) container:

```bash
tools/bws_run /path/to/paper -- leeni paper.tex
```
- **Zero Network Access**: Prevents packages from making external network calls.
- **Empty Home Directory**: Unsets `~/.config` and `~/.ssh`.
- **Read-Only TeX Trees**: System font and TeX Live caches are mounted read-only.

---

## 5. Environment Sanitization & Overrides

### Sanitizing Environment (`--no-env`)
Stray environment variables in `~/.bashrc` or `~/.zshrc` (such as `TEXINPUTS=".:/old/path:"`) can cause mysterious compiler errors. The `--no-env` flag unsets TeX-related variables during execution:

```bash
l --no-env paper.tex
```

Variables reset include:
`TEXINPUTS`, `BIBINPUTS`, `BSTINPUTS`, `PDFTEXINPUTS`, `XETEXINPUTS`, `LUATEXINPUTS`, `TEXMFHOME`, `TEXMFCNF`.

Symlink shortcuts: running `latex_env_free`, `bibtex_env_free`, or `pdflatex_env_free` automatically enables `--no-env`.

### Passing Custom TeX Options (`LATEXOPTS`)
To pass low-level flags directly to the underlying TeX engine:

```bash
LATEXOPTS="-shell-escape -synctex=1" l paper.tex
```

---

## 6. Concurrency & Process Locking (`--lock` / `--no-lock`)

When using editor extensions that compile on save or watch mode (`lw`), multiple `leeni` processes can run concurrently, risking corruption of `junk/` artifacts.

- **Default (`--lock`)**: `leeni` uses an atomic file lock (`flock`) on a target-specific lockfile in `/tmp`. A second process will display a polite waiting indicator until the active build finishes.
- **Disabling (`--no-lock`)**: When running automated parallel CI test matrices across independent sub-documents, pass `--no-lock` to disable locking:
  ```bash
  l --no-lock paper.tex
  ```

---

## 7. Legacy REVTeX 4.0 Compatibility

Physics papers written prior to 2010 frequently use `\documentclass{revtex4}` (which was superseded by `revtex4-1` and `revtex4-2` and removed from modern TeX Live). Compiling these legacy documents yields missing class errors.

`leeni` bundles a clean, LPPL-licensed REVTeX 4.0 tree:
- Installed to `~/.local/share/leeni/texmf` during `tools/install`.
- Auto-injected into the compiler search path only when `\documentclass{revtex4}` is detected.
- Bundled automatically into `-z` and `--arxiv` archives so the recipient can compile without missing classes.

---

## 8. Execution Tracing & Profiling (`--trace`, `-T`, `-r`)

When debugging complex build issues or optimizing compilation speed:

- **`-T`, `--time`**: Emits a wall-clock execution timing breakdown per compilation pass and bibliography step.
- **`--trace`**: Prints the exact subprocess command line, working directory, and environment variable overrides before each execution.
- **`-r`, `--raw`**: Bypasses diagnostic filtering and prints raw, unbuffered compiler stdout/stderr directly to the terminal.

## 9. Convergence Loop Behavior & Limits

- **Passes**: up to `-n`/`passes` LaTeX passes (default 5, maximum 10). The loop stops as soon as the `.aux` files and the pagination side files (`.toc`, `.lof`, `.lot`, `.out`, `.nav`, `.snm`) stop changing and the pass output requests no rerun.
- **Not converged**: if a rerun is still requested at the pass limit, or the `.aux` state starts cycling between earlier values, `leeni` stops, emits a `leeni: build did not converge` warning (counted by `--werror` and the JSON output), and does not cache the build.
- **Bibliography runs**: BibTeX/Biber runs once, and at most twice if the first run is provably stale (uncovered citations, a changed citation set, or a changed `.bcf`). A bibliography still stale at exit prevents caching. With `-n 1` bibliography tools are skipped, since no later pass could use their output.
- **Stale bibliography files**: a `.bbl`, `.bcf` or biblatex `.aux` left in `junk/` by a build using the other bibliography system is discarded before the first pass.
- **Single bibliography only**: `bibtex` is run on the main document's `.aux` only. `multibib`/`chapterbib` documents that need one BibTeX run per sub-`.aux` are not handled automatically; run those tools by hand.
