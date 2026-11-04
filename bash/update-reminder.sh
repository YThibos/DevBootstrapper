# shellcheck shell=bash
# Reminder for terminals other than WezTerm, which runs the daily update itself.
# Shared by the bash and zsh interactive layers.
if [ "${TERM_PROGRAM:-}" != WezTerm ] && [ -z "${DEVBOOT_NO_REMINDER:-}" ]; then
  if [ ! -r "$DEV_TOOLS/state/last-update" ] || [ "$(cat "$DEV_TOOLS/state/last-update")" != "$(date +%Y-%m-%d)" ]; then
    printf 'DevBootstrapper: no update today yet - run devup (last: %s)\n' \
      "$(cat "$DEV_TOOLS/state/last-update" 2>/dev/null || echo never)"
  fi
fi
true
