# VS Code Integration with leeni

`leeni` integrates with Visual Studio Code in two ways:
1. **Native VS Code Tasks** (zero extensions required).
2. **LaTeX Workshop Extension** (the full IDE LaTeX setup).

---

## Instant Automated Setup (`l --vscode-init`)

Run the following command inside your LaTeX project root:

```bash
l --vscode-init
```

`leeni` automatically creates or updates the `.vscode/` configuration files:
* **`.vscode/tasks.json`**: Sets up `Build LaTeX (leeni)` with `l --compile` as the default build task (`Ctrl+Shift+B` / `Cmd+Shift+B`) and matches error/warning/alert/note messages into the **Problems** panel.
* **`.vscode/settings.json`**: Configures LaTeX Workshop tools, recipes, and sets `outDir: "%DIR%/junk"` so diagnostics and previewers synchronize cleanly.
* **Non-destructive & Idempotent**: If `.vscode/tasks.json` or `.vscode/settings.json` already exist, your other tasks and settings are preserved.

---

## Workflow 1: Native VS Code Tasks (Zero Extensions)

You can build documents using VS Code's standard task runner without installing any LaTeX extension.

Create `.vscode/tasks.json` in your project root:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Build LaTeX (leeni)",
      "type": "shell",
      "command": "l",
      "args": ["--compile"],
      "group": {
        "kind": "build",
        "isDefault": true
      },
      "presentation": {
        "reveal": "silent",
        "panel": "shared"
      },
      "problemMatcher": {
        "owner": "latex",
        "fileLocation": ["relative", "${workspaceFolder}"],
        "pattern": {
          "regexp": "^([^:]+):(\\d+)(?::(\\d+))?:\\s+(error|warning|alert|note):\\s+(.*)$",
          "file": 1,
          "line": 2,
          "column": 3,
          "severity": 4,
          "message": 5
        }
      }
    }
  ]
}
```

### Key Shortcuts:
* `Ctrl+Shift+B` (or `Cmd+Shift+B` on macOS): Trigger compilation.
* `Ctrl+Shift+M` (or `Cmd+Shift+M`): Open the **Problems** panel.
* `F8` / `Shift+F8`: Jump directly to the next or previous problem in the editor.

---

## Workflow 2: LaTeX Workshop Extension

If you use the popular [LaTeX Workshop](https://marketplace.visualstudio.com/items?itemName=James-Yu.latex-workshop) extension, configure `leeni` as a custom compiler tool and recipe in `.vscode/settings.json` (or your global User Settings):

```json
{
  "latex-workshop.latex.tools": [
    {
      "name": "leeni",
      "command": "l",
      "args": ["--vscode-lw", "%DOC%"],
      "env": {}
    }
  ],
  "latex-workshop.latex.recipes": [
    {
      "name": "leeni",
      "tools": ["leeni"]
    }
  ],
  "latex-workshop.latex.recipe.default": "leeni",
  "latex-workshop.latex.outDir": "%DIR%/junk",
  "latex-workshop.latex.autoClean.run": "never"
}
```

### Why set `outDir` to `junk`?
`leeni` isolates temporary build artifacts (`.log`, `.aux`, `.fls`) in `junk/`. Telling LaTeX Workshop that `"latex-workshop.latex.outDir": "%DIR%/junk"` ensures its internal log parser can find `junk/<doc>.log` and correctly populate VS Code's diagnostic view.

---

## SyncTeX (Forward & Reverse Search)

`leeni` compiles documents with `-synctex=1` by default and automatically exports `<doc>.synctex.gz` (and `<doc>.pdf`) to the project root directory, while also preserving copies in `junk/`.

### In LaTeX Workshop (Internal Viewer):
* **Forward Search** (editor $\rightarrow$ PDF): `Ctrl+Alt+J` (macOS: `Cmd+Option+J`) jumps to the corresponding line in the PDF viewer.
* **Reverse Search** (PDF $\rightarrow$ editor): `Ctrl+Click` (macOS: `Cmd+Click`) anywhere in the PDF jumps back to the exact source line in VS Code.

### In External Viewers:
Because the `.pdf` and `.synctex.gz` files live side-by-side in your project root, external PDF viewers with SyncTeX support work out of the box:
* **Linux**: Zathura, Evince, Okular
* **macOS**: Skim
* **Windows**: SumatraPDF
