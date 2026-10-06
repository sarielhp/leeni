# Architecture & Internal Design

`latex_it` is designed as a modular, dependency-minimal Ruby application that manages the end-to-end lifecycle of LaTeX document compilation.

---

## 1. Design Principles

- **Zero Working-Directory Pollution**: Intermediate auxiliary files are isolated in `junk/`. Only the target PDF, bibliography (`.bbl`), and SyncTeX file (`.synctex.gz`) reside in the project root.
- **Minimal Redundant Builds**: File modification times and content checksums eliminate unnecessary compiler passes when the document is already up to date.
- **Actionable Diagnostics**: TeX logs are filtered and classified into four tiers, suppressing low-level engine noise so authors can fix errors quickly.
- **Zero-Dependency Runtime**: Relies almost entirely on the Ruby standard library (`fileutils`, `open3`, `optparse`, `tmpdir`, `shellwords`), requiring only the optional `rainbow` gem for colored terminal output.
- **Single-File Distribution**: While organized into clean modular components under `lib/latex_it/` for development, `tools/bundle` compiles everything into a standalone executable.

---

## 2. Compilation Lifecycle

The build pipeline follows an orderly sequence of phases:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Discovery      Locate main .tex file, detect engine      │
│ 2. Pre-Flight     Scan for unclosed braces & syntax errors  │
│ 3. Workspace      Set up isolated junk/ directory & lockfile│
│ 4. Change Check   Compare file hashes; exit if up to date   │
│ 5. Compiler Loop  Execute LaTeX & BibTeX passes (1 to 10)   │
│ 6. Export Targets Copy .pdf, .bbl, .synctex.gz to root      │
│ 7. Diagnostics    Parse log; report errors, alerts, warnings│
└─────────────────────────────────────────────────────────────┘
```

### Phase 1: Main File & Engine Discovery
- If no file is specified on the command line, `latex_it` scans the current directory using heuristics: checks `.mainfile`, `<dirname>.tex`, filters preamble snippets (`prefix*.tex`, `prelim*.tex`), and searches for `\begin{document}`.
- Engine auto-detection reads `% !TEX TS-program` or `% !TEX program` magic comments, AUCTeX file variables, or package requirements (`luacode`, `luamplib`).

### Phase 2: Pre-Flight Auditing
- `LaTeXBraceChecker` reads the target source file before invoking LaTeX.
- Checks lexical balance of curly braces `{ ... }`, detects bracket mistypes like `{]`, and verifies matching environments (`\begin{foo} ... \end{bar}`).

### Phase 3: Directory Isolation (`junk/`)
- Builds run with `-output-directory=junk`.
- Build state is recorded in `junk/.build_state.json` (engine, option signature, and a SHA256 per input) and checked by `targets_up_to_date?` before any pass runs.

### Phase 4: Convergence Pass Scheduling
- **Check State**: Checks compiler recorder dependencies (`.fls`) and checksums. If no inputs changed and target PDF exists, exits in 0 passes.
- **Pass 1**: Runs initial LaTeX pass.
- **Bibliography Pass**: If citations are unresolved or `.bib` files were modified, runs `bibtex` or `biber` (auto-detected via `.bcf` or `.aux`).
- **Subsequent Passes**: Reruns LaTeX up to the configured pass limit (default: 5) only if `.aux` changes or rerun notifications appear in the log.

### Phase 5: Target Export & Diffing
- Successfully built `.pdf`, `.bbl`, and `.synctex.gz` files are exported to the project directory.
- When `--update-if-changed` is active, `pdftotext -layout` compares the newly generated PDF with the existing file. If text is unchanged, the target file is not overwritten, preventing unnecessary PDF viewer reloads.

---

## 3. Modular Library Structure

The codebase is organized into modular files under `lib/latex_it/`:

| Module | Responsibility |
| :--- | :--- |
| `version.rb` | Canonical version string (`VERSION`) and executable metadata. |
| `color.rb` | Terminal ANSI color rendering via `Rainbow` with automatic plain-text fallback. |
| `compatibility.rb` | REVTeX 4.0 legacy compatibility tree staging and path injection. |
| `config.rb` | JSONC configuration loader, quote-aware parser, and defaults. |
| `utils.rb` | Engine detection, main file heuristics, log noise filtering, and file utilities. |
| `brace_checker.rb` | Static lexical environment and brace validator. |
| `diagnostics.rb` | AUCTeX-compatible log parser and 4-tier diagnostic classifier. |
| `error_catalog.rb` | Declarative catalog of 55 TeX/LaTeX compilation errors with token extractors and explanations. |
| `builder.rb` | Orchestrator managing convergence, caching, bibliography scheduling, and output finalization. |
| `build_runtime.rb` | Build locking, workspace preparation, compiler process execution, timeouts, and individual LaTeX passes. |
| `packager.rb` | Bundler for portable paper zip archives (`-z`) and `/tmp` sandbox verifier (`-t`). |
| `flattener.rb` | Recursive subfile inliner and comment sanitizer for arXiv packages. |
| `meta_extractor.rb` | Source parser extracting Title, Authors, and MathJax-compatible Abstract. |
| `arxiv.rb` | arXiv submission manager, biblatex version shielding, and visual page verification. |
| `cli_targets.rb` | CLI target dispatch for compilation, metadata, bibliography extraction, and arXiv workflows. |

---

## 4. Development & Quality Tooling

- **Standalone Bundler (`tools/bundle`)**: Bundles `lib/` modules into the single standalone executable `latex_it`.
- **Code Metrics Auditor (`tools/gate_audit_code`)**: Enforces method complexity invariants: Cognitive Complexity $\le 15$, indentation depth $\le 4$, method length $\le 80$ lines.
- **Tiered Quality Gate (`tools/gate`)**:
  - `--fast`: Syntax check + unit tests in $\sim 2$ seconds.
  - `--medium`: Adds core LaTeX integration tests.
  - `--full`: Complete suite including sandbox builds and paper verifications.
- **Corpus Test Runner (`tools/test_error_corpus`)**: Parallel runner verifying all 55 error reproducers against real LaTeX engines in $\sim 4$ seconds.

---

## 5. Architectural Decision Records (ADRs)

Key architectural patterns and rejected design alternatives are formally recorded in:

- **[`docs/decisions.md`](decisions.md)**: Includes ADR-0001 (rejection of Homebrew tap distribution), ADR-0002 (native `-llm` flag over daemonized MCP server), and ADR-0003 (external orchestration via `just` over internal compiler pre-build hooks).
