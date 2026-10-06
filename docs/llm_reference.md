# `leeni` Technical Reference for LLMs & AI Agents

> **Audience**: Autonomous coding agents (Claude Code, Antigravity, Cursor, OpenCode, Aider) and programmatic pipelines.  
> **Purpose**: Dense, token-optimized technical reference covering CLI flags, configuration schemas, exit codes, and diagnostic contracts. Zero prose filler.

---

## 1. Quick Execution Contract

When compiling LaTeX documents in a repository where `leeni` (or `l`) is available:

```bash
# Recommended compile invocation for all AI agents:
l -llm paper.tex

# With all folded warnings displayed:
l -llm -a paper.tex

# Programmatic JSON response:
l --json paper.tex
```

### Exit Codes
| Exit Code | Meaning | Agent Action |
| :--- | :--- | :--- |
| `0` | Compilation succeeded (or targets up-to-date). Output is empty in `-llm` mode if 0 diagnostics. | Proceed to next task. Target PDF `<stem>.pdf` is ready. |
| `1` | Compilation failed (syntax error, missing package, or warnings with `-W`). | Parse GNU diagnostic lines (`file:line: error: msg`) and edit source. |
| `2` | Command-line option error or invalid invocation. | Review CLI arguments. |

---

## 2. Core Architectural Invariants

- **Junk Quarantine**: All compilation artifacts (`.aux`, `.log`, `.toc`, `.fls`, `.out`, `.nav`, `.snm`) reside exclusively in `junk/`. Only `<file>.pdf`, `<file>.bbl`, and `<file>.synctex.gz` are written to root.
- **Engine Selection Precedence**: CLI flag (`-e`) / symlink personality (`llua`, `lp`) $>$ `% !TEX program = <engine>` magic comment $>$ `.l.jsonc` `"engine"` $>$ default (`xelatex`).
- **Convergence Loop**: Multi-pass scheduler runs up to `passes` (default 5). Exits early if `.aux` digests match across passes. Executes BibTeX/Biber if citations are unresolved or `.bib` files modified.
- **Cache State**: Persisted in `junk/.build_state.json`. If inputs (`*.tex`, `*.bib`, styles) and CLI options match SHA256 hashes, exits `0` in 0 passes.

---

## 3. Comprehensive CLI Options Reference

