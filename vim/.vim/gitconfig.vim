nnoremap <silent> <leader>g :Git<CR>
nnoremap <silent> <leader>gl :GV<CR>

" ============================================================================
" GV.vim Custom Diff Stat Feature
" Press <CR> on a commit to show diff --stat, then <CR> on a file to vimdiff
" ============================================================================

" Script-local variables
let s:gv_old_commit = ''
let s:gv_new_commit = ''

" Find existing DiffStat window
function! s:FindDiffStatWindow()
  for l:winnr in range(1, winnr('$'))
    if getwinvar(l:winnr, 'gv_diffstat', 0)
      return l:winnr
    endif
  endfor
  return 0
endfunction

" Fill DiffStat buffer with git diff --stat output
" old_sha: older commit, new_sha: newer commit (can be same for single commit mode)
function! s:FillDiffStatBuffer(old_sha, new_sha)
  setlocal modifiable
  silent %delete _

  " Determine diff range
  if a:old_sha ==# a:new_sha
    " Single commit mode: compare with parent
    let l:range = a:old_sha . '^..' . a:old_sha
    let l:header = '# Diff stat for: ' . a:old_sha
  else
    " Two commit mode: compare between commits
    let l:range = a:old_sha . '..' . a:new_sha
    let l:header = '# Diff stat: ' . a:old_sha[:6] . '..' . a:new_sha[:6]
  endif

  " Execute git diff --stat with full path width (no truncation)
  let l:result = FugitiveExecute(['diff', '--stat=200,200', l:range])
  let l:output = l:result.stdout

  " Handle initial commit (no parent)
  if l:result.exit_status != 0 && a:old_sha ==# a:new_sha
    let l:result = FugitiveExecute(['diff-tree', '--stat=200,200', '--root', a:old_sha])
    let l:output = l:result.stdout
  endif

  " Add header
  call setline(1, l:header)
  call append(1, '# Press <CR> on a file to view vimdiff, q to close')
  call append(2, '')

  " Add diff stat output
  call append(3, l:output)

  setlocal nomodifiable

  " Move cursor to first file line (skip header)
  normal! 4G
endfunction

" Setup DiffStat buffer
function! s:SetupDiffStatBuffer(old_sha, new_sha)
  " Mark this window
  let w:gv_diffstat = 1

  " Scratch buffer settings
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nomodeline
  setlocal nowrap
  setlocal cursorline

  " Fill content
  call s:FillDiffStatBuffer(a:old_sha, a:new_sha)

  " Setup keymaps
  nnoremap <buffer> <silent> <CR> :call <SID>OpenFileDiff()<CR>
  nnoremap <buffer> <silent> q :close<CR>
endfunction

" Main entry: show diff --stat for selected commit(s)
" visual: 0 for normal mode (single commit), 1 for visual mode (two commits)
function! s:GVShowDiffStat(visual)
  if a:visual
    " Visual mode: get SHA from first and last selected lines
    let l:sha1 = gv#sha(getline("'<"))
    let l:sha2 = gv#sha(getline("'>"))
    if empty(l:sha1) || empty(l:sha2)
      echohl WarningMsg | echo 'Could not get commits from selection' | echohl None
      return
    endif
    " sha1 is older (top), sha2 is newer (bottom) in git log
    let s:gv_old_commit = l:sha2
    let s:gv_new_commit = l:sha1
  else
    " Normal mode: single commit
    let l:sha = gv#sha()
    if empty(l:sha)
      echohl WarningMsg | echo 'No commit found on current line' | echohl None
      return
    endif
    let s:gv_old_commit = l:sha
    let s:gv_new_commit = l:sha
  endif

  " Check for existing diffstat window
  let l:diffstat_win = s:FindDiffStatWindow()
  if l:diffstat_win > 0
    execute l:diffstat_win . 'wincmd w'
    call s:FillDiffStatBuffer(s:gv_old_commit, s:gv_new_commit)
    wincmd p
  else
    " Create new vsplit on the right
    vertical botright new
    call s:SetupDiffStatBuffer(s:gv_old_commit, s:gv_new_commit)
    wincmd p
  endif
endfunction

