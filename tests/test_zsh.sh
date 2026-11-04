#!/usr/bin/env bash
# Tests compare against literal "$VAR" and "~/" strings, and type shell code, on purpose.
# shellcheck disable=SC2016,SC2088
# The zsh opt-in (docs/shell.md): without it ~/.zshrc is never touched; with it zsh sees the same
# environment and tools as bash, and gets the prompt, the keys, the completion and the history
# options of the laptop. Needs zsh; CI installs it.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox

if ! command -v zsh >/dev/null 2>&1; then
  echo "  skipped: zsh is not installed"
  finish
  exit
fi

# A stock-Ubuntu-like bash setup, so that bash -lc reads the DevBootstrapper blocks.
printf 'case $- in\n    *i*) ;;\n      *) return;;\nesac\n' >"$HOME/.bashrc"
printf 'if [ -n "$BASH_VERSION" ]; then\n    . "$HOME/.bashrc"\nfi\nif [ -d "$HOME/.local/bin" ] ; then\n    PATH="$HOME/.local/bin:$PATH"\nfi\n' >"$HOME/.profile"

# Stand-ins for the tools whose shell integration differs per shell: each prints what it was asked.
# They start without forking, like the real native tools, so they do not eat the startup budget.
for tool in mise zoxide fzf; do
  printf '#!/bin/sh\nfor last; do :; done\necho "export FAKE_%s=$last"\n' "${tool^^}" >"$FAKEBIN/$tool"
  chmod +x "$FAKEBIN/$tool"
done

# Like yargs, ng picks the completion template from $SHELL; the bash one breaks zsh.
cat >"$FAKEBIN/ng" <<'NG'
#!/usr/bin/env bash
case ${SHELL:-} in
  *zsh*) echo "compdef _ng_yargs_completions ng" ;;
  *) echo "complete -o default -F _ng_yargs_completions ng" ;;
esac
NG
chmod +x "$FAKEBIN/ng"

devup() { run bash "$DEV/install/devup.sh" "$@" 2>&1; }
zsh_i() { run zsh -i -c "$1" 2>&1; }

