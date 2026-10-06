" Vim compiler file
" Compiler: leeni
" Maintainer: Sariel Har-Peled

if exists("current_compiler")
  finish
endif
let current_compiler = "leeni"

if exists(":CompilerSet") != 2
  command -nargs=* CompilerSet setlocal <args>
endif

CompilerSet makeprg=l\ --compile\ $*

" Universal errorformat matching GNU standard compiler output from leeni --compile:
"   paper.tex:3:1: error: undefined control sequence \foo
"   paper.tex:42: warning: reference `nonexistent' on page 1 undefined
"   paper.tex:85: warning: [alert] label `foo' multiply defined
"   paper.tex:120: note: overfull \hbox (1.5pt too wide) detected
CompilerSet errorformat=
      \%f:%l:%c:\ %t%*[^:]:\ %m,
      \%f:%l:\ %t%*[^:]:\ %m,
      \%f:%l:\ %m,
      \%-G%.%#
