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

# Read slide separator line numbers from any buffer.  Used by the public
# GetSlideLines() (current buffer) and by focus mode helpers (original buffer).
def GetSlideLinesFromBuf(buf: number): list<number>
    var lines = getbufline(buf, 1, '$')
    var total = len(lines)
    var slides: list<number> = []
    var in_frontmatter = false

    for i in range(total)
        if lines[i] ==# '---'
            if !in_frontmatter
                slides->add(i + 1)
                # Peek ahead past blank lines to check for a YAML key on the
                # next non-blank line ('key:' pattern).  If found, this '---'
                # opened a front-matter block rather than a slide separator.
                var peek = i + 1
                while peek < total && lines[peek] =~# '^\s*$'
                    peek += 1
                endwhile
                if peek < total && lines[peek] =~# '^[A-Za-z_][A-Za-z0-9_-]*\s*:'
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

export def GetSlideLines(): list<number>
    return GetSlideLinesFromBuf(bufnr('%'))
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

# Return the [start, end] 1-based inclusive line range of slide_idx inside buf.
def FocusGetRange(buf: number, slide_idx: number): list<number>
    var slides    = GetSlideLinesFromBuf(buf)
    var slide_start = slides[slide_idx]
    # For the last slide, slide_end is the final line of the buffer.
    # len(getbufline(...)) equals the last 1-based line number because
    # getbufline returns one entry per line.
    var slide_end   = slide_idx + 1 < len(slides)
        ? slides[slide_idx + 1] - 1
        : len(getbufline(buf, 1, '$'))
    return [slide_start, slide_end]
enddef

# Replace all lines of the current buffer with `content`.
# setline() replaces from line 1 but does not shrink the buffer, so any
# trailing lines left over from longer previous content are pruned explicitly.
def FocusReplaceContent(content: list<string>)
    var old_count = line('$')
    var new_count = len(content)
    setline(1, content)
    if old_count > new_count
        deletebufline(bufnr('%'), new_count + 1, old_count)
    endif
enddef

# Add (or refresh) the ghost-text annotation on line 1 of the scratch buffer
# showing the slide position in the same format as the original buffer, with
# an [F] marker to indicate focus mode.
def FocusUpdateGhostText()
    EnsurePropType()
    var slide_idx = b:slidev_focus_slide_idx
    var total     = len(GetSlideLinesFromBuf(b:slidev_focus_orig_buf))
    var buf       = bufnr('%')
    prop_remove({type: PROP_TYPE, bufnr: buf, all: true}, 1, 1)
    prop_add(1, 0, {
        bufnr:      buf,
        type:       PROP_TYPE,
        text:       $'  ⟨ slide {slide_idx + 1} / {total} [F] ⟩',
        text_align: 'after',
    })
enddef

# Write the scratch buffer's current lines back to the corresponding slide
# range in the original presentation buffer.  Called before every navigation
# step and before exiting focus mode.
def FocusFlush()
    var orig_buf  = b:slidev_focus_orig_buf
    var slide_idx = b:slidev_focus_slide_idx
    var [slide_start, slide_end] = FocusGetRange(orig_buf, slide_idx)
    var new_lines = getbufline(bufnr('%'), 1, '$')
    deletebufline(orig_buf, slide_start, slide_end)
    appendbufline(orig_buf, slide_start - 1, new_lines)
enddef

# Replace the scratch buffer's content with slide_idx from the original buffer.
def FocusLoadSlide()
    var orig_buf  = b:slidev_focus_orig_buf
    var slide_idx = b:slidev_focus_slide_idx
    var [slide_start, slide_end] = FocusGetRange(orig_buf, slide_idx)
    var content   = getbufline(orig_buf, slide_start, slide_end)
    FocusReplaceContent(content)
    FocusUpdateGhostText()
    cursor(1, 1)
    normal! zt
    echo $'[Slidev] slide {slide_idx + 1} / {len(GetSlideLinesFromBuf(orig_buf))}'
enddef

# Move forward by count slides while in focus mode.
def FocusNavForward(count: number)
    FocusFlush()
    var orig_buf  = b:slidev_focus_orig_buf
    var slide_idx = b:slidev_focus_slide_idx
    var total     = len(GetSlideLinesFromBuf(orig_buf))
    var new_idx   = min([slide_idx + count, total - 1])
    if new_idx == slide_idx
        echo '[Slidev] already on last slide'
        return
    endif
    b:slidev_focus_slide_idx = new_idx
    FocusLoadSlide()
enddef

# Move backward by count slides while in focus mode.
def FocusNavBackward(count: number)
    FocusFlush()
    var orig_buf  = b:slidev_focus_orig_buf
    var slide_idx = b:slidev_focus_slide_idx
    var new_idx   = max([slide_idx - count, 0])
    if new_idx == slide_idx
        echo '[Slidev] already on first slide'
        return
    endif
    b:slidev_focus_slide_idx = new_idx
    FocusLoadSlide()
