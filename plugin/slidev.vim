vim9script

# Guard lets users set their own values in vimrc before this plugin loads.
if !exists('g:slidev_strictness')
    g:slidev_strictness = 3
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
