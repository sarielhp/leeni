# Emergency stop: job aborted, no legal \end found

## TeX Output
```text
! Emergency stop.
<*> example.tex

*** (job aborted, no legal \end found)
```

## Explanation
TeX read to the end of the main file without meeting `\end{document}` and stopped the job. The message names no file or line: TeX is back at the command line (`<*>`) when it gives up. The usual causes are a file truncated by an editor, a sync tool or a merge, a deleted `\end{document}`, or an `\endinput` (or an unclosed `\iffalse`) that skips it. `leeni` reports the error at the last line of the main file.

## How to Fix
1. Restore `\end{document}` at the end of the main file.
2. If it is there, look for `\endinput`, an unclosed `\iffalse ... \fi`, or a `comment` environment that is never closed.
3. If the file is shorter than it should be, recover it from version control or a backup.