enddef

# Exit focus mode: flush, wipe scratch buffer, return to original.
def FocusExit()
    FocusFlush()
    var orig_buf  = b:slidev_focus_orig_buf
    var slide_idx = b:slidev_focus_slide_idx
    # Switching away triggers bufhidden=wipe and automatically deletes the scratch.
    execute $'buffer {orig_buf}'
    # We are now in the original buffer.
    b:slidev_focus = false
    # Place the cursor on the separator line of the last focused slide.
    var slides = GetSlideLines()
    if slide_idx < len(slides)
        cursor(slides[slide_idx], 1)
        normal! zt
    endif
    echo '[Slidev] focus off'
enddef

export def FocusSlide()
    # If called from the scratch buffer, exit focus mode.
    if get(b:, 'slidev_focus_scratch', false)
        FocusExit()
        return
    endif

    # Guard against opening a second focus session on the same buffer.
    if get(b:, 'slidev_focus', false)
        echo '[Slidev] focus already active — press <leader>z in the focus window to exit'
        return
    endif

    var slides = GetSlideLines()
    if empty(slides)
        echo '[Slidev] no slides found'
        return
    endif

    var cur       = line('.')
    var slide_idx = -1
    for i in range(len(slides))
        if slides[i] <= cur
            slide_idx = i
        endif
    endfor

    if slide_idx < 0
        echo '[Slidev] cursor is not inside a slide'
        return
    endif

    var orig_buf = bufnr('%')
    var [slide_start, slide_end] = FocusGetRange(orig_buf, slide_idx)
    var content = getbufline(orig_buf, slide_start, slide_end)

    # Mark the original buffer as having an active focus session, and remember
    # the scratch bufnr so Disable() can clean up if needed.
    b:slidev_focus = true

    # Create and switch to a scratch buffer in the current window.
    var scratch = bufadd('')
    bufload(scratch)
    b:slidev_focus_scratch_buf = scratch
    execute $'buffer {scratch}'

    # Configure the scratch buffer (current buffer is now scratch).
    setlocal buftype=nofile noswapfile bufhidden=wipe nobuflisted filetype=markdown

    # Store focus metadata.
    b:slidev_focus_scratch   = true
    b:slidev_focus_orig_buf  = orig_buf
    b:slidev_focus_slide_idx = slide_idx

    # Populate with the current slide's lines and show the ghost-text annotation.
    FocusReplaceContent(content)
    FocusUpdateGhostText()

    # Buffer-local navigation mappings — <ScriptCmd> resolves the private
    # helpers in this script's scope without needing the slidev# prefix.
    nnoremap <buffer> ]] <ScriptCmd>FocusNavForward(v:count1)<CR>
    nnoremap <buffer> [[ <ScriptCmd>FocusNavBackward(v:count1)<CR>
    nnoremap <buffer> <leader>z <ScriptCmd>FocusSlide()<CR>

    cursor(1, 1)
    normal! zt
    echo $'[Slidev] focus on — slide {slide_idx + 1} / {len(slides)}'
enddef

# ── Enable / Disable ──────────────────────────────────────────────────────────

export def Disable()
    # If a focus scratch buffer is open, wipe it before tearing down the plugin.
    if get(b:, 'slidev_focus', false)
        var scratch = get(b:, 'slidev_focus_scratch_buf', -1)
        if scratch >= 0 && bufexists(scratch)
            execute $'bwipeout! {scratch}'
        endif
        b:slidev_focus = false
    endif

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

    # -buffer is required to delete buffer-local commands; without it
    # delcommand would look for (and fail to find) a global command.
    silent! execute 'delcommand -buffer SlidevGoToSlideNum'
    silent! execute 'delcommand -buffer SlidevRefresh'
    silent! execute 'delcommand -buffer SlidevFocus'
    silent! execute 'delcommand -buffer SlidevDisable'

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

    # command! bodies are not inside this script's scope, so the autoload
    # prefix slidev# is required to reach the exported functions.
    command! -buffer -nargs=1 SlidevGoToSlideNum call slidev#GoToSlide(<args>)
    command! -buffer SlidevRefresh call slidev#UpdateGhostText()
    command! -buffer SlidevFocus call slidev#FocusSlide()
    command! -buffer SlidevDisable call slidev#Disable()

    b:slidev_active = true

    UpdateGhostText()
    # Use a named augroup with 'autocmd! * <buffer>' so re-running Setup()
    # (e.g. via :SlidevEnable) does not register duplicate autocmds.
    augroup SlidevGhost
        autocmd! * <buffer>
        autocmd TextChanged,TextChangedI,BufWritePost <buffer> slidev#UpdateGhostText()
    augroup END
enddef
