# Agent Instructions for Maintaining `latex_it`

This document provides architectural guidelines, core invariants, development workflows, and acceleration instructions for AI agents and maintainers working in the [`latex_it`](latex_it) repository.

---

## 1. Core Architecture & Repository Layout

- **Primary Executable**: [`latex_it`](latex_it)
  - Modular Ruby executable (`#!/usr/bin/env ruby`) with zero-build development workflow (`require_relative 'lib/latex_it/...'`).
  - Supports symlink personalities (`l`, `lw`, `ll`, `llua`, `latex_clean`, `latex_file_in_dir`, `latex_env_free`).
- **Modular Core Library (`lib/latex_it/`)**:
  - `version.rb`: Canonical version string, executable path, and constants.
  - `color.rb`: ANSI color rendering via `Rainbow` with graceful plain-text `NullString` fallback.
  - `compatibility.rb`: Environment adjustments for vendor styles (e.g. `revtex4`).
  - `config.rb`: Unified JSONC configuration loader (`.l.jsonc`, `~/.config/latex_it/config.jsonc`) and quote-aware parser.
  - `utils.rb`: Engine detection, main file discovery heuristics, noise filtering, and directory cleanup.
  - `brace_checker.rb`: Lexical environment-scoped brace validator and AUCTeX formatter.
  - `flattener.rb`: TeX input tree resolution, comment stripping, and flattening.
  - `meta_extractor.rb`: Paper metadata parsing (title, authors, abstract, comments).
  - `diagnostics.rb`: LaTeX compilation log diagnostic analysis, AUCTeX error extraction, and 4-tier categorization.
  - `builder.rb`: Compilation lifecycle manager, convergence scheduler, caching, and output finalization.
  - `build_runtime.rb`: Locking, `junk/` workspace preparation, compiler execution, timeouts, and LaTeX passes.
  - `packager.rb`: Portable zip archive bundler (`-z`), active figure source discovery, and styles isolation.
  - `arxiv.rb`: Sanitized, flattened arXiv submission packager and sandbox verification.
  - `cli_targets.rb`: CLI target dispatch for builds, metadata, bibliography extraction, and arXiv workflows.
- **Workflow & Quality Tooling** (`tools/`):
  - [`tools/gate_audit_code`](tools/gate_audit_code): High-performance AST metrics auditor enforcing cognitive complexity, depth, and method sizing.
  - [`tools/bundle`](tools/bundle): Compiles modular `lib/` components into a single standalone executable.
  - [`tools/gate`](tools/gate): Tiered quality gate (`--fast`, `--medium`, `--full`) verifying syntax, code metrics, and tests.
  - [`tools/setup_ruby_dev`](tools/setup_ruby_dev): Automated environment auditor and installer for Ruby gems, LSPs, and CLI tools.
  - [`tools/install`](tools/install): Bundles `latex_it` into a standalone binary at `~/bin/latex_it` with `~/bin/l` symlink.
  - [`tools/bump`](tools/bump): Validates clean git tree, runs `tools/gate --full`, increments version, commits, tags, and pushes.
  - [`tools/test_error_corpus`](tools/test_error_corpus): Standalone on-demand test runner verifying real-world error fixtures in `docs/errors/`.
- **Automated Test Suite** (`test/`):
  - `test/test_*.rb`: Fast regression and end-to-end tests using `minitest`.
  - `test/fixups/`: ArXiv test repair records and schema.
- **Documentation & Configuration**:
  - [`README.md`](README.md): User-facing feature reference, options, and architecture guide.
  - [`docs/`](docs/): Comprehensive technical guides (`arxiv.md`, `diagnostics.md`, `configuration.md`, `orchestration.md`, `advanced_topics.md`, `architecture.md`) and [`docs/errors/`](docs/errors/) error catalog.
  - [`AGENTS.md`](AGENTS.md): Machine-readable contract and developer guidelines for AI agents.

---

## 2. Invariants & Strict Rules