for file in "$DEV"/zsh/*.zsh; do
  assert_true "$(basename "$file") is valid zsh" zsh -n "$file"
done

# ---------------------------------------------------------------------------- without the opt-in

printf '# the user'"'"'s own zshrc\nHISTSIZE=123\nalias mine=true\n' >"$HOME/.zshrc"
cp "$HOME/.zshrc" "$SANDBOX/zshrc.orig"
devup --only render,links >/dev/null
assert_true "without DEV_SHELL ~/.zshrc is byte-identical after devup" cmp -s "$HOME/.zshrc" "$SANDBOX/zshrc.orig"
assert_true "without DEV_SHELL there is no ~/.zshenv" test ! -e "$HOME/.zshenv"
assert_contains "$(cat "$HOME/.bashrc")" "DevBootstrapper" "bash keeps its blocks"
mkdir -p "$DEV/.local"
printf 'DEV_SHELL=bash\n' >"$DEV/.local/profile.env"
devup --only render,links >/dev/null
assert_true "with DEV_SHELL=bash ~/.zshrc is byte-identical after devup" cmp -s "$HOME/.zshrc" "$SANDBOX/zshrc.orig"
assert_eq "$(run bash -c '. "$0/bash/env.sh"; echo "$DEV_SHELL"' "$DEV")" bash "the shell is bash by default"
assert_eq "$(printf 'DEV_SHELL=fish\n' >"$DEV/.local/profile.env"; run bash -c '. "$0/bash/env.sh"; echo "$DEV_SHELL"' "$DEV")" bash "a shell other than zsh means bash"

# ---------------------------------------------------------------------------- with the opt-in

cat >"$DEV/.local/profile.env" <<'PROFILE'
DEV_SHELL=zsh
DEV_PROFILE=work
DEV_PROXY_URL=http://proxy.corp.example:3128
DEV_NO_PROXY=localhost,.corp.example
PROFILE
printf 'SAMPLE_TOKEN=tok123\nSAMPLE_SPACES='"'"'two words'"'"'\n' >"$DEV/.secrets"
printf 'shopt -s globstar\n' >"$DEV/bash/local.sh"
printf 'LOCAL_ZSH=loaded\n' >"$DEV/zsh/local.zsh"
devup --only completions >/dev/null
out=$(devup --only render,links)
assert_contains "$out" "added the DevBootstrapper blocks to ~/.zshenv and ~/.zshrc" "devup adds the zsh blocks on opt-in"
assert_eq "$(head -1 "$HOME/.zshenv")" "# >>> DevBootstrapper (zsh env) >>>" "the environment block is at the top of ~/.zshenv"
assert_contains "$(tail -3 "$HOME/.zshrc")" "bootstrap.zsh\"" "the interactive block is at the bottom of ~/.zshrc"
assert_contains "$(cat "$HOME/.zshrc")" "alias mine=true" "the user's own ~/.zshrc content is kept"
cp "$HOME/.zshrc" "$SANDBOX/zshrc.after1"
cp "$HOME/.zshenv" "$SANDBOX/zshenv.after1"
out=$(devup --only render,links)
assert_contains "$out" "links in place (0 changed)" "a second devup changes no links"
assert_true "a second devup leaves ~/.zshrc unchanged" cmp -s "$HOME/.zshrc" "$SANDBOX/zshrc.after1"
assert_true "a second devup leaves ~/.zshenv unchanged" cmp -s "$HOME/.zshenv" "$SANDBOX/zshenv.after1"
assert_contains "$(run bash -c '. "$0/lib/common.sh"; DEV_SHELL=zsh base_packages' "$DEV")" "zsh" "zsh is an apt package once opted in"
assert_not_contains "$(run bash -c '. "$0/lib/common.sh"; DEV_SHELL=bash base_packages' "$DEV")" "zsh" "and is not installed without the opt-in"

# The same environment as bash, from login shells and plain `zsh -c`.
for var in DEV_HOME DEV_TOOLS DEV_SHELL XDG_CACHE_HOME MISE_DATA_DIR MISE_CACHE_DIR GRADLE_USER_HOME npm_config_cache \
  HTTPS_PROXY https_proxy NO_PROXY DEV_PROXY_HOST DEV_PROXY_PORT DEV_MAVEN_NON_PROXY_HOSTS JAVA_TOOL_OPTIONS \
  DEV_MAVEN_MIRROR_OF STARSHIP_CONFIG SAMPLE_TOKEN SAMPLE_SPACES; do
  want=$(run bash -lc 'printf %s "${'"$var"'-unset}"')
  assert_eq "$(run zsh -lc 'printf %s "${'"$var"'-unset}"')" "$want" "zsh -lc sees $var as bash does"
done
assert_eq "$(run zsh -c 'printf %s "$DEV_HOME"')" "$DEV" "plain zsh -c gets the environment too, through ~/.zshenv"
assert_eq "$(run zsh -lc 'echo $PATH' | cut -d: -f1-4)" "$(run bash -lc 'echo $PATH' | cut -d: -f1-4)" "zsh -lc has the same toolkit PATH entries first"
assert_eq "$(run zsh -lc 'command -v gitid')" "$DEV/bin/gitid" "zsh -lc finds the DevBootstrapper commands"
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\n' >"$HOME/.local/bin/ruff" && chmod +x "$HOME/.local/bin/ruff"
assert_eq "$(run zsh -lc 'command -v ruff')" "$HOME/.local/bin/ruff" "zsh -lc finds the tools in ~/.local/bin, as bash -lc does from ~/.profile"
assert_eq "$(run zsh -lc 'echo $PATH')" "$(run bash -lc 'echo $PATH')" "zsh -lc has the PATH of bash -lc"
assert_eq "$(run zsh -c 'command -v ruff')" "" "a non-login zsh does not read ~/.profile, as a non-login bash does not"
assert_eq "$(run zsh -lc 'true' 2>&1)" "" "non-interactive zsh prints nothing"
assert_eq "$(run zsh -ic 'printf %s "$DEV_PROXY_URL"' 2>&1)" "http://proxy.corp.example:3128" "interactive zsh sees the proxy"

# The interactive layer: tools, aliases, functions, history.
inter=$(zsh_i 'alias ll gs; print -r -- "HISTSIZE=$HISTSIZE"; whence -w mkcd gh; echo "mise=$FAKE_MISE zoxide=$FAKE_ZOXIDE fzf=$FAKE_FZF"; dev | head -1')
assert_contains "$inter" "ll='ls -lh --color=auto'" "zsh gets DevBootstrapper's ll"
assert_contains "$inter" "gs='git status -sb'" "zsh gets the git aliases"
assert_contains "$inter" "mkcd: function" "zsh gets the shell functions"
assert_contains "$inter" "gh: function" "zsh gets the gh wrapper"
assert_contains "$inter" "mise=zsh zoxide=zsh fzf=--zsh" "mise, zoxide and fzf are activated for zsh"
assert_contains "$inter" "DevBootstrapper - your portable development toolkit" "dev works in zsh"
assert_eq "$(run bash -ic 'echo "mise=$FAKE_MISE zoxide=$FAKE_ZOXIDE fzf=$FAKE_FZF"' 2>&1 | tail -1)" "mise=bash zoxide=bash fzf=--bash" "and for bash as before"
assert_eq "$(run zsh -i -c true 2>&1 >/dev/null)" "" "interactive zsh prints nothing on stderr"
assert_eq "$(zsh_i 'echo $LOCAL_ZSH')" "loaded" "zsh/local.zsh is loaded"
assert_true "Ubuntu's global compinit is skipped, so no dump lands in ~" test ! -e "$HOME/.zcompdump"
assert_eq "$(zsh_i '[[ -o histignorealldups ]] && [[ -o sharehistory ]] && echo options; echo "$HISTFILE $SAVEHIST"')" "options
$HOME/.zsh_history 100000" "history ignores all duplicates and is shared between tabs"
assert_eq "$(zsh_i 'echo $+functions[reload] $__devboot_shell')" "1 zsh" "reload exists for zsh"
reminder=$(run env -u DEVBOOT_NO_REMINDER zsh -ic 'true' 2>&1)
assert_contains "$reminder" "run devup" "terminals other than WezTerm get the update reminder in zsh too"

# Completion.
comp=$(zsh_i 'zstyle -L ":completion:*" menu; zstyle -L ":completion:*" group-name; zstyle -L ":completion:*" matcher-list; echo "gitid=${_comps[gitid]} dev=${_comps[dev]}"')
assert_contains "$comp" "menu 'select=long'" "completion offers a menu to select from"
assert_contains "$comp" "group-name ''" "completion groups the results by kind"
assert_contains "$comp" "m:{a-z}={A-Z}" "completion matches case-insensitively"
assert_contains "$comp" "gitid=__devboot_complete_gitid dev=__devboot_complete_dev" "DevBootstrapper commands complete in zsh"
assert_true "completion keeps its dump under tools/cache" test -f "$DEV/tools/cache/zsh/zcompdump"
assert_contains "$(run env TERM=xterm-256color zsh -i -c 'zstyle -L ":completion:*:default" list-colors')" "di=01;34" "completion colours files as ls does"
mkdir -p "$DEV/.local/git"
printf '[account "github-me"]\n\thost = github.com\n[context "work"]\n\temail = w@example.com\n' >"$DEV/.local/git/identities.gitconfig"
assert_eq "$(zsh_i '__devboot_identity_names account host')" "github-me" "gitid completion reads the accounts"
assert_eq "$(zsh_i '__devboot_identity_names context email')" "work" "gitid completion reads the contexts"

# The prompt.
repo="$SANDBOX/repo"
git init -q "$repo" && git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
prompt_git() { zsh_i "source $DEV/zsh/prompt.zsh; cd $repo; __devboot_prompt_git"; }
assert_eq "$(prompt_git)" " %F{87}git:[%F{green}$(git -C "$repo" branch --show-current)%F{87}]%f" "a clean branch is green"
echo x >"$repo/new.txt"
assert_contains "$(prompt_git)" "%F{red}" "untracked files make the branch red"
assert_contains "$(prompt_git)" "*%F{87}]" "and mark it with a star"
git -C "$repo" add new.txt
assert_contains "$(prompt_git)" "%F{yellow}" "staged changes make the branch yellow"
assert_eq "$(zsh_i "source $DEV/zsh/prompt.zsh; cd $SANDBOX; __devboot_prompt_git")" "" "outside a repository the git part is empty"
assert_eq "$(zsh_i "source $DEV/zsh/prompt.zsh; DEV_IS_WSL=1 __devboot_prompt_host_label")" "WSL2" "on WSL the label is WSL2"
assert_eq "$(zsh_i "source $DEV/zsh/prompt.zsh; DEV_IS_WSL= HOST=box.example __devboot_prompt_host_label")" ":box" "elsewhere it is the host name"
assert_contains "$(zsh_i 'print -r -- $PROMPT')" '%F{30}%n%F{37}(' "the prompt starts with the dark teal user and the label"
assert_contains "$(zsh_i 'print -r -- $PROMPT')" '%F{44}%~%f' "followed by the cyan directory"

# The keys, typed into a real terminal (script provides one).
if command -v script >/dev/null 2>&1; then
  esc=$'\e'
  # Keys typed before the line editor is up can be lost, so they wait for it, and a lost key
  # fails the check instead of leaving zsh waiting for input.
  ready="$SANDBOX/line-editor-ready"
  printf 'autoload -Uz add-zle-hook-widget\n__test_ready() { : >%q; }\nadd-zle-hook-widget line-init __test_ready\n' \
    "$ready" >>"$DEV/zsh/local.zsh"
  typed() {
    rm -f "$ready"
    { line_editor_ready && printf '%b' "$1"; } | run timeout 20 script -qec 'zsh -i' /dev/null 2>&1 | tr -d '\r'
  }
  line_editor_ready() {
    for _ in $(seq 100); do
      [ -e "$ready" ] && return
      sleep 0.1
    done
  }
  out=$(typed "printf 'R:%s|' a --b=c${esc}[1;5Dx\\n")
  assert_contains "$out" "R:a|R:x--b=c|" "Ctrl+Left jumps a whole whitespace-delimited word"
  out=$(typed "'R:%s|' a b c${esc}[1;5Hprintf \\n")
  assert_contains "$out" "R:a|R:b|R:c|" "Ctrl+Home goes to the start of the input"
  out=$(typed "printf 'R:%s|' a b${esc}[1;5H${esc}[1;5F c\\n")
  assert_contains "$out" "R:a|R:b|R:c|" "Ctrl+End goes to the end of the input"
  out=$(typed "printf 'R:%s|' a --b=c d${esc}[1;5H${esc}[1;5C${esc}[1;5C${esc}[1;5Cx\\n")
  assert_contains "$out" "R:a|R:x--b=c|R:d|" "Ctrl+Right jumps to the next whitespace-delimited word"
  out=$(typed "printf 'U:%s|' hist\\n${esc}[1;5A\\n")
  assert_eq "$(grep -o 'U:hist|' <<<"$out" | wc -l)" 2 "Ctrl+Up recalls the previous command"
  out=$(typed "printf 'U:%s|' hist\\n${esc}[1;5A${esc}[1;5Bprintf 'D:%s|' ok\\n")
  assert_contains "$out" "D:ok|" "Ctrl+Down goes back to the empty line"
else
  echo "  skipped: no script command to provide a terminal"
fi

# Startup budget with the tools active.
# The median of seven runs, so one start slowed down by a busy machine does not decide it.
ms=$(for _ in 1 2 3 4 5 6 7; do
  start=$(date +%s%N)
  run zsh -i -c exit >/dev/null 2>&1
  echo $((($(date +%s%N) - start) / 1000000))
done | sort -n | sed -n 4p)
if [ "$ms" -lt 200 ]; then pass "interactive zsh startup ${ms} ms is under 200 ms"; else fail "interactive zsh startup under 200 ms" "measured: $ms ms"; fi
assert_contains "$(run "$DEV/bin/dev" startup-time)" "interactive zsh startup:" "dev startup-time measures zsh when opted in"

# ---------------------------------------------------------------------------- opting out again

printf 'DEV_SHELL=bash\n' >"$DEV/.local/profile.env"
out=$(devup --only links)
assert_contains "$out" "removed the DevBootstrapper blocks from ~/.zshenv and ~/.zshrc" "opting out removes the zsh blocks"
assert_true "and leaves ~/.zshrc as it was" cmp -s "$HOME/.zshrc" "$SANDBOX/zshrc.orig"
assert_true "and removes the ~/.zshenv devup created" test ! -e "$HOME/.zshenv"
printf 'DEV_SHELL=zsh\n' >"$DEV/.local/profile.env"
devup --only links >/dev/null
devup --unlink >/dev/null
assert_true "--unlink removes the zsh blocks" cmp -s "$HOME/.zshrc" "$SANDBOX/zshrc.orig"

# A ~/.zshrc whose last line has no newline, as some editors save it.
printf 'alias mine=true' >"$HOME/.zshrc"
devup --only links >/dev/null
assert_eq "$(zsh_i 'alias mine; echo $+functions[reload]')" "mine=true
1" "the block goes on its own line after a last line without a newline"
printf 'DEV_SHELL=bash\n' >"$DEV/.local/profile.env"
devup --only links >/dev/null
assert_eq "$(od -c "$HOME/.zshrc")" "$(printf 'alias mine=true' | od -c)" "opting out restores a last line without a newline byte for byte"

finish
