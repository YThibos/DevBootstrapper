# shellcheck shell=bash
# mise: full activation in interactive shells (JAVA_HOME, per-project versions, env), for the
# shell that loads this file (__devboot_shell is set by bash/bootstrap.sh and zsh/bootstrap.zsh).
command -v mise >/dev/null 2>&1 || return 0
eval "$(mise activate "${__devboot_shell:-bash}")"
