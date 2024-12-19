#!/bin/sh
# install dotfiles repo and symlink
cd ~
DF_DIR="$HOME/dev/dotfiles"
files=( ".bash_profile" ".bashrc" ".git_template" ".gitconfig" ".profile" ".tmux.conf" ".tmuxinator" ".vimrc" ".zsh" ".zshrc" "bin" ".bin" ".terraformrc")
for i in "${files[@]}"
do
ln -s $DF_DIR/$i
done
# ln -s "$DF_DIR/setup/mac/.laptop.local"

# setup VundleVim
if [ ! -d "$HOME/.vim" ]; then
  mkdir "$HOME/.vim"
fi
if [ ! -d "$HOME/.vim/bundle" ]; then
  mkdir "$HOME/.vim/bundle"
fi

# cd $HOME/.vim/bundle
# git clone "git@github.com:VundleVim/Vundle.vim.git"
# vim do :PluginInstall
# vim do :VimProcInstall
