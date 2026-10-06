# Configuration & Environment

`leeni` provides flexible configuration options that can be defined globally, set per-project, or overridden via command-line flags.

---

## 1. Configuration Hierarchy

Settings are resolved using the following order of precedence (highest to lowest):

1. **Command-line flags** (e.g. `-e lualatex`, `-f`, `-x`)
2. **Local project configuration** (`.l.jsonc` or `.leeni.jsonc` in document root)
3. **Global user configuration** (`~/.config/leeni/config.jsonc`)
4. **Built-in defaults**

---

## 2. Project Configuration (`.l.jsonc`)

To create a documented configuration file in your project directory:

```bash
l --config-init
```

This creates `.l.jsonc` pre-populated with default settings and comments:

```jsonc
{
  // Default LaTeX engine: "xelatex", "lualatex", or "pdflatex"
  "engine": "xelatex",

  // Maximum number of compilation passes (1-10)
  "passes": 5,

  // Fast incremental mode: reuse aux files and avoid redundant passes
  "fast": false,

  // Enable diff-based PDF replacement (requires pdftotext)
  "update_on_diff": false,

  // Help screen visual style: "plain" (default) or "lines" (subdued horizontal dividers)
  "help_style": "plain",

  // Overfull \hbox threshold (in pt) to classify as an Alert
  "alert_overfull_pt": 24.0,

  // Overfull \hbox threshold (in pt) to classify as Whatever (suppressed)
  "whatever_overfull_pt": 2.5,

  // Filename patterns ignored when auto-detecting the main .tex document
  "exclude_main_tex": [
    "prefix*.tex",
    "prelim*.tex",
    "preamble*.tex",
    "*.num.tex",
    "pratenddefaultcategory.tex"
  ],

  // Patterns excluded from brace checking and diagnostic source scans
  "exclude_source_tex": [
    "styles/*",
    "macros/*",
    "pkg/*",
    "packages/*",
    "*prefix*.tex",
    "*preamble*.tex",
    "*macros*.tex",
    "*styles*.tex"
  ],

  // Directories searched for bibliography (.bib) files (in addition to root)
  "bib_dirs": ["refs", "bib", "bibliography"],

  // Automatically mirror project subdirectories into junk/ for nested inputs
  "auto_mirror_subdirs": true,

  // Additional subdirectories inside junk/ to pre-create
  "junk_subdirs": ["figs", "fragment"],

  // Route styles to styles/ in zip packages
  "zip": {
    "inject_styles": false
  }
}
```

Comments (`//` and `/* ... */`) and trailing commas are supported in `.l.jsonc` files.

---

## 3. Global Configuration

On first execution, `leeni` automatically creates a global configuration file at:

```
~/.config/leeni/config.jsonc
```

Settings defined here apply to all projects on your machine unless overridden by a project-level `.l.jsonc` or command-line flags.

---

## 4. Environment Variables & Isolation

### Sanitizing Environment (`--no-env`)
LaTeX installations sometimes fail due to stray environment variables set in user shell profiles (`~/.bashrc`, `~/.zshrc`). The `--no-env` flag unsets TeX-related variables:

```bash
l --no-env paper.tex
```

Variables reset include:
- `TEXINPUTS`
- `BIBINPUTS`
- `BSTINPUTS`
- `TEXMFHOME`
- `TEXMFCNF`

Symlink personality: running `latex_env_free`, `bibtex_env_free`, or `pdflatex_env_free` automatically activates `--no-env`.

### Passing Custom Options (`LATEXOPTS`)
You can pass custom options to the underlying TeX engine using the `LATEXOPTS` or `LATEXOPTIONS` environment variables:

```bash
LATEXOPTS="-shell-escape -synctex=1" l paper.tex
```

---

## 5. Concurrency Locking

When compiling large documents in editor setups that trigger builds on save, multiple compiler processes can conflict. `leeni` automatically prevents simultaneous builds in the same directory using file locking (`flock` on `.l.lock`):

- **Default**: Enabled. A second process waits for the active build to complete.
- **Disabling**: Use `--no-lock` if you need to run concurrent builds intentionally.

---

## 6. Diagnostic Color Themes

`leeni` formats error headers, carets, source line numbers, and tier summaries using 24-bit TrueColor themes.

### Theme Resolution Hierarchy
1. **CLI flag**: `l --theme=<theme>`
2. **Environment variable**: `LEENI_THEME` or `L_THEME` (fallback: `COLOR_THEME`, `BASE16_THEME`)
3. **Local/Global config**: `"theme": "blush"` in `.l.jsonc` or `~/.config/leeni/config.jsonc`
4. **Built-in default**: `"blush"`

### Built-in Presets
| Theme | Error Hex | Description |
| :--- | :--- | :--- |
| **`blush`** *(default)* | `#ffcccc` | Soft pastel blush with high luminance on dark backgrounds |
| **`catppuccin`** | `#f38ba8` | Warm soothing pastel crimson (Catppuccin Mocha) |
| **`tokyo-night`** | `#f7768e` | Modern cyberpunk strawberry-rose pastel |
| **`dracula`** | `#ff5555` | Vibrant high-contrast coral red |
| **`nord`** | `#bf616a` | Calm arctic muted brick red |
| **`ansi`** | ANSI 91 | Classic terminal 16-color ANSI bright red |

### Commands
* **Cycle to next theme**:
  ```bash
  l --theme +1
  ```
  Advances to the next theme in the cycle and persists the choice to your global `config.jsonc`.
* **List available themes**:
  ```bash
  l --theme-list
  ```
* **Use custom hex**:
  ```bash
  l --theme="#ff8888"
  ```

---

## 7. Complex Workflows & Multi-Chapter Orchestration

For large projects (such as books, dissertations, or multi-chapter volumes) that require upstream data generation, plot rendering, or pre-processing scripts before compiling:

Do not attempt to embed shell execution scripts directly into LaTeX configuration files. Use a dedicated orchestrator such as **[`just`](https://github.com/casey/just)** with a single root `.justfile`.

See **[docs/orchestration.md](orchestration.md)** for a complete walkthrough of single-command book workflows using `invocation_directory()`.
