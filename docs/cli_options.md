# Command-Line Interface (CLI) Options Reference

This document provides a complete reference for all command-line flags and options supported by `leeni` (`l`).

---

## Quick Reference Summary

| Flag | Category | Description |
| :--- | :--- | :--- |
| `(none)` | Build | Find and compile main document automatically. |
| `-f`, `--force` | Build | Force initial LaTeX run unconditionally, bypassing cache. |
| `-u`, `--single-pass` | Build | Execute a single LaTeX pass only (no BibTeX or rerun loops). |
| `-n`, `--passes NUM` | Build | Maximum compilation passes allowed (1-10, default: 5). |
| `-b`, `--[no-]bib` | Build | Explicitly enable or skip bibliography pass. |
| `-I`, `--[no-]index` | Build | Run makeindex when `.idx` changes. |
| `-e`, `--engine ENG` | Build | Compiler engine: `x` (`xelatex`), `l` (`lualatex`), `p` (`pdflatex`). |
| `--timeout SEC` | Build | Maximum timeout allowed per compiler pass (default: 180s). |
| `-T`, `--time` | Build | Show execution wall-clock time breakdown per pass. |
| `--update-if-changed` | Build | Only replace target PDF if extracted text changed (`pdftotext`). |
| `-c`, `--clean` | Cleaning | Clean temporary build files in `junk/` before compiling. |
| `-C`, `--clean-only` | Cleaning | Clean auxiliary files in directory and exit without compiling. |
| `--junk-dir DIR` | Cleaning | Directory for temporary build artifacts (default: `junk`). |
| `-x`, `--explain` | Diagnostics | Display plain-English boxed explanations and fixes. |
| `-a`, `--all` | Diagnostics | Show all diagnostics across all tiers (including Whatevers). |
| `-W`, `--werror` | Diagnostics | Treat compilation warnings as fatal errors. |
| `-v`, `--verbose` | Diagnostics | Show raw overfull hbox snippet text and resolution steps. |
| `-r`, `--raw` | Diagnostics | Print raw, unfiltered compiler stdout/stderr. |
| `--trace` | Diagnostics | Print exact external subprocess commands and environment. |
| `-s`, `--score` | Diagnostics | Quiet mode: print only numeric error/alert/warning counts. |
| `-cc`, `--compile` | Diagnostics | Strict GNU standard compiler format (`file:line:col: severity: msg`). |
| `-llm`, `--agent` | Diagnostics | Token-optimized mode for AI agents (zero ANSI, folded warnings, silent on success). |
| `--json` | Diagnostics | Output structured compilation and diagnostic results as JSON. |
| `-z`, `--zip` | Packaging | Create self-contained portable zip archive of paper. |
| `-Z`, `--zip-flat` | Packaging | Create self-contained portable zip archive with inlined `.tex`. |
| `-t`, `--verify` | Packaging | Verify portability by testing compilation in `/tmp` sandbox. |
| `-B`, `--bib-extract` | Packaging | Extract cited bibliography entries into local `.bib` file. |
| `--arxiv` | arXiv | Prepare sanitized, flattened, submission-ready arXiv zip package. |
| `--meta` | arXiv | Extract paper metadata and write `arxiv_<file>_meta.txt`. |
| `--no-env` | Environment | Reset environment variables used by LaTeX/BibTeX/Biber. |
| `--[no-]lock` | Environment | Enable/disable lockfile concurrency protection (default: on). |
| `--theme THEME` | Config | Set diagnostic color theme (`blush`, `catppuccin`, etc.). |
| `--theme-list` | Config | List available diagnostic color themes with previews. |
| `--config-init` | Config | Create a local `.l.jsonc` configuration template in current directory. |
| `--config-show` | Config | Show active configuration sources and resolved settings. |
| `--config-save` | Config | Save specified CLI options to configuration file. |
| `--vscode-init` | Config | Create VS Code `tasks.json` and `settings.json` in `.vscode/`. |
| `--gitignore-init` | Config | Create or add standard LaTeX & `junk/` rules to `.gitignore`. |
| `-m`, `--main` | Info | Print detected main LaTeX file and exit. |
| `-h`, `--help` | Help | Show condensed help summary of everyday options. |
| `-H`, `--help-all` | Help | Show complete manual with detailed explanations. |

---

## 1. Compilation & Convergence Options

