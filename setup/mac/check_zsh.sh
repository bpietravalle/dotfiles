#!/bin/sh
fancy_echo() {
  local fmt="$1"; shift

  # shellcheck disable=SC2059
  printf "\n$fmt\n" "$@"
}

update_shell() {
  local shell_path;
  shell_path="$(which zsh)"

  fancy_echo "Changing your shell to zsh ..."
  if ! grep "$shell_path" /etc/shells > /dev/null 2>&1 ; then
    fancy_echo "Adding '$shell_path' to /etc/shells"
    sudo sh -c "echo $shell_path >> /etc/shells"
  fi
  chsh -s "$shell_path"
}

# case "$SHELL" in
#   */zsh)
# if [ "$(which zsh)" != '/usr/local/bin/zsh' ] ; then
#   update_shell
# fi
sudo echo "$(which zsh)" >> /etc/shells
chsh -s $(which zsh)

# ;;
  # *)
    # update_shell
    # ;;
    # esac
