"--------------------------
"VUNDLE CONFIG

set nocompatible
filetype off
runtime match
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
Plugin 'Chiel92/vim-autoformat'
Plugin 'cespare/vim-toml'
Plugin 'dense-analysis/ale'
Plugin 'psf/black'
" Plugin 'davidhalter/jedi-vim'
Plugin 'einars/js-beautify'
Plugin 'fatih/vim-go'
Plugin 'flazz/vim-colorschemes'
Plugin 'jiangmiao/auto-pairs'
Plugin 'gmarik/Vundle.vim'
Plugin 'gioele/vim-autoswap.git'
Plugin 'hashivim/vim-terraform'
Plugin 'juliosueiras/vim-terraform-completion'
Plugin 'ctrlpvim/ctrlp.vim'
Plugin 'jparise/vim-graphql'
Plugin 'leafgarland/typescript-vim'
Plugin 'maksimr/vim-jsbeautify'
Plugin 'MikeCoder/markdown-preview.vim'
Plugin 'mitermayer/vim-prettier', {'do' : 'npm install'}
Plugin 'othree/html5.vim'
Plugin 'pangloss/vim-javascript'
Plugin 'Quramy/vim-js-pretty-template'
Plugin 'rust-lang/rust.vim'
Plugin 'Shougo/vimproc.vim', {'do' : 'make'}
Plugin 'scrooloose/nerdtree'
" Plugin 'scrooloose/syntastic'
Plugin 'fisadev/vim-isort'           " Add for import sorting
Plugin 'vim-python/python-syntax'    " Better Python syntax highlighting
Plugin 'Vimjas/vim-python-pep8-indent'
Plugin 'Shougo/unite-outline'
Plugin 'takac/vim-hardtime'
Plugin 'tell-k/vim-autopep8'
Plugin 'tpope/vim-abolish'
Plugin 'tpope/vim-commentary'
Plugin 'tpope/vim-dispatch'
Plugin 'tpope/vim-fugitive'
Plugin 'tpope/vim-jdaddy'
Plugin 'prisma/vim-prisma'
Plugin 'tpope/vim-repeat'
Plugin 'tpope/vim-surround'
Plugin 'tpope/vim-unimpaired'
Plugin 'tmux-plugins/vim-tmux'
Plugin 'vim-airline/vim-airline'
Plugin 'vim-airline/vim-airline-themes'
" Plugin 'ycm-core/YouCompleteMe', {'do': './install.py --all'}
" Plugin 'neoclide/coc.nvim', {'branch': 'release', 'do': 'npm ci'}
" Plugin 'vim-scripts/AutoComplPop'
Plugin 'vim-scripts/ciscoacl.vim'
"all plugin's must be listed before following 2 lines
call vundle#end()

"-------------------------------
"COLORS
syntax on
set term=screen-256color
set background=dark
colorscheme badwolf

"-------------------------------
"INDENTATION & Lines
filetype plugin indent on
set tabstop=2 "number of spaces per tab
set expandtab "tabs === spaces
set shiftwidth=2
set softtabstop=2 "number of spaces in tab when editing
set autoindent

"-----------------------------
"COMPLETION

"-----------------------------
"UI CONFIG
set number "show line numbers
set showcmd " show command in bottom bar
set cursorline " highlight current line
set wildmenu " visual autocomplete for command menu
set lazyredraw " redraw screen only when needed
set showmatch " highlight matching [{()}]
if has('unnamedplus')
  set clipboard=unnamed,unnamedplus
else
  set clipboard=unnamed
endif
set updatetime=300  " Faster updates
set rnu
set laststatus=2 "always display statusline

"--------------------------------
"SEARCHING
set incsearch "search as chars are enters
set hlsearch "highlight matches
" Use ripgrep if available for faster searching
if executable('rg')
  set grepprg=rg\ --vimgrep
endif

"--------------------------------
"FOLDING
set foldenable
set foldlevelstart=10
set foldnestmax=10
set foldmethod=indent

"Html5 config---------------------------
let g:html5_event_handler_attributes_complete=0
let g:html5_rdfa_attributes_complete=0
let g:html5_microdata_attributes_complete=0
let g:html5_aria_attributes_complete=0

