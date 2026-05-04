vim9script

# Guard lets users set their own values in vimrc before this plugin loads.
if !exists('g:slidev_strictness')
    g:slidev_strictness = 3
endif

# Dev server port used to build the preview URL (Mode A).
if !exists('g:slidev_dev_port')
    g:slidev_dev_port = 3030
endif

# Command template for taking a screenshot of a slide.
# Must contain {url} and {output} placeholders.
# Example: 'brave --headless=new --screenshot={output} --window-size=1920,1080 {url}'
# If unset, the plugin falls back to `pnpm slidev export`.
if !exists('g:slidev_screenshot_cmd')
    g:slidev_screenshot_cmd = ''
endif

# Where the screenshot command writes the image (Mode A) and where chafa reads it from.
if !exists('g:slidev_screenshot_path')
    g:slidev_screenshot_path = '/tmp/slidev-preview/slide.png'
endif

# Common markdown filenames that are documentation, not slidev presentations.
# Lowercased so comparisons in Detect() are case-insensitive.
if !exists('g:slidev_ignored_names')
    g:slidev_ignored_names = [
        'readme.md',
        'contributing.md',
        'license.md',
        'licence.md',
        'changelog.md',
        'changes.md',
        'history.md',
        'authors.md',
        'contributors.md',
        'security.md',
        'support.md',
        'code_of_conduct.md',
        'funding.md',
        'governance.md',
    ]
endif

# SlidevInfo and SlidevEnable are global (not -buffer) so they are reachable
# even in files where the plugin never activated or was disabled.
command! SlidevInfo   call slidev#Info()
command! SlidevEnable call slidev#Enable()

augroup Slidev
    autocmd!
    # autoload: slidev#Detect() is called on every .md open but the autoload
    # file is only sourced the first time, keeping startup cost near zero.
    autocmd BufRead,BufNewFile *.md slidev#Detect()
augroup END
