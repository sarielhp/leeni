# LaTeX Error: Float(s) lost

## TeX Output
```text
./example.tex:28: LaTeX Error: Float(s) lost.

See the LaTeX manual or LaTeX Companion for explanation.
Type  H <return>  for immediate help.
 ...

l.28 \end{document}
```

The line TeX names is only where LaTeX *noticed* the loss, usually `\end{document}` or a `\clearpage`, often pages after the cause. The figure that goes missing is often an innocent later one. In the example below the square vanishes and its `\ref` prints `??`, although the mistake is in the rectangle's caption.

## What leeni reports
```text
example.tex:14: error: LaTeX Error: Float(s) lost (hint: a \marginpar (maybe from a macro
such as \todo or a comment macro) starts here inside a box, float or caption, so it never
reaches the page; LaTeX noticed the lost float only at example.tex:28)
```

`leeni` watches, during every build, for a `\marginpar` or float that starts inside a box, and moves the error to that line. When it saw none (an engine or class it cannot watch), the error stays where TeX put it, with a general hint.

## Explanation
A float (`figure`, `table`, ...) or a `\marginpar` can only be placed if it starts in the main text. Started inside a box, it is queued but never reaches the routine that places floats, so LaTeX's float queue falls one step behind. Each later float is then handled one step late, and whatever is still queued at the next `\clearpage` is reported lost. The boxes that cause this include:

- the body or the caption of another float, `[H]` figures included;
- a `minipage`, `\parbox`, `tcolorbox` or other framed box;
- a footnote;
- a `p{...}` table cell.

The culprit is rarely a literal `\marginpar`. It is usually hidden in a macro:

- `\todo` (todonotes) puts its note in the margin with `\marginpar`;
- review and comment macros (`\note`, `\fixme`, an author's initials) often add a margin mark;
- a macro that wraps a figure.

LaTeX does have a check for this (see [Not in outer par mode](../19_not_in_outer_par_mode/)), but it only catches a float in a horizontal box or in math. It misses a paragraph inside a box, which is where captions, minipages and footnotes put their text. Whether a caption trips the check depends on the class: with `singlelinecheck=false` (set by LIPIcs, among others) a caption is never measured in a box, and the mistake surfaces only as "Float(s) lost".

`\FloatBarrier` and `\clearpage` do not help. They flush floats that LaTeX has queued for placement; the lost one never got there.

## How to Fix
The fix can be subtle, because the line that causes the loss may look harmless.

1. Go to the line `leeni` names. If you only have TeX's line, look at the floats and boxes before it, starting with the captions.
2. Look for macros used inside captions, float bodies, minipages and footnotes, especially review macros such as `\todo`. Remove them from there one at a time (or rewrite them, as below) and rebuild: when the error disappears, you have found the macro.
3. Move the `\marginpar` or float out of the box, or make it something that does not float:
   - `\marginnote{...}` (marginnote package) instead of `\marginpar{...}` puts text in the margin anywhere, captions and boxes included;
   - `\todo[inline]{...}` instead of `\todo{...}` inside floats;
   - inside a minipage, use a non-floating figure: `\captionof{figure}{...}` (caption package) instead of `\begin{figure}`.

If the macro is your own, fixing its definition fixes every use at once. In the example, `\note` changes `\marginpar` to `\marginnote` and nothing else.

## Example
The failing document, [`example.tex`](example.tex):

```latex
\documentclass{article}
% Typesets each caption directly rather than measuring it in a box first;
% many classes set it (LIPIcs, for one). LaTeX's own check, which would say
% "Not in outer par mode" at the caption, then never runs.
\usepackage[singlelinecheck=false]{caption}
% A typical review macro: the remark in the text, an arrow in the margin.
\NewDocumentCommand{\note}{m}{\textbf{[#1]}\marginpar{$\Leftarrow$}}
\begin{document}
Some text before the figures.

\begin{figure}[h]
  \centering
  \rule{3cm}{1cm}
  \caption{A rectangle. \note{check the size}}
  \label{fig:rectangle}
\end{figure}

More text, which refers to Figure~\ref{fig:rectangle}.

\begin{figure}[h]
  \centering
  \rule{2cm}{2cm}
  \caption{A square.}
  \label{fig:square}
\end{figure}

The end, after Figure~\ref{fig:square}.
\end{document}
```

The fixed document, [`fixed.tex`](fixed.tex), changes only the preamble:

```latex
\usepackage[singlelinecheck=false]{caption}
% \marginnote puts the arrow in the margin without making a float, so the
% macro works anywhere, captions and boxes included.
\usepackage{marginnote}
\NewDocumentCommand{\note}{m}{\textbf{[#1]}\marginnote{$\Leftarrow$}}
```

The other fix is to keep `\note` as it was and move `\note{check the size}` out of the caption, into the text after the figure.

## See Also
- [Not in outer par mode](../19_not_in_outer_par_mode/): the same mistake when LaTeX catches it at the spot.
