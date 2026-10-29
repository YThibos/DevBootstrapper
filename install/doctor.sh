#!/usr/bin/env bash
# doctor - health report: tools, apt packages, Docker, network, links and git identities (docs/updates.md).
# Exit status 1 when a required tool is missing; everything else is reported as a warning.
set -uo pipefail

# shellcheck source=lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"
# shellcheck source=bash/env.sh
. "$DEV_HOME/bash/env.sh"

missing=0

# name|command printing a version ("" = presence only)
tools() {
  cat <<'LIST'
java|java -version 2>&1 | head -1
mvn|mvn -v 2>/dev/null | head -1
mvnd|
gradle|
node|node --version
npm|npm --version
ng|
python|python --version
uv|uv --version
claude|claude --version
gh|gh --version | head -1
glab|glab --version | head -1
git|git --version
tmux|tmux -V
jq|jq --version
yq|yq --version
rg|rg --version | head -1
fd|fd --version
fzf|fzf --version
bat|bat --version
eza|
zoxide|zoxide --version
delta|delta --version
lazygit|
lazydocker|
starship|starship --version | head -1
xh|xh --version | head -1
glow|
shellcheck|
shfmt|shfmt --version
LIST
}

heading "Tools"
while IFS='|' read -r name cmd; do
  if ! have "$name"; then
    printf '  %s✗%s %-11s missing\n' "$_c_red" "$_c_off" "$name"
    missing=$((missing + 1))
    continue
  fi
  version=''
  [ -n "$cmd" ] && version=$(timeout 15 bash -c "$cmd" 2>/dev/null | tr -d '\r' | head -1)
  printf '  %s✓%s %-11s %s\n' "$_c_green" "$_c_off" "$name" "${version:-installed}"
done < <(tools)

heading "Base packages"
if have dpkg-query; then
  absent=()
  while IFS= read -r pkg; do
    # shellcheck disable=SC2016 # ${Status} is dpkg-query's field, not a shell variable
    dpkg-query -W -f '${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' || absent+=("$pkg")
  done < <(base_packages)
  if [ ${#absent[@]} -eq 0 ]; then
    ok "every apt package in install/apt-packages.txt is installed"
  else
    warn "apt packages missing: ${absent[*]} (run: devup --only apt)"
  fi
else
  info "no dpkg on this system"
fi

heading "Docker"
if have docker && server=$(timeout 10 docker version --format '{{.Server.Version}}' 2>/dev/null) && [ -n "$server" ]; then
  ok "Docker engine $server"
else
  warn "Docker is not reachable: start Docker Desktop and enable WSL integration for this distribution"
fi

heading "Network"
if [ -n "${DEV_PROXY_URL:-}" ]; then info "proxy: $DEV_PROXY_URL"; fi
if timeout 15 curl -fsSI --max-time 10 https://github.com >/dev/null 2>&1; then
  ok "github.com reachable over HTTPS"
else
  warn "github.com is not reachable over HTTPS (proxy or certificate settings: dev docs network)"
fi

heading "Links"
for pair in "$HOME/.gitconfig|$DEV_HOME/config/git/gitconfig" "$HOME/.config/mise/conf.d/devbootstrapper.toml|$DEV_HOME/config/mise/config.toml"; do
  link=${pair%%|*}
  target=${pair#*|}
  if [ "$(readlink "$link" 2>/dev/null)" = "$target" ]; then ok "${link/#$HOME/~}"; else warn "${link/#$HOME/~} is not linked (run devup)"; fi
done
if grep -qF '>>> DevBootstrapper (env) >>>' "$HOME/.bashrc" 2>/dev/null; then
  ok "the ~/.bashrc blocks are in place"
else
  warn "$HOME/.bashrc has no DevBootstrapper blocks (run devup)"
fi

heading "Git identities"
"$DEV_HOME/bin/gitid" doctor || true

heading "Secrets"
if [ -f "$DEV_HOME/.secrets" ]; then
  perms=$(stat -c %a "$DEV_HOME/.secrets")
  if [ "$perms" = 600 ]; then
    ok ".secrets is private (600)"
  else
    warn ".secrets has mode $perms; run: chmod 600 $DEV_HOME/.secrets"
  fi
else
  warn "no .secrets yet (copy .secrets.example)"
fi

echo
if [ "$missing" -gt 0 ]; then
  err "$missing tool(s) missing; run devup"
  exit 1
fi
ok "all tools present"
