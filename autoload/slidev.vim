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

    # Join the text-property changes into the preceding undo block so that
    # pressing u does not first jump the cursor to line 1 of the file.
    # silent! absorbs E790 when there is nothing to join with (e.g. on the
    # very first edit or immediately after an undo).
    silent! undojoin

    # Wipe all existing annotations before redrawing so edits that add or
    # remove '---' lines don't leave stale slide numbers behind.
    prop_remove({type: PROP_TYPE, bufnr: buf, all: true}, 1, line('$'))

    # Get the usable window width excluding the gutter.
    var winid = bufwinid(buf)
    if winid == -1
        winid = win_getid() # Fallback if buffer isn't active
    endif
    var wininfo = getwininfo(winid)[0]
    var usable_width = wininfo.width - wininfo.textoff

    # Determine the target boundary: column 80 or window width
    var target_col = min([80, usable_width])

    for i in range(total)
        var lnum = slides[i]

        # Calculate visual widths
        var line_len = strdisplaywidth(getline(lnum))
        var msg = $' {i + 1} / {total} '
        var msg_len = strdisplaywidth(msg)
        var pre = ' '
        var pre_len = strdisplaywidth(pre)

        # Calculate the padding needed to push the text to the target column
        var gap = target_col - line_len - pre_len -  msg_len

        # If there's a gap, fill it with a separating char
        var text_to_show = pre .. (gap > 0 ? repeat('-', gap) .. msg : msg)

        # col 0 means the text is appended after the last character on the line
        prop_add(lnum, 0, {
            bufnr:      buf,
            type:       PROP_TYPE,
            text:       text_to_show,
            text_align: 'after',
        })
    endfor
enddef

# ── Navigation ────────────────────────────────────────────────────────────────

def HandleJumpFocus(jump_count: number, key: string)
    # Execute the raw jump command with the user's count
    execute $'normal! {jump_count}{key}'

    # If the jump kept us in the presentation and focus is active, re-focus the new slide
    if get(b:, 'slidev_focus', false) == true
        b:slidev_focus = false
        FocusSlide()
    endif
enddef

export def GoForward(count: number)
    var slides = GetSlideLines()
    var cur = line('.')
    var ahead = slides->filter((_, v) => v > cur)
    if empty(ahead)
        return
    endif

    # Add current take-off location to the jump list
    normal! m`

    # Clamp so a count larger than the number of remaining slides lands on the
    # last one rather than indexing out of bounds.
    cursor(ahead[min([count - 1, len(ahead) - 1])], 1)
    # Scroll the separator to the top so slide content is immediately visible.
    normal! zt
    # Re-apply focus to the new slide when focus mode is active.
    if get(b:, 'slidev_focus', false)
        b:slidev_focus = false
        FocusSlide()
    endif
enddef

export def GoBackward(count: number)
    var slides = GetSlideLines()
    var cur = line('.')
    var behind = slides->filter((_, v) => v < cur)
    if empty(behind)
        return
    endif

    # Add current take-off location to the jump list
    normal! m`

    # max(..., 0) prevents a negative index when count exceeds available slides.
    cursor(behind[max([len(behind) - count, 0])], 1)
    normal! zt
    # Re-apply focus to the new slide when focus mode is active.
    if get(b:, 'slidev_focus', false)
        b:slidev_focus = false
        FocusSlide()
    endif
enddef

