vim9script

# ── Detection ─────────────────────────────────────────────────────────────────

export def Detect()
    # Respect an explicit opt-out set by :SlidevDisable so re-entering the
    # buffer (e.g. switching windows) never re-activates the plugin.
    if get(b:, 'slidev_disabled', false)
        return
    endif
    # Compare lowercased filename against the ignored list so the check is
    # case-insensitive on all platforms.
    var basename = expand('%:t')->tolower()
    if index(g:slidev_ignored_names, basename) >= 0
        return
    endif

    var strictness = get(g:, 'slidev_strictness', 3)

    # Level 1 gate: every slidev presentation starts with a YAML front-matter
    # opener on line 1.  Files that don't have it are skipped immediately.
    if getline(1) !=# '---'
        return
    endif
    if strictness == 1
        Setup()
        return
    endif

    # Level 2 gate: a package.json must exist somewhere up the directory tree.
    # The '.;' search path makes findfile() walk upward from cwd.
    var pkg_path = findfile('package.json', '.;')
    if pkg_path == ''
        return
    endif
    if strictness == 2
        Setup()
        return
    endif

    # Level 3 gate: the package.json must actually list a slidev package.
    # We merge dependencies and devDependencies so either location counts.
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

    # Level 4 gate: a prettier config with a *.md override exists, which is
    # the pattern Slidev's own scaffolding generates.  We check all standard
    # prettier config filenames; JS variants are skipped because we cannot
    # safely execute them to read their contents.
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
        # Parse a standalone JSON/YAML prettier config file.
        try
            prettier_data = readfile(cfg_path)->join("\n")->json_decode()
        catch
        endtry
    elseif has_key(pkg_data, 'prettier')
        # Fall back to an inline "prettier" key inside package.json.
        prettier_data = pkg_data['prettier']
    endif

    var overrides: list<any> = get(prettier_data, 'overrides', [])
    var has_md_override = false
    for entry in overrides
        var files = get(entry, 'files', [])
        # The 'files' field can be a string or a list; normalise to list.
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
    # Track whether we are inside a YAML front-matter block so the closing
    # '---' is not mistaken for a slide separator.
    var in_frontmatter = false

    for lnum in range(1, total)
        if getline(lnum) ==# '---'
            if !in_frontmatter
                slides->add(lnum)
                # Peek ahead past blank lines to check for a YAML key on the
                # next non-blank line ('key:' pattern).  If found, this '---'
                # opened a front-matter block rather than a slide separator.
                var peek = lnum + 1
                while peek <= total && getline(peek) =~# '^\s*$'
                    peek += 1
                endwhile
                if peek <= total && getline(peek) =~# '^[A-Za-z_][A-Za-z0-9_-]*\s*:'
                    in_frontmatter = true
                endif
            else
                # This '---' closes the front-matter block; the next '---'
                # will be treated as a slide separator again.
                in_frontmatter = false
            endif
        endif
    endfor

    return slides
enddef

# ── Ghost text ────────────────────────────────────────────────────────────────

const PROP_TYPE = 'SlidevSlideNum'

def EnsurePropType()
    # prop_type_add() errors if the type already exists, so guard with a check.
    if prop_type_get(PROP_TYPE) == {}
        prop_type_add(PROP_TYPE, {highlight: 'SlidevSlideNumHL'})
    endif
enddef

export def UpdateGhostText()
    var buf = bufnr('%')
    var slides = GetSlideLines()
    var total = len(slides)

    # Wipe all existing annotations before redrawing so edits that add or
    # remove '---' lines don't leave stale slide numbers behind.
    prop_remove({type: PROP_TYPE, bufnr: buf, all: true}, 1, line('$'))

    for i in range(total)
        # col 0 means the text is appended after the last character on the line.
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
    # Clamp so a count larger than the number of remaining slides lands on the
    # last one rather than indexing out of bounds.
    cursor(ahead[min([count - 1, len(ahead) - 1])], 1)
    # Scroll the separator to the top so slide content is immediately visible.
    normal! zt
