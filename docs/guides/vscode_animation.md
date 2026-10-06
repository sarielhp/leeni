# VS Code Headless Automation & Demo Recording Guide

This document captures the complete technical methodology, architecture, configurations, and lessons learned while automating authentic recordings of Visual Studio Code running `leeni` via the LaTeX Workshop extension in a headless Linux environment.

---

## 1. Objectives & Requirements

- **Authentic Execution**: Run real VS Code with LaTeX Workshop inside a virtual display (`Xvfb`) rather than a synthetic HTML/DOM simulation.
- **Visual Clarity & Typography**: Double font size and scale the interface (`window.zoomLevel: 1.5`, `editor.fontSize: 22`) so code, squiggles, and diagnostics fill the 1080p frame crisply without empty space.
- **Diagnostic Highlighting & Emojis**: Render structured diagnostics in hover tooltips and the Problems panel with full-color visual cues:
  - ❓ `Why:` — Explanation of root cause (`\u{2753}`)
  - 🔧 `Fix:` — Actionable remediation step (`\u{1F527}`)
  - 👀 `See:` — Documentation / reference link (`\u{1F440}`)
- **Deliverables**: Produce both high-resolution MP4 (`docs/vscode_latex_it_demo.mp4`) and an optimized GIF (`docs/vscode_latex_it_demo.gif`).

---

## 2. Headless Display & Recording Stack

The automation pipeline runs entirely under X11 without requiring a physical monitor:

| Component | Tool / Version | Purpose |
| :--- | :--- | :--- |
| **Display Server** | `xvfb-run` (1920x1080x24) | Virtual X11 framebuffer |
| **Window Manager** | `xfwm4 --compositor=off` | Window decoration, active focus, and maximize handling |
| **Capture Engine** | `ffmpeg` (`x11grab`) | 30 fps lossless/H.264 desktop capture |
| **Input Synthesis** | `xdotool` | Synthetic keyboard shortcuts and mouse clicks |
| **Window Control** | `wmctrl` | Maximizing window to fill exact 1920x1080 viewport |

### Invocation Pattern

```bash
xvfb-run -a -s "-screen 0 1920x1080x24" ruby path/to/record_script.rb
```

---

## 3. Critical Gotchas & Root-Cause Solutions

### 3.1. Stale Sockets & The "Another instance of Code is running" Blocker
- **Symptom**: VS Code silently exits or connects to an existing daemon, failing to open a window on the virtual display.
- **Root Cause**: VS Code binds Unix domain sockets under `/run/user/<UID>/vscode-*.sock`. Stale sockets from previous headless runs mislead the launcher.
- **Solution**:
  1. Kill lingering processes prior to launch: `killall -9 code xfwm4 ffmpeg`.
  2. Clear host sockets: `rm -f /run/user/<UID>/vscode-*.sock`.
  3. Isolate runtime directories per run:
     ```ruby
     ENV['XDG_RUNTIME_DIR'] = Dir.mktmpdir('vsc_xdg_')
     user_data_dir = Dir.mktmpdir('vsc_ud_')
     ```

### 3.2. Heredoc Interpolation vs. Runtime `$DISPLAY`
- **Symptom**: Black screen recording (15 KB PNG frames with mean pixel color ~0.2).
- **Root Cause**: If a parent script writes an inner runner script using an unquoted heredoc (`<<~RUBY`), `ENV['DISPLAY']` evaluates at generation time on the host (e.g. `:1` or null) instead of reading the dynamic `$DISPLAY` assigned by `xvfb-run` (e.g. `:99`, `:117`).
- **Solution**: Use a quoted heredoc (`<<~'RUBY'`) or pass paths and variables via `ARGV`. Inside the inner script, always read `display = ENV['DISPLAY']` at runtime.

### 3.3. Welcome Modals & Copilot Popups
- **Symptom**: A large modal ("Welcome to VS Code: Sign in to use GitHub Copilot") blocks the editor workspace.
- **Root Cause**: Fresh `--user-data-dir` instances trigger default onboarding flows.
- **Solution**:
  - Disable Copilot extensions via CLI arguments:
    ```bash
    --disable-extension github.copilot --disable-extension github.copilot-chat
    ```
  - Pre-seed settings in both workspace `.vscode/settings.json` and user `settings.json`:
    ```json
    {
      "chat.commandCenter.enabled": false,
      "github.copilot.enable": { "*": false },
      "workbench.tips.enabled": false,
      "workbench.startupEditor": "none",
      "workbench.welcomePage.walkthroughs.openOnInstall": false,
      "security.workspace.trust.enabled": false,
      "security.workspace.trust.startupPrompt": "never",
      "telemetry.telemetryLevel": "off"
    }
    ```
  - Fallback UI dismissal:
    ```ruby
    system('xdotool', 'mousemove', '1550', '188', 'click', '1') # Click modal close button
    system('xdotool', 'key', 'Escape')
    ```

### 3.4. Extension Collision on `.tex` Files
- **Symptom**: Multiple extensions competing for the LaTeX language mode (`mathematic.vscode-latex` vs. `james-n-lambiase.latex-workshop`).
- **Solution**: Explicitly disable the redundant extension:
  ```bash
  --disable-extension mathematic.vscode-latex
  ```

