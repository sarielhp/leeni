# Package siunitx Error: Package 'units' incompatible

## TeX Output
```text
/.../siunitx/siunitx.sty:65: Package siun
itx Error: Package 'units' incompatible.

For immediate help type H <return>.
 ...                                              
                                                  
l.65   \__siunitx_load_check:n
                              
/.../siunitx/siunitx.sty:9704: LaTeX cmd 
Error: Command '\unit' already defined.

For immediate help type H <return>.
 ...                                              
                                                  
l.9704   }
          
./example.tex:5: Package siunitx Error: Package 'units' incompatible.

For immediate help type H <return>.
 ...                                              
                                                  
l.5 \begin{document}
                    
```

## Explanation
siunitx refuses to be loaded next to a package that defines the commands it provides. `units` defines `\unit` (and `\unitfrac`), so when `siunitx` loads it raises `Package 'units' incompatible` from inside `siunitx.sty`. The load continues, `siunitx` tries to define `\unit` itself and `\unit` is already defined, and at `\begin{document}` siunitx checks the clash again and repeats its error. All three messages come from the one conflicting package. `leeni` reports a single error, at the `\usepackage{siunitx}` line that loaded it, with a hint naming the package to remove.

## How to Fix
1. Remove the conflicting package: drop `\usepackage{units}` and keep `siunitx`.
2. Write its commands with siunitx: `\unit{\metre}` in place of `\unit{m}`, and `\qty{3}{\metre\per\second}` for a number with a unit (siunitx's `\unit` does not take a number).
