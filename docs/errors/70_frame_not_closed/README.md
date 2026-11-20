# File ended while scanning use of \beamer@collect@@body

## TeX Output
```text
! File ended while scanning use of \beamer@collect@@body.
```

## Explanation
A beamer `frame` reads its whole body as an argument, up to its `\end{frame}`. When that `\end{frame}` is missing, TeX reads to the end of the file and stops with no line number, naming only the internal macro that collects the body. `tabularx` (`\TX@get@body`) and `environ`-based environments fail the same way. `leeni` reports the error at the `\begin` that is never closed.

## How to Fix
1. Add the missing `\end{frame}` (or `\end{tabularx}`, ...) where the environment should end.
