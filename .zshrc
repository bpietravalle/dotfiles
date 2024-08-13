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
source ~/.zsh/ssh.zsh
source ~/.zsh/zsh-nvm.plugin.zsh
# source ~/.zsh/plugins.zsh
# source ~/.zsh/aws.zsh

precmd() {
  if [[ -n "$TMUX" ]]; then
    tmux setenv "$(tmux display -p 'TMUX_PWD_#D')" "$PWD"
  fi
}

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm
export PATH="$HOME/.yarn/bin:$PATH" # version 1 yarn global bin
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# recommended by rbenv
eval "$(rbenv init - --no-rehash)"
source ~/bin/tmuxinator.zsh

ulimit -n 100000 unlimited # might change to 65536 65536
# tabtab source for packages
# uninstall by removing these lines
[[ -f ~/.config/tabtab/__tabtab.zsh ]] && . ~/.config/tabtab/__tabtab.zsh || true



# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/brianpietravalle/.bin/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/brianpietravalle/.bin/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/brianpietravalle/.bin/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/brianpietravalle/.bin/google-cloud-sdk/completion.zsh.inc'; fi

# Created by `pipx` on 2023-05-10 01:32:30
export PATH="$PATH:/Users/brianpietravalle/.local/bin"

# Created by `pipx` on 2023-05-10 02:19:45
export PATH="$PATH:/Users/brianpietravalle/Library/Python/3.11/bin"
