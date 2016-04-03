"--------------------------
"VUNDLE CONFIG

set nocompatible
filetype off
runtime match
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
Plugin 'einars/js-beautify'
Plugin 'flazz/vim-colorschemes'
Plugin 'gmarik/Vundle.vim'
Plugin 'kana/vim-textobj-user'
Plugin 'kchmck/vim-coffee-script'
Plugin 'kien/ctrlp.vim'
Plugin 'maksimr/vim-jsbeautify'
Plugin 'nelstrom/vim-textobj-rubyblock'
Plugin 'othree/html5.vim'
Plugin 'pangloss/vim-javascript'
Plugin 'scrooloose/nerdtree'
Plugin 'scrooloose/syntastic'
Plugin 'takac/vim-hardtime'
Plugin 'ternjs/tern_for_vim'
Plugin 'tpope/vim-abolish'
Plugin 'tpope/vim-commentary'
Plugin 'tpope/vim-dispatch'
Plugin 'tpope/vim-fugitive'
Plugin 'tpope/vim-haml'
Plugin 'tpope/vim-repeat'
Plugin 'tpope/vim-surround'
Plugin 'tpope/vim-unimpaired'

"all plugin's must be listed before following 2 lines
call vundle#end()
"-------------------------------
"COLORS
syntax enable
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
set omnifunc=syntaxcomplete#Complete
"-----------------------------
"UI CONFIG
set number "show line numbers
set showcmd " show command in bottom bar
set cursorline " highlight current line
set wildmenu " visual autocomplete for command menu
set lazyredraw " redraw screen only when needed
set showmatch " highlight matching [{()}]
set clipboard=unnamedplus
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

"----------------------------------
"register mngt
noremap <leader>r :registers<CR>
"buffer mngt
nnoremap <silent> [b :bprevious<CR>
nnoremap <silent> ]b :bnext<CR>
nnoremap <silent> [B :bfirst<CR>
nnoremap <silent> ]B :blast<CR>

"----------------------------------
"TERN
noremap <leader>df <ESC>:TernDef<CR>
noremap <leader>dc <ESC>:TernDoc<CR>
noremap <leader>tp <ESC>:TernType<CR>
noremap <leader>rf <ESC>:TernRefs<CR>
noremap <leader>rn <ESC>:TernRename<CR>

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
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
let g:syntastic_javascript_checkers = ['eslint']
let g:syntastic_javascript_eslint_exec = 'eslint_d'
let g:syntastic_yaml_checkers = ['yamlxs']
"------------------------------------
"NERDTREE CONFIG
"automatically starts nerdtree if no file specified
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif
"automatically close vim if nerdtree is only remaining window open
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTreeType") && b:NERDTreeType == "primary") | q | endif
"shortcut to start nerdtree
map <C-n> :NERDTreeToggle<CR> 
"-------------------------------------
"FUGITIVE CONFIG
set statusline=%<%f\ %h%m%r%{fugitive#statusline()}%=%-14.(%l,%c%V%)\ %P
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
"-----Mappings for JSbeautify-------------
autocmd FileType javascript noremap <buffer>  <C-f> :call JsBeautify()<CR>
autocmd FileType html noremap <buffer> <C-f> :call HtmlBeautify()<CR>
autocmd FileType css noremap <buffer> <C-f> :call CSSBeautify()<CR>
"--------Vim-hardtime config-------------
let g:hardtime_default_on = 1
let g:hardtime_showmsg = 1
let g:hardtime_maxcount = 2
let g:hardtime_all_different_key = 1
" need to set rnu after hardtime
" autocmd InsertEnter * :set number
" autocmd InsertLeave * :set rnu
set rnu
"------------Vim-coffeescript----------------
autocmd QuickFixCmdPost * nested cwindow | redraw!
" let coffee_lint_options = '-f	coffeelint.json'
noremap <leader>cw <ESC>:CoffeeWatch<CR>
noremap <leader>cr <ESC>:CoffeeRun<CR>
noremap <leader>cl <ESC>:CoffeeLint<CR>

