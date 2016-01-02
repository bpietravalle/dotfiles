# Colorize output, add file type indicator, and put sizes in human readable format
alias ls='ls -GFh'
alias reload=". ~/.zshrc && echo 'ZSH config reloaded from ~/.zshrc'"
# Same as above, but in long listing format
alias ll='ls -GFhl'

#quiet mode for bugs with ubuntu/Chromium
alias google='google-chrome --disable-gpu'

alias rake='noglob rake'
alias bower='noglob bower'
alias bro='browserify'
alias g='gulp '

alias gs='git status '
alias ga='git add '
alias gb='git branch '
alias gc='git commit'
alias gd='git diff'
alias go='git checkout '
alias gk='gitk --all&'
alias gx='gitx --all'

alias bb='cd $BABY/browser/src/app && vim'
alias bm='cd $BABY/mobile/files/src/app && vim'
alias bmd='cd $BABY/mobile/dist/src/app && vim'
alias bs='cd $BABY/server/src && vim'
alias fs='cd $POSH/src/ && vim'
alias fl='cd $SPORTY/src/ && vim'
