# Agent Instructions for Maintaining `leeni`

This document provides architectural guidelines, core invariants, development workflows, and acceleration instructions for AI agents and maintainers working in the [`leeni`](leeni) repository.

---

## 1. Core Architecture & Repository Layout

- **Primary Executable**: [`leeni`](leeni)
  - Modular Ruby executable (`#!/usr/bin/env ruby`) with zero-build development workflow (`require_relative 'lib/leeni/...'`).
  - Supports symlink personalities (`l`, `lw`, `ll`, `llua`, `latex_clean`, `latex_file_in_dir`, `latex_env_free`).
- **Modular Core Library (`lib/leeni/`)**:
  - `version.rb`: Canonical version string, executable path, and constants.
  - `color.rb`: ANSI color rendering via `Rainbow` with graceful plain-text `NullString` fallback.
  - `compatibility.rb`: Environment adjustments for vendor styles (e.g. `revtex4`).
  - `config.rb`: Unified JSONC configuration loader (`.l.jsonc`, `~/.config/leeni/config.jsonc`) and quote-aware parser.
  - `build_workspace.rb`: XDG cache location and per-project build directory resolution.
  - `utils.rb`: Engine detection, main file discovery heuristics, noise filtering, and directory cleanup.
  - `brace_checker.rb`: Lexical environment-scoped brace validator and AUCTeX formatter.
  - `flattener.rb`: TeX input tree resolution, comment stripping, and flattening.
  - `meta_extractor.rb`: Paper metadata parsing (title, authors, abstract, comments).
  - `diagnostics.rb`: LaTeX compilation log diagnostic analysis, AUCTeX error extraction, and 4-tier categorization.
  - `builder.rb`: Compilation lifecycle manager, convergence scheduler, caching, and output finalization.
  - `build_runtime.rb`: Locking, cache workspace preparation, compiler execution, timeouts, and LaTeX passes.
  - `packager.rb`: Portable zip archive bundler (`-z`), active figure source discovery, and styles isolation.
  - `arxiv.rb`: Sanitized, flattened arXiv submission packager and sandbox verification.
  - `cli_targets.rb`: CLI target dispatch for builds, metadata, bibliography extraction, and arXiv workflows.
- **Workflow & Quality Tooling** (`tools/`):
  - [`tools/gate_audit_code`](tools/gate_audit_code): High-performance AST metrics auditor enforcing cognitive complexity, depth, and method sizing.
  - [`tools/bundle`](tools/bundle): Compiles modular `lib/` components into a single standalone executable.
  - [`tools/gate`](tools/gate): Tiered quality gate (`--fast`, `--medium`, `--full`) verifying syntax, code metrics, and tests.
  - [`tools/setup_ruby_dev`](tools/setup_ruby_dev): Automated environment auditor and installer for Ruby gems, LSPs, and CLI tools.
  - [`tools/install`](tools/install): Bundles `leeni` into a standalone binary at `~/bin/leeni` with `~/bin/l` symlink.
  - [`tools/bump`](tools/bump): Increments the version, runs the full gate on that version, commits, and atomically publishes the branch and tag.
  - [`tools/release`](tools/release): Commits checked changes, runs `tools/bump`, and optionally installs after publication.
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
- **Isolated Build Output (XDG cache by default)**:
  All intermediate build artifacts must remain confined to the per-project build directory under `$XDG_CACHE_HOME/leeni/projects/` (falling back to `~/.cache`). Explicit `--junk-dir junk` preserves the project-local compatibility layout. Only final targets (`<file>.pdf`, `<file>.bbl`, `<file>.synctex.gz`) are exported to the project root. Cache state lives in the build directory's `.build_state.json`.
- **Engine Support**:
  `xelatex` is the default engine, with `lualatex` and `pdflatex` supported as alternatives.
- **Dependency Minimalism**:
  Rely on Ruby standard library modules (`fileutils`, `open3`, `optparse`, `tmpdir`, `shellwords`) and minimal mature gems (`rainbow`, `minitest`).
