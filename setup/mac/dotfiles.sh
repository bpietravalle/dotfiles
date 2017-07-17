#!/bin/bash
# install dotfiles repo and symlink
if [ ! -d "$HOME/docs" ]; then
  mkdir "$HOME/docs"
fi
if [ ! -d "$HOME/docs/dev" ]; then
  mkdir "$HOME/docs/dev"
fi
cd ~/docs/dev
git clone "git@github.com:bpietravalle/dotfiles.git"
cd ~
DF_DIR="~/docs/dev/dotfiles"
files=( ".bash_profile" ".bashrc" ".git_template" ".gitconfig" ".profile" ".tmux.conf" ".tmuxinator" ".vimrc" ".zsh" ".zshrc" "bin")

for i in "${files[@]}"
do
ln -s $DF_DIR/$i
done

ln -s "$DF_DIR/setup/mac/.laptop.local"
