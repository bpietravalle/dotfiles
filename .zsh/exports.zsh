# Currently this path is appendend to dynamically when picking a ruby version
export NODE_PATH=$HOME/local/lib/node_modules

export PATH=$NODE_PATH:/usr/local/sbin:/usr/local/bin:/usr/local/share/npm/bin:$PATH

# Setup terminal, and turn on colors
export TERM=xterm-256color
export CLICOLOR=1
export LSCOLORS=Gxfxcxdxbxegedabagacad

# Enable color in grep
export GREP_OPTIONS='--color=auto'
export GREP_COLOR='3;33'
export EDITOR=vim
# This resolves issues install the mysql, postgres, and other gems with native non universal binary extensions
export ARCHFLAGS='-arch x86_64'

# export LESS='--ignore-case --raw-control-chars'
export PAGER='most'
# 
# CTAGS Sorting in VIM/Emacs is better behaved with this in place
export LC_COLLATE=C

#
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" # Load RVM into a shell session *as a function*
### Added by the Heroku Toolbelt
export PATH="/usr/local/heroku/bin:$PATH"
#
# added by travis gem
[ -f $HOME/.travis/travis.sh ] && source $HOME/.travis/travis.sh


# help!
# autoload -U run-help
# autoload run-help-git
# autoload run-help-svn
# autoload run-help-svk
# unalias run-help
# alias help=run-help
