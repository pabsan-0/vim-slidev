# slidev.vim

A Vim9 plugin for editing [Slidev](https://sli.dev) presentations.

Slidev is a neat tool for crafting slides, yet its `.md` files usually end up being ~1k lines of mixed markdown, code blocks and glue HTML, making them really hard to grasp. This plugin makes for easier navigation and tweaking with a bit of ghost text plus a few, non-intrusive, mappings.


<img style="height: 320px" src="./.doc/demo.gif"/>

## Features 

- **Filetype auto-detection** based on context with configurable strictness (package.json)
- **Navigation** with `<C-n>` / `<C-p>` (count-aware)
- **Ghost text** showing separators and slide numbers
- **Slide editing** — add and delete slides, tweak links
<!-- - **Dev server** — launch `pnpm dev` in a terminal split -->

## Installation

With [vim-plug](https://github.com/junegunn/vim-plug):
```vim
Plug 'pabsan-0/vim-slidev'
```

Or manually, clone into `~/.vim/pack/plugins/start/vim-slidev`.

## Configuration

```vim
" Slidev filetype detection strictness (1–4, default 3) 
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
| `<leader>z` | Toggle single-slide focus view (`:SlidevFocus`) |
| `<leader>R` | Run `pnpm dev %` in a terminal split |
| `<leader>l` | Wrap the current WORD or visual selection into a link `md` tag |
| `<leader>L` | Move all links in the slide to the bottom |
| `<leader>d` | Wrap selection in a multiline HTML comment |

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
| `:SlidevRunDev` | Run development `slidev` server via `pnpm` |
| `:SlidevRefresh` | Refresh ghost text (Already wrapped on autocmd) |
| `:SlidevFocus` | Toggle single-slide focus (folds other slides away) |
| `:SlidevDisable` | Deactivate all Slidev features for the current buffer |
| `:SlidevDigestLinks` | Move all links in the slide to the bottom |
| `:SlidevConvertToLink` | Spawn empty, or wrap selection in multiline HTML comment |