- **Function Complexity & Sizing Invariant (Cognitive Complexity + Tiered Sizing)**:
  - **Cognitive Complexity — Hard Limit ≤ 15**: Methods must not exceed a cognitive complexity score of 15. Control jumps, nested branches, and state-dependent logic must be decomposed into named helpers.
  - **Nesting Depth — Hard Limit ≤ 4**: No code may be indented more than 4 control-flow levels deep (`def` -> level 1 -> level 2 -> level 3 -> level 4). Reaching level 5 requires immediate helper extraction. Allows natural resource blocks (`Dir.chdir`, `with_lock`) and nested algorithms (like 2D loops or edit distance).
  - **Tiered Length Ceiling**:
    - **Algorithmic / Logic Functions**: **Hard limit 80 lines**.
    - **Declarative / "Dumb" Functions**: **Up to 120 lines** allowed IF and ONLY IF Cognitive Complexity is ≤ 5 (e.g. CLI `OptionParser` option declarations, configuration dictionaries, or pure linear step pipelines).
  - **Data vs Logic Separation**: Large lookup dictionaries, explanation mappings, and static string tables must live in frozen module constants, never inside function bodies.
- **File Sizing Guidelines**:
  Keep methods concise and maintain modular files in the **300–700 line** range (soft warning at 800 lines, hard limit 1100 lines). Never split a file across a method body.
- **Language Policy**:
  All scripts, tooling, and test runners must be written in idiomatic **Ruby** (`#!/usr/bin/env ruby`). Do not introduce Python, Bash, Sed, or Awk scripts.
- **Canonical Interface & Anti-Alias Policy (Strict No Redundant Aliases)**:
  Maintain a strictly minimal, clean CLI hierarchy without redundant aliases. Aliases blow up the command-line interface of a program. Every command-line option must have at most one canonical long name and optionally at most one single-letter shortcut (e.g. `-f, --force`, `-u, --single-pass`). Never add multiple single-letter shortcuts (e.g. `-u` and `-1` to the same command) or multiple long option names (e.g. `--single-pass` and `--one-pass`) to the same command. A single-letter shortcut is fine, but two single-letter shortcuts to the same command are strictly prohibited.
- **Isolated Build Output (`junk/`)**:
  All intermediate build artifacts must remain confined to `junk/`. Only final targets (`<file>.pdf`, `<file>.bbl`, `<file>.synctex.gz`) are exported to the project root. Cache state lives in `junk/.build_state.json`.
- **Engine Support**:
  `xelatex` is the default engine, with `lualatex` and `pdflatex` supported as alternatives.
- **Dependency Minimalism**:
  Rely on Ruby standard library modules (`fileutils`, `open3`, `optparse`, `tmpdir`, `shellwords`) and minimal mature gems (`rainbow`, `minitest`).
- **Quality Gate Integrity — Strictly Never Skip**:
  Skipping or bypassing the quality gate is strictly forbidden under any circumstances. Releases, bumps, and changes must pass the required gate tier without exception.
- **Async Execution & Reactive Wait (Zero Polling)**:
  When any command runs longer than 10s and is detached to the background as an async task, the agent **must not** enter a polling loop with `manage_task(action: 'status')` or set sleep timers with `schedule`. The agent must output a single concise notification and **stop calling tools** to yield the turn. The Antigravity environment will automatically wake up the agent via a `<SYSTEM_MESSAGE>` when the command finishes.

---

## 3. The `latex_it` Execution Contract

Any modifications to compilation logic must honor the following invariants:

1. **Intelligent Convergence Pass Model**:
   - **Default**: Tracks source dependencies via `-recorder` (`.fls`) and SHA256 build state. Exits in 0 passes if targets are up to date; runs 1 pass if citations/labels are stable; runs pre-primary BibTeX/Biber if `.bib` changed; and only executes extra passes (up to `-n`, default 5) when `.aux` changes or rerun is requested in logs.
   - **Force Rebuild (`-f` / `--force`)**: Bypasses the initial up-to-date check and forces the first LaTeX pass, continuing with subsequent passes and BibTeX only if needed for convergence.
   - **Single Pass (`-u` / `--single-pass`)**: Executes exactly 1 LaTeX pass with bibliography passes disabled (forces a single rebuild pass and exits immediately).
   - **`--fast` / `lw`**: Accepted for compatibility and currently no-ops. Incremental behaviour is provided unconditionally by `targets_up_to_date?`; either implement a distinct meaning for this flag or remove it.
2. **Bibliography Safety**:
   - Detect tool automatically: Biber (via `.bcf` / `.run.xml`) or BibTeX (via `\bibdata` and `\citation` in `.aux`).
   - Root `.bbl` is only overwritten if the generated `junk/*.bbl` contains valid bibliography entries (`\bibitem` or `\entry`).
   - `.bbl.bak` is preserved during updates.
3. **Target PDF Update Guard (`--update-if-changed`)**:
   - When `--update-if-changed` is active and `pdftotext` is available, skip replacing the target PDF if the extracted text layout matches the existing PDF (prevents document viewers from reloading on non-visual edits).
