#!/usr/bin/env bash
# Tests compare against literal "$VAR" and "~/" strings, and type shell code, on purpose.
# shellcheck disable=SC2016,SC2088
# What the tmux-driven WezTerm needs from the machine: the rendered tmux configuration, Fira Code
# in .local/fonts, and the completions devup generates for zsh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox

devup() { run bash "$DEV/install/devup.sh" "$@" 2>&1; }
mkdir -p "$DEV/.local"

# The tmux configuration: rendered for the machine's shell and linked from ~/.tmux.conf.
tmux_conf() { cat "$DEV/.local/tmux/tmux.conf"; }
printf 'DEV_SHELL=zsh\n' >"$DEV/.local/profile.env"
devup --only render,links >/dev/null
assert_eq "$(readlink "$HOME/.tmux.conf")" "$DEV/.local/tmux/tmux.conf" "~/.tmux.conf is the file that is linked"
assert_contains "$(tmux_conf)" 'set -g default-command "zsh -l"' "tmux starts zsh as a login shell when opted in"
assert_contains "$(tmux_conf)" "set -g allow-passthrough on" "tmux lets the shell talk to WezTerm"
assert_not_contains "$(tmux_conf)" "{{" "no template placeholder is left in the rendered file"
printf 'DEV_SHELL=bash\n' >"$DEV/.local/profile.env"
devup --only render >/dev/null
assert_contains "$(tmux_conf)" 'set -g default-command "bash -l"' "tmux starts bash as a login shell by default"
: >"$DEV/.local/profile.env"
devup --only render >/dev/null
assert_contains "$(tmux_conf)" 'set -g default-command "bash -l"' "and without any shell setting"
if command -v tmux >/dev/null 2>&1; then
  tmux_run() { run env TMUX_TMPDIR="$SANDBOX" tmux -L devboot-test "$@"; }
  tmux_run -f "$HOME/.tmux.conf" new-session -d -s check
  assert_eq "$(tmux_run show-options -g default-command)" 'default-command "bash -l"' "tmux accepts the rendered configuration"
  assert_eq "$(tmux_run show-options -gv allow-passthrough)" on "and has passthrough on"
  tmux_run kill-server
fi

# Fira Code: downloaded once into .local/fonts, with a stand-in for curl.
fira="$SANDBOX/fira"
mkdir -p "$fira/ttf" "$fira/variable_ttf"
touch "$fira/ttf/FiraCode-Regular.ttf" "$fira/ttf/FiraCode-Bold.ttf" "$fira/variable_ttf/FiraCode-VF.ttf"
(cd "$fira" && python3 -c "
import zipfile
with zipfile.ZipFile('$SANDBOX/fira.zip', 'w') as z:
    for name in ('ttf/FiraCode-Regular.ttf', 'ttf/FiraCode-Bold.ttf', 'variable_ttf/FiraCode-VF.ttf'):
        z.write(name)
")
cat >"$FAKEBIN/curl" <<CURL
#!/usr/bin/env bash
echo "\$*" >>"$SANDBOX/curl.log"
while [ \$# -gt 0 ]; do [ "\$1" = -o ] && cp "$SANDBOX/fira.zip" "\$2"; shift; done
CURL
chmod +x "$FAKEBIN/curl"
out=$(devup --only fonts)
assert_contains "$out" "installed Fira Code" "devup installs Fira Code"
assert_true "the regular weight is in .local/fonts" test -f "$DEV/.local/fonts/FiraCode-Regular.ttf"
assert_true "the bold weight is in .local/fonts" test -f "$DEV/.local/fonts/FiraCode-Bold.ttf"
assert_true "the variable font is left out" test ! -e "$DEV/.local/fonts/FiraCode-VF.ttf"
assert_contains "$(cat "$SANDBOX/curl.log")" "github.com/tonsky/FiraCode/releases/download/" "the font comes from the Fira Code releases"
out=$(devup --only fonts)
assert_contains "$out" "Fira Code is installed" "a second run changes nothing"
assert_eq "$(wc -l <"$SANDBOX/curl.log")" 1 "and downloads nothing"
rm "$DEV/.local/fonts/FiraCode-Regular.ttf" "$FAKEBIN/curl"
printf '#!/usr/bin/env bash\nexit 22\n' >"$FAKEBIN/curl"
assert_contains "$(devup --only fonts)" "FAILED  fonts" "a failed download fails the step"

# Completions: bash as before, and zsh only when opted in.
cat >"$FAKEBIN/gh" <<'GH'
#!/usr/bin/env bash
echo "#compdef gh for ${*: -1}"
GH
# Like yargs, ng picks the completion template from $SHELL.
cat >"$FAKEBIN/ng" <<'NG'
#!/usr/bin/env bash
case ${SHELL:-} in
  *zsh*) echo "compdef _ng_yargs_completions ng" ;;
  *) echo "complete -o default -F _ng_yargs_completions ng" ;;
esac
NG
chmod +x "$FAKEBIN/gh" "$FAKEBIN/ng"
mkdir -p "$DEV/tools/cache/zsh"
touch "$DEV/tools/cache/zsh/zcompdump" "$DEV/tools/cache/zsh/zcompdump.zwc"
out=$(devup --only completions)
assert_contains "$out" "bash completions generated for " "bash completions are generated"
assert_contains "$(cat "$DEV/tools/completions/completions/gh")" "for bash" "the gh completion is for bash"
assert_contains "$(cat "$DEV/tools/completions/completions/ng")" "complete -o default" "ng completes for bash with the bash template"
assert_true "no zsh completions without the opt-in" test ! -d "$DEV/tools/completions/zsh"
assert_true "the completion dump is kept without the opt-in" test -f "$DEV/tools/cache/zsh/zcompdump"
printf 'DEV_SHELL=zsh\n' >"$DEV/.local/profile.env"
out=$(devup --only completions)
assert_contains "$out" "zsh completions generated for " "zsh completions are generated when opted in"
assert_contains "$(cat "$DEV/tools/completions/zsh/_gh")" "for zsh" "the gh completion is a zsh completion function"
assert_eq "$(cat "$DEV/tools/completions/zsh/ng.zsh")" "compdef _ng_yargs_completions ng" "ng is a script to source with the zsh template"
assert_true "the completion dump is rebuilt after new completions" test ! -e "$DEV/tools/cache/zsh/zcompdump"

finish