"-----------------------------------
"LEADER SHORTCUTS

"auto align current paragraph
noremap <leader>a =ip
"show invisibles
nmap <leader>l :set list!<CR>
"yank paragraph
noremap <leader> cp yap<S-{>p
noremap <leader>w <ESC>:w<CR>
inoremap <leader>w <ESC>:w<CR>
noremap <leader>wq :wq<CR>
inoremap <leader>wq <ESC>:wq<CR>
"Quickly open/reload vimrc
noremap <leader>ev :split $MYVIMRC<CR>
noremap <leader>cv <ESC>:w<CR>:source $MYVIMRC<CR>

"----------------------------------
" Location & QF list
noremap <leader>lo <ESC>:lopen<CR>
noremap <leader>lc <ESC>:lclose<CR>
noremap <leader>cl <ESC>:cclose<CR>

"----------------------------------
" Fugitive
noremap <leader>gs <ESC>:Gstatus<CR>
noremap <leader>gd <ESC>:Gdiff<CR>
noremap <leader>gb <ESC>:Gblame<CR>

"----------------------------------
"register mngt
noremap <leader>r :registers<CR>
"buffer mngt
nnoremap <silent> [b :bprevious<CR>
nnoremap <silent> ]b :bnext<CR>
nnoremap <silent> [B :bfirst<CR>
nnoremap <silent> ]B :blast<CR>

"----------------------------------
nnoremap <leader>m :MarkdownPreview GitHub<CR>

"----------------------------------
"SEARCH/SUB
nnoremap & :&&<CR>
xnoremap & :&&<CR>

"----------------------------------
"SYNTASTIC CONFIG- recommended

set statusline+=%#warningsmsg#
" set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
" let g:syntastic_always_populate_loc_list = 0
" let g:syntastic_auto_loc_list = 0
" let g:syntastic_check_on_open = 1
" let g:syntastic_check_on_wq = 0
" let g:syntastic_aggregate_errors = 1
" let g:syntastic_javascript_checkers = []
" let g:syntastic_javascript_eslint_exec = 'eslint_d'
" let g:syntastic_yaml_checkers = ['yamlxs']
" let g:syntastic_typescript_checkers = ['ale']


" let g:syntastic_python_python_exec = 'python3'
" let g:syntastic_python_checkers = ['pycodestyle']
" let g:syntastic_python_pycodestyle_args = '--ignore=E501'

" (Optional)Remove Info(Preview) window
set completeopt-=preview

" (Optional)Hide Info(Preview) window after completions
autocmd CursorMovedI * if pumvisible() == 0|pclose|endif
autocmd InsertLeave * if pumvisible() == 0|pclose|endif

" (Optional) Enable terraform plan to be include in filter
" let g:syntastic_terraform_tffilter_plan = 1
" (Optional) Default: 0, enable(1)/disable(0) plugin's keymapping
let g:terraform_completion_keys = 1
" (Optional) Default: 1, enable(1)/disable(0) terraform module registry completion
let g:terraform_registry_module_completion = 0

"----------------------------------------------------
" Python Configuration
" augroup black_on_save
"   autocmd!
"   autocmd BufWritePre *.py Black
" augroup end

" nnoremap <leader>b <ESC> :Black<CR>
" au BufRead,BufNewFile *.py setlocal textwidth=
let g:ale_python_black_options = '--line-length=88'
let g:ale_python_isort_options = '--profile black'
let g:ale_python_mypy_options = '--ignore-missing-imports'
let g:ale_python_ruff_options = '--select E,W,F,I,UP,B,C4,SIM,PIE --ignore E501,W503,E203'
let g:ale_python_ruff_format_options = '--line-length=88'
"----------------------------------------------------
" Vim-Typescript Config
let g:typescript_compiler_binary = ''
let g:typescript_compiler_options = ''
let g:AutoPairsFlyMode = 1
autocmd QuickFixCmdPost [^l]* nested cwindow
autocmd QuickFixCmdPost ^l* nested lwindow

" Define a custom tflint fixer
function! TflintFix(buffer) abort
    " Try to find the tflint config file in the current directory or parent directories
    let l:tflint_config = findfile('.tflint.hcl', '.;')
    let l:config_option = ''

    if !empty(l:tflint_config)
        let l:config_dir = fnamemodify(l:tflint_config, ':p:h')
        let l:config_option = '--config=' . shellescape(l:tflint_config)
    endif

    " Use the local tflint if available
    let l:executable = 'tflint'

    " Return the command to execute
    return {
    \   'command': l:executable . ' ' . l:config_option . ' --fix %t',
    \   'read_temporary_file': 1,
    \}
endfunction

" Register the custom fixer with ALE
call ale#fix#registry#Add('tflint', 'TflintFix', ['terraform'], 'Fix terraform files with tflint')

" Ale config - Advanced TypeScript Navigation
" TypeScript navigation with ALE
nnoremap <leader>gd :ALEGoToDefinition<CR>
nnoremap <leader>gr :ALEFindReferences<CR>
nnoremap <leader>gh :ALEHover<CR>
nnoremap <leader>gn :ALENext<CR>
nnoremap <leader>gp :ALEPrevious<CR>
nnoremap <leader>ca :ALECodeAction<CR>
nnoremap <leader>rn :ALERename<CR>
nnoremap <leader>imp :ALEOrganizeImports<CR>
nnoremap <silent> <leader>en :ALENextWrap<CR>
nnoremap <silent> <leader>ep :ALEPreviousWrap<CR>
nnoremap <silent> <leader>ef :ALEFirst<CR>
nnoremap <silent> <leader>el :ALELast<CR>
nnoremap <leader>jpt <ESC>:JsPreTmpl html<CR>
nnoremap <leader>jpc <ESC>:JsPreTmplClear<CR>

" ALE Configuration
let g:ale_typescript_tsserver_use_global = 0
let g:ale_lint_on_save = 1
let g:ale_lint_on_enter = 1
" let g:ale_lint_delay = 1000
" let g:ale_echo_delay = 100
" let g:ale_command_timeout = 10
let g:ale_lint_on_insert_leave = 0
let g:ale_completion_enabled = 1
let g:ale_completion_autoimport = 1
let g:ale_completion_max_suggestions = 50
let g:ale_lint_on_text_changed = 'never'
let g:airline#extensions#ale#enabled = 1
let g:ale_set_loclist = 0
let g:ale_set_quickfix = 0
let g:ale_open_list = 0
let g:ale_sign_errors = '\u+2022'
let g:ale_sign_warning = '.'
let b:ale_fix_on_save = 1
let g:ale_javascript_eslint_suppress_missing_config = 1
let g:ale_typescript_prettier_use_local_config = 1
" temporary increase logging
let g:ale_history_enabled = 1
let g:ale_history_log_output = 1

let g:ale_command_timeout =200
" Global ALE fixers and linters
let g:ale_fixers = {
\   '*': ['remove_trailing_lines', 'trim_whitespace'],
\   'javascript': ['prettier', 'eslint'],
\   'typescript': ['prettier', 'eslint'],
\   'python': ['ruff', 'ruff_format', 'black'],
\   'terraform': ['terraform', 'tflint'],
\}

let g:ale_linters = {
\   'javascript': ['eslint'],
\   'typescript': ['eslint', 'tsserver'],
\   'python': ['pylsp', 'ruff', 'mypy'],
\   'terraform': ['tflint', 'terraform'],
\}
" Remove the global omnifunc line and use this instead
augroup ale_completion
  autocmd!
  autocmd FileType python setlocal omnifunc=ale#completion#OmniFunc
  autocmd FileType javascript setlocal omnifunc=ale#completion#OmniFunc
  autocmd FileType typescript setlocal omnifunc=ale#completion#OmniFunc
augroup end
let g:ale_completion_delay = 100
let g:ale_echo_msg_format = '[%linter%] %s [%severity%]'

" Terraform Configuration
let g:terraform_fmt_on_save = 1
let g:terraform_align = 1

"----------------------------------------------------

" Python config
function! DetectVirtualEnv()
    if exists("$VIRTUAL_ENV")
        let g:ale_python_black_executable = $VIRTUAL_ENV . '/bin/black'
        let g:ale_python_flake8_executable = $VIRTUAL_ENV . '/bin/flake8'
        let g:ale_python_isort_executable = $VIRTUAL_ENV . '/bin/isort'
        let g:ale_python_mypy_executable = $VIRTUAL_ENV . '/bin/mypy'
    endif
endfunction
let g:ale_python_pylsp_executable = 'pylsp'
let g:ale_python_pylsp_use_global = 1
let g:ale_python_pylsp_config = {
\   'pylsp': {
\     'plugins': {
\       'pycodestyle': {'enabled': v:false},
\       'mccabe': {'enabled': v:false},
\       'pyflakes': {'enabled': v:false},
\       'flake8': {'enabled': v:false},
\       'autopep8': {'enabled': v:false},
\       'yapf': {'enabled': v:false},
\       'pylint': {'enabled': v:false},
\       'ruff': {
\         'enabled': v:true,
\         'lineLength': 88,
\         'select': ['E', 'W', 'F', 'I', 'UP', 'B', 'C4', 'SIM', 'PIE'],
\         'ignore': ['E501', 'W503', 'E203']
\       }
\     }
\   }
\}
augroup python_config
  autocmd!
  autocmd BufWritePre *.py ALEFix
  autocmd FileType python setlocal tabstop=4 shiftwidth=4 expandtab
  autocmd FileType python setlocal textwidth=88
  " autocmd FileType python setlocal colorcolumn=89
augroup end
augroup python_venv
  autocmd!
  autocmd FileType python call DetectVirtualEnv()
augroup end
"----------------------------------------------------
" === nerdtree CONFIG ===

" Automatically start NERDTree if no file is specified
autocmd StdinReadPre * let s:std_in = 1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif

" Close Vim if NERDTree is the only remaining window
autocmd BufEnter * if (winnr('$') == 1 && exists('b:NERDTreeType') && b:NERDTreeType == 'primary') | q | endif

" Toggle NERDTree without creating an extra buffer
function! ToggleNERDTreeSmart()
  if exists("t:NERDTreeBufName") && bufwinnr(t:NERDTreeBufName) != -1
    NERDTreeToggle
  else
    NERDTreeToggle
    if bufname('%') !=# '' && &filetype !=# 'nerdtree'
      NERDTreeFind
    endif
  endif
endfunction
" noremap <leader>nt<ESC>:NERDTreeCWD<CR> #not working

nnoremap <C-n> :call ToggleNERDTreeSmart()<CR>

" Position and cleanup settings
let g:NERDTreeWinPos = "left"
let g:NERDTreeAutoDeleteBuffer = 1

" Change working directory only for real files, not NERDTree or empty buffers
autocmd BufEnter * if &buftype == '' && &filetype !=# 'nerdtree' && expand('%') !=# '' | silent! lcd %:p:h | endif



"-------------------------------------
"FUGITIVE CONFIG
set statusline=%<%f\ %h%m%r%{fugitive#statusline()}%=%-14.(%l,%c%V%)\ %P
:set tags^=./.git/tags;

"----MISC-Mappings--------------------
" disable arrow keys
noremap <Up> <Nop>
inoremap <Up> <Nop>
noremap <Down> <Nop>
inoremap <Down> <Nop>
noremap <Left> <Nop>
inoremap <Left> <Nop>
noremap <Right> <Nop>
inoremap <Right> <Nop>

"-----Mappings for Prettier-------------
noremap <leader>pr <ESC>:Prettier<CR>

"-----Mappings for Autoformat-------------
noremap <leader>af <ESC>:Autoformat<CR>

"-----Mappings for JSbeautify-------------
" Autoformat works for json if jsBeautify does not
autocmd FileType json noremap <buffer>  <C-f> :call JsBeautify()<CR>
autocmd FileType javascript noremap <buffer>  <C-f> :call JsBeautify()<CR>
autocmd FileType html noremap <buffer> <C-f> :call HtmlBeautify()<CR>
autocmd FileType css noremap <buffer> <C-f> :call CSSBeautify()<CR>

"--------Vim-hardtime config-------------
let g:hardtime_default_on = 1
let g:hardtime_showmsg = 1
let g:hardtime_maxcount = 2
let g:hardtime_all_different_key = 1

" for quickfix/location list auto open
augroup myvimrc
  autocmd!
    autocmd QuickFixCmdPost [^l]* cwindow
    autocmd QuickFixCmdPost l*    lwindow
augroup END

" for syntax highlighting for various files
augroup filetype
        au! BufRead,BufNewFile *.crules     set filetype=ciscoacl
        au! BufRead,BufNewFile *.acl        set filetype=ciscoacl
        au! BufRead,BufNewFile *.tfvars.*   set filetype=terraform
        au! BufRead,BufNewFile *.xbrl       set filetype=xml
        au! BufRead,BufNewFile Dockerfile*  set filetype=dockerfile
        au! BufRead,BufNewFile .env.*       set filetype=sh
        au! BufRead,BufNewFile *.template   set filetype=yaml

augroup END

" for syntax highlighting for go templates for hugo
function DetectGoHtmlTmpl()
    if expand('%:e') == "html" && search("{{") != 0
        set filetype=gohtmltmpl
    endif
    if expand('%:e') == "xml" && search("{{") != 0
        set filetype=gohtmltmpl
    endif
endfunction

augroup filetypedetect
    au! BufRead,BufNewFile * call DetectGoHtmlTmpl()
augroup END

" Fix Prettier integration
let g:prettier#autoformat = 1
let g:prettier#autoformat_require_pragma = 0
let g:prettier#exec_cmd_async = 1

" Improve CtrlP for fuzzy file lookup
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlP'
let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_user_command = ['.git', 'cd %s && git ls-files -co --exclude-standard']
let g:ctrlp_custom_ignore = {
  \ 'dir':  '\v[\/](\.git|\.hg|\.svn|node_modules|__pycache__|\.pytest_cache|venv|\.venv)$',
  \ 'file': '\v\.(exe|so|dll|pyc)$',
  \ }
" let g:ctrlp_working_path_mode = 0  " Keep working directory unchanged

" File type specific settings

" tell autoswap.vim about tmux
let g:autoswap_detect_tmux = 1

" https://webpack.js.org/configuration/watch/#vim
:set backupcopy=yes

" Extend JavaScript / TypeScript comment syntax to recognize custom JSDoc tags
augroup jsdoc_custom_tags
  autocmd!
  autocmd FileType javascript,typescript,typescriptreact call JsDocCustomTags()
augroup END

function! JsDocCustomTags()
  syn match jsDocCustomTag "* @flow-\w\+"
  hi def link jsDocCustomTag jsDocTags
endfunction

command! -nargs=+ FlowComment call InsertFlowComment(<f-args>)

function! InsertFlowComment(step, type)
  " Build the full comment block as a list
  let l:comment = [
        \ '/**',
        \ ' * @flow-step ' . a:step,
        \ ' * @flow-type ' . a:type,
        \ ' * @flow-group ',
        \ ' * @flow-trigger ',
        \ ' * @flow-next ',
        \ ' * @flow-condition ',
        \ ' * @flow-previous ',
        \ ' * @flow-previous-condition ',
        \ ' * @flow-desc ',
        \ ' */'
        \ ]

  " Insert the block above current line
  call append(line('.') - 1, l:comment)

  " Auto-indent the inserted block
  execute (line('.') - len(l:comment)) . ',' . (line('.') - 1) . 'normal ='
endfunction
" Map <Leader>fc to prompt
nnoremap <silent> <Leader>fc :call FlowCommentPrompt()<CR>

function! FlowCommentPrompt()
  let l:step = input('Flow Step: ')
  let l:type = input('Flow Type: ')
  execute 'FlowComment ' . l:step . ' ' . l:type
endfunction

autocmd BufNewFile,BufRead *.jsonl set filetype=json

command! PrettifySvg %!prettier --parser html --print-width 130
