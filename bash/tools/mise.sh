# shellcheck shell=bash
# mise: full activation in interactive shells (JAVA_HOME, per-project versions, env).
command -v mise >/dev/null 2>&1 || return 0
eval "$(mise activate bash)"
