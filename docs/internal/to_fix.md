# Diagnostic Output Modernization & Noise Reduction Plan

This document details required enhancements to `leeni`'s standard diagnostic display, addressing line-number clickability, message verbosity, redundant line references, and raw TeX jargon. It includes a comprehensive analysis of the diagnostic run on `~/rand_alg/notes/book.tex`.

---

## 1. Core Issues & Requirements

### 1.1 Embedded Clickable Hyperlinks in Regular Mode
- **Current State**: Clickable OSC 8 hyperlinks (`\e]8;;file://...#L...\e\...`) are only emitted in compiler mode (`--compile` / `-cc`). Regular human-readable output prints plain text line numbers (`455: ` or `71--75: `).
- **Target State**: When terminal OSC 8 hyperlinks are supported (auto-detected or forced via `--link`), line numbers and file banners in regular output must be clickable hyperlinks. Clicking `455:` jumps directly to line 455 of the file in editors (VS Code, Emacs, Vim, Sublime) and terminal emulators (Kitty, iTerm2, WezTerm, Ghostty, Foot, Warp).
- **Format**:
  - File header: `\e]8;;file:///path/to/file.tex\e\\── 06_verify/verify.tex (2 alerts) ──\e]8;;\e\\`
  - Single line: `\e]8;;file:///path/to/file.tex#455\e\\455:\e]8;;\e\\`
  - Range: `\e]8;;file:///path/to/file.tex#71\e\\71--75:\e]8;;\e\\`

---

### 1.2 Multi-Defined Label Aggregation & Cross-Linking
- **Current State**:
  ```text
  ── 06_verify/verify.tex (2 alerts) ─────────────────────────────────────────────
         455: LaTeX Warning: Label `sec:complexity' multiply defined (location 1 of 3)

  ── 24_and_or/and_or_tree.tex (1 alert) ─────────────────────────────────────────
          30: LaTeX Warning: Label `sec:complexity' multiply defined (location 2 of 3)

  ── 37_complexity_classes/complexity.tex (2 alerts) ─────────────────────────────
          33: LaTeX Warning: Label `sec:complexity' multiply defined (location 3 of 3)
  ```
- **Problems**:
  1. Boilerplate text `LaTeX Warning: Label \`...\' multiply defined (location X of Y)` repeats on every occurrence.
  2. The occurrences are fragmented across distant file banners; to fix them, the user must manually hunt through the entire log to find where the other definitions live.
- **Target State**:
  Aggregate duplicates across files and display cross-references directly at each occurrence:
  ```text
  ── 06_verify/verify.tex ────────────────────────────────────────────────────────
         455: Warning: label 'sec:complexity' duplicate (also at 24_and_or/and_or_tree.tex:30, 37_complexity_classes/complexity.tex:33)
  ```
  Each target location (`file:line`) should be a clickable OSC 8 link.

---

### 1.3 Overfull & Underfull Box Deduplication and Precision
- **Current State**:
  ```text
         125: Overfull \hbox (54.46506pt too wide) detected at line 125
    108--108: Overfull \hbox (50.97342pt too wide) in paragraph at lines 108--108
      71--75: Overfull \hbox (5.72282pt too wide) in paragraph at lines 71--75
    169--171: Underfull \hbox (badness 10000) in paragraph at lines 169--171
    158--181: Overfull \hbox (10.08925pt too wide) in alignment at lines 158--181
  ```
- **Problems**:
  1. **Redundant line numbers**: The line number is already displayed as the prefix (`125:` or `71--75:`). Repeating `detected at line 125` or `in paragraph at lines 71--75` wastes 40% of the screen width.
  2. **Single-line ranges**: `108--108` is printed instead of `108`.
  3. **Absurd precision**: Points are formatted as raw TeX floats with 5 decimal places (`54.46506pt`).
  4. **TeX jargon**: `\hbox` is implementation trivia that distracts from the core message: how much content spilled outside the margin.
