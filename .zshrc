source ~/.zsh/colors.zsh
source ~/.zsh/setopt.zsh
source ~/.zsh/exports.zsh
source ~/.zsh/prompt.zsh
source ~/.zsh/completion.zsh
source ~/.zsh/aliases.zsh
source ~/.zsh/bindkeys.zsh
source ~/.zsh/functions.zsh
source ~/.zsh/history.zsh
source ~/.zsh/zsh_hooks.zsh
source ~/.zsh/zsh-nvm.plugin.zsh
#not currently using ~/.zsh/ssh-find-agent.sh
precmd() {
  if [[ -n "$TMUX" ]]; then
    tmux setenv "$(tmux display -p 'TMUX_PWD_#D')" "$PWD"
  fi
}

eval $(setxkbmap -option caps:swapescape)


export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm
export PATH="$HOME/.yarn/bin:$PATH"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# recommended by rbenv
eval "$(rbenv init - --no-rehash)"
source ~/bin/tmuxinator.zsh

# tabtab source for serverless package
# uninstall by removing these lines or running `tabtab uninstall serverless`
[[ -f /home/bpietravalle/.nvm/versions/node/v8.9.1/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.zsh ]] && . /home/bpietravalle/.nvm/versions/node/v8.9.1/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.zsh
# tabtab source for sls package
# uninstall by removing these lines or running `tabtab uninstall sls`
[[ -f /home/bpietravalle/.nvm/versions/node/v8.9.1/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.zsh ]] && . /home/bpietravalle/.nvm/versions/node/v8.9.1/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.zsh
# tabtab source for slss package
# uninstall by removing these lines or running `tabtab uninstall slss`
[[ -f /home/bpietravalle/.nvm/versions/node/v8.9.1/lib/node_modules/serverless/node_modules/tabtab/.completions/slss.zsh ]] && . /home/bpietravalle/.nvm/versions/node/v8.9.1/lib/node_modules/serverless/node_modules/tabtab/.completions/slss.zsh
