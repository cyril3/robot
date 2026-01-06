call plug#begin()

Plug 'preservim/nerdtree'
" 1. 状态栏主插件
Plug 'vim-airline/vim-airline'
" 2. 状态栏主题插件 (可选，但推荐)
Plug 'vim-airline/vim-airline-themes'

call plug#end()

nnoremap <leader>n :NERDTreeToggle<CR>
nnoremap <leader>f :NERDTreeFind<CR>
let NERDTreeMinimalUI = 1

" 1. 如果启动 vim 时没有指定文件，则自动打开 NERDTree
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif

" 2. 当 NERDTree 是最后一个窗口时，自动退出 Vim (这是很多人的痛点)
autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif

" 3. 防止 NERDTree 覆盖原来的窗口，始终在侧边打开
autocmd BufEnter * if bufname('#') =~ 'NERD_tree_\d\+' && bufname('%') !~ 'NERD_tree_\d\+' && winnr('$') > 1 |
    \ let buf=bufnr() | buffer# | execute "normal! \<C-W>w" | execute 'buffer'.buf | endif

" 1. 开启顶部 Tabline (这行最重要，实现了类似 VS Code 的标签页效果)
let g:airline#extensions#tabline#enabled = 1

" 3. 文件名显示模式
" ':t' = 只显示文件名 (推荐)
" ':p' = 显示全路径
let g:airline#extensions#tabline#fnamemod = ':t'

function! SmartBufferSwitch(direction)
  " 1. 检测当前窗口是否为 NERDTree
  if &filetype == 'nerdtree'
    " 2. 如果是，则尝试跳回上一个普通窗口 (wincmd p)
    wincmd p
  endif

  " 4. 执行切换命令 (bnext 或 bprev)
  execute 'b' . a:direction
endfunction

" --- 重新映射快捷键 ---
" 使用 Tab 切换下一个 (调用上面的函数)
nnoremap <Tab> :call SmartBufferSwitch('next')<CR>

" 使用 Shift + Tab 切换上一个
nnoremap <S-Tab> :call SmartBufferSwitch('prev')<CR>
" 使用 Tab 键切换下一个 Buffer
"nnoremap <Tab> :bnext<CR>
" 使用 Shift + Tab 切换上一个 Buffer
"nnoremap <S-Tab> :bprev<CR>
