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

# The directory as the path of a file:// URL: the ASCII characters that would end or change
# the URL (space, %, #, ? and the like) are percent-encoded; other characters stay as they are.
__devboot_wezterm_url_path() {
  local path=$1 out='' c i
  case $path in
    *[\ %#?\"\<\>\\^\`\{\|\}]* | *[[:cntrl:]]*) ;;
    *) printf '%s' "$path"; return ;;
  esac
  for ((i = 0; i < ${#path}; i++)); do
    c=${path:i:1}
    case $c in
      [\ %#?\"\<\>\\^\`\{\|\}] | [[:cntrl:]]) printf -v c '%%%02X' "'$c" ;;
    esac
    out+=$c
  done
  printf '%s' "$out"
}

__devboot_wezterm_ssh_mark() {
  __devboot_wezterm_send "$(printf '\e]1337;SetUserVar=ssh_active=%s\a' "$1")"
}

# At every prompt: the directory, and the end of any ssh mark. A prompt means no ssh runs in
# the foreground, so this also clears a mark left by an ssh interrupted before it returned.
__devboot_wezterm_osc7() {
  __devboot_wezterm_send "$(printf '%s]7;file://%s%s%s' $'\e' "${HOSTNAME:-localhost}" "$(__devboot_wezterm_url_path "$PWD")" $'\e\\')"
  if [ -n "${__devboot_wezterm_in_ssh:-}" ]; then
    __devboot_wezterm_ssh_mark ''
    __devboot_wezterm_in_ssh=
  fi
}

case ";${PROMPT_COMMAND:-};" in
  *__devboot_wezterm_osc7*) ;;
  *) PROMPT_COMMAND="__devboot_wezterm_osc7${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac

#: ssh | ssh, telling WezTerm the pane is remote while it runs
ssh() {
  __devboot_wezterm_in_ssh=1
  __devboot_wezterm_ssh_mark "$(printf 1 | base64)"
  command ssh "$@"
  local rc=$?
  __devboot_wezterm_ssh_mark ''
  __devboot_wezterm_in_ssh=
  return "$rc"
}
