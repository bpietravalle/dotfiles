function zsh_recompile {
  autoload -U zrecompile
  rm -f ~/.zsh/*.zwc
  [[ -f ~/.zshrc ]] && zrecompile -p ~/.zshrc
  [[ -f ~/.zshrc.zwc.old ]] && rm -f ~/.zshrc.zwc.old

  for f in ~/.zsh/**/*.zsh; do
    [[ -f $f ]] && zrecompile -p $f
    [[ -f $f.zwc.old ]] && rm -f $f.zwc.old
  done

  [[ -f ~/.zcompdump ]] && zrecompile -p ~/.zcompdump
  [[ -f ~/.zcompdump.zwc.old ]] && rm -f ~/.zcompdump.zwc.old

  source ~/.zshrc
}

function extract {
  echo Extracting $1 ...
  if [ -f $1 ] ; then
      case $1 in
          *.tar.bz2)   tar xjf $1  ;;
          *.tar.gz)    tar xzf $1  ;;
          *.bz2)       bunzip2 $1  ;;
          *.rar)       unrar x $1    ;;
          *.gz)        gunzip $1   ;;
          *.tar)       tar xf $1   ;;
          *.tbz2)      tar xjf $1  ;;
          *.tgz)       tar xzf $1  ;;
          *.zip)       unzip $1   ;;
          *.docx)      unzip $1   ;;
          *.Z)         uncompress $1  ;;
          *.7z)        7z x $1  ;;
          *)        echo "'$1' cannot be extracted via extract()" ;;
      esac
  else
      echo "'$1' is not a valid file"
  fi
}

function ss {
  if [ -e script/server ]; then
    script/server $@
  else
    script/rails server $@
  fi
}

function sc {
  if [ -e script/console ]; then
    script/console $@
  else
    script/rails console $@
  fi
}

function trash () {
  local path
  for path in "$@"; do
    # ignore any arguments
    if [[ "$path" = -* ]]; then :
    else
      local dst=${path##*/}
      # append the time if necessary
      while [ -e ~/.Trash/"$dst" ]; do
        dst="$dst "$(date +%H-%M-%S)
      done
      /bin/mv "$path" ~/.Trash/"$dst"
    fi
  done
}

function gitFindReplace () {
  # on linux
  git grep -l $1 | xargs sed -i "s/$1/$2/g"
  # on mac
# git grep -l 'original_text' | xargs sed -i '' -e 's/original_text/new_text/g'
}

function removeVimBuffers () {
# -type d \( -path dir1 -o -path dir2 -o -path dir3 \) for multiple dirs
#
#doesnt work bc prune removes depth
  find . -path "./node_modules" -prune -name "*.swo" -type f -delete
  find . -path "./node_modules" -prune -name "*.swo" -type f -delete
  find . -path "./node_modules" -prune -name "*.swo" -type f -delete
}
function addWatchers() {
  echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
}
function fixGitObjectsCorruptedErrors() {
# https://stackoverflow.com/questions/11706215/how-to-fix-git-error-object-file-is-empty
  find .git/objects/ -type f -empty | xargs rm
  git fetch -p
  git fsck --full
}
function strip_diff_leading_symbols {
  local color_code_regex="(\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K])"

  # simplify the unified patch diff header
  sed -r "s/^($color_code_regex)diff --git .*$//g" | \
        sed -r "s/^($color_code_regex)index .*$/\n\1$(rule)/g" | \
        sed -r "s/^($color_code_regex)\+\+\+(.*)$/\1+++\5\n\1$(rule)\x1B\[m/g" |\

  # actually strips the leading symbols
  sed -r "s/^($color_code_regex)[\+\-]/\1 /g"
}
# to profile vim -- not sure where else to put it
# :profile start logname.log
# :profile file *
# :profile func *
# :e foo.md
# :q
## Print a horizontal rule
rule () {
  printf "%$(tput cols)s\n"|tr " " "─"}}