enddef

export def GoBackward(count: number)
    var slides = GetSlideLines()
    var cur = line('.')
    var behind = slides->filter((_, v) => v < cur)
    if empty(behind)
        return
    endif
    # max(..., 0) prevents a negative index when count exceeds available slides.
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
    # slides[] is 0-based; slide numbers shown to the user are 1-based.
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
    # Insert blank + separator + blank just before the next slide, or at the
    # very end of the file when the cursor is on the last slide.
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
    # Find the last separator at or above the cursor — that is the start of the
    # current slide.
    for lnum in slides
        if lnum <= cur
            slide_start = lnum
        endif
    endfor
    if slide_start == 0
        echo 'SlidevDeleteSlide: cursor is not inside a slide'
        return
    endif
    # Default end is the last line; the next separator (exclusive) overrides it.
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
    # package.json must exist: it defines the project root and the pnpm workspace.
    # Without it there is no meaningful directory to run the dev server from.
    var pkg_path = findfile('package.json', '.;')
    if pkg_path == ''
        echohl WarningMsg
        echo 'SlidevRunDev: no package.json found up the directory tree'
        echohl None
        return
    endif
    if !executable('pnpm')
        echohl WarningMsg
        echo 'SlidevRunDev: pnpm not found in PATH'
        echohl None
        return
    endif
    var file_abs = expand('%:p')
    if file_abs == ''
        echohl WarningMsg
        echo 'SlidevRunDev: buffer has no file path'
        echohl None
        return
    endif

    var pkg_dir = fnamemodify(pkg_path, ':p:h')
    # Slidev expects the entry file relative to the project root (package.json dir).
    # Strip the leading project-root prefix so the path is portable.
    var rel_file = file_abs
    if stridx(file_abs, pkg_dir) == 0
        rel_file = file_abs[len(pkg_dir) + 1 :]
    endif

    # 'botright terminal' opens exactly one new full-width window at the bottom.
    # 'botright split | terminal' first duplicates the current buffer in a new
    # split and then opens terminal there, which produces three windows.
    # '++cwd' sets the terminal's working directory to the project root so that
    # pnpm resolves dependencies from the correct node_modules.
    execute 'botright terminal ++cwd=' .. shellescape(pkg_dir)
        .. ' pnpm dev ' .. shellescape(rel_file)
enddef

# ── Info ──────────────────────────────────────────────────────────────────────

# Static table used both for display and as the authoritative list of levels.
const STRICTNESS_LEVELS = [
    [1, 'first line is exactly `---`'],
    [2, 'package.json found up the directory tree'],
    [3, 'package.json lists a slidev dependency (default)'],
    [4, 'prettier config has a *.md override'],
]

export def Info()
    var active   = get(b:, 'slidev_active',   false)
    var disabled = get(b:, 'slidev_disabled',  false)
    var strictness = get(g:, 'slidev_strictness', 3)

    var slide_status: string
    if disabled
        # Skip GetSlideLines() entirely when disabled — the buffer should be
        # treated as if the plugin never ran on it.
        slide_status = 'n/a (disabled)'
    else
        var slides = GetSlideLines()
        var total = len(slides)
        var cur = line('.')
        var slide_num = 0
        for i in range(total)
            if slides[i] <= cur
                slide_num = i + 1
            endif
        endfor
        slide_status = slide_num > 0
            ? $'slide {slide_num} / {total}'
            : $'not in a slide (total: {total})'
    endif

    var msg = $"[Slidev] {slide_status}  (active: {active})\n"
    msg ..= $"\nAuto-enable detection levels (g:slidev_strictness):\n"
    for [lvl, desc] in STRICTNESS_LEVELS
        var marker = lvl == strictness ? ' ◀ current' : ''
        msg ..= $"  {lvl}  {desc}{marker}\n"
    endfor
    msg ..= $"\ng:slidev_strictness    = {strictness}"
    msg ..= $"\ng:slidev_ignored_names = {join(get(g:, 'slidev_ignored_names', []), ', ')}"
    # A single multi-line echo triggers Vim's built-in "Press ENTER" prompt,
    # giving a proper blocking output without needing :more or :echomsg tricks.
    echo msg
