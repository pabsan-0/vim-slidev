vim9script

# ── Detection ─────────────────────────────────────────────────────────────────

export def Detect()
    var basename = expand('%:t')->tolower()
    if index(g:slidev_ignored_names, basename) >= 0
        return
    endif

    var strictness = get(g:, 'slidev_strictness', 3)

    if getline(1) !=# '---'
        return
    endif
    if strictness == 1
        Setup()
        return
    endif

    var pkg_path = findfile('package.json', '.;')
    if pkg_path == ''
        return
    endif
    if strictness == 2
        Setup()
        return
    endif

    var pkg_data: dict<any>
    try
        pkg_data = readfile(pkg_path)->join("\n")->json_decode()
    catch
        return
    endtry
    var all_deps = extend(
        copy(get(pkg_data, 'dependencies',    {})),
             get(pkg_data, 'devDependencies', {}))
    var has_slidev = all_deps->keys()->filter((_, k) => k =~# 'slidev') != []
    if !has_slidev
        return
    endif
    if strictness == 3
        Setup()
        return
    endif

    var prettier_names = [
        '.prettierrc', '.prettierrc.json',
        '.prettierrc.yaml', '.prettierrc.yml',
        'prettier.config.js', 'prettier.config.cjs', 'prettier.config.mjs',
    ]
    var pkg_dir = fnamemodify(pkg_path, ':h')
    var cfg_path = ''
    for name in prettier_names
        var candidate = findfile(name, pkg_dir .. ';')
        if candidate != ''
            cfg_path = candidate
            break
        endif
    endfor

    var prettier_data: dict<any> = {}
    if cfg_path != '' && cfg_path !~# '\.js\|\.cjs\|\.mjs'
        try
            prettier_data = readfile(cfg_path)->join("\n")->json_decode()
        catch
        endtry
    elseif has_key(pkg_data, 'prettier')
        prettier_data = pkg_data['prettier']
    endif

    var overrides: list<any> = get(prettier_data, 'overrides', [])
    var has_md_override = false
    for entry in overrides
        var files = get(entry, 'files', [])
        if type(files) == v:t_string
            files = [files]
        endif
        for glob in files
            if glob =~# '\.\(md\|markdown\)'
                has_md_override = true
                break
            endif
        endfor
        if has_md_override
            break
        endif
    endfor

    if !has_md_override
        return
    endif

    Setup()
enddef

# ── Slide-line index ──────────────────────────────────────────────────────────

export def GetSlideLines(): list<number>
    var slides: list<number> = []
    var total = line('$')
    var in_frontmatter = false

    for lnum in range(1, total)
        if getline(lnum) ==# '---'
            if !in_frontmatter
                slides->add(lnum)
                var peek = lnum + 1
                while peek <= total && getline(peek) =~# '^\s*$'
                    peek += 1
                endwhile
                if peek <= total && getline(peek) =~# '^[A-Za-z_][A-Za-z0-9_-]*\s*:'
                    in_frontmatter = true
                endif
            else
                in_frontmatter = false
            endif
        endif
    endfor

    return slides
enddef

# ── Ghost text ────────────────────────────────────────────────────────────────

const PROP_TYPE = 'SlidevSlideNum'

def EnsurePropType()
    if prop_type_get(PROP_TYPE) == {}
        prop_type_add(PROP_TYPE, {highlight: 'SlidevSlideNumHL'})
    endif
enddef

export def UpdateGhostText()
    var buf = bufnr('%')
    var slides = GetSlideLines()
    var total = len(slides)

    prop_remove({type: PROP_TYPE, bufnr: buf, all: true}, 1, line('$'))

    for i in range(total)
        prop_add(slides[i], 0, {
            bufnr:      buf,
            type:       PROP_TYPE,
            text:       $'  ⟨ slide {i + 1} / {total} ⟩',
            text_align: 'after',
        })
    endfor
enddef

# ── Navigation ────────────────────────────────────────────────────────────────

export def GoForward(count: number)
    var slides = GetSlideLines()
    var cur = line('.')
    var ahead = slides->filter((_, v) => v > cur)
    if empty(ahead)
        return
    endif
    cursor(ahead[min([count - 1, len(ahead) - 1])], 1)
    normal! zt
enddef

export def GoBackward(count: number)
    var slides = GetSlideLines()
    var cur = line('.')
    var behind = slides->filter((_, v) => v < cur)
    if empty(behind)
        return
    endif
    cursor(behind[max([len(behind) - count, 0])], 1)
    normal! zt
enddef

export def GoToSlide(num: number)
    var slides = GetSlideLines()
    var total = len(slides)
    if num < 1 || num > total
        echo $'SlidevGoToSlideNum: slide {num} not found (presentation has {total} slides)'
        return
    endif
    cursor(slides[num - 1], 1)
    normal! zt
enddef

# ── Slide editing ─────────────────────────────────────────────────────────────

export def AddSlide()
    var slides = GetSlideLines()
    var cur = line('.')
    var next_slide = 0
    for lnum in slides
        if lnum > cur
            next_slide = lnum
            break
        endif
    endfor
    var insert_at = next_slide > 0 ? next_slide - 1 : line('$')
    append(insert_at, ['', '---', ''])
    cursor(insert_at + 2, 1)
    normal! zt
    UpdateGhostText()
enddef

export def DeleteSlide()
    var slides = GetSlideLines()
    if empty(slides)
        return
    endif
    var cur = line('.')
    var slide_start = 0
    for lnum in slides
        if lnum <= cur
            slide_start = lnum
        endif
    endfor
    if slide_start == 0
        echo 'SlidevDeleteSlide: cursor is not inside a slide'
        return
    endif
    var slide_end = line('$')
    for lnum in slides
        if lnum > slide_start
            slide_end = lnum - 1
            break
        endif
    endfor
    deletebufline('%', slide_start, slide_end)
    UpdateGhostText()
enddef

export def RunDev()
    if !executable('pnpm')
        echohl WarningMsg
        echo 'SlidevRunDev: pnpm not found in PATH'
        echohl None
        return
    endif
    var file = expand('%:p')
    if file == ''
        echohl WarningMsg
        echo 'SlidevRunDev: buffer has no file path'
        echohl None
        return
    endif
    execute 'botright split | terminal pnpm dev ' .. shellescape(file)
enddef

# ── Info ──────────────────────────────────────────────────────────────────────

export def Info()
    var slides = GetSlideLines()
    var total = len(slides)
    var cur = line('.')

    var slide_num = 0
    for i in range(total)
        if slides[i] <= cur
            slide_num = i + 1
        endif
    endfor

    var slide_status = slide_num > 0
        ? $'slide {slide_num} / {total}'
        : $'not in a slide (total: {total})'

    echo $'[Slidev] {slide_status}'
    echo $'  g:slidev_strictness    = {get(g:, "slidev_strictness", 3)}'
    echo $'  g:slidev_ignored_names = {join(g:slidev_ignored_names, ", ")}'
enddef

# ── Single-slide focus ────────────────────────────────────────────────────────

export def FocusSlide()
    if get(b:, 'slidev_focus', false)
        setlocal foldmethod=manual
        normal! zE
        b:slidev_focus = false
        echo '[Slidev] focus off'
        return
    endif

    var slides = GetSlideLines()
    if empty(slides)
        echo '[Slidev] no slides found'
        return
    endif

    var cur = line('.')
    var slide_start = 0
    var slide_end = line('$')

    for lnum in slides
        if lnum <= cur
            slide_start = lnum
        endif
    endfor

    if slide_start == 0
        echo '[Slidev] cursor is not inside a slide'
        return
    endif

    for lnum in slides
        if lnum > slide_start
            slide_end = lnum - 1
            break
        endif
    endfor

    setlocal foldmethod=manual
    normal! zE

    if slide_start > 1
        execute $'1,{slide_start - 1}fold'
    endif
    if slide_end < line('$')
        execute $'{slide_end + 1},{line("$")}fold'
    endif

    b:slidev_focus = true
    normal! zt
    echo '[Slidev] focus on'
enddef

# ── Setup ─────────────────────────────────────────────────────────────────────

export def Setup()
    if hlget('SlidevSlideNumHL', true)->empty()
        highlight default link SlidevSlideNumHL Comment
    endif
    EnsurePropType()

    nnoremap <buffer> ]] <ScriptCmd>GoForward(v:count1)<CR>
    nnoremap <buffer> [[ <ScriptCmd>GoBackward(v:count1)<CR>
    nnoremap <buffer> <leader>s :SlidevGoToSlideNum<Space>
    nnoremap <buffer> <leader>a <ScriptCmd>AddSlide()<CR>
    nnoremap <buffer> <leader>D <ScriptCmd>DeleteSlide()<CR>
    nnoremap <buffer> <leader>R <ScriptCmd>RunDev()<CR>
    nnoremap <buffer> <leader>i <ScriptCmd>Info()<CR>
    nnoremap <buffer> <leader>z <ScriptCmd>FocusSlide()<CR>

    command! -buffer -nargs=1 SlidevGoToSlideNum call slidev#GoToSlide(<args>)
    command! -buffer SlidevRefresh call slidev#UpdateGhostText()
    command! -buffer SlidevInfo call slidev#Info()
    command! -buffer SlidevFocus call slidev#FocusSlide()

    UpdateGhostText()
    augroup SlidevGhost
        autocmd! * <buffer>
        autocmd TextChanged,TextChangedI,BufWritePost <buffer> slidev#UpdateGhostText()
    augroup END

    echo $'[Slidev] mappings active (strictness={get(g:, "slidev_strictness", 3)})'
enddef
