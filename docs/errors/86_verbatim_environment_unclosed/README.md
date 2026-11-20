# File ended inside a verbatim environment

## TeX Output
```text
! Emergency stop.
<*> example.tex
               
*** (job aborted, no legal \end found)
 
!  ==> Fatal error occurred, no output PDF file produced!
```

## Explanation
`\lstnewenvironment{codetext}[1]{\begin{center}#1}{\end{center}}` opens `center` in the code that runs at `\begin{codetext}`. listings reads an environment body verbatim until the matching `\end{...}` of the environment name it recorded, which is now `center`: `\end{codetext}` no longer ends it, the rest of the file is swallowed, and TeX stops at `\end{document}` with no line. `leeni` reports the environment that was left open, at its `\begin{codetext}` line, with a hint naming `\lstnewenvironment`.

## How to Fix
1. Do not open an environment in the begin code of `\lstnewenvironment`; use the primitive `\center ... \endcenter` or a box (`\par\noindent\parbox{\linewidth}{...}`) instead of `center`.
2. Or write the environment with `\newenvironment` and `\begin{lstlisting}` inside it.