enddef

# ── Single-slide focus ────────────────────────────────────────────────────────

export def FocusSlide()
    if get(b:, 'slidev_focus', false)
        # Restore the foldmethod that was active before focus mode was entered.
        execute $'setlocal foldmethod={get(b:, "slidev_prev_foldmethod", "manual")}'
        # zE deletes all folds so the restored foldmethod starts from a clean
        # slate (avoids leftover manual folds when switching to e.g. 'indent').
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

    b:slidev_prev_foldmethod = &l:foldmethod
    setlocal foldmethod=manual
    # zE clears any pre-existing folds before we create the two surrounding ones.
    normal! zE

    # Fold everything before the current slide and everything after it.
    # The ':' prefix before the range is required in Vim9script (E1050).
    if slide_start > 1
        execute $':1,{slide_start - 1}fold'
    endif
    if slide_end < line('$')
        execute $':{slide_end + 1},{line("$")}fold'
    endif

    b:slidev_focus = true
    normal! zt
    echo '[Slidev] focus on'
enddef

# ── Snippets ──────────────────────────────────────────────────────────────────

# Map common file extensions to fenced-code-block language identifiers.
def ExtToLang(ext: string): string
    var map: dict<string> = {
        c: 'c', h: 'c', cpp: 'cpp', cc: 'cpp', cxx: 'cpp', hpp: 'cpp',
        cs: 'csharp', fs: 'fsharp',
        go: 'go', rs: 'rust', swift: 'swift', kt: 'kotlin',
        java: 'java', scala: 'scala', groovy: 'groovy',
        js: 'javascript', ts: 'typescript', jsx: 'jsx', tsx: 'tsx',
        mjs: 'javascript', cjs: 'javascript',
        py: 'python', rb: 'ruby', lua: 'lua', php: 'php', pl: 'perl',
        sh: 'bash', bash: 'bash', zsh: 'bash', fish: 'fish', ps1: 'powershell',
        html: 'html', css: 'css', scss: 'scss', sass: 'sass', less: 'less',
        json: 'json', yaml: 'yaml', yml: 'yaml', toml: 'toml', xml: 'xml',
        md: 'markdown', sql: 'sql', vim: 'vim', r: 'r', dart: 'dart',
        ex: 'elixir', exs: 'elixir', erl: 'erlang', hs: 'haskell',
        tf: 'hcl', hcl: 'hcl', proto: 'protobuf', graphql: 'graphql',
    }
    return get(map, ext, ext)
enddef

# Resolve a Slidev snippet reference (@/... or ./... or bare path) to an
# absolute file path.  Returns '' when the file cannot be found.
def ResolveSnippetRef(ref: string): string
    var md_dir = expand('%:p:h')
    if ref =~# '^@/'
        # '@/' is the Vite/Slidev project root (where package.json lives).
        # Fall back to the md's directory when no package.json is found.
        var rel = ref[2 :]
        var pkg_path = findfile('package.json', '.;')
        if pkg_path != ''
            var candidate = fnamemodify(pkg_path, ':p:h') .. '/' .. rel
            if filereadable(candidate)
                return candidate
            endif
        endif
        var candidate = md_dir .. '/' .. rel
        return filereadable(candidate) ? candidate : ''
    elseif ref =~# '^\.'
        return md_dir .. '/' .. ref
    else
        return md_dir .. '/' .. ref
    endif
enddef

