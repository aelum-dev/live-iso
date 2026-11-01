#
# ~/.bashrc
#
# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
PS1='[\u@\h \W]\$ '

alias app-search="pacman -Ss"
alias app-install="sudo pacman -Syu"
alias app-remove="sudo pacman -Rsn"
