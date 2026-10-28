# shellcheck shell=bash
# fzf key bindings: Ctrl-r history search, Ctrl-t file picker, Alt-c cd into a folder.
command -v fzf >/dev/null 2>&1 || return 0
#: Ctrl-r | fuzzy search shell history
#: Ctrl-t | fuzzy pick a file into the command line
if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi
eval "$(fzf --bash 2>/dev/null)"
