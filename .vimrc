"--------------------------
"VUNDLE CONFIG

set nocompatible
filetype off
runtime match
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
Plugin 'Chiel92/vim-autoformat'
Plugin 'dense-analysis/ale'
Plugin 'davidhalter/jedi-vim'
Plugin 'einars/js-beautify'
Plugin 'flazz/vim-colorschemes'
Plugin 'jiangmiao/auto-pairs'
Plugin 'gmarik/Vundle.vim'
Plugin 'gioele/vim-autoswap.git'
Plugin 'hashivim/vim-terraform'
Plugin 'ctrlpvim/ctrlp.vim'
Plugin 'jparise/vim-graphql'
Plugin 'leafgarland/typescript-vim'
Plugin 'maksimr/vim-jsbeautify'
Plugin 'MikeCoder/markdown-preview.vim'
Plugin 'mitermayer/vim-prettier', {'do' : 'npm install'}
Plugin 'othree/html5.vim'
Plugin 'pangloss/vim-javascript'
" Plugin 'Quramy/tsuquyomi'
Plugin 'Quramy/vim-js-pretty-template'
Plugin 'rust-lang/rust.vim'
Plugin 'Shougo/vimproc.vim', {'do' : 'make'}
Plugin 'scrooloose/nerdtree'
Plugin 'scrooloose/syntastic'
" Plugin 'Shougo/Deoplete.nvim'
Plugin 'Shougo/unite-outline'
Plugin 'takac/vim-hardtime'
" Plugin 'ternjs/tern_for_vim' "issues with es6 and/or reading py library
Plugin 'tell-k/vim-autopep8'
Plugin 'tpope/vim-abolish'
Plugin 'tpope/vim-commentary'
Plugin 'tpope/vim-dispatch'
Plugin 'tpope/vim-fugitive'
Plugin 'tpope/vim-jdaddy'
Plugin 'tpope/vim-repeat'
Plugin 'tpope/vim-surround'
Plugin 'tpope/vim-unimpaired'
Plugin 'tmux-plugins/vim-tmux'
Plugin 'vim-airline/vim-airline'
Plugin 'vim-airline/vim-airline-themes'
Plugin 'vim-scripts/AutoComplPop'
Plugin 'vim-scripts/ciscoacl.vim'
"all plugin's must be listed before following 2 lines
call vundle#end()
"-------------------------------
"COLORS
" syntax enable
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
set softtabstop=3 "number of spaces in tab when editing
set autoindent
"-----------------------------
"COMPLETION
set omnifunc=ale#completion#OmniFunc
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
"--------------------------------
"SEARCHING
set incsearch "search as chars are enters
set hlsearch "highlight matches

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
"TERN
" uninstalled tern_for_vim due to issues with es6
" noremap <leader>df <ESC>:TernDef<CR>
" noremap <leader>dc <ESC>:TernDoc<CR>
" noremap <leader>tp <ESC>:TernType<CR>
" noremap <leader>rf <ESC>:TernRefs<CR>
" noremap <leader>rn <ESC>:TernRename<CR>

"----------------------------------
"SEARCH/SUB
nnoremap & :&&<CR>
xnoremap & :&&<CR>
"----------------------------------
"SYNTASTIC CONFIG- recommended

set statusline+=%#warningsmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_aggregate_errors = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
let g:syntastic_javascript_checkers = ['eslint']
let g:syntastic_javascript_eslint_exec = 'eslint_d'
" let g:syntastic_javascript_eslint_exe='$(npm bin)/eslint' ## project specific
let g:syntastic_yaml_checkers = ['yamlxs']

" let g:tsuquyomi_disable_quickfix = 1
" let g:syntastic_typescript_checkers = ['tsuquyomi']
let g:syntastic_typescript_checkers = ['ale']

let g:syntastic_html_tidy_ignore_errors = ["proprietary attribute " ,"has invalid value", "attribute name", "trimming empty \<", "inserting implicit ", "unescaped \&" , "lacks \"action", "lacks value", "lacks \"src", "lacks \"alt", "is not recognized!", "discarding unexpected", "replacing obsolete "]

