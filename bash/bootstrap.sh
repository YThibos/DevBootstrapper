# shellcheck shell=bash
# DevBootstrapper entry point (docs/shell.md), sourced from two marked blocks in ~/.bashrc:
#   . bootstrap.sh env   top of ~/.bashrc: environment layer for every shell, also non-interactive
#   . bootstrap.sh       bottom of ~/.bashrc: interactive layer, after Ubuntu's own defaults
[ -n "${BASH_VERSION:-}" ] || return 0

__devboot_bash="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The environment layer loads once per shell process.
if [ "${__devboot_env_loaded:-}" != "$$" ]; then
  # shellcheck source=bash/env.sh
  . "$__devboot_bash/env.sh"
  __devboot_env_loaded=$$
fi

if [ "${1:-}" = env ]; then
  unset __devboot_bash
  return 0
fi
case $- in
  *i*) ;;
  *)
    unset __devboot_bash
    return 0
    ;;
esac

# Interactive layer, in this order. Each file skips silently when its tool is missing.
for __devboot_f in \
  tools/history.sh \
  tools/mise.sh \
  tools/git.sh \
  tools/java.sh \
  tools/node.sh \
  tools/docker.sh \
  tools/fzf.sh \
  tools/zoxide.sh \
  tools/wsl.sh \
  aliases.sh \
  functions.sh \
  completions.sh \
  prompt.sh \
  local.sh; do
  # shellcheck disable=SC1090
  [ -r "$__devboot_bash/$__devboot_f" ] && . "$__devboot_bash/$__devboot_f"
done
unset __devboot_f __devboot_bash

# Reminder for terminals other than WezTerm, which runs the daily update itself.
if [ "${TERM_PROGRAM:-}" != WezTerm ] && [ -z "${DEVBOOT_NO_REMINDER:-}" ]; then
  if [ ! -r "$DEV_TOOLS/state/last-update" ] || [ "$(cat "$DEV_TOOLS/state/last-update")" != "$(date +%Y-%m-%d)" ]; then
    printf 'DevBootstrapper: no update today yet - run devup (last: %s)\n' \
      "$(cat "$DEV_TOOLS/state/last-update" 2>/dev/null || echo never)"
  fi
fi
true
