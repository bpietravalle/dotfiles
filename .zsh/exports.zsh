#USR###############
# PATH EXPORTS #
# ##############

[ -f $HOME/.travis/travis.sh ] && source $HOME/.travis/travis.sh
export PYTHON_BIN=/usr/local/opt/python/libexec/bin # python3 rewrites
export NODE_PATH=$HOME/local/lib/node_modules
export USR_BIN=/usr/local/bin
export LOCAL_DOT_BIN=$HOME/.bin
export LOCAL_BIN=$HOME/bin
export HOME_BIN=$HOME/local/bin
export RBENV_PATH=$HOME/.rbenv/bin
export YARN_PATH=$HOME/.yarn/bin
export GOLANG_EXE_PATH=/usr/local/go/bin
export GOPATH=$HOME/go
export CARGO_PATH=$HOME/.cargo/bin
export GO_BIN_PATH=$GOPATH/bin
export FABRIC_BIN_PATH=$HOME/docs/dev/fabric-samples/bin
export PYTHON3_BIN=/Users/brianpietravalle/Library/Python/3.7/bin
PG_APP_PATH=/Applications/Postgres.app/Contents/Versions/latest/bin
export PATH=$RBENV_PATH:$HOME_BIN:$NODE_PATH:$USR_BIN:$LOCAL_BIN:$LOCAL_DOT_BIN:$GO_BIN_PATH:$GOLANG_EXE_PATH:$YARN_PATH:$CARGO_PATH:$FABRIC_BIN_PATH:$PYTHON_BIN:$PYTHON3_BIN:$PG_APP_PATH:$PATH

# this is for mac
# export PATH=${PATH}:/Applications/Android\ Studio.app/sdk/platform-tools:/Applications/Android\ Studio.app/sdk/tools
# export JAVA_HOME=$(/usr/libexec/java_home)
# export PATH=${JAVA_HOME}/bin:$PATH

################
# Misc. EXPORTS #
# ##############

# Setup terminal, and turn on colors
export TERM=xterm-256color
export CLICOLOR=1
export LSCOLORS=Gxfxcxdxbxegedabagacad

# Recommened for tmux to show window titles properly
export DISABLE_AUTO_TITLE=true

# Enable color in grep
export GREP_OPTIONS='--color=auto'
export GREP_COLOR='3;33'
export EDITOR=vim
# This resolves issues install the mysql, postgres, and other gems with native non universal binary extensions
export ARCHFLAGS='-arch x86_64'

# CTAGS Sorting in VIM/Emacs is better behaved with this in place
export LC_COLLATE=C
export KEYTIMEOUT=1
