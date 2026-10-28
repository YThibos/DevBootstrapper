# shellcheck shell=bash
# General aliases. Annotate each with a "#: usage | description" line for dev cheat.
#: ll / la / lt | long list / with hidden files / tree (eza when installed)
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first'
  alias ll='eza -l --git --group-directories-first'
  alias la='eza -la --git --group-directories-first'
  alias lt='eza --tree --level=2 --group-directories-first'
else
  alias ls='ls --color=auto'
  alias ll='ls -lh --color=auto'
  alias la='ls -lAh --color=auto'
  alias lt='ls -R'
fi
alias grep='grep --color=auto'
#: .. / ... | up one / two folders
alias ..='cd ..'
alias ...='cd ../..'
#: dh | go to the dev home
#: src / home / work | go to sources/, sources/home/, sources/work/
alias dh='cd "$DEV_HOME"'
alias src='cd "$DEV_HOME/sources"'
alias home='cd "$DEV_HOME/sources/home"'
alias work='cd "$DEV_HOME/sources/work"'
#: path | PATH, one entry per line
alias path='tr ":" "\n" <<<"$PATH"'
#: tm | attach to (or start) the tmux session "main"
alias tm='tmux new-session -A -s main'
#: cl | claude
alias cl='claude'
