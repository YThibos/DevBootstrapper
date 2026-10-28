# shellcheck shell=bash
# git shortcuts. gh and glab run through the gitid wrappers so the right account is used,
# even after mise puts the real binaries first on PATH.
#: g | git
#: gs | short status with branch
#: gl | last 20 commits as a graph
#: gd / gds | diff / staged diff
#: lg | lazygit
alias g='git'
alias gs='git status -sb'
alias gl='git log --oneline --graph --decorate -20'
alias gd='git diff'
alias gds='git diff --staged'
command -v lazygit >/dev/null 2>&1 && alias lg='lazygit'
gh() { "$DEV_HOME/bin/wrappers/gh" "$@"; }
glab() { "$DEV_HOME/bin/wrappers/glab" "$@"; }