" Parse file path from diff --stat line
function! s:ParseDiffStatFile()
  let l:line = getline('.')

  " Skip header and summary lines
  if l:line =~ '^#' || l:line =~ '^\s*$' || l:line =~ 'files\? changed'
    return ''
  endif

  " Handle renamed files: " old => new | "
  let l:match = matchlist(l:line, '^\s*\(.\{-}\)\s*=>\s*\(.\{-}\)\s*|')
  if len(l:match) > 2
    " Extract the new path, handling {old => new} format
    let l:path = substitute(l:match[0], '\s*|.*', '', '')
    let l:path = substitute(l:path, '^\s*', '', '')
    " Handle {old => new} within path
    if l:path =~ '{.\{-} => .\{-}}'
      let l:path = substitute(l:path, '{\(.\{-}\) => \(.\{-}\)}', '\2', 'g')
    else
      return trim(l:match[2])
    endif
    return l:path
  endif

  " Normal format: " path/to/file | 10 ++--"
  let l:match = matchlist(l:line, '^\s*\(\S\+\)\s*|')
  if len(l:match) > 1
    return l:match[1]
  endif

  return ''
endfunction

" Tab number to return to after closing vimdiff
let s:gv_source_tab = 0

" Close vimdiff tab and return to diff stat
function! s:CloseVimdiffTab()
  diffoff!
  " Go back to the source tab first, then close the vimdiff tab
  let l:current_tab = tabpagenr()
  if s:gv_source_tab > 0 && s:gv_source_tab != l:current_tab
    execute 'tabnext ' . s:gv_source_tab
    execute 'tabclose ' . l:current_tab
  else
    tabclose
  endif
  " Focus on diff stat window if it exists
  let l:diffstat_win = s:FindDiffStatWindow()
  if l:diffstat_win > 0
    execute l:diffstat_win . 'wincmd w'
  endif
endfunction

" Open vimdiff for selected file
function! s:OpenFileDiff()
  let l:file = s:ParseDiffStatFile()
  if empty(l:file)
    echohl WarningMsg | echo 'No file found on current line' | echohl None
    return
  endif

  let l:old_sha = s:gv_old_commit
  let l:new_sha = s:gv_new_commit
  if empty(l:old_sha) || empty(l:new_sha)
    echohl WarningMsg | echo 'No commit context found' | echohl None
    return
  endif

  " Determine the actual refs to use for file content
  if l:old_sha ==# l:new_sha
    " Single commit mode: compare with parent
    let l:old_ref = l:old_sha . '^'
    let l:new_ref = l:new_sha
  else
    " Two commit mode
    let l:old_ref = l:old_sha
    let l:new_ref = l:new_sha
  endif

  " Use FugitiveExecute for proper git repo context
  let l:new_result = FugitiveExecute(['show', l:new_ref . ':' . l:file])
  let l:new_content = l:new_result.exit_status == 0 ? l:new_result.stdout : []

  let l:old_result = FugitiveExecute(['show', l:old_ref . ':' . l:file])
  let l:old_content = l:old_result.exit_status == 0 ? l:old_result.stdout : []

  " Save current tab number to return to later
  let s:gv_source_tab = tabpagenr()

  " Open vimdiff in new tab
  tabnew

  " Setup old version (left)
  enew
  if !empty(l:old_content)
    call setline(1, l:old_content)
  else
    call setline(1, ['(File does not exist in this commit)'])
  endif
  setlocal buftype=nofile bufhidden=wipe noswapfile nomodifiable
  execute 'silent file ' . l:old_ref . ':' . l:file
  diffthis

  " Setup new version (right)
  vertical rightbelow new
  if !empty(l:new_content)
    call setline(1, l:new_content)
  else
    call setline(1, ['(File does not exist in this commit)'])
  endif
  setlocal buftype=nofile bufhidden=wipe noswapfile nomodifiable
  execute 'silent file ' . l:new_ref . ':' . l:file
  diffthis

  " Setup quit mapping for both windows
  windo nnoremap <buffer> <silent> q :call <SID>CloseVimdiffTab()<CR>

  " Focus left window
  wincmd h
endfunction

" Setup custom mappings for GV filetype
function! s:SetupGVCustomMappings()
  " Normal mode: single commit
  nnoremap <buffer> <silent> <CR> :call <SID>GVShowDiffStat(0)<CR>
  " Visual mode: compare two commits
  xnoremap <buffer> <silent> <CR> :<C-u>call <SID>GVShowDiffStat(1)<CR>
endfunction

augroup GVCustomDiffStat
  autocmd!
  autocmd FileType GV call s:SetupGVCustomMappings()
augroup END

