# Text dropped: no font active (nullfont)

## TeX Output
```text
Missing character: There is no s ("73) in font nullfont!
Missing character: There is no t ("74) in font nullfont!
...
```

## Explanation
Inside a `tikzpicture` no font is active outside nodes, so text written there (stray words, a `;` after a command that does not take one, an `[options]` list separated from its `\begin{tikzpicture}`) is typeset in `nullfont` and dropped. TeX notes each lost character on its own line, with no source line. `leeni` joins a run of these notes into the dropped text, reports it as one error, and finds the line by that text.

## How to Fix
1. Put the text in a `node`, attach the option list to the command it belongs to, or delete the stray characters.
