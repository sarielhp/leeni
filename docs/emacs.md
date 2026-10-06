# Emacs & AUCTeX Integration with leeni

`leeni` has dedicated support for GNU Emacs and the AUCTeX package via the `--emacs` flag.

---

## Why `--emacs`?

Standard `leeni` formats diagnostics with colored borders, box frames, and source snippets designed for human terminal reading. However, Emacs and AUCTeX parse compilation buffers using regular expressions expecting standard TeX file tracking (`(filename.tex ... )`) and line anchors (`l.<line>`).

Passing `--emacs` automatically:
* Emits parenthesized file stack markers (`(chapters/intro.tex ... )`) that AUCTeX tracks.
* Formats error continuation blocks so AUCTeX's parser can extract the exact source lines.
* Suppresses terminal progress indicators, ANSI escapes, and decorative border lines.
* Reports warnings with standard `LaTeX Warning: ... on input line <line>` formatting.

---

## AUCTeX Setup (`init.el` or `~/.emacs`)

To add `leeni` as a build command in AUCTeX, add the following to your Emacs configuration:

```elisp
(eval-after-load "tex"
  '(add-to-list 'TeX-command-list
                '("leeni" "l --emacs %t" TeX-run-TeX nil (latex-mode)
                  :help "Build with leeni and jump to errors") t))
```

### Setting `leeni` as the Default Command
If you want AUCTeX to default to `leeni` instead of `LaTeX`:

```elisp
(setq-default TeX-command-default "leeni")
```

### Everyday AUCTeX Workflow:
* `C-c C-c`: Choose `leeni` and press `Enter` to compile.
* `C-c \`` (`TeX-next-error`): Jump directly to the offending line for each error or warning.
* `C-c C-l` (`TeX-recenter-output-buffer`): View the full compilation log buffer.

---

## Standard Emacs Compilation Mode (`M-x compile`)

For Emacs's built-in `compilation-mode` (`M-x compile`, `next-error` `C-x \``), use the `--compile` flag instead of `--emacs`. The `--compile` flag outputs diagnostics in strict GNU Coding Standards format (`file:line:col: severity: message`) in stream encounter order:

```elisp
;; In ~/.emacs or init.el:
(add-hook 'latex-mode-hook
          (lambda ()
            (setq-local compile-command "l --compile")))
```

### Colored Compilation Output
By default, `leeni` disables ANSI escape sequences under `INSIDE_EMACS=...compile` so line numbers match standard GNU compilation regexes cleanly. To enable color in `compilation-mode`:

```elisp
;; Enable ANSI colors in compilation buffers
(add-hook 'compilation-filter-hook 'ansi-color-compilation-filter)

;; In latex-mode-hook:
(setq-local compile-command "l --compile --color")
```

### Usage:
* `M-x compile`: Runs `l --compile`.
* `C-x \`` (`next-error`): Jumps directly to the next diagnostic line.
* `M-p` / `M-n`: Navigate previous and next errors in the compilation buffer.

> [!NOTE]
> `--compile` and `--emacs` represent different integration paradigms and cannot be combined. `--emacs` emits raw AUCTeX parenthesis file-tracking blocks (`TeX-command-list`), while `--compile` formats output for the GNU `compile` command (`M-x compile`). Passing both results in an exit status of 2.
