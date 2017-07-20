#!/bin/sh

#install node
nvm install "v7.10.1"
nvm alias default "v7.10.1"

# install/update global npm packages
files=( "@angular/cli" "karma-cli" "gulp-cli" "eslint" "eslint_d" "jsonlint" "yo" "npm-check" "tslint" "promirepl" "typescript" "typescript-formatter" "generator-fountain-webapp" "generator-fountain-angular2" "prettier" )

for i in "${files[@]}"
do
npm install -g $i
done

#install ternjs in vim
cd ~/.vim/bundle
git clone "git@github.com:ternjs/tern_for_vim.git"
cd tern_for_vim
npm install

# final check vim version
vim --version

# install tidy-html5 -maybe
# https://github.com/htacg/tidy-html5/blob/next/README/BUILD.md