### `-f`, `--force`
Bypasses `junk/.build_state.json` and forces the first LaTeX pass to run unconditionally. Subsequent passes and BibTeX will only run if required for convergence.
```bash
l -f paper.tex
```

### `-u`, `--single-pass`
Draft mode: executes exactly 1 LaTeX pass, skipping BibTeX/Biber and ignoring rerun notifications. Ideal for quick syntax verification during rapid drafting.
```bash
l -u paper.tex
```

### `-n`, `--passes NUM`
Sets the maximum number of compilation passes allowed (1-10, default: 5). If cross-references or bibliographies do not stabilize within this limit, or the auxiliary state starts cycling between values, `leeni` stops, reports a warning (which `--werror` treats as an error), and does not cache the build.
```bash
l -n 2 paper.tex
```

### `-b`, `--[no-]bib`
Explicitly enables or disables the bibliography pass. By default, `leeni` automatically detects whether BibTeX or Biber is required based on auxiliary files (`.aux` / `.bcf`).
```bash
l --no-bib paper.tex
```

### `-I`, `--[no-]index`
Runs `makeindex` automatically whenever the `.idx` file changes.
```bash
l -I book.tex
```

### `-e`, `--engine ENGINE`
Selects the LaTeX engine. Accepts canonical names or single-letter shortcuts:
- `x` or `xelatex` (default)
- `l` or `lualatex`
- `p` or `pdflatex`
```bash
l -e lualatex paper.tex
```

### `--update-if-changed`
Uses `pdftotext` to extract and compare text layout between the newly compiled PDF and the existing target. If text layout has not changed, the target file is not overwritten, preventing PDF viewer reload flicker on non-visual edits.
```bash
l --update-if-changed paper.tex
```

### `-T`, `--time`
Displays wall-clock execution timing breakdown per compilation pass and bibliography step.
```bash
l -T paper.tex
```

---

## 2. Cleaning & Workspace Isolation

### `-c`, `--clean`
Wipes the `junk/` directory before starting compilation, ensuring a 100% clean rebuild without leftover auxiliary state.
```bash
l -c paper.tex
```

### `-C`, `--clean-only`
Removes temporary auxiliary files (`.aux`, `.log`, `.bbl`, `.fls`, `.toc`, etc.) from the current directory and `junk/`, then exits immediately without compiling.
```bash
l -C
```

### `--junk-dir DIR`
Specifies the directory where intermediate build artifacts are isolated. Defaults to `junk` (or auto-detects `.junk` if present).
```bash
l --junk-dir=.build paper.tex
```

---

## 3. Diagnostics & Error Filtering

### `-x`, `--explain`
Renders formatted, plain-English explanation boxes for TeX errors and common warnings, complete with root causes and actionable fixes.
```bash
l -x paper.tex
```

### `-a`, `--all`
Disables diagnostic tier suppression, displaying all notices across all tiers—including minor sub-millimeter layout overflow notices (**Whatevers**) and standard Warnings.
```bash
l -a paper.tex
```

### `-W`, `--werror`
Treats compilation warnings and Alerts as fatal errors, causing `leeni` to exit with a non-zero status.
```bash
l -W paper.tex
```

### `-v`, `--verbose`
Enables verbose output mode, showing raw overfull `\hbox` snippet text, font substitutions, and pass resolution details.
```bash
l -v paper.tex
```

### `-r`, `--raw`
Bypasses `leeni`'s diagnostic interception engine entirely and streams raw, unfiltered compiler stdout/stderr directly to the terminal.
```bash
l -r paper.tex
```

### `--trace`
Prints the exact external subprocess command, working directory, and environment variable overrides before each compiler invocation.
```bash
l --trace paper.tex
```

### `-s`, `--score`
Quiet mode: suppresses compilation output and prints only numeric error, alert, and warning counts.
```bash
l -s paper.tex
```

### `-cc`, `--compile`
Formats diagnostics according to the strict GNU compiler standard (`file:line:col: severity: message`), suitable for IDE problem matchers and Unix pipe tools.
```bash
l -cc paper.tex
```

### `-llm`, `--agent`
Optimized mode for AI coding agents (Claude Code, Cursor, Aider, OpenCode):
- Guaranteed plaintext (zero ANSI escapes, zero terminal hyperlinks).
- Completely silent (`exit 0` with 0 bytes stdout/stderr) on clean builds or cached targets.
- Automatically folds repeated citation/layout warnings into 2 instances + count.
```bash
l -llm paper.tex
```