let g:syntastic_python_python_exec = 'python3'
let g:syntastic_python_checkers = ['pycodestyle']
"----------------------------------------------------
" vim-autopep8 config - using syntastic to show errors and autopep8 to fix
let g:autopep8_on_save = 1
let g:autopep8_disable_show_diff=1
"----------------------------------------------------
" Vim-Typescript Config
" with current setup, this plugin is needed to set ts file type >
" https://github.com/vim-syntastic/syntastic/issues/1655
let g:typescript_compiler_binary = 'tsc'
let g:typescript_compiler_options = '--lib es7'
let g:AutoPairsFlyMode = 1
autocmd QuickFixCmdPost [^l]* nested cwindow
autocmd QuickFixCmdPost ^l* nested lwindow

" Ale config
nnoremap <leader>def <ESC>:ALEGoToDefinition<CR>
nnoremap <leader>ref <ESC>:ALEFindReferences<CR>
nnoremap <leader>hov <ESC>:ALEHover<CR>
nnoremap <leader>sym <ESC>:ALESymbolSearch<CR>

nnoremap <leader>jpt <ESC>:JsPreTmpl html<CR>
nnoremap <leader>jpc <ESC>:JsPreTmplClear<CR>


let g:ale_completion_tsserver_autoimport = 1
let g:ale_completion_enabled = 1
let g:airline#extensions#ale#enabled = 1
let g:ale_set_loclist = 0
let g:ale_set_quickfix = 1
let g:ale_open_list = 1
" test what it does automatically first
" let g:ale_linters = {
" \   'javascript': ['eslint_d'],
" \}
" let b:ale_fixers = ['prettier', 'eslint']
let g:ale_fix_on_save = 1
" let g:deoplete#enable_at_startup = 1
"
"----------------------------------------------------
"NERDTREE CONFIG
"automatically starts nerdtree if no file specified
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif
"automatically close vim if nerdtree is only remaining window open
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTreeType") && b:NERDTreeType == "primary") | q | endif
"shortcut to start nerdtree
map <C-n> :NERDTreeToggle<CR> 

"CWD to current folder when open file
autocmd BufEnter * silent! lcd %:p:h

"-------------------------------------
"FUGITIVE CONFIG
set statusline=%<%f\ %h%m%r%{fugitive#statusline()}%=%-14.(%l,%c%V%)\ %P
:set tags^=./.git/tags;
" set statusline+=%{fugitive#statusline()}
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
"--------editorconfig-vim-------------
" let g:EditorConfig_exclude_patterns = ["fugitive://.*","scp://.*"]


"--------Vim-hardtime config-------------
let g:hardtime_default_on = 1
let g:hardtime_showmsg = 1
let g:hardtime_maxcount = 2
let g:hardtime_all_different_key = 1
" need to set rnu after hardtime
" autocmd InsertEnter * :set number
" autocmd InsertLeave * :set rnu
set rnu
set laststatus=2 "always display statusline
" open location/quickfix for data returned from grep,vimgrep, etc
augroup myvimrc
  autocmd!
    autocmd QuickFixCmdPost [^l]* cwindow
    autocmd QuickFixCmdPost l*    lwindow
augroup END

" for syntax highlighting for act files
augroup filetype 
        au! BufRead,BufNewFile *.crules     set filetype=ciscoacl 
        au! BufRead,BufNewFile *.acl        set filetype=ciscoacl 
augroup END 

" vim-terraform
let g:terraform_fmt_on_save=1

let g:prettier#autoformat = 0
autocmd BufWritePre *.js,*.jsx,*.mjs,*.ts,*.tsx,*.css,*.less,*.scss,*.json,*.graphql,*.md,*.vue,*.yaml,*.html PrettierAsync

au BufNewFile,BufRead Dockerfile* set filetype=dockerfile
au BufNewFile,BufRead .env.* set filetype=sh
" from https://webpack.js.org/configuration/watch/#vim
" set backupcopy=yes
"
" tell autoswap.vim about tmux
let g:autoswap_detect_tmux = 1
