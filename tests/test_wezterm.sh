#!/usr/bin/env bash
# The shell side of the WezTerm backgrounds: OSC 7 on every prompt, the ssh mark, tmux passthrough.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox

esc=$'\e'
cat >"$FAKEBIN/ssh" <<'SSH'
#!/usr/bin/env bash
printf '[ssh %s]' "$*"
exit 3
SSH
chmod +x "$FAKEBIN/ssh"

sh() { run bash -c ". \"$DEV/bash/tools/wezterm.sh\"; $1"; }

assert_eq "$(sh 'cd /tmp && HOSTNAME=box __devboot_wezterm_osc7')" "${esc}]7;file://box/tmp${esc}\\" "the prompt hook reports the directory with OSC 7"
assert_contains "$(sh 'echo "$PROMPT_COMMAND"')" "__devboot_wezterm_osc7" "the hook is on PROMPT_COMMAND"
assert_eq "$(run bash -c "PROMPT_COMMAND=other; . \"$DEV/bash/tools/wezterm.sh\"; . \"$DEV/bash/tools/wezterm.sh\"; echo \"\$PROMPT_COMMAND\"")" "__devboot_wezterm_osc7;other" "sourcing twice adds the hook once and keeps the existing command"
assert_eq "$(sh 'cd /tmp && TMUX=x HOSTNAME=box __devboot_wezterm_osc7')" "${esc}Ptmux;${esc}${esc}]7;file://box/tmp${esc}${esc}\\${esc}\\" "inside tmux the sequence is wrapped for passthrough"

out=$(sh 'ssh host -p 22; echo " rc=$?"')
assert_eq "$out" "${esc}]1337;SetUserVar=ssh_active=MQ==$(printf '\a')[ssh host -p 22]${esc}]1337;SetUserVar=ssh_active=$(printf '\a') rc=3" "ssh marks the pane while it runs, clears the mark and keeps the exit code"

finish