4. **Portable Paper Bundling (`-z` / `--zip`)**:
   - Gathers input dependencies from `.fls`, filtering out system TeX Live packages (`texmf-dist`).
   - Discovers companion figure source files (`.fig`, `.ipe`, `.isy`, `.svg`, `.asy`, `.gp`, `.gnuplot`, `.py`, `.R`) matching compiled figure stems and stripped view suffixes.
   - Preserves compiled `.bbl` and skips BibTeX/Biber passes when valid `.bbl` exists and no `.bib` files are present.
   - Supports supplementary assets via trailing `-- <files...>`.
   - Default `inject_styles: false` places styles in root for universal journal compatibility without modifying `.tex` source code.
5. **Sandbox Portability Verification (`-t` / `--verify`)**:
   - Unpacks bundle into `/tmp/latex_it_verify_XXXX` sandbox.
   - Compiles with `latex_it --no-env` (wiping ambient `TEXINPUTS`, `BIBINPUTS`, `TEXMFHOME`).
   - Compares PDF text layout against bundled PDF with `pdftotext -layout`.
6. **Agent & LLM Compilation Profile (`-llm` / `--agent`)**:
   - Autonomous coding agents must invoke `l -llm [file.tex]`.
   - Guaranteed plaintext: zero ANSI escape codes (`\e[...]`), zero OSC 8 terminal hyperlinks (`\e]8;;`).
   - 100% silent `exit 0` on clean builds and cached up-to-date targets.
   - Automatic warning folding (2 examples + count note for undefined citations, undefined references, and overfull boxes).
   - Low-severity notes (`whatevers`) suppressed by default.
   - Automatic log-tail fallback on unclassified compiler crashes.
   - Structured JSON output available via `--json`.
   - Complete token-optimized technical reference: see [docs/llm_reference.md](llm_reference.md).

---

## 4. Development Workflow & Automated Tooling

> [!IMPORTANT]
> **User Command Convention — "Make <something>"**:
> An instruction from the user saying `"Make <something>"` (or `"make <something>"`) is shorthand to run `./tools/<something>`. For example:
> - `"Make install"` or `"make install"` ➔ `./tools/install -v`
> - `"Make bump"` or `"make bump"` ➔ `./tools/bump`
> - `"Make gate"` or `"make gate"` ➔ `./tools/gate --medium`
> - `"Make audit"` or `"make audit"` ➔ `./tools/gate_audit_code`
> There is no Makefile in this repository; do not create one.

Always execute quality workflows through the provided scripts:

### 1. `tools/gate` (Tiered Quality Gate)
- `--fast` (default) checks Ruby syntax and deterministic unit tests. Run it after every edit.
- `--medium` adds practical real-LaTeX integration tests. Run it after roughly ten fast checks and before committing or changing build logic.
- `--full` adds long-running integration, BWS, archive/visual verification, and ArXiv corpus tests. Run it before bumping or pushing, and in CI.
- Every tier checks Ruby syntax across `latex_it`, `tools/`, and `test/`.
- **Trigger**: Run the appropriate tier continuously during development.
  ```bash
  rtk ./tools/gate --fast
  rtk ./tools/gate --medium
  rtk ./tools/gate --full
  ```

### 2. `tools/setup_ruby_dev` (Environment & Tooling Auditor)
- Audits and provisions local gems and system binaries.
- **Audit mode**:
  ```bash
  ./tools/setup_ruby_dev --check-only
  ```
- **Auto-install mode**:
  ```bash
  ./tools/setup_ruby_dev
  ```

### 3. Static Analysis & Linting
- Verify code style and syntax offenses:
  ```bash
  rtk rubocop latex_it tools/ test/
  ```
- Automatically correct safe offenses:
  ```bash
  rtk rubocop -A latex_it tools/ test/
  ```

### 4. `tools/install` (Local Binary Installation)
- Copies `latex_it` to `~/bin/latex_it` (setting permissions to `0755`).
- Creates symbolic link `~/bin/l -> latex_it`.
- **Trigger**:
  ```bash
  ./tools/install
  ```

### 5. `tools/bump` (Version Bump, Tag & Push Workflow)
- Ensures working tree is completely clean (aborts if uncommitted changes exist).
- Runs [`tools/gate --full`](tools/gate) automatically. (Do not run `--full` manually before bumping to avoid duplicate gate runs).
- Increments version by +0.0.1 (patch by default, or `--major` / `--minor`) in [`lib/latex_it/version.rb`](lib/latex_it/version.rb) and bundled `latex_it`.
- Commits changes, creates a release git tag, and pushes to remote with `--follow-tags`.
- **Trigger**:
  ```bash
  ./tools/bump
  ```