- **Quality Gate Integrity — Strictly Never Skip**:
  Skipping or bypassing the quality gate is strictly forbidden under any circumstances. Releases, bumps, and changes must pass the required gate tier without exception.
- **Async Execution & Reactive Wait (Zero Polling)**:
  When any command runs longer than 10s and is detached to the background as an async task, the agent **must not** enter a polling loop with `manage_task(action: 'status')` or set sleep timers with `schedule`. The agent must output a single concise notification and **stop calling tools** to yield the turn. The Antigravity environment will automatically wake up the agent via a `<SYSTEM_MESSAGE>` when the command finishes.

---

## 3. The `leeni` Execution Contract

Any modifications to compilation logic must honor the following invariants:

1. **Intelligent Convergence Pass Model**:
   - **Default**: Tracks source dependencies via `-recorder` (`.fls`) and SHA256 build state. Exits in 0 passes if targets are up to date; runs 1 pass if citations/labels are stable; runs pre-primary BibTeX/Biber if `.bib` changed; and only executes extra passes (up to `-n`, default 5) when `.aux` changes or rerun is requested in logs.
   - **Force Rebuild (`-f` / `--force`)**: Bypasses the initial up-to-date check and forces the first LaTeX pass, continuing with subsequent passes and BibTeX only if needed for convergence.
   - **Single Pass (`-u` / `--single-pass`)**: Executes exactly 1 LaTeX pass with bibliography passes disabled (forces a single rebuild pass and exits immediately).
   - **`--fast` / `lw`**: Accepted for compatibility and currently no-ops. Incremental behaviour is provided unconditionally by `targets_up_to_date?`; either implement a distinct meaning for this flag or remove it.
2. **Bibliography Safety**:
   - Detect tool automatically: Biber (via `.bcf` / `.run.xml`) or BibTeX (via `\bibdata` and `\citation` in `.aux`).
   - Root `.bbl` is only overwritten if the generated build-directory `.bbl` contains valid bibliography entries (`\bibitem` or `\entry`).
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
   - Unpacks bundle into `/tmp/leeni_verify_XXXX` sandbox.
   - Compiles with `leeni --no-env` (wiping ambient `TEXINPUTS`, `BIBINPUTS`, `TEXMFHOME`).
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

> [!IMPORTANT]
> **Black-Box Repository Tooling (No Source Reading)**:
> The scripts in `tools/` (`tools/check`, `tools/build`, `tools/lint`, `tools/gate`, `tools/commit`, `tools/bump`, `tools/release`, `tools/install`) are fixed repository contracts.
> Do NOT read, parse, or reverse-engineer the source code of `tools/` scripts when executing workflows. Invoke them directly using their documented CLI options.

Always execute quality workflows through the provided scripts:

### 1. `tools/check` (Repository Quality Gate)
- Runs the default quality gate (`tools/gate --fast`) ensuring syntax, code metrics, and fast unit tests pass.
- **Trigger**:
  ```bash
  rtk proxy tools/check
  ```

### 2. `tools/gate` (Tiered Quality Gate)
- `--fast` (default) checks Ruby syntax and deterministic unit tests. Run it after every edit.
- `--medium` adds practical real-LaTeX integration tests. Run it after roughly ten fast checks and before committing or changing build logic.
- `--full` adds long-running integration, BWS, archive/visual verification, and ArXiv corpus tests. Run it before bumping or pushing, and in CI.
- Every tier checks Ruby syntax across `leeni`, `tools/`, and `test/`.
- **Trigger**: Run the appropriate tier continuously during development.
  ```bash
  rtk ./tools/gate --fast
  rtk ./tools/gate --medium
  rtk ./tools/gate --full
  ```

### 3. `tools/setup_ruby_dev` (Environment & Tooling Auditor)
- Audits and provisions local gems and system binaries.
- **Audit mode**:
  ```bash
  ./tools/setup_ruby_dev --check-only
  ```
