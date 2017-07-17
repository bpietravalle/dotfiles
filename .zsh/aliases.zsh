# Colorize output, add file type indicator, and put sizes in human readable format
alias ls='ls -GFh'
alias reload=". ~/.zshrc && echo 'ZSH config reloaded from ~/.zshrc'"
# Same as above, but in long listing format
alias ll='ls -GFhl'
#quiet mode for bugs with ubuntu/Chromium
alias google='google-chrome --disable-gpu'

alias kk='kill -9 '
alias lsw='lsof -wni '

alias bower='noglob bower'
alias bro='browserify'
alias g='gulp '

alias gsm='git submodule '
alias gs='git status '
alias ga='git add '
alias gb='git branch '
alias gc='git commit'
alias gd='git diff'
alias go='git checkout '
alias gk='gitk --all&'
alias gx='gitx --all'

alias df='vim $GINGER'
alias bb='cd $BABY/browser/src/app && vim'
alias bm='cd $BABY/mobile/ && vim'
alias bs='cd $BABY/server/src && vim'
alias fs='cd $POSH/src/ && vim'
alias fl='cd $SPORTY/src/ && vim'

alias ms='tmuxinator start'
alias tks='tmux kill-session -t'
alias lcov='cat ./coverage/lcov-report/lcov.info | ./node_modules/coveralls/bin/coveralls.js' 

alias jm='jsdoc2md --plugin dmd-bitbucket '
alias jmd='jsdoc2md --plugin dmd-bitbucket --src ./*.js > ./README.md'

alias nas='npmAddScript '

alias bolt='firebase-bolt '
alias iib='ionic build ios '
alias gib=' g build && ionic build ios '
alias docker-test-build='docker run --rm -it -e "PAYLOAD_FILE=repl/payload-mock.json" -e "CONFIG_FILE=repl/config-mock.yml" '
alias docker-test-local='docker run --rm -it -e "PAYLOAD_FILE=repl/payload-mock.json" -e "CONFIG_FILE=repl/config-mock.yml" -v "$PWD":/app -w /app iron/node '
# from https://gist.github.com/jhartikainen/36a955f3bfe06557e16e
# returns added (A), modified (M), untracked (??) filenames
# function git_changed_files {
#   echo $(git status -s | grep -E '[AM?]+\s.+?\.js$' | cut -c3-)
# }
# run lint over changed files, if any
# alias lint='(files=$(git_changed_files); if [[ -n $files ]]; then eslint ${=files}; fi)'

