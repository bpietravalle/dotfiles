#!/bin/sh
# install dotfiles repo and symlink
if [ ! -d "$HOME/docs" ]; then
  mkdir "$HOME/docs"
fi
if [ ! -d "$HOME/docs/dev" ]; then
  mkdir "$HOME/docs/dev"
fi
cd $HOME/docs/dev
git clone "git@github.com:bpietravalle/dotfiles.git"
cd dotfiles
git fetch --all
git pull --all
cd ~
DF_DIR="$HOME/docs/dev/dotfiles"
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

cd $HOME/.vim/bundle
git clone "git@github.com:VundleVim/Vundle.vim.git"
# vim do :PluginInstall
# vim do :VimProcInstall