| Flag | Long Form | Value Type | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `-llm` | `--agent` | flag | `false` | **Primary agent profile**: Pure plaintext, folded warnings, silent on clean success. |
| `--json` | *(none)* | flag | `false` | Emit structured JSON result payload on stdout. |
| `-f` | `--force` | flag | `false` | Force initial LaTeX run unconditionally (bypasses build cache). |
| `-u` | `--single-pass`| flag | `false` | Execute exactly 1 LaTeX pass without BibTeX/Biber or convergence passes. |
| `-n` | `--passes` | integer (1–10)| `5` | Maximum number of LaTeX compilation passes. |
| `-b` | `--[no-]bib` | boolean | auto | Force or skip bibliography pass (Biber or BibTeX). |
| `-I` | `--[no-]index` | boolean | `false` | Run `makeindex` when `.idx` changes. |
| `-e` | `--engine` | `x`,`l`,`p` | `x` (`xelatex`)| Compiler: `x` (`xelatex`), `l` (`lualatex`), `p` (`pdflatex`). |
| `-c` | `--clean` | flag | `false` | Remove `junk/` artifacts before starting build. |
| `-C` | `--clean-only` | flag | `false` | Remove `junk/` and root auxiliary files and exit immediately. |
| *(none)* | `--junk-dir` | string | `junk` | Directory for temporary build artifacts (`junk` or `.junk`). |
| `-x` | `--explain` | flag | `false` | Print boxed plain-English explanations on first diagnostic occurrence. |
| `-a` | `--all` | flag | `false` | Display all diagnostics (disables warning folding and whatever suppression). |
| `-W` | `--werror` | flag | `false` | Treat alerts and warnings as fatal errors (exit code 1). |
| `-r` | `--raw` | flag | `false` | Print unfiltered raw stdout/stderr from TeX compilers. |
| `-s` | `--score` | flag | `false` | Suppress stdout; print numeric diagnostic counts only. |
| `-v` | `--verbose` | flag | `false` | Verbose logging; show raw overfull snippets. |
| `-T` | `--time` | flag | `false` | Print wall-clock execution time per pass. |
| `-m` | `--main` | flag | `false` | Print detected root `.tex` filename and exit. |
| `-M` | `--deps` | flag | `false` | Output Makefile dependency rule for document and exit. |
| `-z` | `--zip` | flag | `false` | Create self-contained portable zip archive of paper, styles, and figures. |
| `-Z` | `--zip-flat` | flag | `false` | Create portable zip with flattened/inlined `.tex` source. |
| `-t` | `--verify` | flag | `false` | Test portable zip in isolated `/tmp` sandbox with clean environment. |
| `-B` | `--bib-extract`| flag | `false` | Extract cited references into local standalone `.bib` file. |
| `--arxiv`| *(none)* | flag | `false` | Produce submission-ready, comment-stripped arXiv archive. |
| `--meta` | *(none)* | flag | `false` | Extract sanitized metadata and write `arxiv_<file>_meta.txt`. |
| `--update-if-changed` | flag | `false` | Skip overwriting target PDF if extracted text is unchanged (`pdftotext`). |
| `--no-env`| *(none)* | flag | `false` | Clear ambient `TEXINPUTS`, `BIBINPUTS`, and `TEXMFHOME`. |
| `--[no-]lock` | boolean | `true` | File locking concurrency protection (`flock`). |
| `--[no-]color` | boolean | auto | Terminal ANSI color escape sequences. |
| `--[no-]link` | boolean | auto | Terminal OSC 8 clickable hyperlinks. |
| `--alert-hbox` | float (pt) | `24.0` | Overfull `\hbox` size in pt promoted to **Alert**. |
| `--whatever-pt` | float (pt) | `2.5` | Overfull `\hbox` size in pt demoted to **Whatever** (suppressed). |
| `-cc` | `--compile` | flag | `false` | GNU standard compiler output (`file:line:col: severity: msg`). |
| *(none)* | `--gitignore-init` | flag | `false` | Additive setup: create or add standard LaTeX & `junk/` rules to `.gitignore`. |

---

## 4. Configuration Schema (`.l.jsonc`)

Local file: `./.l.jsonc` (or `./.leeni.jsonc`).
Global file: `~/.config/leeni/config.jsonc`.

```jsonc
{
  "engine": "xelatex",               // "xelatex" | "lualatex" | "pdflatex"
  "passes": 5,                       // 1 .. 10
  "junk_dir": "junk",                // "junk" | ".junk" (build artifact directory)
  "index": false,                    // boolean (makeindex)
  "update_on_diff": false,           // boolean (suppress PDF write if text unchanged)
  "time": false,                     // boolean (timing diagnostics)
  "raw": false,                      // boolean (unfiltered engine output)
  "trace": false,                    // boolean (log subprocess commands)
  "color": null,                     // true | false | null (auto)
  "links": null,                     // true | false | null (auto OSC 8 links)
  "theme": "blush",                  // "blush" | "catppuccin" | "tokyo-night" | "dracula" | "nord" | "ansi"
  "lock": true,                      // boolean (flock concurrency guard)
  "werror": false,                   // boolean (warnings are fatal)
  "alert_overfull_pt": 24.0,         // float (threshold for Alert tier)
  "whatever_overfull_pt": 2.5,       // float (threshold for Whatever tier)
  "suppress_whatevers": true,        // boolean (hide micro-noise)
  "suppress_warnings": false,        // boolean (hide standard warnings)
  "suppress_alerts": false,          // boolean (hide structural alerts)
  "bib_dirs": ["refs", "bib"],       // string[] (directories to scan for .bib files)
  "junk_subdirs": ["figs"],          // string[] (subdirs to pre-create in junk_dir)
  "auto_mirror_subdirs": true,       // boolean (mirror project subdirs into junk_dir)
  "exclude_main_tex": ["preamble*"], // string[] (globs ignored for main file detection)
  "exclude_source_tex": ["styles/*"] // string[] (globs ignored for brace/syntax audit)
}
```

---

## 5. Diagnostic Severity Tiers

