# Emergency stop: cannot \read from terminal in nonstop modes

## TeX Output
```text
./example.tex:5: Emergency stop.
<read 2>
         
l.5 \readline\reader to \data
                             
*** (cannot \read from terminal in nonstop modes)
 
./example.tex:5:  ==> Fatal error occurred, no output PDF file produced!
```

## Explanation
`\openin` of a file that does not exist leaves the stream unopened and reports nothing; the following `\readline` then falls back to reading from the terminal, which nonstop mode forbids, so TeX stops with `Emergency stop` and the parenthetical `cannot \read from terminal in nonstop modes`. The document can be perfectly balanced — nothing else in it is wrong. `leeni` reports one error at TeX's line, saying which read failed and why the stream was not open.

## How to Fix
1. Check the file name given to `\openin` (here `no_such_list.txt`).
2. If the file may be absent, test for it: `\openin\reader=file.txt`, then `\ifeof\reader` before the loop and `\fi` around the `\readline`.
