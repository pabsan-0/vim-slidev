# slidev.vim

A Vim9 plugin for editing [Slidev](https://sli.dev) presentations.

## Features

- **Auto-detection** with configurable strictness
- **Navigation** with `<C-n>` / `<C-p>` (count-aware)
- **Ghost text** showing `⟨ slide N / total ⟩` on each separator line
- **Slide editing** — add and delete slides
- **Dev server** — launch `pnpm dev` in a terminal split

## Installation

With [vim-plug](https://github.com/junegunn/vim-plug):
```vim
Plug 'pabsan-0/vim-slidev'
```

Or manually, clone into `~/.vim/pack/plugins/start/vim-slidev`.

## Configuration

```vim
" Detection strictness (1–4, default 3)
g:slidev_strictness = 3

" Filenames never treated as Slidev files (case-insensitive basenames)
g:slidev_ignored_names += ['notes.md']
```

See `:help slidev` for full documentation.

## Mappings

| Mapping | Action |
|---|---|
| `<C-n>` / `<C-p>` | Next / prev slide (count-aware) |
| `<leader>s` | `:SlidevGoToSlideNum` prompt |
| `<leader>a` | Add slide after current |
| `<leader>D` | Delete current slide |
| `<leader>R` | Run `pnpm dev %` in a terminal split |
| `<leader>i` | Print slide info (`:SlidevInfo`) |
| `<leader>z` | Toggle single-slide focus view (`:SlidevFocus`) |

## Commands

**Always available (any buffer):**

| Command | Action |
|---|---|
| `:SlidevInfo` | Show slide position, all strictness levels, and variable values |
| `:SlidevEnable` | Activate Slidev in the current buffer (bypasses detection) |

**Buffer-local (active Slidev buffers only):**

| Command | Action |
|---|---|
| `:SlidevGoToSlideNum {n}` | Jump to slide n |
| `:SlidevRefresh` | Refresh ghost text |
| `:SlidevFocus` | Toggle single-slide focus (folds other slides away) |
| `:SlidevDisable` | Deactivate all Slidev features for the current buffer |

