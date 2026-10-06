# Demystifying Underfull Boxes in LaTeX (`\hbox` and `\vbox`)

A plain-English guide to understanding, diagnosing, and fixing one of LaTeX's most baffling compiler messages: **`Underfull \hbox (badness 10000)`** and **`Underfull \vbox (badness 10000)`**.

---

## 1. The Horror at Line 256

You run `leeni` (or `pdflatex`), and the compiler reports:

```text
256: Note: underfull \hbox (badness 10000)
```

You open line 256 in your editor. There are no typos, no missing braces, no broken macros, and the PDF even renders without crashing. You wonder:

> *"What on earth is an underfull box, what is badness, and why is it 10,000?!"*

### The Plain-English Translation

- **`\hbox`** stands for **Horizontal Box**. In 99% of documents, an `\hbox` is just **a single line of text** across a paragraph or column (or a cell inside a table).
- **`Underfull`** means the text on that line did not have enough words to reach the right margin, so TeX had to stretch the spaces between words.
- **`badness 10000`** is TeX's maximum penalty score ($10\,000 = \infty$). It means **TeX had to stretch the spacing to infinity**, almost always because it was forced to justify a line that has **zero words** on it.

---

## 2. The Mental Model: Rigid Boxes and Springy Glue

TeX does not typeset characters onto a fixed word-processor grid. Instead, TeX thinks in terms of **rigid boxes** (words) connected by **springy glue** (the whitespace between words):

```
┌───────┐      ┌──────────────┐      ┌────────┐
│ Hello │ ~~~~ │ springy      │ ~~~~ │ world! │
└───────┘ glue └──────────────┘ glue └────────┘
|<────────────────── Column Width (\hsize) ──────────────────>|
```

When TeX justifies a line across the column width (`\hsize`), it measures how far the springs had to stretch beyond their natural comfort level:

| Badness ($b$) | Meaning | What You See |
| :--- | :--- | :--- |
| **$0$** | Natural width | Perfect, natural spacing. |
| **$1 \le b \le 100$** | Slight stretch | Flawless typography; completely imperceptible. |
| **$100 < b < 1000$** | Moderate stretch | Acceptable in narrow columns. |
| **$b \ge 1000$** | Exceeds `\hbadness` | TeX logs an `Underfull \hbox` notice. |
| **$b = 10\,000$** | **Infinite stretch ($\infty$)** | Maximum alarm: TeX was forced to stretch empty space! |

### Why Normal Paragraphs Don't Complain

In a normal paragraph, the last line almost never reaches the right margin. Why doesn't TeX complain about every single paragraph ending?

Because whenever a paragraph ends normally (via an empty line or `\par`), TeX automatically adds an invisible infinite spring called **`\parfillskip`**:
```latex
\parfillskip = 0pt plus 1fil
```
This infinite spring absorbs all the leftover whitespace on the right, allowing the last line to end naturally at ragged-right.

**`badness 10000` happens when you force a line break in a way that creates an empty line without `\parfillskip`.**

---

## 3. The 5 Real-World Traps (With Verified Reproducers)

Every example below has been tested and verified against TeX engines.

---

### Trap 1: Trailing `\\` Before a Blank Line (The #1 Beginner Trap)

In Microsoft Word or Markdown, you hit Enter to start a new paragraph. Beginners often think LaTeX requires `\\` to break the line *and* an empty line to start a new paragraph.

- **Reproducer**: [`01_trailing_backslash_bad.tex`](01_trailing_backslash_bad.tex)
- **Solution**: [`01_trailing_backslash_good.tex`](01_trailing_backslash_good.tex)

```latex
% ❌ FAULTY CODE (01_trailing_backslash_bad.tex):
\documentclass{article}
\begin{document}
This is the conclusion of our first thought.\\

This is the start of the next thought.
\end{document}
```

#### What TeX Saw:
1. `\\` forced an immediate line break.
2. The empty line triggered `\par` (end of paragraph).
3. Between the `\\` and the `\par`, TeX created a **ghost line with zero words**!
4. TeX tried to stretch that zero-word line across the margin $\rightarrow$ **`badness 10000`**.

#### The Fix:
**Delete the `\\`.** In LaTeX, a blank line alone is the canonical way to start a new paragraph.

```latex
% ✔ FIXED CODE (01_trailing_backslash_good.tex):
\documentclass{article}
\begin{document}
This is the conclusion of our first thought.

This is the start of the next thought.
\end{document}
```

---

### Trap 2: Double Backslash (`\\\\`) for Vertical Space

When authors want an extra gap between paragraphs, they often type `\\\\`.

- **Reproducer**: [`02_double_backslash_bad.tex`](02_double_backslash_bad.tex)
- **Solution**: [`02_double_backslash_good.tex`](02_double_backslash_good.tex)

```latex
% ❌ FAULTY CODE (02_double_backslash_bad.tex):
\documentclass{article}
\begin{document}
This is the first sentence.\\\\
This is the second sentence.
\end{document}
```

#### What TeX Saw:
- The first `\\` broke the line.
- The second `\\` immediately broke an empty line.
- An empty line forced to justify $\rightarrow$ **`badness 10000`**.

#### The Fix:
Never use `\\\\` for vertical space. Use standard paragraph breaks or `\vspace`:

```latex
% ✔ FIXED CODE (02_double_backslash_good.tex):
\documentclass{article}
\begin{document}
This is the first sentence.

This is the second sentence.
\end{document}
```
*(If extra gap is needed, use `\par\vspace{\bigskipamount}` or `\medskip`.)*

---

### Trap 3: Trailing `\\` Before `\end{...}`