export def GoToSlide(num: number)
    var slides = GetSlideLines()
    var total = len(slides)
    if num < 1 || num > total
        echo $'SlidevGoToSlideNum: slide {num} not found (presentation has {total} slides)'
        return
    endif

    # Add current take-off location to the jump list
    normal! m`

    if get(b:, 'slidev_focus') == false
        # slides[] is 0-based; slide numbers shown to the user are 1-based.
        cursor(slides[num - 1], 1)
    else
        # Workaround to jump while focus mode enabled
        silent! ExitFocus()
        cursor(slides[num - 1], 1)
        silent! FocusSlide()
    endif

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

# ── Link digesting ────────────────────────────────────────────────────────────

export def DigestLinks()
    var saved_view = winsaveview()

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

    # The separator '---' is at slide_start; slide content begins on the next line.
    if slide_start >= slide_end
        echo '[Slidev] no links found'
        return
    endif

    var content_lines: list<string> = getline(slide_start + 1, slide_end)

    # ── Detect and strip trailing presenter notes (HTML comment block) ────────
    # In Slidev an HTML comment at the bottom of a slide is a presenter note.
    # The reference list must be inserted *above* these notes.
    var presenter_notes: list<string> = []

    # Find last non-blank line.
    var j = len(content_lines) - 1
    while j >= 0 && content_lines[j] =~# '^\s*$'
        j -= 1
    endwhile

    # If the last non-blank line closes a comment, scan backward for its opener.
    if j >= 0 && content_lines[j] =~# '-->\s*$'
        var k = j
        while k >= 0
            if content_lines[k] =~# '<!--'
                if k > 0
                    presenter_notes = content_lines[k :]
                    content_lines   = content_lines[0 : k - 1]
                else
                    presenter_notes = copy(content_lines)
                    content_lines   = []
                endif
                break
            endif
            k -= 1
        endwhile
    endif

    # ── Parse existing definition block ───────────────────────────────────────
    # Scan backwards for lines matching [N]: url (with optional blank lines).
    var old_defs: dict<string> = {}
    var def_start_idx = -1
    var i = len(content_lines) - 1
    while i >= 0
        var ln = content_lines[i]
        if ln =~# '^\[\d\+\]: '
            def_start_idx = i
            var m = matchlist(ln, '^\[\(\d\+\)\]: \(.*\)$')
            if !empty(m)
                old_defs[m[1]] = m[2]
            endif
        elseif ln =~# '^\s*$'
            # blank line — keep scanning
        else
            break
        endif
        i -= 1
    endwhile

    # Strip definition block and the blank lines immediately preceding it.
    var body_lines: list<string>
    if def_start_idx >= 0
        var strip_from = def_start_idx
        while strip_from > 0 && content_lines[strip_from - 1] =~# '^\s*$'
            strip_from -= 1
        endwhile
        body_lines = strip_from > 0 ? content_lines[0 : strip_from - 1] : []
    else
        body_lines = copy(content_lines)
    endif

    # Strip trailing blank lines from body so assembly spacing is clean.
    while !empty(body_lines) && body_lines[len(body_lines) - 1] =~# '^\s*$'
        remove(body_lines, -1)
    endwhile

    # ── Scan and rewrite links, skipping HTML comment content ─────────────────
    # Process content left-to-right, top-to-bottom:
    #   [text][N]   → renumber N; reuse same new index for repeated old N
    #   [text][]    → placeholder (about:blank)
    #   [text](url) → convert to [text][new_idx]
    #   [text]()    → placeholder (about:blank)
    # Content inside <!-- ... --> comments is passed through unchanged.
    var next_idx = 1
    var old_to_new: dict<number> = {}
    var new_urls: dict<string>   = {}
    var new_body: list<string>   = []
    var in_html_comment = false

    for body_line in body_lines
        var result = ''
        var pos = 0
        var line_len = len(body_line)

        while pos < line_len
            var rest = body_line[pos :]

            # ── Inside a multiline HTML comment: passthrough until --> ────────
            if in_html_comment
                var close_idx = match(rest, '-->')
                if close_idx >= 0
                    result ..= rest[0 : close_idx + 2]
                    pos += close_idx + 3
                    in_html_comment = false
                else
                    result ..= rest
                    pos = line_len
                endif
                continue
            endif

            # ── HTML comment open <!-- ────────────────────────────────────────
            if len(rest) >= 4 && rest[0 : 3] ==# '<!--'
                var after_open = rest[4 :]
                var close_idx  = match(after_open, '-->')
                if close_idx >= 0
                    # Comment opens and closes on this line — passthrough entire span.
                    result ..= rest[0 : close_idx + 6]
                    pos += close_idx + 7
                else
                    # Comment opens but does not close — carry state to next lines.
                    in_html_comment = true
                    result ..= rest
                    pos = line_len
                endif
                continue
            endif

            # ── Numbered reference: [text][N] ─────────────────────────────────
            var ref_match = matchlist(rest, '^\(\[[^\]]\{-}\]\)\[\(\d\+\)\]')
            if !empty(ref_match)
                var full      = ref_match[0]
                var text_part = ref_match[1]
                var old_idx   = ref_match[2]
                if !has_key(old_to_new, old_idx)
                    old_to_new[old_idx] = next_idx
                    new_urls[string(next_idx)] = get(old_defs, old_idx, 'about:blank')
                    next_idx += 1
                endif
                result ..= $'{text_part}[{old_to_new[old_idx]}]'
                pos += len(full)
                continue
            endif

            # ── Empty reference: [text][] ─────────────────────────────────────
            var empty_ref_match = matchlist(rest, '^\(\[[^\]]\{-}\]\)\[\]')
            if !empty(empty_ref_match)
                var full      = empty_ref_match[0]
                var text_part = empty_ref_match[1]
                new_urls[string(next_idx)] = 'about:blank'
                result ..= $'{text_part}[{next_idx}]'
                next_idx += 1
                pos += len(full)
                continue
            endif

            # ── Inline link: [text](url) or [text]() ─────────────────────────
            var inline_match = matchlist(rest, '^\(\[[^\]]\{-}\]\)(\([^)]*\))')
            if !empty(inline_match)
                var full      = inline_match[0]
                var text_part = inline_match[1]
                var url       = inline_match[2] ==# '' ? 'about:blank' : inline_match[2]
                new_urls[string(next_idx)] = url
                result ..= $'{text_part}[{next_idx}]'
                next_idx += 1
                pos += len(full)
                continue
            endif

            result ..= rest[0]
            pos += 1
        endwhile

        new_body->add(result)
    endfor

    if empty(new_urls)
        echo '[Slidev] no links found'
        return
    endif

    # ── Build new definition block ─────────────────────────────────────────────
    var def_block: list<string> = []
    for idx in range(1, next_idx - 1)
        def_block->add($'[{idx}]: {new_urls[string(idx)]}')
    endfor

    # Structure: body + blank + definitions + blank + presenter notes (if any)
    var new_content = new_body + [''] + def_block + ['']
    if !empty(presenter_notes)
        new_content = new_content + presenter_notes
    endif

    # ── Replace slide content ──────────────────────────────────────────────────
    deletebufline('%', slide_start + 1, slide_end)
    append(slide_start, new_content)

    UpdateGhostText()
    echo '[Slidev] links digested'
    winrestview(saved_view)
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

def ExitFocus()
    execute $'setlocal foldmethod={get(b:, "slidev_prev_foldmethod", "manual")}'
    # zE deletes all folds so the restored foldmethod starts from a clean
    # slate (avoids leftover manual folds when switching to e.g. 'indent').
    normal! zE
    b:slidev_focus = false
    # Remove the boundary-movement mappings installed when focus was entered.
    silent! execute 'nunmap <buffer> k'
    silent! execute 'nunmap <buffer> j'
    normal! zt
    echo '[Slidev] focus off'
enddef

# Called by the <buffer> k mapping while focus mode is active.
# While inside the slide the cursor moves normally.  Once the cursor is on
# the *upper* closed fold (line < slide_start) a second k exits focus and
# places the cursor just above the slide.  Pressing j from the upper fold
# just executes a normal j (re-entering the slide) — no exit.
def FocusMoveUp()
    var cur = line('.')
    var slide_start = get(b:, 'slidev_focus_start', 1)
    if foldclosed(cur) >= 0 && cur < slide_start
        # Cursor is on the upper closed fold — user is insisting upward.
        # Capture the target line *before* ExitFocus() removes the folds so
        # the cursor ends up adjacent to the slide, not at the fold's first line.
        var target = slide_start - 1
        ExitFocus()
        if target >= 1
            cursor(target, 1)
        endif
    else
        execute $'normal! {v:count1}k'
    endif
enddef

# Mirror of FocusMoveUp() for downward movement.
# Exits focus only when the cursor is on the *lower* closed fold (line >
# slide_end).  Pressing k from the lower fold re-enters the slide normally.
def FocusMoveDown()
    var cur = line('.')
    var slide_end = get(b:, 'slidev_focus_end', line('$'))
    if foldclosed(cur) >= 0 && cur > slide_end
        var target = slide_end + 1
        ExitFocus()
        if target <= line('$')
            cursor(target, 1)
        endif
    else
        execute $'normal! {v:count1}j'
    endif
enddef

export def FocusSlide()
    if get(b:, 'slidev_focus', false)
        ExitFocus()
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
    b:slidev_focus_start = slide_start
    b:slidev_focus_end   = slide_end
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
    # Install boundary-movement mappings so the user can exit focus by
    # pressing k/j a second time once the cursor is on a closed fold.
    nnoremap <buffer> k <ScriptCmd>FocusMoveUp()<CR>
    nnoremap <buffer> j <ScriptCmd>FocusMoveDown()<CR>
    normal! zt
    echo '[Slidev] focus on'
enddef

# ── Enable / Disable ──────────────────────────────────────────────────────────

export def Disable()
    # Wrap key sequences as strings inside execute() for reliable parsing in
    # Vim9script.  silent! absorbs the error when a mapping does not exist
    # (e.g. called on an un-setup buffer).
    silent! execute 'nunmap <buffer> <C-p>'
    silent! execute 'nunmap <buffer> <C-n>'
    silent! execute 'nunmap <buffer> <C-o>'
    silent! execute 'nunmap <buffer> <C-i>'
    silent! execute 'nunmap <buffer> <leader>s'
    silent! execute 'nunmap <buffer> <leader>a'
    silent! execute 'nunmap <buffer> <leader>D'
    silent! execute 'nunmap <buffer> <leader>R'
    silent! execute 'nunmap <buffer> <leader>i'
    silent! execute 'nunmap <buffer> <leader>z'
    silent! execute 'nunmap <buffer> <leader>L'
    # These are only present when focus mode was active at disable time.
    silent! execute 'nunmap <buffer> k'
    silent! execute 'nunmap <buffer> j'

    # -buffer is required to delete buffer-local commands; without it
    # delcommand would look for (and fail to find) a global command.
    silent! execute 'delcommand -buffer SlidevGoToSlideNum'
    silent! execute 'delcommand -buffer SlidevRefresh'
    silent! execute 'delcommand -buffer SlidevFocus'
    silent! execute 'delcommand -buffer SlidevDisable'
    silent! execute 'delcommand -buffer SlidevDigestLinks'

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
    nnoremap <buffer> <C-n> <ScriptCmd>GoForward(v:count1)<CR>
    nnoremap <buffer> <C-p> <ScriptCmd>GoBackward(v:count1)<CR>

    # Override jump list keys to maintain focus mode if enabled
    nnoremap <buffer> <C-o> <ScriptCmd>HandleJumpFocus(v:count1, "\<C-o>")<CR>
    nnoremap <buffer> <C-i> <ScriptCmd>HandleJumpFocus(v:count1, "\<C-i>")<CR>

    # Generic utils
    nnoremap <buffer> <leader>s :SlidevGoToSlideNum<Space>
    nnoremap <buffer> <leader>a <ScriptCmd>AddSlide()<CR>
    nnoremap <buffer> <leader>D <ScriptCmd>DeleteSlide()<CR>
    nnoremap <buffer> <leader>R <ScriptCmd>RunDev()<CR>
    nnoremap <buffer> <leader>i <ScriptCmd>Info()<CR>
    nnoremap <buffer> <leader>z <ScriptCmd>FocusSlide()<CR>
    nnoremap <buffer> <leader>L <ScriptCmd>DigestLinks()<CR>

    # command! bodies are not inside this script's scope, so the autoload
    # prefix slidev# is required to reach the exported functions.
    command! -buffer -nargs=1 SlidevGoToSlideNum call slidev#GoToSlide(<args>)
    command! -buffer SlidevRefresh call slidev#UpdateGhostText()
    command! -buffer SlidevFocus call slidev#FocusSlide()
    command! -buffer SlidevDisable call slidev#Disable()
    command! -buffer SlidevDigestLinks call slidev#DigestLinks()

    b:slidev_active = true

    UpdateGhostText()
    # Use a named augroup with 'autocmd! * <buffer>' so re-running Setup()
    # (e.g. via :SlidevEnable) does not register duplicate autocmds.
    augroup SlidevGhost
        autocmd! * <buffer>
        autocmd TextChanged,TextChangedI,BufWritePost,VimResized <buffer> slidev#UpdateGhostText()
    augroup END
enddef
