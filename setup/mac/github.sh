#!/bin/sh

# add new ssh key for github
# https://help.github.com/articles/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
ssh-keygen -t rsa -b 4096 -C "bpietravalle@gmail.com"
# Enter filename - use id_rsa_github
eval "$(ssh-agent -s)"
ssh-add -K ~/.ssh/id_rsa_github
pbcopy < ~/.ssh/id_rsa_github.pub
# go to Settings > SSH and GPG Keys > New SSH Key
# test ssh
# ssh -T git@github.com
