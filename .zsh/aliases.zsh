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
alias gk='gitk --all&'
alias gx='gitx --all'

alias bb='$BITBRAID_PATH'
alias bbf='$BITBRAID_PATH/frontend'
alias bblibs='$BITBRAID_PATH/frontend/libs'
alias bbshareser='$BITBRAID_PATH/frontend/libs/shared/services'
alias bbapp='$BITBRAID_PATH/frontend/apps/web/src/app'
alias bbfeat='$BITBRAID_PATH/frontend/libs/web/features'
alias bbpage='$BITBRAID_PATH/frontend/libs/web/pages'

alias ms='tmuxinator start'
alias tks='tmux kill-session -t'
alias tls='tmux ls'
alias lcov='cat ./coverage/lcov-report/lcov.info | ./node_modules/coveralls/bin/coveralls.js' 

alias jm='jsdoc2md --plugin dmd-bitbucket '
alias jmd='jsdoc2md --plugin dmd-bitbucket --src ./*.js > ./README.md'

alias nas='npmAddScript '

alias docker-clean=' \
  docker ps --no-trunc -aqf "status=exited" | xargs docker rm ; \
  docker images --no-trunc -aqf "dangling=true" | xargs docker rmi ; \
  docker volume ls -qf "dangling=true" | xargs docker volume rm'

# from https://gist.github.com/jhartikainen/36a955f3bfe06557e16e
# returns added (A), modified (M), untracked (??) filenames
# function git_changed_files {
#   echo $(git status -s | grep -E '[AM?]+\s.+?\.js$' | cut -c3-)
# }
# run lint over changed files, if any
# alias lint='(files=$(git_changed_files); if [[ -n $files ]]; then eslint ${=files}; fi)'
alias dk='docker '
alias dki='docker image'
alias dkc='docker-compose '
alias dkcc='docker container'
