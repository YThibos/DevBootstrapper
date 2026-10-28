#!/usr/bin/env bash
# Tests compare against literal "$VAR" and "~/" strings on purpose.
# shellcheck disable=SC2016,SC2088
# The ~/.bashrc blocks, environment and interactive layers, managed links, template rendering,
# devup idempotency, --unlink, the pull step, the allow-list .gitignore and the dev command.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox

# A stock-Ubuntu-like ~/.bashrc and ~/.profile.
cat >"$HOME/.bashrc" <<'RC'
# ~/.bashrc: executed by bash(1) for non-login shells.
case $- in
    *i*) ;;
      *) return;;
esac
HISTSIZE=1000
alias ll='ls -alF'
RC
cat >"$HOME/.profile" <<'PROFILE'
if [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
PROFILE
cp "$HOME/.bashrc" "$SANDBOX/bashrc.orig"

# Pre-existing files: a tool-written Claude setting (adopted) and an old ~/.npmrc (backed up).
mkdir -p "$HOME/.claude"
printf '{\n  "model": "opus"\n}\n' >"$HOME/.claude/settings.json"
echo "registry=https://old.example/" >"$HOME/.npmrc"

devup() { run bash "$DEV/install/devup.sh" "$@" 2>&1; }
out=$(devup --only render,links,identities)
assert_contains "$out" "ok      links" "devup links step succeeds"
assert_eq "$(head -1 "$HOME/.bashrc")" "# >>> DevBootstrapper (env) >>>" "the environment block is at the top of ~/.bashrc"
assert_contains "$(tail -3 "$HOME/.bashrc")" "bootstrap.sh\"" "the interactive block is at the bottom"
assert_contains "$(cat "$HOME/.bashrc")" 'alias ll='"'"'ls -alF'"'" "Ubuntu's own ~/.bashrc content is kept"

for pair in ".gitconfig|config/git/gitconfig" ".config/mise/conf.d/devbootstrapper.toml|config/mise/config.toml" \
  ".config/mise/config.toml|.local/mise/config.toml" ".local/share/mise|tools/mise" ".cache|tools/cache" \
  ".tmux.conf|config/tmux/tmux.conf" ".m2/settings.xml|.local/maven/settings.xml" ".npmrc|.local/npm/npmrc" \
  ".claude/settings.json|config/claude/settings.json" ".claude/CLAUDE.md|config/claude/CLAUDE.md"; do
  assert_eq "$(readlink "$HOME/${pair%%|*}")" "$DEV/${pair#*|}" "~/${pair%%|*} links to ${pair#*|}"
done
assert_contains "$(cat "$DEV/config/claude/settings.json")" '"model": "opus"' "an existing Claude setting is adopted into the dev home"
assert_eq "$(cat "$DEV"/tmp/backup-*/.npmrc 2>/dev/null)" "registry=https://old.example/" "a replaced ~/.npmrc is kept in tmp/backup-<date>/"

cp "$HOME/.bashrc" "$SANDBOX/bashrc.after1"
out=$(devup --only render,links,identities)
assert_contains "$out" "links in place (0 changed)" "a second devup run changes no links"
assert_true "a second devup run leaves ~/.bashrc unchanged" cmp -s "$HOME/.bashrc" "$SANDBOX/bashrc.after1"

# Environment layer: login non-interactive shells (bash -lc, WezTerm's update tab) get it, silently.
assert_eq "$(run bash -lc 'echo "$DEV_HOME"')" "$DEV" "bash -lc loads DEV_HOME"
assert_eq "$(run bash -lc 'command -v gitid')" "$DEV/bin/gitid" "bash -lc has DevBootstrapper commands on PATH"
assert_eq "$(run bash -lc 'echo "$XDG_CACHE_HOME"')" "$DEV/tools/cache" "caches point into tools/cache"
assert_eq "$(run bash -lc 'true' 2>&1)" "" "non-interactive shells print nothing"

# Interactive layer: loads after Ubuntu's defaults, so DevBootstrapper wins.
inter=$(run bash -i -c 'alias ll; alias gs; echo "HISTSIZE=$HISTSIZE"; type -t mkcd; type -t gh' 2>&1)
assert_contains "$inter" "alias ll='ls -lh --color=auto'" "interactive shells get DevBootstrapper's ll over Ubuntu's"
assert_contains "$inter" "alias gs='git status -sb'" "git aliases load"
assert_contains "$inter" "HISTSIZE=50000" "history settings override Ubuntu's"
assert_contains "$inter" "function" "functions load (mkcd, gh wrapper)"
assert_not_contains "$inter" "rror" "interactive startup prints no errors without any optional tool installed"
reminder=$(run env -u DEVBOOT_NO_REMINDER bash -i -c 'true' 2>&1)
assert_contains "$reminder" "run devup" "terminals other than WezTerm get the update reminder"
mkdir -p "$DEV/tools/state" && date +%Y-%m-%d >"$DEV/tools/state/last-update"
reminder=$(run env -u DEVBOOT_NO_REMINDER bash -i -c 'true' 2>&1 | grep -v -e 'terminal process group' -e 'no job control')
assert_eq "$reminder" "" "no reminder once today's update ran"

# Startup budget (no optional tools here, so this guards the bash layer itself).
ms=$(run "$DEV/bin/dev" startup-time | sed -n 's/.*startup: \([0-9]*\) ms.*/\1/p')
if [ -n "$ms" ] && [ "$ms" -lt 200 ]; then pass "interactive startup ${ms} ms is under 200 ms"; else fail "interactive startup under 200 ms" "measured: ${ms:-?} ms"; fi

# Rendering with a work profile: proxy, no-proxy list, a mirror URL that needs XML escaping.
mkdir -p "$DEV/.local"
cat >"$DEV/.local/profile.env" <<'PROF'
DEV_PROFILE=work
DEV_PROXY_URL=http://proxy.corp.example:3128
DEV_NO_PROXY=localhost,.corp.example
DEV_MAVEN_MIRROR_URL='https://repo.corp.example/maven?a=1&b=2'
DEV_NPM_REGISTRY=https://npm.corp.example/registry/
PROF
echo "NPM_REGISTRY_TOKEN=npm-secret" >>"$DEV/.secrets"
devup --only render >/dev/null
xml="$DEV/.local/maven/settings.xml"
assert_true "rendered Maven settings are well-formed XML" python3 -c "import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])" "$xml"
assert_contains "$(cat "$xml")" "<host>proxy.corp.example</host>" "Maven proxy host from the profile"
assert_contains "$(cat "$xml")" "<port>3128</port>" "Maven proxy port from the profile"
assert_contains "$(cat "$xml")" "<nonProxyHosts>localhost|*.corp.example</nonProxyHosts>" "Maven non-proxy hosts converted from NO_PROXY"
assert_contains "$(cat "$xml")" "maven?a=1&amp;b=2" "mirror URL is XML-escaped"
assert_contains "$(cat "$xml")" '${env.MAVEN_MIRROR_PASSWORD}' "mirror credentials stay environment references"
assert_contains "$(cat "$xml")" "<localRepository>$DEV/tools/cache/m2/repository</localRepository>" "Maven's local repository is in tools/cache"
npmrc=$(cat "$DEV/.local/npm/npmrc")
assert_contains "$npmrc" "registry=https://npm.corp.example/registry/" "npm registry from the profile"
assert_contains "$npmrc" '//npm.corp.example/registry/:_authToken=${NPM_REGISTRY_TOKEN}' "npm token stays an environment reference"
assert_not_contains "$npmrc" "npm-secret" "the npm token value is never written"
assert_contains "$(run bash -lc 'echo "$JAVA_TOOL_OPTIONS"')" "-Dhttps.proxyHost=proxy.corp.example" "Java gets the proxy"
printf 'DEV_PROFILE=home\n' >"$DEV/.local/profile.env"
devup --only render >/dev/null
assert_not_contains "$(cat "$xml")" "<proxies>" "the home profile renders no proxy"

# dev: help, cheat sheet, docs.
assert_contains "$(run "$DEV/bin/dev")" "dev cheat" "dev shows an overview"
cheat=$(run "$DEV/bin/dev" cheat)
for want in "gitid list" "mvnuse [version]" "jdkuse [version]" "clone <url> [context]" "Alt+l" "Ctrl-b d" "devup"; do
  assert_contains "$cheat" "$want" "dev cheat lists: $want"
done
assert_eq "$(run "$DEV/bin/dev" cheat maven | grep -c 'mvn')" "$(run "$DEV/bin/dev" cheat maven | grep -c '^  ')" "dev cheat <filter> narrows the sheet"
assert_contains "$(run "$DEV/bin/dev" docs)" "getting-started" "dev docs lists the topics"
assert_contains "$(run "$DEV/bin/dev" docs identities)" "gitid" "dev docs <topic> shows a topic"

# --unlink removes links and blocks but keeps Ubuntu's ~/.bashrc and the dev home.
devup --unlink >/dev/null
assert_true "--unlink removes ~/.gitconfig" test ! -e "$HOME/.gitconfig"
assert_true "--unlink restores ~/.bashrc to its original content" cmp -s "$HOME/.bashrc" "$SANDBOX/bashrc.orig"
assert_true "--unlink keeps the dev home" test -d "$DEV/bash"

# The allow-list .gitignore: machine content never shows up as changes.
git -C "$DEV" init -q && git -C "$DEV" add -A && git -C "$DEV" -c user.email=t@t -c user.name=t commit -qm init
mkdir -p "$DEV/tools/mise" "$DEV/sources/client/app" "$DEV/sources/home/proj" "$DEV/.local/git"
touch "$DEV/tools/mise/x" "$DEV/tmp/scratch.txt" "$DEV/sources/client/app/f" "$DEV/sources/home/proj/f" "$DEV/.local/git/x" "$DEV/bash/local.sh" "$DEV/.secrets"
assert_eq "$(git -C "$DEV" status --porcelain)" "" "tools, tmp, sources, .local, .secrets and bash/local.sh never appear in git status"
assert_eq "$(git -C "$DEV" ls-files | grep -c -E '^(\.secrets$|\.local/|tools/)')" 0 "no machine files are tracked"

# The pull step: fast-forwards a clean dev home, refuses to pull over local changes.
origin="$SANDBOX/origin.git"
git clone -q --bare "$DEV" "$origin"
git -C "$DEV" remote add origin "$origin"
git -C "$DEV" fetch -q origin
git -C "$DEV" branch -q -u "origin/$(git -C "$DEV" branch --show-current)"
other="$SANDBOX/other"
git clone -q "$origin" "$other"
echo "# new" >>"$other/config/git/ignore"
git -C "$other" -c user.email=t@t -c user.name=t commit -qam "upstream change"
git -C "$other" push -q origin HEAD
echo "# local edit" >>"$DEV/bash/aliases.sh"
out=$(devup --only pull)
assert_contains "$out" "has local changes" "pull skips a dev home with local changes"
git -C "$DEV" checkout -q -- bash/aliases.sh
out=$(devup --only pull)
assert_contains "$out" "pulled 1 commit" "pull fast-forwards a clean dev home"
assert_contains "$(tail -1 "$DEV/config/git/ignore")" "# new" "the upstream change arrived"

finish
