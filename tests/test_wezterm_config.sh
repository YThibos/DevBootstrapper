#!/usr/bin/env bash
# The WezTerm configuration, run against a stand-in for the wezterm module (tests/wezterm_harness.lua):
# the tmux-driven key model, the tab prompt, and EDI's face with its image fallbacks.
# Needs a Lua interpreter (lua5.4); CI installs it.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox

LUA=$(command -v lua5.4 || command -v lua)
if [ -z "$LUA" ]; then
  echo "  skipped: no Lua interpreter"
  finish
  exit
fi

harness() { "$LUA" "$REPO/tests/wezterm_harness.lua" "$REPO" "$HOME" "$@"; }
use_settings() { mkdir -p "$DEV/.local" && cp "$REPO/.local.example/wezterm.lua" "$DEV/.local/wezterm.lua"; }
caret_b=$'\x02'

keys=$(harness keys | sed "s/$caret_b/^B/g; s/$(printf '\r')/^M/g")
while IFS='@' read -r key command; do
  assert_contains "$keys" "$key SendString ^B: | pause 50ms | SendString $command^M" "$key opens tmux's command prompt, then sends: $command"
done <<'TABLE'
ALT+Enter@split-window -h
ALT|SHIFT+Enter@split-window -v
ALT+h@select-pane -L
ALT+j@select-pane -D
ALT+k@select-pane -U
ALT+l@select-pane -R
CTRL|SHIFT+w@kill-pane
CTRL+n@new-window
CTRL+Tab@next-window
CTRL|SHIFT+Tab@previous-window
ALT|SHIFT+N@break-pane
ALT+z@resize-pane -Z
ALT+c@copy-mode
TABLE
assert_contains "$keys" "CTRL+t PromptInputLine" "Ctrl+t prompts for a name"
assert_contains "$keys" "ALT+1 ActivateTab 0" "Alt+1 switches to the first tab"
assert_contains "$keys" "ALT+0 ActivateTab 9" "Alt+0 switches to the tenth tab"
assert_eq "$(printf '%s\n' "$keys" | grep -c 'ActivateTab')" 10 "ten tab keys"
assert_eq "$(printf '%s\n' "$keys" | awk '{ print $1 }' | sort | uniq -d)" "" "no key is bound twice"
assert_contains "$keys" "ALT|SHIFT+L ShowLauncher" "the launcher moved to Alt+Shift+l, as Alt+l moves between panes"

assert_contains "$(harness prompt work)" "domain=WSL:Ubuntu bash -lc command -v tmux >/dev/null 2>&1 && exec tmux new-session -A -s work;" "a name opens that tmux session in a new tab"
assert_not_contains "$(harness prompt work)" ignored "and is not reported as ignored"
assert_eq "$(harness prompt 'a b')" ignored "a name with a space is ignored"
assert_eq "$(harness prompt 'x;reboot')" ignored "a name that could inject a command is ignored"
assert_eq "$(harness prompt a.b)" ignored "a name tmux would reject is ignored"
assert_contains "$(harness startup)" "exec tmux new-session -A -s main" "the first window is the tmux session main"

# Reloading: WezTerm cannot watch files inside WSL, so the configuration checks them itself.
assert_eq "$(harness reload none)" "before the interval: 0, after: " "nothing changed, nothing reloads"
mkdir -p "$DEV/.local"
assert_eq "$(harness reload local)" "before the interval: 0, after: ReloadConfiguration" ".local/wezterm.lua appearing reloads once, after the check interval"
rm "$DEV/.local/wezterm.lua"

# EDI's face.
edi_title=edi-261104-0853
image() { harness face "$edi_title" | sed -n 's/^image=//p'; }
use_settings
assert_eq "$(harness reload local)" "before the interval: 0, after: ReloadConfiguration" "a change to .local/wezterm.lua reloads the configuration"
assert_eq "$(harness font-size)" "11.0" "the font size is 11 by default"
printf 'font_size = 9.0,\n' >"$SANDBOX/size" && sed -i "/^return {/r $SANDBOX/size" "$DEV/.local/wezterm.lua"
assert_eq "$(harness font-size)" "9.0" "a machine sets its own font size in .local/wezterm.lua"
assert_eq "$(harness face "$edi_title")" "" "without any image the EDI rule is skipped silently"
mkdir -p "$HOME/EDI/docs/images"
touch "$HOME/EDI/docs/images/EDI-darkness.jpg"
assert_eq "$(image)" "$HOME/EDI/docs/images/EDI-darkness.jpg" "EDI's face is docs/images/EDI-darkness.jpg of the EDI checkout"
out=$(harness face "$edi_title")
assert_contains "$out" "font=Fira Code JetBrains Mono" "EDI's face is set in Fira Code"
assert_contains "$out" "foreground=#35aab6" "EDI's text is dark cyan"
mkdir -p "$HOME/.edi/state"
touch "$HOME/.edi/state/wallpaper.png"
assert_eq "$(image)" "$HOME/.edi/state/wallpaper.png" "EDI's own wallpaper is preferred when it exists"
rm "$HOME/.edi/state/wallpaper.png"
assert_eq "$(image)" "$HOME/EDI/docs/images/EDI-darkness.jpg" "and the checkout's picture is the fallback again without it"
assert_eq "$(harness face "$edi_title" | sed -n 's/^image=//p' | wc -l)" 1 "the face is a single image over the black underlay"

mkdir -p "$HOME/checkouts/EDI/docs/images"
touch "$HOME/checkouts/EDI/docs/images/EDI-darkness.jpg"
rm -r "$HOME/EDI"
assert_eq "$(image)" "" "an EDI checkout elsewhere is not found by default"
sed -i "s|local edi = '~/EDI'|local edi = '~/checkouts/EDI'|" "$DEV/.local/wezterm.lua"
assert_eq "$(image)" "$HOME/checkouts/EDI/docs/images/EDI-darkness.jpg" "the EDI checkout path is configurable"
assert_eq "$(harness face 'some-other-title')" "" "other panes keep their own look"

finish