---

## 5. Pre-Installed Tooling & Acceleration

The following developer tools are pre-configured in the environment:

| Tool | Location / Command | Purpose for AI Agents |
| :--- | :--- | :--- |
| **`rtk`** | `rtk` (in `PATH`) | **CLI output token compression proxy.** Prefix all shell commands with `rtk` (e.g. `rtk git status`, `rtk ./tools/gate`) to compress terminal output by 60–90%. |
| **`ast-grep` (`sg`)** | `sg` (in `PATH`) | **Structural AST search & rewrite.** Use `rtk sg -p '<pattern>' -l ruby` instead of fragile regex searches. |
| **`rubocop`** | `rubocop` (Ruby gem) | **Static analysis & formatting.** Lint and auto-correct Ruby code. |
| **`ruby-lsp`** | `ruby-lsp` (Ruby gem) | **Shopify Language Server.** Fast symbol navigation, definitions, and code intelligence. |
| **`repomix`** | `repomix` (in `PATH`) | **Repository context packer.** Generates token-optimized codebase snapshots for LLM prompts. |
| **`pdftotext`** | `pdftotext` (in `PATH`) | **Poppler PDF text extractor.** Enables text diff verification in `latex_it -d`. |
| **`minitest`** | Ruby gem | **Unit test runner.** Powers `tools/gate` and `test/test_*.rb`. |
| **`rainbow`** | Ruby gem | **Colorized diagnostics.** ANSI color rendering in terminal output. |

---

## 6. Adversarial Audit Lenses

When reviewing, refactoring, or evaluating changes to `latex_it`, evaluate across these 5 domain lenses:

1. **Systems & Concurrency**:
   - File locking (`--lock` with `flock`) must prevent race conditions without deadlocking.
   - Child process execution via `Open3.capture2e` must handle process exit statuses and signal termination gracefully.
2. **Correctness & Heuristics**:
   - Main file heuristic detection must accurately resolve `.mainfile`, directory name matching, and candidate filtering without false positives.
   - Auxiliary file hashing (`compute_aux_hash`) must accurately reflect all `.aux` changes across subdirectories.
3. **Resilience & Fault Tolerance**:
   - Missing compilers (`xelatex`, `biber`, `bibtex`) or system tools must fail fast with actionable error messages.
   - Subprocess noise (METAFONT, `mktextfm`) must be filtered cleanly without suppressing underlying TeX errors.
4. **Performance & Incremental Efficiency**:
   - `targets_up_to_date?` must avoid redundant LaTeX and bibliography passes whenever the cached build state is valid.
   - Text diff checking (`-d`) must avoid disk writes and unnecessary PDF viewer reloads when content is identical.
5. **CLI Consistency & User Experience**:
   - Clean, readable `-h` help text.
   - Colorized diagnostic outputs with fallback to plain text if `rainbow` is absent or `--emacs` is supplied.

---

## 7. Agent Batching & Efficiency Guidelines

- **Autonomous Batching**:
  Combine code edits, test updates, and quality gate verification (`tools/gate`) within a single agent turn instead of requesting piecemeal confirmations.
- **Fast Feedback**:
  Execute `rtk ./tools/gate` for sub-second verification after making modifications.
- **Token Efficiency**:
  Always prefix shell commands with `rtk` (e.g. `rtk ./tools/gate`, `rtk rubocop`, `rtk ls`).
- **AST Pattern Refactoring**:
  Use `ast-grep` (`sg`) to inspect or transform method signatures and patterns:
  ```bash
  rtk sg -p 'def $NAME($$$ARGS) $$$BODY end' -l ruby latex_it
  ```
- **Async Background Tasks & Reactive Wait**:
  `run_command` has a 10s synchronous timeout (`WaitMsBeforeAsync: 10000`). When a task runs in the background:
  - **Never poll**: Do NOT call `manage_task(action: 'status')` or loop in turns.
  - **Yield immediately**: Post a single concise update explaining the operation is running in the background, and invoke **zero tools** in that turn.
  - **Await reactive wakeup**: The Antigravity platform automatically wakes the agent with a `<SYSTEM_MESSAGE>` containing the exit code and complete output as soon as the background task finishes.
  - **Never skip quality gates**: Impatience or long execution time is never a justification to bypass `--full` or skip checks.
