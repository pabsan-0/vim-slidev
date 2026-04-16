vim9script

if !exists('g:slidev_strictness')
    g:slidev_strictness = 3
endif

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

augroup Slidev
    autocmd!
    autocmd BufRead,BufNewFile *.md slidev#Detect()
augroup END
