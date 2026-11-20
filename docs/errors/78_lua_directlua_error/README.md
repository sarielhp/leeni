# Lua error in \directlua

## TeX Output
```text
[\directlua]:1: unexpected symbol near '\'.
l.6 \directlua{tex.print("hello")}
```

## Explanation
`\directlua` passes its argument through TeX before Lua reads it: macros are expanded and active characters are replaced. Here csquotes has made `"` active, so the Lua code receives a quotation macro instead of a string delimiter. LuaTeX names the error by its Lua chunk, `[\directlua]`, line 1 of the code, and may print it on the same line as the files it has just opened; `leeni` reports it at the TeX line that ran the code (`l.6`).

## How to Fix
1. Put the code in a `luacode` environment (`\usepackage{luacode}`), which reads it verbatim.
2. Or keep the code in a `.lua` file and load it with `\directlua{dofile("code.lua")}`.
