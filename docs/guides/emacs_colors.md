# Using `leeni` Colors in GNU Emacs

This guide explains how ANSI colors interact with GNU Emacs, why raw terminal escapes confuse AUCTeX's error parser, and how to configure Emacs to display rich, colorized compiler diagnostics and source frames.

---

## 1. Why Raw ANSI Colors Confuse AUCTeX

If `leeni` emits standard terminal ANSI escape codes (`\e[31m`, `\e[0m`) into an AUCTeX output buffer:

1. **Filename Corruption**: AUCTeX parses compiler errors using the regular expression `^(.+?):[0-9]+: `. When ANSI codes surround the file or line number (e.g. `\e[31mmain.tex:15:1:\e[0m`), AUCTeX captures `\e[31mmain.tex` as the filename.
2. **Failed File Verification**: AUCTeX calls `(file-exists-p "\e[31mmain.tex")`, which returns `nil`.
3. **Skipped Diagnostics**: AUCTeX assumes the line is not a real TeX error and skips past it. Pressing `C-c \`` (`TeX-next-error`) reports `"No more errors"` even when the compilation failed.
4. **Column Number Mismatch**: Standard terminal mode outputs Rust-style column locations (`file:line:col:`, e.g. `main.tex:15:1:`). AUCTeX only recognizes single-colon lines (`main.tex:15: `); the second colon causes AUCTeX to treat `:15` as part of the filename (`main.tex:15`).
5. **Context Anchors**: AUCTeX relies on standard TeX `l.<line> <token>` lines followed by a space-indented continuation line to locate and place the editing cursor on the offending macro.

This is why `leeni --emacs` strictly disables ANSI escapes and outputs plain-text diagnostics conforming to TeX's classic error and file-stack convention.

---

## 2. Approach 1: Full Colors & Source Frames via Emacs `compilation-mode` (Recommended)

If you want the **full terminal experience**—including boxed banners, Rust-style source frames, bold red erroneous tokens, bold green remediation suggestions, and exact column navigation:

Run standard `l` (without `--emacs`) inside Emacs's universal `compilation-mode`.

### Configuration (`~/.emacs` or `init.el`)

```elisp
;; Enable ANSI color rendering in compilation buffers
(require 'ansi-color)
(add-hook 'compilation-filter-hook 'ansi-color-compilation-filter)

;; Set compilation command default to `l` in LaTeX mode
(add-hook 'latex-mode-hook
          (lambda ()
            (setq-local compile-command "l")))

;; Optional: Convenient keybinding for one-touch compilation
(global-set-key (kbd "<f5>") (lambda () (interactive) (compile "l")))
```

### Why It Works

* `ansi-color-compilation-filter` intercepts incoming process output and converts ANSI escape sequences directly into native Emacs text properties (`font-lock-face`), stripping the raw escape characters from the buffer text.
* Emacs's built-in `compilation-mode` understands modern compiler syntax (`file:line:col: error:`).
* Pressing `C-x \`` (`next-error`) or clicking the error jump link navigates straight to the exact line and column in your document.

---

## 3. Approach 2: AUCTeX Native Output Fontification

If your primary editing workflow is built on AUCTeX's command runner (`C-c C-c` -> `leeni`):

### Native Syntax Highlighting

AUCTeX's output buffer (`*TeX output*`, accessible via `C-c C-l`) already applies Emacs faces natively via `TeX-output-mode`. It colorizes warnings (yellow), errors (red), and file transitions according to your active Emacs theme without needing ANSI escape codes from the compiler.

### Filtering ANSI Escapes in AUCTeX Process Buffer

If you want AUCTeX to interpret ANSI color codes emitted by child processes rather than displaying raw escape characters, advise AUCTeX's process filter:

```elisp
(require 'ansi-color)

(defun my/auctex-ansi-filter (process _string)
  (when-let ((buf (process-buffer process)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (ansi-color-apply-on-region (point-min) (point-max))))))

(advice-add 'TeX-command-filter :after #'my/auctex-ansi-filter)
```

> **Note**: Even with ANSI translation enabled, AUCTeX's jump mechanism (`C-c \``) still requires the diagnostic structure produced by `l --emacs` (parenthesized file stack `(main.tex ... )`, `l.<line>` anchors, and `LaTeX Warning:` prefixes).

---

## 4. Comparison Summary

| Feature | Emacs `compilation-mode` (`l`) | AUCTeX (`l --emacs`) |
| :--- | :--- | :--- |
| **Command** | `M-x compile` / `<f5>` | `C-c C-c` |
| **Error Jumping** | `C-x \`` (`next-error`) | `C-c \`` (`TeX-next-error`) |
| **Terminal Colors** | Full ANSI (`ansi-color-compilation-filter`) | Handled via Emacs faces (`TeX-output-mode`) |
| **Source Framing** | Rust-style source snippet with carets (`^^^`) | Standard TeX `l.<line>` context lines |
| **Fix Suggestions** | Bold green suggestion line | Plain-text `Did you mean '...'?` line |
| **Column Accuracy** | Exact character column jumping | Token-search based on `l.<line>` |