# Extract the fenced code block the cursor is in (or on its delimiters) to a
# file under snippets/ and replace the block with a <<< @/snippets/<file>
# reference.  Accepts an optional filename; when omitted the user is prompted.
export def SnippetExtract(fname_arg: string = '')
    var cur    = line('.')
    var total  = line('$')

    # Walk backward to find the nearest opening fence (``` or ~~~).
    var fence_open = 0
    var fence_pat  = ''
    for lnum in range(cur, 1, -1)
        var lc = getline(lnum)
        if lc =~# '^```'
            fence_open = lnum
            fence_pat  = '```'
            break
        elseif lc =~# '^~~~'
            fence_open = lnum
            fence_pat  = '~~~'
            break
        endif
    endfor

    if fence_open == 0
        echohl WarningMsg
        echo '[Slidev] cursor is not inside a fenced code block'
        echohl None
        return
    endif

    # Walk forward from the opening fence to find the closing fence.
    var fence_close = 0
    for lnum in range(fence_open + 1, total)
        if getline(lnum) =~# '^' .. fence_pat .. '\s*$'
            fence_close = lnum
            break
        endif
    endfor

    if fence_close == 0
        echohl WarningMsg
        echo '[Slidev] could not find the closing fence'
        echohl None
        return
    endif

    # Reject if the cursor is outside [fence_open, fence_close].
    if cur > fence_close
        echohl WarningMsg
        echo '[Slidev] cursor is not inside a fenced code block'
        echohl None
        return
    endif

    # Extract language specifier from the opening fence line.
    var lang = getline(fence_open)->matchstr('^' .. fence_pat .. '\s*\zs\S*')

    # Lines between the fences (exclusive) are the snippet content.
    var code_lines = getline(fence_open + 1, fence_close - 1)

    # Determine the filename: use the argument, or ask the user.
    var fname = fname_arg
    if fname == ''
        fname = input('Snippet filename: ')
    endif
    if fname == ''
        return
    endif

    # Write the snippet to snippets/<fname>, relative to the .md file.
    var snippets_dir = expand('%:p:h') .. '/snippets'
    if !isdirectory(snippets_dir)
        mkdir(snippets_dir, 'p')
    endif
    var full_path = snippets_dir .. '/' .. fname
    writefile(code_lines, full_path)

    # Replace the fenced block with a Slidev snippet reference.
    deletebufline('%', fence_open, fence_close)
    append(fence_open - 1, '<<< @/snippets/' .. fname)

    UpdateGhostText()
    echo '[Slidev] snippet extracted → snippets/' .. fname
enddef

# Inline a <<< @/... snippet reference back as a fenced code block.
# When bang is true the snippet file is deleted after inlining.
export def SnippetInline(bang: bool)
    var cur = line('.')
    var lc  = getline(cur)

    # Match both <<< @/path and <<< ./path forms.
    var ref = lc->matchstr('^<<<\s\+\zs[^[:space:]].*')
    if ref == ''
        echohl WarningMsg
        echo '[Slidev] current line is not a snippet reference (<<< @/... or <<< ./...)'
        echohl None
        return
    endif

    var snippet_path = ResolveSnippetRef(ref)
    if snippet_path == '' || !filereadable(snippet_path)
        echohl WarningMsg
        echo '[Slidev] snippet file not found: ' .. ref
        echohl None
        return
    endif

    var lang        = ExtToLang(fnamemodify(snippet_path, ':e'))
    var code_lines  = readfile(snippet_path)
    var replacement = ['```' .. lang] + code_lines + ['```']

    deletebufline('%', cur)
    append(cur - 1, replacement)

    if bang
        delete(snippet_path)
        echo '[Slidev] snippet inlined and ' .. fnamemodify(snippet_path, ':t') .. ' deleted'
    else
        echo '[Slidev] snippet inlined from ' .. fnamemodify(snippet_path, ':t')
    endif

    UpdateGhostText()
enddef

# ── Enable / Disable ──────────────────────────────────────────────────────────