| Tier | Severity Label | Definition & Examples | Default Behavior in `-llm` |
| :--- | :--- | :--- | :--- |
| **Errors** | `error:` | Hard compilation crashes preventing PDF output. Syntax errors, missing packages, undefined control sequences. | Emitted first (max 5 errors displayed). Suppresses all lower tiers. |
| **Alerts** | `warning: [alert]` | Silent flaws that compile with exit code 0 but corrupt document semantics. Inverted `\label` before `\caption`, overfull `\hbox` $\ge 24\text{pt}$, duplicate labels, Type 3 raster fonts. | Displayed in plaintext. Counted towards `-W` fatal errors. |
| **Warnings**| `warning:` | Standard typesetting notices. Undefined citations, undefined `\ref`, overfull `\hbox` ($2.5\text{pt} < \text{pt} < 24\text{pt}$). | Folded: top 2 instances displayed + summary count note. |
| **Whatevers**| `note:` | Harmless cosmetic noise. Micro-overfull `\hbox` ($\le 2.5\text{pt}$), `hyperref` bookmark math removals, font substitutions. | **Suppressed** by default. Shown only with `-a`. |

---

## 6. Behavior of `-llm` Mode

1. **Zero ANSI / OSC 8**: Guaranteed plaintext. No `\e[` sequences, no OSC 8 hyperlinks `\e]8;;`.
2. **Silence on Clean Success**: If exit code is 0 and no actionable alerts/warnings exist, output is 0 bytes.
3. **Category Folding**: Undefined citations, references, and overfull boxes show at most 2 instances:
   ```text
   paper.tex:12: warning: [alert] undefined citation 'knuth1984'
   paper.tex:15: warning: [alert] undefined citation 'lamport1994'
   leeni: note: 48 more undefined citations in paper.tex (pass -a to show all)
   ```
4. **Log-Tail Fallback on Crash**: If engine exits non-zero without a standard regex match:
   ```text
   paper.tex:1: error: compilation failed with unclassified error
   paper.tex:1: note: compiler log tail:
   > ! Emergency stop.
   > <read 2> \relax
   > l.42 \include{missing}
   ```

---

## 7. `--json` Schema Specification

```json
{
  "success": false,
  "exit_code": 1,
  "pdf_path": null,
  "summary": {
    "errors": 1,
    "alerts": 0,
    "warnings": 2,
    "whatevers": 0
  },
  "diagnostics": [
    {
      "file": "paper.tex",
      "line": 42,
      "col": 1,
      "tier": "errors",
      "category": "undefined_control_sequence",
      "message": "undefined control sequence \\myTypo",
      "token": "\\myTypo",
      "hint": "did you mean \\myType?",
      "index": 0,
      "repeat_count": 1
    }
  ],
  "folded_counts": {},
  "log_tail": null
}
```

---

## 8. Common LaTeX Errors & Agent Remediations

| Error Pattern | Root Cause | Agent Remediation |
| :--- | :--- | :--- |
| `undefined control sequence \foo` | Typo in macro or missing package. | Verify spelling; check if `\usepackage{...}` is required in preamble. |
| `Inverted \label before \caption` | `\label` placed before `\caption`. | Move `\label{...}` to immediately *after* `\caption{...}` inside float. |
| `Missing $ inserted` | Math symbol (`_`, `^`, `\alpha`) in text mode. | Wrap symbol in `$ ... $` or escape (`\_`). |
| `File ended while scanning use of` | Unclosed brace `{` or environment argument. | Check line for missing closing brace `}`. |
| `\begin{env} ended by \end{other}` | Mismatched environment tags. | Ensure `\begin{foo}` matches `\end{foo}`. |
| `Package biblatex Error: File ... not found` | Missing compiled `.bbl` or backend mismatch. | Run `l -f` to force rebuild; verify `bib_dirs` in `.l.jsonc`. |
| `Token not allowed in a PDF string` | Math or formatting macro inside `\section{...}`. | Use `\texorpdfstring{$O(n)$}{O(n)}` in section title. |
| `Overfull \hbox ... (>= 24pt)` | Line extends >8.5mm past page margin. | Add discretionary hyphen `\-` or wrap offending text in `sloppypar`. |
