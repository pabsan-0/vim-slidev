# slidev.vim

A Vim9 plugin for editing [Slidev](https://sli.dev) presentations.

## Features

- **Auto-detection** with configurable strictness
- **Navigation** with `<C-n>` / `<C-p>` (count-aware)
- **Ghost text** showing `⟨ slide N / total ⟩` on each separator line
- **Slide editing** — add and delete slides
- **Dev server** — launch `pnpm dev` in a terminal split
- **Preview** — live slide preview via `chafa` in a vertical split (`<leader>P`)

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

" Dev server port (default 3030) — used to build the preview URL in Mode A
g:slidev_dev_port = 3030

" Command for taking a screenshot of a slide (Mode A).
" Must contain {url} (slide URL) and {output} (file path) placeholders.
" Example:
"   let g:slidev_screenshot_cmd = 'brave --headless=new --screenshot={output} --window-size=1920,1080 {url}'
" When unset (default), the plugin falls back to `pnpm slidev export` (Mode B).
g:slidev_screenshot_cmd = ''

" Where Mode A writes the screenshot image (and where chafa reads it from).
" Default: /tmp/slidev-preview/slide.png
g:slidev_screenshot_path = '/tmp/slidev-preview/slide.png'
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
| `<leader>P` | Toggle live slide preview (`:SlidevPreviewToggle`) |

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
| `:SlidevPreviewToggle` | Toggle live slide preview in a vertical split |
| `:SlidevPreviewRefresh` | Force re-render of the current slide in the preview |
| `:SlidevDisable` | Deactivate all Slidev features for the current buffer |