- **Target State**:
  ```text
         125: Alert: 54.47pt too wide
         108: Alert: 50.97pt too wide
      71--75: Warning: 5.72pt too wide
    169--171: Note: underfull line (badness 10000)
    158--181: Warning: 10.09pt too wide (math alignment)
  ```

---

### 1.4 Colors Changing in Mid-Flight (Bug)
- **Current State**:
  During terminal execution (notably observed when running on large multi-chapter projects like `~/rand_alg/notes/book.tex`), the output colors oscillate and mutate unexpectedly mid-stream:
  1. A single file's warnings section unpredictably switches between pastel yellow, harsh dark magenta, and cyan across adjacent lines.
  2. File banners switch colors multiple times within the same horizontal line (colored dashes $\rightarrow$ uncolored filename $\rightarrow$ uncolored count $\rightarrow$ colored dashes).
  3. Themes drop from 24-bit TrueColor pastels into raw 16-color ANSI codes on certain message types.
  4. Tags like `[leeni]` strip all remaining color from subsequent text on the line.
- **Target State**:
  Strictly cohesive, predictable color hierarchy:
  1. All items in the **warnings** tier consistently use warning yellow (or theme warning tone). No random switching to magenta or cyan.
  2. Every color used in diagnostics has an explicit palette entry in [`lib/leeni/color.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/color.rb) so TrueColor pastels never abruptly downgrade to 16-color ANSI.
  3. Header banners maintain harmonious styling without mid-line resets to raw terminal default.
  4. Text following embedded tags retains its active tier color without being reset to terminal default.

---

### 1.5 Line Numbers Changing & Jumbling (Bug)
- **Current State**:
  During diagnostic display, line numbers exhibit multiple forms of instability:
  1. **Line number colors change mid-flight**: Underfull boxes switch the line number color to **Blue**, while adjacent warnings display line numbers in **Cyan**.
  2. **Line numbers appear out of order**: In chapters with multiple overfull boxes, warnings are sorted by severity rather than source line number, causing line numbers to jump forward and backward erratically.
  3. **Format mutation**: Line numbers fluctuate between single lines (`125:`), ranges (`71--75:`), redundant single-line ranges (`108--108:`), and blank prefixes (`   :`).
  4. **Multi-pass shifts**: Line numbers shift between early convergence passes and final passes as citations and references resolve from `??` to full text.
  5. **File tracking desynchronization**: TeX log 79-column line wrapping can corrupt the paren-based `file_stack`, attributing line numbers from sub-files to the wrong parent or chapter file.
- **Target State**:
  1. Strict monotonic ascending line-number order within each file (`1..N`).
  2. Constant, uniform color for all line numbers in the gutter prefix (Cyan or theme accent).
  3. Normalized line representations: collapse `108--108` to `108`; display ranges only when truly multiline.
  4. Robust file tracking that handles TeX log line-wraps without paren desynchronization.

---

## 2. Analysis of Diagnostic Run on `~/rand_alg/notes/book.tex`

Execution command:
```bash
l ~/rand_alg/notes/book.tex
```
Summary stats: `Errors: 0, Alerts: 193, Warnings: 114, Whatevers: 92 (Whatevers suppressed)`

### Line-by-Line Category Analysis

| Diagnostic Category | Current Raw Output | Issues in Current Output | Proposed Compact Output |
| :--- | :--- | :--- | :--- |
| **Duplicate Labels** | `455: LaTeX Warning: Label \`sec:complexity\' multiply defined (location 1 of 3)` | Verbose boilerplate; unclickable; location 2 and 3 are separated by hundreds of lines. | `455: Warning: label 'sec:complexity' duplicate (also at and_or_tree.tex:30, complexity.tex:33)` *(with clickable links)* |
| **Overfull Box (single line)** | `125: Overfull \hbox (54.46506pt too wide) detected at line 125` | Repeats line number; raw 5-digit decimal float; TeX `\hbox` jargon. | `125: Alert: 54.47pt too wide` |
| **Overfull Box (range)** | `71--75: Overfull \hbox (5.72282pt too wide) in paragraph at lines 71--75` | Repeats `in paragraph at lines 71--75`; 5 decimal places. | `71--75: Warning: 5.72pt too wide` |
| **Overfull Box (identical range)** | `108--108: Overfull \hbox (50.97342pt too wide) in paragraph at lines 108--108` | Redundant range `108--108` should collapse to single line `108`. | `108: Alert: 50.97pt too wide` |
| **Overfull Box (alignment)** | `158--181: Overfull \hbox (10.08925pt too wide) in alignment at lines 158--181` | Repeats line range; alignment context can be noted concisely. | `158--181: Warning: 10.09pt too wide (alignment)` |
| **Underfull Box** | `169--171: Underfull \hbox (badness 10000) in paragraph at lines 169--171` | Repeats line numbers; `\hbox` jargon. | `169--171: Note: underfull line (badness 10000)` |
| **Duplicate Undefined References** | `219: LaTeX Warning: Hyper reference \`lemma:Chernoff's inequality\' on page 239 undefined on input line 219.`<br>`219: LaTeX Warning: Reference \`lemma:Chernoff's inequality\' on page 239 undefined on input line 219.` | Emitted TWICE for every broken reference (once by hyperref, once by LaTeX kernel); repeats line number; backtick quote. | `219: Warning: undefined reference 'lemma:Chernoff's inequality' (page 239)` *(deduplicated to 1 entry)* |
| **Undefined Reference (standard)** | `203: LaTeX Warning: Reference \`exer:star:distortion\' on page 352 undefined on input line 203.` | Repeats `on input line 203`; verbose prefix `LaTeX Warning:`. | `203: Warning: undefined reference 'exer:star:distortion' (page 352)` |
| **Undefined Citation** | `354: LaTeX Warning: Citation 'h-a6q-61' on page 33 undefined on input line 354.` | Repeats `on input line 354`; verbose prefix `LaTeX Warning:`. | `354: Warning: undefined citation 'h-a6q-61' (page 33)` |
| **Empty Bibliography** | `422: LaTeX Warning: Empty bibliography on input line 422.` *(repeated across 12 chapters)* | Repeats `on input line 422`; boilerplate jargon. | `422: Warning: empty bibliography` |
| **Invalid Math Mode Command** | `133: LaTeX Warning: Command \L invalid in math mode on input line 133.` | Repeats `on input line 133`; verbose prefix. | `133: Warning: command \L invalid in math mode` |
| **Multi-line Package Warning** | `146: Package amsmath Warning: Foreign command \atopwithdelims; (amsmath) \frac or \genfrac should be used instead (amsmath) on input line 146.` | Transcript line-wrap fragments `(amsmath)` into the message; repeats `on input line 146`. | `146: Warning: [amsmath] foreign command \atopwithdelims; use \frac or \genfrac instead` |
| **Missing Bib Entry** | `── bibliography (1 warning) ──`<br>` : Missing database entry: 'h-a6q-61'` | Line prefix is blank spaces ` : `; lacks file context. | `bib: Warning: missing database entry 'h-a6q-61'` |
| **Auxiliary File Box** | `── junk/book.toc (1 warning) ──`<br>` 156--156: Overfull \hbox (3.016pt too wide) in paragraph at lines 156--156` | Points into `junk/book.toc` without indicating that it is a generated table of contents entry; `156--156` range. | `156: Warning: 3.02pt too wide (in generated TOC)` |

---

## 3. Detailed Side-by-Side Examples

### Example A: Duplicate Labels (Current vs. Proposed)

**Current:**
```text
── 06_verify/verify.tex (2 alerts) ─────────────────────────────────────────────
       455: LaTeX Warning: Label `sec:complexity' multiply defined (location 1 of 3)
       601: LaTeX Warning: Label `def:b:p:p' multiply defined (location 1 of 2)

── 08_k_wise/k_wise.tex (4 alerts) ─────────────────────────────────────────────
       624: LaTeX Warning: Label `sec:h:m:i' multiply defined (location 1 of 2)
       629: LaTeX Warning: Label `lemma:cheby:higher' multiply defined (location 1 of 2)
```

**Proposed (Clean, Compact, Cross-Referenced with Clickable Links):**
```text
── 06_verify/verify.tex (2 alerts) ─────────────────────────────────────────────
       455: Alert: label 'sec:complexity' duplicate (also at and_or_tree.tex:30, complexity.tex:33)
       601: Alert: label 'def:b:p:p' duplicate (also at complexity.tex:177)

── 08_k_wise/k_wise.tex (4 alerts) ─────────────────────────────────────────────
       624: Alert: label 'sec:h:m:i' duplicate (also at higher_moments.tex:26)
       629: Alert: label 'lemma:cheby:higher' duplicate (also at higher_moments.tex:31)
```

---

### Example B: Overfull & Underfull Boxes (Current vs. Proposed)

**Current:**
```text
── 13_cond_exp/cond_exp.tex (3 alerts) ─────────────────────────────────────────
  108--108: Overfull \hbox (50.97342pt too wide) in paragraph at lines 108--108
       125: Overfull \hbox (54.46506pt too wide) detected at line 125
       180: Overfull \hbox (59.70702pt too wide) detected at line 180

── 14_treaps/treaps.tex (4 alerts) ─────────────────────────────────────────────
        58: Overfull \hbox (72.05925pt too wide) detected at line 58
       331: Overfull \hbox (52.92728pt too wide) detected at line 331
  366--381: Overfull \hbox (81.97362pt too wide) in paragraph at lines 366--381
       457: Overfull \hbox (79.90944pt too wide) detected at line 457
```

**Proposed (Clean, Compact, Rounded, No Line Repetition):**
```text
── 13_cond_exp/cond_exp.tex (3 alerts) ─────────────────────────────────────────
       108: Alert: 50.97pt too wide
       125: Alert: 54.47pt too wide
       180: Alert: 59.71pt too wide

── 14_treaps/treaps.tex (4 alerts) ─────────────────────────────────────────────
        58: Alert: 72.06pt too wide
       331: Alert: 52.93pt too wide
  366--381: Alert: 81.97pt too wide
       457: Alert: 79.91pt too wide
```

---

### Example C: Hyperref & Standard Reference Deduplication

**Current:**
```text
── 28_frequence_est/frequency_est.tex (7 warnings) ─────────────────────────────
        76: LaTeX Warning: Hyper reference `theo:Chebychev:inequality' on page 238 undefined on input line 76.
       219: LaTeX Warning: Hyper reference `lemma:Chernoff's inequality' on page 239 undefined on input line 219.
       219: LaTeX Warning: Reference `lemma:Chernoff's inequality' on page 239 undefined on input line 219.
       750: Overfull \hbox (17.01059pt too wide) detected at line 750
  772--778: Overfull \hbox (11.49782pt too wide) in paragraph at lines 772--778
       798: LaTeX Warning: Hyper reference `lemma:f:e:using:ch' on page 247 undefined on input line 798.
       798: LaTeX Warning: Reference `lemma:f:e:using:ch' on page 247 undefined on input line 798.
```

**Proposed (Deduplicated, Clean Quotes, Rounded Floats):**
```text
── 28_frequence_est/frequency_est.tex (5 warnings) ─────────────────────────────
        76: Warning: undefined reference 'theo:Chebychev:inequality' (page 238)
       219: Warning: undefined reference 'lemma:Chernoff's inequality' (page 239)
       750: Warning: 17.01pt too wide
  772--778: Warning: 11.50pt too wide
       798: Warning: undefined reference 'lemma:f:e:using:ch' (page 247)
```

---

## 4. Deep-Dive Bug Analysis: Mid-Flight Color Shifting & Bleeding

Empirical analysis of the diagnostic run on `~/rand_alg/notes/book.tex` identified 5 distinct root causes responsible for the user-reported "colors changing in mid flight":

### 4.1 Intra-Tier Color Flipping (Yellow ↔ Magenta ↔ Cyan within Warnings)
- **Location**: [`lib/leeni/diagnostics.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/diagnostics.rb#L396-L404) and [`lib/leeni/diagnostics.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/diagnostics.rb#L501).
- **Mechanism**:
  When LaTeX log items are parsed, `Overfull \hbox` is unconditionally assigned `base_color: :magenta` and `Underfull \hbox` is assigned `base_color: :cyan`.
  If an overfull box has severity $\ge 20\,\text{pt}$, `extract_alerts` reassigns its `base_color` to `:red` and promotes it to the `alerts` tier.
  However, all remaining box warnings ($< 20\,\text{pt}$) remain in the `warnings` tier while **retaining `base_color: :magenta` or `:cyan`**!
  Standard LaTeX warnings (undefined references, duplicate labels, citation warnings) have `base_color: :yellow`.
- **Manifestation in `28_frequence_est/frequency_est.tex`**:
  ```text
  ── 28_frequence_est/frequency_est.tex (7 warnings) ──   <- Header dashes in YELLOW
    76: Warning: undefined reference '...'                 <- Line & text in YELLOW
   219: Warning: undefined reference '...'                 <- Line & text in YELLOW
   750: Overfull \hbox (17.01pt too wide)...               <- Line & text flips to MAGENTA!
  772--778: Overfull \hbox (11.50pt too wide)...           <- Line & text flips to MAGENTA!
   798: Warning: undefined reference '...'                 <- Line & text flips back to YELLOW!
  ```
  Within the same file and tier, text flips between Yellow, Magenta, and Cyan.

### 4.2 Theme Palettes Omit `:magenta` & `:blue` (Abrupt TrueColor Fallback)
- **Location**: [`lib/leeni/color.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/color.rb#L10-L59) and [`lib/leeni/color.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/color.rb#L194-L208).
- **Mechanism**:
  [`LatexColor::THEMES`](file:///home/sariel/prog/26/leeni/lib/leeni/color.rb#L10) defines 6 color themes (`blush`, `catppuccin`, `tokyo-night`, `dracula`, `nord`, `ansi`). Every theme defines hex codes for `:red`, `:yellow`, `:cyan`, and `:green`.
  **Neither `:magenta` nor `:blue` is defined in any theme.**
  When TrueColor output is active, `RainbowThemeOverride` matches `:red`, `:yellow`, `:cyan`, `:green` to 24-bit TrueColor pastel escape sequences (e.g. `\e[38;2;255;204;204m`).
  When Rainbow encounters `:magenta` (used for overfull box warnings and `[leeni]` tags) or `:blue` (used for cyan line numbers in `colorize_line_num`), `colors[values.first]` returns `nil`. Rainbow calls `super`, abruptly falling back to standard 16-color ANSI (`\e[35m` and `\e[34m`).
- **Visual Impact**:
  Harsh, highly saturated, dark 16-color ANSI purple and blue suddenly flash amid smooth, high-luminance pastel peach and pink tones.

### 4.3 Mid-Line Banner Color Flip
- **Location**: [`lib/leeni/diagnostics.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/diagnostics.rb#L959-L972).
- **Mechanism**:
  `format_file_separator` constructs:
  ```ruby
  lead = Rainbow('── ').send(color).bright
  file_part = Rainbow(item_file).bold
  count_part = " (#{count_str}) "
  tail = Rainbow(dashes).send(color).bright
  "#{lead}#{file_part}#{count_part}#{tail}"
  ```
  `lead` ends with `\e[0m` (reset). `file_part` sets bold but leaves color unspecified. `count_part` has no ANSI escapes. `tail` reasserts `color`.
- **Visual Impact**:
  On every single file banner, the eye scans horizontally:
  `[Red/Yellow dashes]` $\rightarrow$ `[Default terminal gray/white filename]` $\rightarrow$ `[Default terminal gray/white count]` $\rightarrow$ `[Red/Yellow dashes]`.
  The line changes color mid-flight twice across a single banner.

### 4.4 Broken `reassert` Reset in Tag Highlighting
- **Location**: [`lib/leeni/diagnostics.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/diagnostics.rb#L142-L149).
- **Mechanism**:
  ```ruby
  def highlight_leeni_tag(str, base_color = :red)
    return str if @options[:emacs] || @options[:color] == false
    return str unless str.include?('[leeni]')

    reassert = Rainbow('').send(base_color).bright.to_s
    tag = "#{Rainbow('[leeni]').magenta.bold}#{reassert}"
    str.gsub('[leeni]', tag)
  end
  ```
  Calling `Rainbow('').send(base_color).bright.to_s` on an empty string emits `"\e[38;2;...m\e[0m\e[1m\e[0m"`.
- **Visual Impact**:
  Instead of restoring `base_color`, `reassert` executes `\e[0m`, immediately stripping all foreground color and weight from the rest of the diagnostic message! The remainder of the line bleeds into plain uncolored text.

### 4.5 Split Tier Iteration vs. File-Grouped Traversal
- **Location**: [`lib/leeni/diagnostics.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/diagnostics.rb#L1792-L1800).
- **Mechanism**:
  `render_non_error_tiers` executes:
  ```ruby
  print_diagnostics_body([], alert_items, tier_label: 'alerts', io: io) if !suppress_alerts && !alert_items.empty?
  print_diagnostics_body(reg_warns, [], tier_label: 'warnings', io: io) if !suppress_warnings && !reg_warns.empty?
  ```
  In a 58-chapter document, alerts across all chapters are printed first in **RED** (from Chapter 6 through Chapter 58). Then the loop begins anew, printing warnings for Chapter 2, Chapter 3, etc. in **YELLOW**.
- **Visual Impact**:
  As the screen scrolls, a file like `28_frequence_est/frequency_est.tex` is printed in Red during the alert phase, and then dozens of screens later reappears in Yellow and Magenta. The user experiences an impression of oscillating colors and jumping file contexts during compilation.

---

## 5. Deep-Dive Bug Analysis: Line Number Fluctuations & Jumbling

Empirical analysis identified 5 distinct mechanisms causing line number instability, ordering jumps, and color mutations:

### 5.1 Non-Monotonic / Jumbled Line Ordering (Severity-Sorted Overfull Boxes)
- **Location**: [`lib/leeni/diagnostics.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/diagnostics.rb#L798-L813).
- **Mechanism**:
  In `sort_diagnostic_items`, overfull box warnings are partitioned into `sorted_overfull` and sorted by `sev.to_f` (box width), rather than source line number:
  ```ruby
  sorted_overfull = overfull_warnings.sort_by do |w|
    sev = w[:severity] || extract_box_severity(w[:text].to_s)
    [format_display_path(w[:file]), sev.to_f, w[:line] || 0, w[:index] || 0]
  end
  ```
- **Manifestation in `17_min_cut/mincut.tex`**:
  ```text
  ── 17_min_cut/mincut.tex (6 alerts) ──
     99--110: Overfull \hbox (29.57pt too wide)
         304: Overfull \hbox (44.05pt too wide)
         157: Overfull \hbox (82.31pt too wide)    <- Jumps backward from line 304 to 157!
    371--393: Overfull \hbox (91.55pt too wide)
         546: Overfull \hbox (107.67pt too wide)
         121: Overfull \hbox (115.01pt too wide)   <- Jumps backward from line 546 to 121!
  ```
  Instead of progressing downward monotonically through the source file (`99 -> 121 -> 157 -> 304 -> 371 -> 546`), line numbers jump back and forth erratically because severity sorting overrides document order.

### 5.2 Intra-File Line Number Color Flipping (Cyan vs. Blue)
- **Location**: [`lib/leeni/diagnostics.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/diagnostics.rb#L71-L75).
- **Mechanism**:
  ```ruby
  def colorize_line_num(str, base_color = nil)
    return str if @options[:emacs]
    base_color == :cyan ? Rainbow(str).blue.bright.to_s : Rainbow(str).cyan.bright.to_s
  end
  ```
  When `base_color` is `:cyan` (which is assigned to all `Underfull \hbox` items), `colorize_line_num` renders the line number prefix in **Blue** instead of **Cyan**.
- **Manifestation in `42_partitions/partitions.tex`**:
  ```text
  169--171: Underfull \hbox (badness 10000) ...   <- Line number prefix is BLUE (\e[34m)
  169--171: Overfull \hbox (7.46pt too wide) ...   <- Line number prefix is CYAN (\e[38;2;...m)
  ```
  Two adjacent lines with the exact same line number render in two completely different colors, making it appear that line numbers are glitching or mutating mid-stream.

### 5.3 Redundant Range Formatting (`108--108` vs `108`)
- **Location**: [`lib/leeni/diagnostics.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/diagnostics.rb#L509).
- **Mechanism**:
  TeX logs report paragraph-level boxes as `in paragraph at lines 108--108`, but statement-level boxes as `detected at line 125`.
  The parser extracts `line_str = "108--108"` and directly prints it as `108--108:`.
  This causes line representations to mutate arbitrarily between single integers and redundant ranges within the same file.

### 5.4 Multi-Pass Convergence Shifts (Unresolved `??` vs Resolved Citations)
- **Location**: [`lib/leeni/diagnostics.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/diagnostics.rb#L1847-L1853).
- **Mechanism**:
  `find_last_latex_log` reads the log from the latest available pass (`err_xelatex_3`, `_2`, or `_1`).
  On pass 1, references are unresolved (`??`), equations lack numbers, and bibliographies are empty. On pass 3, resolved text expands paragraphs and pushes subsequent lines down.
  If an error or aborted pass leaves an earlier pass log in `junk/`, or if a user checks diagnostics during intermediate passes, box warning lines shift across builds.

### 5.5 TeX Log 79-Column Line-Wrapping Corrupting `file_stack`
- **Location**: [`lib/leeni/diagnostics.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/diagnostics.rb#L20) and [`lib/leeni/diagnostics.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/diagnostics.rb#L407-L431).
- **Mechanism**:
  TeX hard-wraps log lines at 79 columns. When a file inclusion path spans a line break, `LOG_FILE_PATTERN` fails to recognize the file extension on the continuation line, pushing `nil` onto `file_stack`.
  Subsequent closing parentheses `)` pop the stack prematurely, causing `current_log_file` to fall back to `@filename` (`book.tex`) or an earlier chapter.
  As a result, a diagnostic occurring at line 42 of `chapter2.tex` gets attributed to `book.tex:42`, changing both the file and the apparent line number.

---

## 6. Architectural Implementation Steps

### Phase 1: Diagnostic Normalizer & Cleaner
1. **Strict Ascending Line Sorting**:
   - In `sort_diagnostic_items`, sort all warnings and alerts by `[format_display_path(file), line_no, index]`.
   - Never sort overfull boxes by severity at the expense of line order; display alerts/warnings strictly monotonically within each file.
2. **Box Dimension & Line Cleaning**:
   - Strip `\s*(?:detected at line \d+|in paragraph at lines \d+--\d+|in alignment at lines \d+--\d+)`.
   - Round `(\d+\.\d{2})\d*pt` to 2 decimal places (`$1pt`).
   - Simplify identical line ranges: `line_str.sub(/^(\d+)--\1$/, '\1')` (`108--108` $\rightarrow$ `108`).
   - Replace `Overfull \hbox (\S+ too wide)` with `$1 too wide`.
   - Replace `Underfull \hbox \(badness (\d+)\)` with `underfull line (badness $1)`.
3. **Reference & Citation Normalization**:
   - Deduplicate `Hyper reference` and `Reference` records for the same target key and line.
   - Replace `LaTeX Warning: (?:Hyper reference|Reference) \`([^\']+)\' on page (\d+) undefined on input line \d+\.?` with `undefined reference '$1' (page $2)`.
   - Replace `LaTeX Warning: Citation '([^']+)' on page (\d+) undefined on input line \d+\.?` with `undefined citation '$1' (page $2)`.
4. **Duplicate Label Cross-Reference Aggregation**:
   - During cataloging in `lib/leeni/diagnostics.rb`, build a label index: `{ label_name => [ { file: f, line: l }, ... ] }`.
   - When rendering duplicate label warnings, list other target definitions: `also at #{other_locations.map { |loc| "#{loc[:file]}:#{loc[:line]}" }.join(', ')}`.

### Phase 2: Color & Line-Gutter Stabilization
1. **Normalize Warnings Tier Base Color**:
   - Ensure all items in `reg_warns` consistently use `:yellow` (or theme warning color). Do not override box warnings to `:magenta` or `:cyan` inside the warnings tier.
2. **Uniform Gutter Line Number Color**:
   - Keep gutter line numbers consistently in **Cyan** (or theme accent). Deprecate the `base_color == :cyan ? blue : cyan` branch in `colorize_line_num`.
3. **Harmonize Theme Palette**:
   - Define `:magenta` and `:blue` theme pastels in `LatexColor::THEMES` across all themes, or map tier colors strictly within the 4 standard theme tones (`red`, `yellow`, `cyan`, `green`) to eliminate harsh 16-color ANSI drops.
4. **Cohesive File Banners**:
   - Ensure `format_file_separator` styles the filename and count consistently (e.g. bold white/bright with tier-colored brackets) without stripping or resetting mid-line.
5. **Fix Tag / Hint Escape Sequences**:
   - Fix `highlight_leeni_tag` so that ANSI color codes are cleanly reasserted without emitting premature `\e[0m` resets.

### Phase 3: Terminal Link Integration (Regular Display)
1. **Format Location Links**:
   - In `lib/leeni/diagnostics.rb`'s standard human-readable printer, wrap line numbers in OSC 8 escape sequences when `link_enabled?` is active:
     ```ruby
     def format_line_prefix(file, line_str, link_enabled: true)
       return line_str.rjust(10) unless link_enabled

       target_line = line_str[/^\d+/] || '1'
       abs_path = URI::DEFAULT_PARSER.escape(File.expand_path(file))
       uri = "file://#{abs_path}##{target_line}"
       "\e]8;;#{uri}\e\\#{line_str.rjust(10)}\e]8;;\e\\"
     end
     ```
2. **File Banner Links**:
   - Wrap the file path in `── <file> (<count>) ──` with `file://<abs_path>`.

### Phase 4: Robust Log Unwrapping & File Tracking
1. Pre-process TeX logs to rejoin lines broken by TeX's 79-column hard line-wrap before running `track_log_file`.
2. Ensure `file_stack` remains perfectly synchronized so sub-file line numbers are never attributed to root documents or sibling chapters.

### Phase 5: Verification & Quality Gates
1. Add regression test suites:
   - `test/test_diagnostic_formatting.rb`: Verifies regex transformations on box warnings, reference deduplication, duplicate label cross-referencing, monotonic line sorting, and consistent color assignments.
   - `test/test_regular_terminal_links.rb`: Verifies OSC 8 sequences in regular mode when run in simulated PTY.
2. Verify sizing constraints:
   - Keep [`lib/leeni/diagnostics.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/diagnostics.rb) and [`lib/leeni/builder.rb`](file:///home/sariel/prog/26/leeni/lib/leeni/builder.rb) within standards.
   - Run `tools/gate_audit_code`, `tools/bundle --check`, and `tools/gate --medium`.