### 3.5. Secondary Chat Sidebar
- **Symptom**: An empty secondary sidebar opens on the right side of the editor.
- **Solution**: Dismiss via Command Palette:
  ```ruby
  system('xdotool', 'key', 'ctrl+shift+p')
  sleep 0.5
  system('xdotool', 'type', '--delay', '40', 'View: Close Secondary Side Bar')
  sleep 0.5
  system('xdotool', 'key', 'Return')
  ```

---

## 4. UI Geometry & Coordinates (`1920x1080`, `zoomLevel: 1.5`, `fontSize: 22`)

When maximized under `xfwm4` at `zoomLevel: 1.5`, editor line coordinates stabilize at:

| UI Element / Code Target | Coordinates `(X, Y)` | Action |
| :--- | :--- | :--- |
| **Line 6** (`\ref{sec:missing}`) | `(450, 315)` | Warning hover (undefined reference) |
| **Line 8** (`\badMacroNameHere`) | `(450, 390)` | Error hover (undefined control sequence) |
| **Line 10** (`\hbox to 20pt...`) | `(450, 460)` | Warning hover (overfull hbox) |
| **Modal Close Button** | `(1550, 188)` | Close initial onboarding popups |
| **Secondary Sidebar Close** | `(1888, 65)` | Close side pane if open |

### Reliable Hover Tooltip Triggering
Mouse hovering alone in Xvfb can be timing-sensitive. The most reliable trigger is:
1. Click the target line: `xdotool mousemove X Y click 1`
2. Send VS Code hover command: `xdotool key ctrl+k key ctrl+i` (`editor.action.showHover`)
3. Dismiss before proceeding: `xdotool key Escape`

---

## 5. LaTeX Workshop Integration Config

Pre-configure `.vscode/settings.json` in the workspace directory:

```json
{
  "latex-workshop.latex.tools": [
    {
      "name": "leeni",
      "command": "/home/sariel/bin/l",
      "args": ["-u", "--vscode-lw", "%DOC%"]
    }
  ],
  "latex-workshop.latex.recipes": [
    {
      "name": "leeni",
      "tools": ["leeni"]
    }
  ],
  "latex-workshop.latex.recipe.default": "leeni",
  "latex-workshop.latex.autoBuild.run": "never",
  "window.zoomLevel": 1.5,
  "editor.fontSize": 22,
  "editor.minimap.enabled": false,
  "editor.hover.delay": 150
}
```

Pre-seed explicit build keybinding in user `keybindings.json`:
```json
[
  {
    "key": "ctrl+alt+b",
    "command": "latex-workshop.build"
  }
]
```

---

## 6. Demo Script Execution Flow

The canonical recorded walkthrough consists of the following timed sequence:

```
[00:00 - 00:04]  Launch VS Code, maximize window, dismiss dialogs, close secondary sidebar.
[00:04 - 00:08]  Display initial LaTeX source with deliberate errors & warnings.
[00:08 - 00:14]  Trigger build (Ctrl+Alt+B) -> leeni executes via LaTeX Workshop.
[00:14 - 00:20]  Open Problems panel (Ctrl+Shift+M) -> Shows red squiggles and colored emojis:
                 ❓ Why: Undefined control sequence '\badMacroNameHere'
                 🔧 Fix: Check macro spelling or add package
[00:20 - 00:26]  Click Line 8 and trigger hover popup (Ctrl+K, Ctrl+I) displaying formatted markdown.
[00:26 - 00:32]  Comment out error line (`%`), save (Ctrl+S).
[00:32 - 00:38]  Recompile (Ctrl+Alt+B) -> Error clears cleanly; only warnings remain.
[00:38 - 00:43]  Hover Line 6 (Undefined reference `\ref{sec:missing}`).
[00:43 - 00:48]  Hover Line 10 (Overfull `\hbox`).
[00:48 - 00:50]  Clean shutdown of ffmpeg and window manager.
```

---

## 7. High-Quality GIF Conversion

To convert the resulting MP4 into a crisp, artifact-free GIF under 3 MB:

```bash
ffmpeg -y -i docs/vscode_latex_it_demo.mp4 \
  -vf "fps=10,scale=1280:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
  docs/vscode_latex_it_demo.gif
```

---

## 8. Summary Checklist for Future Runs

- [ ] Clean up `/run/user/<UID>/vscode-*.sock` and kill stale `code`/`xvfb` processes.
- [ ] Pass isolated `XDG_RUNTIME_DIR` and `--user-data-dir`.
- [ ] Disable conflicting extensions (`mathematic.vscode-latex`, Copilot).
- [ ] Ensure quoted heredoc (`<<~'RUBY'`) so `$DISPLAY` evaluates inside `xvfb-run`.
- [ ] Pre-populate workspace `.vscode/settings.json` with `leeni` recipe and zoom settings.
- [ ] Use `ctrl+k ctrl+i` for deterministic hover rendering.
- [ ] Verify output frame count and non-zero bitrate before finalizing.
