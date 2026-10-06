# Vim & Neovim Integration with leeni

`leeni` provides first-class support for Vi, Vim, and Neovim through the standard `--compile` flag and the bundled Vim compiler plugin.

---

## Quick Start (Zero-Plugin)

You can use `leeni` directly with Vim's built-in `:make` command without installing any plugins.

In your `~/.vim/after/ftplugin/tex.vim` (or `~/.config/nvim/after/ftplugin/tex.lua`):

### Vimscript (`~/.vim/after/ftplugin/tex.vim`):
```vim
setlocal makeprg=l\ --compile
setlocal errorformat=%f:%l:%c:\ %t%*[^:]:\ %m,%f:%l:\ %t%*[^:]:\ %m,%f:%l:\ %m,%-G%.%#
```

### Lua (`~/.config/nvim/after/ftplugin/tex.lua`):
```lua
vim.opt_local.makeprg = "l --compile"
vim.opt_local.errorformat = "%f:%l:%c: %t%*[^:]: %m,%f:%l: %t%*[^:]: %m,%f:%l: %m,%-G%.%#"
```

Whenever you run `:make` inside a `.tex` file:
* All compilation errors, alerts, and warnings automatically populate the **Quickfix list** (`:copen`).
* Navigating with `:cnext` and `:cprev` jumps directly to the file, line, and column.
* Clean builds complete silently with zero noise.

---

## Compiler Plugin (`docs/vim/compiler/leeni.vim`)

The repository includes a standard Vim compiler script at [`docs/vim/compiler/leeni.vim`](vim/compiler/leeni.vim).

### Installation:
Copy or symlink `docs/vim/compiler/leeni.vim` into your Vim/Neovim compiler directory:
```bash
# Classic Vim
mkdir -p ~/.vim/compiler
cp docs/vim/compiler/leeni.vim ~/.vim/compiler/

# Neovim
mkdir -p ~/.config/nvim/compiler
cp docs/vim/compiler/leeni.vim ~/.config/nvim/compiler/
```

### Usage:
In any LaTeX buffer:
```vim
:compiler leeni
:make
```

---

## Asynchronous Building

### With `tpope/vim-dispatch`:
```vim
:compiler leeni
:Make
```
Compiles in the background without freezing your editor and loads errors into Quickfix when finished.

### With `skywind3000/asynrun.vim`:
```vim
:AsyncRun -program=make l --compile
```

---

## VimTeX Integration

If you use [VimTeX](https://github.com/lervag/vimtex), configure it to use `l` and recognize `junk/` as the build directory:

```vim
let g:vimtex_compiler_method = 'generic'
let g:vimtex_compiler_generic = {
      \ 'command' : 'l --compile',
      \ }
let g:vimtex_build_dir = 'junk'
```

---

## Classic Vi & POSIX vi

In traditional `vi` or `nvi` where Quickfix lists are not present, simply run:

```vim
:!l
```

`leeni` executes directly in a subshell, outputting its clean diagnostic summary before returning to the editor buffer.

