# Colorize output, add file type indicator, and put sizes in human readable format
alias ls='ls -GFh'
alias vim='/opt/homebrew/bin/vim'
alias python='python3'
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
alias gsp='git-sync'   # sync + prune: pull --ff-only + fetch --tags + local orphan prune
alias glc='git-local-clean'   # full local reset: delete all non-default branches + worktrees (no landed-proof, never origin)
alias grc='git-remote-clean'  # full remote reset: delete all origin branches with no open PR (no landed-proof, 6h grace unless -f)
alias bfg='java -jar $HOME/bfg-1.14.0.jar'

alias ms='tmuxinator start'
alias tks='tmux kill-session -t'
alias tls='tmux ls'
alias tat='tmux a -t'
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
alias dkc='docker compose '
alias dkcc='docker container'
alias dkn='docker network'
alias dkv='docker volume'
alias dkspf='docker system prune -f'

alias tfw='terraform workspace'
alias tfa='terraform apply'
alias claude="~/.local/bin/claude"
alias pip="pip3"
alias snowsql="/Applications/SnowSQL.app/Contents/MacOS/snowsql"
alias gpl="gh pr list"
alias gpv="gh pr view"
alias gpc="gh pr checks"
alias gil="gh issue list"
alias giv="gh issue view"
alias grl="gh run list"
alias grv="gh run view"

# Claude shell management moved to ~/.zsh/claude.zsh