In environments like `quote`, `minipage`, or theorems, lines are often separated by `\\`. Authors frequently leave a trailing `\\` on the very last line:

- **Reproducer**: [`03_environment_end_bad.tex`](03_environment_end_bad.tex)
- **Solution**: [`03_environment_end_good.tex`](03_environment_end_good.tex)

```latex
% ❌ FAULTY CODE (03_environment_end_bad.tex):
\documentclass{article}
\begin{document}
\begin{quote}
  First line of quotation.\\
  Second line of quotation.\\
\end{quote}
\end{document}
```

#### What TeX Saw:
`\end{quote}` internally issues a `\par` to close the quotation. The trailing `\\` created a ghost line right before `\par` $\rightarrow$ **`badness 10000`**.

#### The Fix:
Remove `\\` from the final line of the environment:

```latex
% ✔ FIXED CODE (03_environment_end_good.tex):
\documentclass{article}
\begin{document}
\begin{quote}
  First line of quotation.\\
  Second line of quotation.
\end{quote}
\end{document}
```

---

### Trap 4: `\linebreak` on a Short Line

LaTeX provides two different break commands:

| Command | Behavior | What Happens on a Short Line |
| :--- | :--- | :--- |
| `\\` or `\newline` | Breaks line and fills the remainder with ragged-right space (`\hfil`). | Clean ragged-right line. |
| `\linebreak` | Breaks line **AND forces full justification** across the margin. | Words get stretched all the way across the page! |

- **Reproducer**: [`04_linebreak_bad.tex`](04_linebreak_bad.tex)
- **Solution**: [`04_linebreak_good.tex`](04_linebreak_good.tex)

```latex
% ❌ FAULTY CODE (04_linebreak_bad.tex):
\documentclass{article}
\begin{document}
Short line.\linebreak
This is the next sentence that follows.
\end{document}
```

#### What TeX Saw:
`\linebreak` forced two words (`Short line.`) to justify across the full page width $\rightarrow$ **`badness 10000`**.

#### The Fix:
Replace `\linebreak` with `\newline`:

```latex
% ✔ FIXED CODE (04_linebreak_good.tex):
\documentclass{article}
\begin{document}
Short line.\newline
This is the next sentence that follows.
\end{document}
```

---

### Trap 5: `Underfull \vbox (badness 10000)` Under `\flushbottom`

While an `\hbox` is a horizontal line of text, a **`\vbox`** is a vertical page or column container:

```text
Warning: underfull \vbox (badness 10000) has occurred while \output is active [1]
```

- **Reproducer**: [`05_vbox_flushbottom_bad.tex`](05_vbox_flushbottom_bad.tex)
- **Solution**: [`05_vbox_flushbottom_good.tex`](05_vbox_flushbottom_good.tex)

```latex
% ❌ FAULTY CODE (05_vbox_flushbottom_bad.tex):
\documentclass{book}
\flushbottom
\begin{document}
Short paragraph on page 1.

Another short paragraph on page 1.

\pagebreak
This is page 2.
\end{document}
```

#### What TeX Saw:
1. Two-sided book classes enable `\flushbottom` by default, requiring the bottom of every page to hit the exact same vertical baseline.
2. `\pagebreak` asks TeX to break the page **and stretch vertical glue across the whole height**.
3. With only two short paragraphs, the vertical glue had to stretch to infinity $\rightarrow$ **`badness 10000`**.

#### The Fix:
- Use `\newpage` (or `\clearpage`) instead of `\pagebreak` so the short page is ragged-bottom:
  ```latex
  % ✔ FIXED CODE (05_vbox_flushbottom_good.tex):
  \newpage
  ```
- Or add `\raggedbottom` to your preamble to allow all pages to end naturally without vertical distortion.

---

## 4. Underfull `\hbox` with Finite Badness ($< 10000$)

When TeX reports a number like `badness 2350`, the line is not empty—it is just **loose**:

```text
88: Note: underfull \hbox (badness 2350)
```

This happens in narrow columns (e.g. two-column papers or `p{3cm}` table cells) when TeX cannot find a hyphenation point for a long word.

### Actionable Fixes:
1. **Discretionary Hyphens (`\-`)**: Insert `\-` inside technical or compound words to give TeX permission to hyphenate (e.g. `multi\-di\-men\-sion\-al`).
2. **`sloppypar`**: Wrap the tricky paragraph in `\begin{sloppypar}...\end{sloppypar}` to relax whitespace thresholds locally.
3. **`\raggedright`**: For narrow table columns or sidebars, disable full justification.
4. **Reword Text**: Adding or removing a word often resolves the line break naturally.

---

## 5. Quick Decision Table

| What You See | Likely Cause | Fix |
| :--- | :--- | :--- |
| `underfull \hbox (badness 10000)` | Trailing `\\` before an empty line | Delete the `\\` at the end of the line. |
| `underfull \hbox (badness 10000)` | Double `\\\\` | Replace `\\\\` with an empty line or `\vspace`. |
| `underfull \hbox (badness 10000)` | Trailing `\\` in `quote` / `minipage` | Remove `\\` from the final row before `\end{...}`. |
| `underfull \hbox (badness 10000)` | `\linebreak` on a short line | Replace `\linebreak` with `\newline`. |
| `underfull \hbox (badness 1000..9000)` | Narrow column / unhyphenated word | Add `\-` to long words or wrap in `sloppypar`. |
| `underfull \vbox (badness 10000)` | `\pagebreak` under `\flushbottom` | Replace `\pagebreak` with `\newpage` or use `\raggedbottom`. |
