# Command-Line Interface (CLI) Options Reference

This document provides a complete reference for all command-line flags and options supported by `leeni` (`l`).

All long options accept either `-` or `--` and allow internal dashes to be omitted. For example, `--zip-alone`, `-zip-alone`, `--zipalone`, and `-zipalone` are equivalent; so are `--no-styles-inject` and `-nostylesinject`. Option values keep their original spelling, including values after `=`. Single-letter options and grouped short flags such as `-zt` still work. A complete recognized long name takes precedence over a short-flag group. Spellings after the `--` separator are treated as filenames.

## Browse this reference

- [Quick reference](#quick-reference-summary)
- [Building and convergence](#building)
- [Cleaning and cache](#cleaning)
- [Diagnostics](#diagnostics)
- [Paper packaging](#packaging)
- [arXiv submission](#arxiv)
- [Environment and configuration](#configuration)
- [Help and information](#help)
- [Shortcut commands](#shortcuts)

---

## Quick Reference Summary

| Flag | Category | Description |
| :--- | :--- | :--- |
| `(none)` | Build | Find and compile main document automatically. |
| `-f`, `--force` | Build | Force initial LaTeX run unconditionally, bypassing cache. |
| `--force-file` | Build | Force using specified file even if it matches `exclude_main_tex`. |
| `-u`, `--single-pass` | Build | Execute a single LaTeX pass only (no BibTeX or rerun loops). |
| `-n`, `--passes NUM` | Build | Maximum compilation passes allowed (1-10, default: 5). |
| `-b`, `--[no-]bib` | Build | Explicitly enable or skip bibliography pass. |
| `--[no-]draft-passes` | Build | Skip PDF output on passes certain to be followed by another (default: on). |
| `--[no-]index` | Build | Run makeindex when `.idx` changes. |
| `-e`, `--engine ENG` | Build | Compiler engine: `x` (`xelatex`), `l` (`lualatex`), `p` (`pdflatex`). |
| `--timeout SEC` | Build | Maximum timeout allowed per compiler pass (default: 180s). |
| `-T`, `--time` | Build | Show execution wall-clock time breakdown per pass. |
| `--no-export` | Build | Leave the working tree untouched; outputs stay in the build directory. |
| `--update-if-changed` | Build | Only replace target PDF if extracted text changed (`pdftotext`). |
| `--[no-]relatex-synctex` | Build | With lualatex, a background `relatex` replaces the SyncTeX with a verified word-level one. |
| `--[no-]xelatex-preview` | Build | With `--relatex-synctex`, build a XeLaTeX preview that relatex replaces with its LuaLaTeX PDF and word-level SyncTeX. |
| `--synctex-status` | Build | Show whether the background relatex SyncTeX run is alive, with its log tail. |
| `-c`, `--clean` | Cleaning | Clean the project cache and regenerable root files before compiling. |
| `-C`, `--clean-only` | Cleaning | Clean the project cache and root auxiliary files, then exit. |
| `--junk-dir DIR` | Cleaning | Override the XDG cache build directory. |
| `-x`, `--explain` | Diagnostics | Display plain-English boxed explanations and fixes. |
| `-a`, `--all` | Diagnostics | Show all diagnostics across all tiers (including Whatevers). |
| `-W`, `--werror` | Diagnostics | Treat compilation warnings as fatal errors. |
| `--errors-only` | Diagnostics | Suppress alerts, warnings and Whatevers; fail only on real errors. Disables configured `werror`; with `--all` or `--werror`, the last flag wins. |
| `-v`, `--verbose` | Diagnostics | Show raw overfull hbox snippet text and resolution steps. |
| `-r`, `--raw` | Diagnostics | Print raw, unfiltered compiler stdout/stderr. |
| `--trace` | Diagnostics | Print exact external subprocess commands and environment. |
| `-s`, `--score` | Diagnostics | Quiet mode: print only numeric error/alert/warning counts. |
| `-cc`, `--compile` | Diagnostics | Strict GNU standard compiler format (`file:line:col: severity: msg`). |
| `-llm`, `--agent` | Diagnostics | Token-optimized mode for AI agents (zero ANSI, folded warnings, silent on success). |
| `--json` | Diagnostics | Output structured compilation and diagnostic results as JSON. |
| `-z`, `--zip` | Packaging | Create self-contained portable zip archive of paper. |
| `--sandbox` | Packaging | Rebuild from an isolated copy kept in the cache with `--no-env` and compare the PDFs. |
| `--zip-alone` | Packaging | `--sandbox` with strict checks (no errors or alerts), then zip the sandbox. |
| `-Z`, `--zip-flat` | Packaging | Create self-contained portable zip archive with inlined `.tex`. |
| `-t`, `--verify` | Packaging | Check the zip's contents in the cache sandbox with `--no-env`, then zip that sandbox. |
| `-I`, `--make-indep` | Packaging | Convert the paper in place to compile with `--no-env`; originals saved in `old_ver_yy_mm_dd_hh_mm.zip`. |
| `--dry-run` | Packaging | With `-I`: check the conversion and show the changes without making them. |
| `--bib-fix` | Bibliography | Build; add missing entries, `@string` macros and `@preamble` blocks to the paper's own `.bib` from `bib_fix_sources` and `BIBINPUTS` (see [bibkit.md](bibkit.md)). |
| `--bib-missing` | Diagnostics | Build as usual; print only the keys of cited entries missing from the bibliography (regular output on errors). |
| `-B`, `--bib-extract` | Packaging | Extract cited bibliography entries into local `.bib` file. |
| `--arxiv` | arXiv | Prepare sanitized, flattened, submission-ready arXiv zip package. |
| `--meta` | arXiv | Extract paper metadata and write `arxiv_<file>_meta.txt`. |
| `--no-env` | Environment | Reset environment variables used by LaTeX/BibTeX/Biber. |
| `--[no-]lock` | Environment | Enable/disable lockfile concurrency protection (default: on). |
| `--theme THEME` | Config | Set diagnostic color theme (`blush`, `catppuccin`, etc.). |
| `--theme-list` | Config | List available diagnostic color themes with previews. |
| `--set-main-file FILE` | Config | Set main LaTeX document in local `.l.jsonc` and exit. |
| `--config-init` | Config | Create a local `.l.jsonc` configuration template in current directory. |
| `--config-show` | Config | Show active configuration sources and resolved settings. |
| `--report [LEVEL]` | Config | Write a problem-report bundle (diagnostics, build logs, environment; `full` adds sources) and exit. |
| `--doctor [TARGET]` | Config | Report engines, helper tools, cache state and quarantined builds; show one case, `clear` them, or `prune` stale build directories. |
| `--config-save` | Config | Save specified CLI options to configuration file. |
| `--config-unset KEY` | Config | Remove a saved setting from local or global configuration. |
| `--vscode-init` | Config | Create VS Code `tasks.json` and `settings.json` in `.vscode/`. |
| `--gitignore-init` | Config | Create or add standard LaTeX & `junk/` rules to `.gitignore`. |
| `-m`, `--main` | Info | Print detected main LaTeX file and exit. |
| `-h`, `--help` | Help | Show condensed help summary of everyday options. |
| `-H`, `--help-all` | Help | Show complete manual with detailed explanations. |

---

## 1. Compilation & Convergence Options {#building}

### `-f`, `--force`
Bypasses `.build_state.json` in the project cache and forces the first LaTeX pass to run unconditionally. Subsequent passes and BibTeX will only run if required for convergence.
```bash
l -f paper.tex
```

### `--force-file`
Forces `leeni` to compile the specified `.tex` file even if its filename matches an `exclude_main_tex` pattern (e.g. `prefix.tex` or `preamble.tex`).
```bash
l --force-file prefix.tex
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

### `--[no-]draft-passes`
Off by default (config key `"draft_passes"`; measured gain on a 31-page paper: 0.18 s of 11 s per fresh build). A LaTeX pass runs in draft mode (`-draftmode` for pdflatex and lualatex, `-no-pdf` for xelatex: aux files, log and diagnostics as usual, no PDF) only when leeni knows before running it that another pass follows: a bibliography tool is certain to run after the first pass (no `.bbl` yet while the sources cite from a `\bibliography`/`\addbibresource` database, `--bib`, or a `.bib` changed since the last run), or makeindex is (`--index` with no `.ind` yet), and `-n` leaves room for another pass. Passes that rerun only because labels may have changed stay regular, as do `-u`, `--raw` and dvi engines. The last pass always writes the PDF: when a draft pass turns out to be the last one (the tool did not run or failed), a regular pass follows at once. `--json` reports the count as `build.draft_passes`.
```bash
l --no-draft-passes paper.tex
```

### `--[no-]index`
Runs `makeindex` automatically whenever the `.idx` file changes.
```bash
l --index book.tex
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

### `--[no-]relatex-synctex`
Opt-in, lualatex only, and silently off when `relatex` is not on `PATH` (config key `"relatex_synctex"`). When a rebuild starts, leeni stops the previous run's relatex, pins one build time (`SOURCE_DATE_EPOCH=<now>`, `FORCE_SOURCE_DATE=1`, unless `SOURCE_DATE_EPOCH` is already set) for its own passes, and starts `relatex synctex . --main FILE.tex --for FILE.pdf` detached (own process group, `nice 19`), which outlives leeni. Once leeni's PDF is in the working tree, relatex installs a word-level `FILE.synctex.gz` only if its own PDF is byte-identical; a viewer that re-reads the SyncTeX file picks it up without a PDF reload. A failed build stops it. The pid file and log (`relatex_synctex.pid`, `relatex_synctex.log`) live in the project build directory. Not used with `--no-export`, `-z`, `-t`, `--sandbox`, `--arxiv` or `-I`.
```bash
l -e lualatex --relatex-synctex paper.tex
```

### `--[no-]xelatex-preview`
Opt-in (config key `"xelatex_preview"`), and only together with `--relatex-synctex` for a lualatex document. leeni's own passes run `xelatex` instead, so the PDF and its SyncTeX arrive quickly and the SyncTeX names the right files (LuaLaTeX's can send clicks into a package such as a TikZ library until relatex's arrives). relatex runs with `--replace-pdf`: it builds with LuaLaTeX and installs its own PDF together with its word-level `FILE.synctex.gz` in place of XeLaTeX's pair, only while `FILE.pdf` is still the file it waited for and the sources are unchanged (SyncTeX renamed first, PDF second; a newer build is never overwritten, relatex logs `superseded` and installs nothing). The viewer shows the XeLaTeX PDF first and the LuaLaTeX one a few seconds later, so use it for papers that look alike under both engines. No build date is pinned (XeTeX would date `\today` in UTC). `--synctex-status` names the mode.
```bash
l -e lualatex --relatex-synctex --xelatex-preview paper.tex
```

### `--synctex-status`
Prints whether the background relatex SyncTeX run is still alive, its mode (identity, or the XeLaTeX preview that relatex replaces) and the last lines of its log, then exits.
```bash
l --synctex-status paper.tex
```

### `-T`, `--time`
Displays wall-clock execution timing breakdown per compilation pass and bibliography step.
```bash
l -T paper.tex
```

---

## 2. Cleaning & Workspace Isolation {#cleaning}

### `-c`, `--clean`
Wipes the project build cache, legacy `junk/` and `.junk/` directories, and regenerable root auxiliary files before compilation.
```bash
l -c paper.tex
```

### `-C`, `--clean-only`
Removes the selected project's build cache, legacy `junk/` and `.junk/` directories, and regenerable root auxiliary files (`.aux`, `.log`, `.fls`, `.toc`, etc.). Final PDFs and `.bbl` files are preserved.
```bash
l -C
```

### `--junk-dir DIR`
Specifies the directory where intermediate build artifacts are isolated. The default is a per-project directory under `$XDG_CACHE_HOME/leeni/projects/` (falling back to `~/.cache`). Set `--junk-dir junk` for the former project-local layout.
```bash
l --junk-dir=.build paper.tex
```

### `--no-export`
Leaves the working tree untouched: the PDF, `.bbl` and `.synctex.gz` stay in the build directory, and root auxiliary files are neither moved nor removed. The up-to-date check uses the build directory's PDF. With `--junk-dir`, a tool can keep its own build of a paper (another engine, say) without disturbing the author's.
```bash
l --no-export --junk-dir ~/.cache/tool/paper -e lualatex --json paper.tex
```

---

## 3. Diagnostics & Error Filtering {#diagnostics}

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
Emits structured JSON output containing exit codes, target paths, and all classified diagnostics. Its `build` object reports the engine that ran, the absolute build directory (`build_dir`), the LaTeX passes run by this call (`passes`, 0 when up to date), `up_to_date`, and whether the passes converged (`converged`).
```bash
l --json paper.tex
```

---

## 4. Paper Packaging & Portability {#packaging}

### `-z`, `--zip`
Creates a self-contained portable `.zip` archive containing the paper, active figures, styles, a local `.bst`, and compiled `.bbl` without system TeX Live packages. Archives are never nested: `.zip` files (such as `old_ver_*.zip` backups) are left out even when named after `--`.
```bash
l -z paper.tex
```

### `--sandbox`
After the normal build, copies every file the paper used into a sandbox kept in the cache (`$XDG_CACHE_HOME/leeni/sandboxes/<project>/paper`): sources, figures, the `.bbl`, local `.bib` and `.bst` files, and styles from outside the project in `styles/` with the LaTeX search path added. The sandbox is rebuilt there with `--no-env`, using its own `HOME` and TeX trees, and its PDF is compared with the paper's (text layout, plus rendered pages when `pdftoppm` is installed). Between runs only changed files are copied and files the paper no longer uses are deleted, so the sandbox build is incremental. The project and its PDF are never changed. `l -c`/`-C` and the daily cache pruning remove the sandbox together with the build cache.

```bash
l --sandbox paper.tex
```

### `--zip-alone`
Runs `--sandbox` with a forced rebuild and strict checks, then zips the sandbox, so the archive is exactly what built without the environment (minus SyncTeX files). Verification requires a newly generated, nonempty PDF, zero errors and alerts, identical extracted text layout, and identical rendered pages at 150 dpi. Requires `pdftotext` and `pdftoppm`; verification failure preserves any existing archive. Standard LaTeX packages must still be installed.

```bash
l --zip-alone paper.tex
```

Add `--errors-only` to suppress alerts and warnings in both builds and allow alerts during archive verification:

```bash
l --zipalone --errors-only paper.tex
```

Real errors still fail verification. PDF text and rendered-page comparisons still apply.

### `-Z`, `--zip-flat`
Creates a flattened `.zip` archive where all nested `\input` and `\include` subfiles are recursively inlined into a single monolithic `.tex` file (required by journals like IEEE, Springer, and Elsevier).
```bash
l -Z paper.tex
```

### `-t`, `--verify`
Builds the archive's contents in the paper's sandbox in the cache (the one `--sandbox` uses), compiles it with `--no-env`, compares the PDF text with the paper's PDF, and zips the sandbox only when they match.
```bash
l -z -t paper.tex
```

### `-I`, `--make-indep`
Converts the paper in place so it compiles with `--no-env`:

- styles, classes and inputs found through `TEXINPUTS`, `TEXMFHOME`, `TEXMFLOCAL` or similar search paths are copied into `styles/`, and the main file gets {% raw %}`\def\input@path{{styles/}}`{% endraw %};
- files the sources name by a path outside the project (`\input{../shared}`, `\includegraphics{/abs/fig}`) are copied into `styles/` under a unique name and every reference to them is rewritten, including references inside other copied files; `\graphicspath` entries outside the project become `styles/`;
- a file found through a search path keeps the part of its path that the sources spell out: `\input{sub/x}` found as `../sub/x.tex` through `TEXINPUTS=../` becomes `styles/sub/x.tex`;
- a `.bst` file found through `BSTINPUTS` is copied next to the paper;
- the cited entries of `.bib` files outside the project are extracted into `<doc>.bib` (with `bibtool` for BibTeX, `biber` for biblatex), and `\bibliography` / `\addbibresource` are pointed at it.

The converted tree is first rebuilt with `--no-env` in a `/tmp` sandbox and its PDF text compared with the original; if that fails, nothing is changed. Otherwise the originals of every changed file are saved in `old_ver_yy_mm_dd_hh_mm.zip`, together with `leeni-make-indep-new-files.txt` listing the files that were added. Running it again on a converted paper changes nothing. If `styles/` is a symbolic link (for example to a shared styles collection), or any file it would write is one, it stops with an error instead of writing through the link; an existing real `styles/` directory is used as is. Fonts from a personal TeX tree cannot be moved this way and are reported.
Add `--dry-run` to run the sandbox check and print what would be copied, plus a diff of every file that would be edited, without changing anything.
```bash
l -I paper.tex
l -I --dry-run paper.tex
```

### `--bib-missing`
Builds as usual (LaTeX, then BibTeX or Biber) and prints only the cited keys that have no bibliography entry, one per line, sorted; nothing when every citation resolves. A cached build is answered from the build directory without recompiling. The exit status is 1 when any key is missing and 0 when none is, so scripts can test it. If the build has errors, the regular output is shown instead and the exit status is 1. Cannot be combined with `-s`, `-u`, `--no-bib`, or the packaging/arXiv targets; output formats such as `-llm` or `--json` are overridden.
```bash
l --bib-missing paper.tex
```

### `--bib-fix`
Builds, then adds to the paper's own `.bib` file what it lacks: cited entries that are missing (with their `crossref`/`xdata` parents), undefined `@string` macros, and the `@preamble` blocks those use. Everything is copied verbatim from the files in the `bib_fix_sources` config list, then from `BIBINPUTS`; files inside the project are not searched. Every bibliography file of the paper must lie inside the project (run `-I` first otherwise); the target is `<paper>.bib` if the paper uses it, else the first file it names. `@string` and `@preamble` blocks go at the top of the file, entries at the end; the previous file is kept as `<file>.bak` and the paper is rebuilt.

When a key has differing versions (after ignoring ties, braces, whitespace and bookkeeping fields such as `file` or `abstract`, and when no version contains the others), the first is added and every other one as `<key>_leeni_alt_N` after a `% leeni-bib-fix:` marker comment. Every build raises an alert until you keep one version under the real key and delete the others. A version from `bib_fix_sources` wins outright. Keys found nowhere, or found only with different capitalisation, are reported; exit status 1 when keys remain missing. `--dry-run` shows the plan without writing. Design: [bibkit.md](bibkit.md).
```bash
l --bib-fix paper.tex
l --bib-fix --dry-run paper.tex
```

### `-B`, `--bib-extract`
Extracts only the bibliography entries cited in your document from your master `.bib` database into a minimal, standalone `.bib` file.
```bash
l -B paper.tex
l -B --bib-name=local_refs.bib paper.tex
```

---

## 5. arXiv Submission {#arxiv}

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

## 6. Environment & Configuration {#configuration}

### `--no-env`
Also accepts `-noenv`, `--noenv`, and `-no-env`.

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

### `--set-main-file <file>`
Sets the `main_file` configuration property in the local `.l.jsonc` file (creating it if needed) and exits immediately.
```bash
l --set-main-file paper.tex
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

### `--report [LEVEL]`
Writes a zip under `$XDG_CACHE_HOME/leeni/reports/` with leeni's diagnostics (text and JSON), the build logs, the environment, and the latest quarantined case for the project. `full` adds the project-local sources from the recorder; the default does not, because build logs already carry fragments of typeset text and sources are the whole paper. Nothing is uploaded: interactively, with `gh` installed, leeni offers to open a GitHub issue carrying only the summary; `-llm` and `--json` print the bundle path and never ask.
```bash
l --report paper.tex
l --report=full paper.tex
```

### `--doctor [TARGET]`
Reports which engines and helper tools are on the PATH, the cache location, project count, size and stale entries, and the builds quarantined by the automatic cache recovery (see Advanced Topics §10). A case name shows its manifest and first error block; `clear` removes every case; `prune` removes the cached build directories of deleted projects and of projects idle for more than `cache_days` days (default 10), the sweep that otherwise runs once a day after a build (see Advanced Topics §12). Plain text under `-llm`, JSON with `--json`.
```bash
l --doctor
l --doctor paper-20261028-133113
l --doctor clear
l --doctor prune
```

### `--config-save`
Persists CLI options passed on the command line into `.l.jsonc` (or global config with `--global`).
```bash
l -e lualatex --update-if-changed --config-save
```

### `--config-unset KEY`
Removes a saved setting from `.l.jsonc`, or from the global configuration with `--global`, then exits. Removing `junk_dir` restores the XDG cache default unless another configuration scope sets it.
```bash
l --config-unset junk_dir --global
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

## 7. Help & Information {#help}

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

## 8. Symlink Shortcuts & Personalities {#shortcuts}

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