export def Disable()
    # In Vim9script, special key sequences like ]] and [[ are not parsed
    # correctly when written inline in a nunmap statement.  Wrapping them as
    # strings inside execute() is the reliable approach.  silent! absorbs the
    # error when a mapping does not exist (e.g. called on an un-setup buffer).
    silent! execute 'nunmap <buffer> ]]'
    silent! execute 'nunmap <buffer> [['
    silent! execute 'nunmap <buffer> <leader>s'
    silent! execute 'nunmap <buffer> <leader>a'
    silent! execute 'nunmap <buffer> <leader>D'
    silent! execute 'nunmap <buffer> <leader>R'
    silent! execute 'nunmap <buffer> <leader>i'
    silent! execute 'nunmap <buffer> <leader>z'
    silent! execute 'nunmap <buffer> <leader>xe'
    silent! execute 'nunmap <buffer> <leader>xi'

    # -buffer is required to delete buffer-local commands; without it
    # delcommand would look for (and fail to find) a global command.
    silent! execute 'delcommand -buffer SlidevGoToSlideNum'
    silent! execute 'delcommand -buffer SlidevRefresh'
    silent! execute 'delcommand -buffer SlidevFocus'
    silent! execute 'delcommand -buffer SlidevDisable'
    silent! execute 'delcommand -buffer SlidevSnippetExtract'
    silent! execute 'delcommand -buffer SlidevSnippetInline'

    # Remove ghost-text annotations that prop_add() left on the separator lines.
    var buf = bufnr('%')
    prop_remove({type: PROP_TYPE, bufnr: buf, all: true}, 1, line('$'))

    # Clear the autocmd that would otherwise re-run UpdateGhostText() on edits.
    autocmd! SlidevGhost * <buffer>

    b:slidev_active   = false
    # Mark the buffer so Detect() skips it on the next BufRead/BufEnter.
    b:slidev_disabled = true
    echo '[Slidev] disabled'
enddef

export def Enable()
    # Clear the opt-out flag first so Setup() — and any future Detect() call —
    # can activate normally.
    b:slidev_disabled = false
    Setup()
enddef

# ── Setup ─────────────────────────────────────────────────────────────────────

export def Setup()
    # Only define the highlight group if the user has not already customised it.
    if hlget('SlidevSlideNumHL', true)->empty()
        highlight default link SlidevSlideNumHL Comment
    endif
    EnsurePropType()

    # <ScriptCmd> keeps the execution context inside this script so function
    # names resolve without a prefix; <Cmd> would require the full slidev# path.
    nnoremap <buffer> ]] <ScriptCmd>GoForward(v:count1)<CR>
    nnoremap <buffer> [[ <ScriptCmd>GoBackward(v:count1)<CR>
    nnoremap <buffer> <leader>s :SlidevGoToSlideNum<Space>
    nnoremap <buffer> <leader>a <ScriptCmd>AddSlide()<CR>
    nnoremap <buffer> <leader>D <ScriptCmd>DeleteSlide()<CR>
    nnoremap <buffer> <leader>R <ScriptCmd>RunDev()<CR>
    nnoremap <buffer> <leader>i <ScriptCmd>Info()<CR>
    nnoremap <buffer> <leader>z <ScriptCmd>FocusSlide()<CR>
    nnoremap <buffer> <leader>xe :SlidevSnippetExtract<Space>
    nnoremap <buffer> <leader>xi <ScriptCmd>SnippetInline(false)<CR>

    # command! bodies are not inside this script's scope, so the autoload
    # prefix slidev# is required to reach the exported functions.
    command! -buffer -nargs=1 SlidevGoToSlideNum call slidev#GoToSlide(<args>)
    command! -buffer SlidevRefresh call slidev#UpdateGhostText()
    command! -buffer SlidevFocus call slidev#FocusSlide()
    command! -buffer SlidevDisable call slidev#Disable()
    command! -buffer -nargs=? -complete=file SlidevSnippetExtract call slidev#SnippetExtract(<q-args>)
    command! -buffer -bang SlidevSnippetInline call slidev#SnippetInline(<bang>0)

    b:slidev_active = true

    UpdateGhostText()
    # Use a named augroup with 'autocmd! * <buffer>' so re-running Setup()
    # (e.g. via :SlidevEnable) does not register duplicate autocmds.
    augroup SlidevGhost
        autocmd! * <buffer>
        autocmd TextChanged,TextChangedI,BufWritePost <buffer> slidev#UpdateGhostText()
    augroup END
enddef
