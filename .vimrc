"--------------------------
"VUNDLE CONFIG

set nocompatible
filetype off
runtime match
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
Plugin 'gmarik/Vundle.vim'
Plugin 'scrooloose/nerdtree'
Plugin 'tpope/vim-fugitive'
Plugin 'kien/ctrlp.vim'
Plugin 'scrooloose/syntastic'
Plugin 'flazz/vim-colorschemes'
Plugin 'kana/vim-textobj-user'
Plugin 'nelstrom/vim-textobj-rubyblock'
Plugin 'tpope/vim-repeat'
Plugin 'tpope/vim-dispatch'
Plugin 'tpope/vim-commentary'
Plugin 'tpope/vim-unimpaired'
Plugin 'tpope/vim-surround'

"all plugin's must be listed before following 2 lines
call vundle#end()
filetype plugin indent on
"-------------------------------
"COLORS
syntax enable
set background=dark
colorscheme solarized
"-------------------------------
"INDENTATION
filetype plugin indent on
set tabstop=2 "number of spaces per tab
set shiftwidth=2
set softtabstop=3 "number of spaces in tab when editing
set autoindent
"-----------------------------
"UI CONFIG
set number "show line numbers
set showcmd " show command in bottom bar
set cursorline " highlight current line
filetype indent on "load filetype-specific indent files
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
set foldenable "enable it
set foldlevelstart=10 "open most folds by default
set foldnestmax=10 "10 mested max
set foldmethod=indent "fold by indentation
"--------------------------------
"MOVEMENTS






"-----------------------------------
"LEADER SHORTCUTS

"auto align current paragraph
noremap <leader>a =ip
"show invisibles
nmap <leader>l :set list!<CR> 
"yank paragraph
noremap <leader> cp yap<S-{>p
"saving file
noremap <leader>c <ESC>:w<CR>
inoremap <leader>c <ESC>:w<CR>
"quitting file
noremap <leader>q :q<CR>
inoremap <leader>q <ESC>:q<CR>
"saving & quitting file
noremap <leader>cq :wq<CR>
inoremap <leader>cq <ESC>:wq<CR>
"Quickly open/reload vimrc
noremap <leader>ev :split $MYVIMRC<CR>
noremap <leader>cv :source $MYVIMRC<CR>

"register mngt
noremap <leader>r :registers<CR>
"buffer mngt
noremap <leader>bb :ls<CR>
noremap <leader>bn :bn<CR>
noremap <leader>bp :bp<CR>
"----------------------------------
"SYNTASTIC CONFIG- recommended

set statusline+=%#warningsmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
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
set statusline+=%{fugitive#statusline()}
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
