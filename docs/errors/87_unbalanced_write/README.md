# Unbalanced write command

## TeX Output
```text
[1
./example.tex:20: Emergency stop.
<inserted text> }\endwrite 
                           
l.20 Foo 
         9
Unbalanced write command
 
./example.tex:20:  ==> Fatal error occurred, no output PDF file produced!
```

## Explanation
`\usepackage[french]{babel}` makes `;` an active character, and `\caption{Foo ; bar}` puts it (with its shorthand expansion) into the `.toc` write. The listing that starts on the same page is shipped out while `listings` has the active character turned off, so the `\write` of the caption entry no longer balances its braces: TeX stops with an Emergency stop and prints `Unbalanced write command` only as help text, with no `!` error line of its own. Its `l.20 Foo 9` is the listing text being read at shipout, not the line to change. `leeni` finds the written caption text in the source and reports the fault at the `\caption` line, with a hint naming babel shorthands and `\protect`.

## How to Fix
1. Protect the character in the moving argument: `\caption{Foo \string; bar}` (or `\protect;`), or give the entry explicitly with `\caption[Foo; bar]{Foo ; bar}`.
2. Load `listings` (and similar packages that change catcodes) after `babel`.