- **Auto-install mode**:
  ```bash
  ./tools/setup_ruby_dev
  ```

### 4. Static Analysis & Linting
- Verify code style and syntax offenses:
  ```bash
  rtk rubocop leeni tools/ test/
  ```
- Automatically correct safe offenses:
  ```bash
  rtk rubocop -A leeni tools/ test/
  ```

### 5. `tools/commit` (Checked Commit Workflow)
- Runs the gate verification and creates a validated commit with the specified commit message.
- **Trigger**:
  ```bash
  rtk proxy tools/commit "Your descriptive commit message"
  ```

### 6. `tools/install` (Local Binary Installation)
- Copies `leeni` to `~/bin/leeni` (setting permissions to `0755`).
- Creates symbolic link `~/bin/l -> leeni`.
- **Trigger**:
  ```bash
  ./tools/install
  ```

### 7. `tools/bump` (Version Bump, Tag & Push Workflow)
- Ensures working tree is completely clean (aborts if uncommitted changes exist).
- Increments version by +0.0.1 (patch by default, or `--major` / `--minor`) in [`lib/leeni/version.rb`](lib/leeni/version.rb).
- Runs [`tools/gate --full`](tools/gate) against the new version, commits, and atomically pushes the branch and tag to the configured upstream.
- Use `--resume` to finish an interrupted release without incrementing the version again.
- **Trigger**:
  ```bash
  ./tools/bump
  ```

### 8. `tools/release` (Full Release & Publication Workflow)
- Runs `tools/commit`, followed by `tools/bump` (which runs `tools/gate --full`, tags, and pushes upstream), and optionally runs `tools/install` if `--install` is supplied.
- **Trigger**:
  ```bash
  rtk proxy tools/release [--install] "Your release commit message"
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
| **`pdftotext`** | `pdftotext` (in `PATH`) | **Poppler PDF text extractor.** Enables text diff verification in `leeni -d`. |
| **`minitest`** | Ruby gem | **Unit test runner.** Powers `tools/gate` and `test/test_*.rb`. |
| **`rainbow`** | Ruby gem | **Colorized diagnostics.** ANSI color rendering in terminal output. |

> [!NOTE]
> **Sandboxing & Host Tool Access**:
> Developer tools such as `rubocop`, `ruby-lsp`, `rainbow`, `minitest` (user gems in `~/.local/share/gem/`) and CLI binaries like `ast-grep`, `repomix`, `rtk` (in `~/.local/bin/`) reside on the host system.
> In sandboxed agent environments (e.g. Bubblewrap or Antigravity default sandbox mode), paths outside the repository workspace are isolated, masking `~/.local/bin/` (except `agy`) and `~/.local/share/gem/`.
> If a required pre-installed tool (such as `rubocop`) is reported missing or if pushing commits/tags upstream fails during `tools/check`, `tools/gate`, `tools/commit`, or `tools/release`, this is an artifact of sandbox filesystem/network isolation. Run the command outside the sandbox (`BypassSandbox: true`) where the host environment tools and network reside, rather than inspecting `tools/` source or attempting to reinstall gems.

---

## 6. Adversarial Audit Lenses

When reviewing, refactoring, or evaluating changes to `leeni`, evaluate across these 5 domain lenses:

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
  rtk sg -p 'def $NAME($$$ARGS) $$$BODY end' -l ruby leeni
  ```
- **Async Background Tasks & Reactive Wait**:
  `run_command` has a 10s synchronous timeout (`WaitMsBeforeAsync: 10000`). When a task runs in the background:
  - **Never poll**: Do NOT call `manage_task(action: 'status')` or loop in turns.
  - **Yield immediately**: Post a single concise update explaining the operation is running in the background, and invoke **zero tools** in that turn.
  - **Await reactive wakeup**: The Antigravity platform automatically wakes the agent with a `<SYSTEM_MESSAGE>` containing the exit code and complete output as soon as the background task finishes.
  - **Never skip quality gates**: Impatience or long execution time is never a justification to bypass `--full` or skip checks.