### `--json`
Emits structured JSON output containing pass counts, exit codes, target paths, and all classified diagnostics.
```bash
l --json paper.tex
```

---

## 4. Paper Packaging & Portability

### `-z`, `--zip`
Creates a self-contained portable `.zip` archive containing the paper, active figures, styles, and compiled `.bbl` without system TeX Live packages.
```bash
l -z paper.tex
```

### `-Z`, `--zip-flat`
Creates a flattened `.zip` archive where all nested `\input` and `\include` subfiles are recursively inlined into a single monolithic `.tex` file (required by journals like IEEE, Springer, and Elsevier).
```bash
l -Z paper.tex
```

### `-t`, `--verify`
Tests the generated `.zip` package by unpacking it into an isolated `/tmp/leeni_verify_XXXX` sandbox and compiling it with `--no-env` to ensure 100% self-contained portability.
```bash
l -z -t paper.tex
```

### `-B`, `--bib-extract`
Extracts only the bibliography entries cited in your document from your master `.bib` database into a minimal, standalone `.bib` file.
```bash
l -B paper.tex
l -B --bib-name=local_refs.bib paper.tex
```

---

## 5. arXiv Submission

### `--arxiv`
Generates a submission-ready arXiv package: inlines TeX files, strips private comments, shields local biblatex packages, and verifies compilation in an isolated sandbox.
```bash
l --arxiv paper.tex
```

### `--meta`
Extracts title, author list, and MathJax-compatible abstract, writing them to `arxiv_<doc>_meta.txt` for easy copy-pasting into the arXiv submission form.
```bash
l --meta paper.tex
```

---

## 6. Environment & Configuration

### `--no-env`
Unsets ambient TeX environment variables (`TEXINPUTS`, `BIBINPUTS`, `BSTINPUTS`, `TEXMFHOME`, etc.) to prevent host machine configuration pollution.
```bash
l --no-env paper.tex
```

### `--[no-]lock`
Enables or disables file locking protection (default: enabled). Prevents simultaneous compiler processes from corrupting intermediate build state.
```bash
l --no-lock paper.tex
```

### `--theme THEME`
Sets the terminal diagnostic color theme (`blush`, `catppuccin`, `tokyo-night`, `dracula`, `nord`, `ansi`). Pass `+1` to cycle to the next theme and save it globally.
```bash
l --theme catppuccin
l --theme +1
```

### `--config-init`
Generates a documented `.l.jsonc` configuration file in the current directory.
```bash
l --config-init
```

### `--config-show`
Displays the active configuration hierarchy, loaded file paths, and merged settings.
```bash
l --config-show
```

### `--config-save`
Persists CLI options passed on the command line into `.l.jsonc` (or global config with `--global`).
```bash
l -e lualatex --update-if-changed --config-save
```

### `--vscode-init`
Generates `.vscode/tasks.json` and `settings.json` configured for `leeni` problem matching and build tasks.
```bash
l --vscode-init
```

### `--gitignore-init`
Appends standard `leeni` and LaTeX ignore rules to `.gitignore`.
```bash
l --gitignore-init
```

---

## 7. Help & Information

### `-m`, `--main`
Detects and prints the main `.tex` document in the current directory using heuristics and exits immediately.
```bash
l -m
```

### `-h`, `--help`
Displays a concise, colorized summary of everyday options.
```bash
l -h
```

### `-H`, `--help-all`
Displays the full man-page manual with detailed descriptions and usage examples for every option.
```bash
l -H
```

---

## 8. Symlink Shortcuts & Personalities

When installed via `tools/install` (or manually symlinked), `leeni` inspects `$PROGRAM_NAME` to automatically adapt its default behavior based on the command invoked:

| Command | Behavior |
| :--- | :--- |
| `l`, `leeni` | Default compilation (`xelatex`, up to 5 passes, automatic bibliography). |
| `lw` | Incremental rebuild (identical to `l`; preserved for compatibility with legacy shortcuts). |
| `ll`, `llua` | Compile using LuaLaTeX (`--engine=lualatex`). |
| `lp`, `pdflatex` | Compile using pdfLaTeX (`--engine=pdflatex`). |
| `clean_latex`, `latex_clean` | Clean temporary and auxiliary files in current directory and exit. |
| `latex_file_in_dir` | Detect and print the main `.tex` document in the current directory and exit. |
| `latex_env_free` | Run `l` with environment sanitization enabled (`--no-env`). |

