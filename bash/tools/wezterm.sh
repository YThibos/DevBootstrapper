# shellcheck shell=bash
# WezTerm integration: report the current directory (OSC 7) and mark ssh sessions (a user
# variable), so the context-aware backgrounds in config/wezterm/wezterm.lua can follow the pane.
# WezTerm cannot see processes inside WSL, so the shell tells it. Inside tmux each sequence is
# wrapped for passthrough (allow-passthrough in config/tmux/tmux.conf).

__devboot_wezterm_send() {
  if [ -n "${TMUX:-}" ]; then
    printf '%sPtmux;%s%s' $'\e' "${1//$'\e'/$'\e\e'}" $'\e\\'
  else
    printf '%s' "$1"
  fi
}

__devboot_wezterm_osc7() {
  __devboot_wezterm_send "$(printf '%s]7;file://%s%s%s' $'\e' "${HOSTNAME:-localhost}" "$PWD" $'\e\\')"
}

__devboot_wezterm_ssh_mark() {
  __devboot_wezterm_send "$(printf '\e]1337;SetUserVar=ssh_active=%s\a' "$1")"
}

case ";${PROMPT_COMMAND:-};" in
  *__devboot_wezterm_osc7*) ;;
  *) PROMPT_COMMAND="__devboot_wezterm_osc7${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac

#: ssh | ssh, telling WezTerm the pane is remote while it runs
ssh() {
  __devboot_wezterm_ssh_mark "$(printf 1 | base64)"
  command ssh "$@"
  local rc=$?
  __devboot_wezterm_ssh_mark ''
  return "$rc"
}
