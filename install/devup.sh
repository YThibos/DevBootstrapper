#!/usr/bin/env bash
# Steps are called by name (step_<name>), which shellcheck cannot follow.
# SC2317 is the code in shellcheck up to 0.10, SC2329 from 0.11 on.
# shellcheck disable=SC2317,SC2329
# devup - install and update DevBootstrapper (docs/updates.md).
# Idempotent: the first install and every daily update run the same steps, in this order:
#   pull         fast-forward the dev home (skipped when it has local changes)
#   windows      copy the launcher and WezTerm stub to the Windows tools folder (WSL only)
#   certs        add the corporate root certificate to Ubuntu's trust store (work profile)
#   apt          apt proxy, git PPA, base packages, upgrade
#   render       render Maven, npm and tmux settings from templates into .local/
#   fonts        install Fira Code into .local/fonts for WezTerm
#   links        link tool configs into place, and the ~/.bashrc blocks (zsh blocks when opted in)
#   mise         install or update mise and every tool in the manifest, prune old versions
#   certs-java   import the corporate root certificate into every installed JDK
#   identities   regenerate the git identity config (gitid sync)
#   completions  generate bash completions for installed tools (and zsh, when opted in)
#   doctor       health report
set -uo pipefail

# shellcheck source=lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"
# shellcheck source=lib/links.sh
. "$DEV_HOME/lib/links.sh"
# shellcheck source=lib/render.sh
. "$DEV_HOME/lib/render.sh"

STEPS=(pull windows certs apt render fonts links mise certs-java identities completions doctor)
FIRST_RUN=0
DAILY=0
REEXECED=0
UNLINK=0
SKIP=''
ONLY=''

usage() {
  cat <<EOF
Usage: devup [--first-run] [--daily] [--skip a,b] [--only a,b] [--unlink]

Steps, in order: ${STEPS[*]}

  --first-run   Interactive machine setup first: profile, proxy, certificate, .secrets,
                shell (bash or zsh), /etc/wsl.conf, ~/.bashrc and git identities.
                Run once by the installer.
  --daily       The daily update started by WezTerm (same steps).
  --skip LIST   Skip steps, comma separated.
  --only LIST   Run only these steps, comma separated.
  --unlink      Remove every link and the ~/.bashrc and zsh blocks DevBootstrapper created.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --first-run) FIRST_RUN=1 ;;
    --daily) DAILY=1 ;;
    --skip) SKIP=$2; shift ;;
    --only) ONLY=$2; shift ;;
    --unlink) UNLINK=1 ;;
    --reexeced) REEXECED=1 ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option $1 (devup --help)" ;;
  esac
  shift
done

# The environment layer gives every step the same PATH, proxy and profile as a shell.
# shellcheck source=bash/env.sh
. "$DEV_HOME/bash/env.sh"

wanted() {
  local s=$1
  [ -z "$ONLY" ] || [[ ,$ONLY, == *,$s,* ]] || return 1
  [[ ,$SKIP, != *,$s,* ]]
}

# ---------------------------------------------------------------------------- helpers

BASHRC_TOP_BEGIN='# >>> DevBootstrapper (env) >>>'
BASHRC_TOP_END='# <<< DevBootstrapper (env) <<<'
BASHRC_BOTTOM_BEGIN='# >>> DevBootstrapper >>>'
BASHRC_BOTTOM_END='# <<< DevBootstrapper <<<'
ZSHENV_BEGIN='# >>> DevBootstrapper (zsh env) >>>'
ZSHENV_END='# <<< DevBootstrapper (zsh env) <<<'
ZSHRC_BEGIN='# >>> DevBootstrapper (zsh) >>>'
ZSHRC_END='# <<< DevBootstrapper (zsh) <<<'

# bootstrap_ref SCRIPT - how a shell startup file refers to a bootstrap script of the dev home.
bootstrap_ref() {
  if [ "$DEV_HOME" = "$HOME/development" ]; then
    # Written literally so the startup file keeps working if the Linux user name changes.
    printf '%s' "\$HOME/development/$1"
  else
    printf '%s' "$DEV_HOME/$1"
  fi
}

# add_rc_block FILE top|bottom BEGIN END COMMENT LINE - adds a marked block that sources the dev
# home, unless FILE has it. Returns 0 when it added the block.
add_rc_block() {
  local rc=$1 where=$2 begin=$3 end=$4 comment=$5 line=$6 tmp
  touch "$rc"
  ! grep -qF "$begin" "$rc" || return 1
  if [ "$where" = top ]; then
    tmp=$(mktemp)
    { printf '%s\n%s\n%s\n%s\n' "$begin" "$comment" "$line" "$end"; cat "$rc"; } >"$tmp"
    cat "$tmp" >"$rc"
    rm -f "$tmp"
  else
    printf '%s\n%s\n%s\n%s\n' "$begin" "$comment" "$line" "$end" >>"$rc"
  fi
}

# remove_rc_block FILE BEGIN END - removes a marked block. Returns 0 when FILE had it, and
# leaves a FILE without it untouched.
remove_rc_block() {
  local rc=$1 begin=$2 end=$3 tmp
  grep -qsF "$begin" "$rc" || return 1
  tmp=$(mktemp)
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip { print }
  ' "$rc" >"$tmp"
  cat "$tmp" >"$rc"
  rm -f "$tmp"
}

ensure_bashrc() {
  local rc="$HOME/.bashrc" ref changed=0
  ref=$(bootstrap_ref bash/bootstrap.sh)
  add_rc_block "$rc" top "$BASHRC_TOP_BEGIN" "$BASHRC_TOP_END" \
    "# Environment for every shell, also non-interactive ones (docs/shell.md)." \
    "[ -f \"$ref\" ] && . \"$ref\" env" && changed=1
  add_rc_block "$rc" bottom "$BASHRC_BOTTOM_BEGIN" "$BASHRC_BOTTOM_END" \
    "# Interactive setup: aliases, functions, completions, prompt (docs/shell.md)." \
    "[ -f \"$ref\" ] && . \"$ref\"" && changed=1
  [ "$changed" -eq 0 ] || info "added the DevBootstrapper blocks to ~/.bashrc"
  return 0
}

remove_bashrc_blocks() {
  local rc="$HOME/.bashrc" removed=0
  remove_rc_block "$rc" "$BASHRC_TOP_BEGIN" "$BASHRC_TOP_END" && removed=1
  remove_rc_block "$rc" "$BASHRC_BOTTOM_BEGIN" "$BASHRC_BOTTOM_END" && removed=1
  [ "$removed" -eq 0 ] || info "removed the DevBootstrapper blocks from ~/.bashrc"
  return 0
}

# zsh is an opt-in layer (docs/shell.md): its blocks exist only while .local/profile.env says
# DEV_SHELL=zsh, and without them ~/.zshenv and ~/.zshrc are never touched.
zsh_opted_in() { [ "$DEV_SHELL" = zsh ]; }

zsh_dir() { printf '%s' "${ZDOTDIR:-$HOME}"; }

ensure_zsh_blocks() {
  local dir ref changed=0
  dir=$(zsh_dir)
  ref=$(bootstrap_ref zsh/bootstrap.zsh)
  add_rc_block "$dir/.zshenv" top "$ZSHENV_BEGIN" "$ZSHENV_END" \
    "# Environment for every zsh, also non-interactive ones (docs/shell.md)." \
    "[ -f \"$ref\" ] && . \"$ref\" env" && changed=1
  add_rc_block "$dir/.zshrc" bottom "$ZSHRC_BEGIN" "$ZSHRC_END" \
    "# Interactive setup: prompt, keys, completion, aliases, functions (docs/shell.md)." \
    "[ -f \"$ref\" ] && . \"$ref\"" && changed=1
  [ "$changed" -eq 0 ] || info "added the DevBootstrapper blocks to ~/.zshenv and ~/.zshrc"
  return 0
}

# remove_zsh_block FILE BEGIN END - removes a marked block, and FILE too when nothing else is in
# it, as then devup created it. Returns 0 when FILE had the block.
remove_zsh_block() {
  local rc=$1
  remove_rc_block "$@" || return 1
  [ -s "$rc" ] || rm -f "$rc"
}

remove_zsh_blocks() {
  local dir removed=0
  dir=$(zsh_dir)
  remove_zsh_block "$dir/.zshenv" "$ZSHENV_BEGIN" "$ZSHENV_END" && removed=1
  remove_zsh_block "$dir/.zshrc" "$ZSHRC_BEGIN" "$ZSHRC_END" && removed=1
  [ "$removed" -eq 0 ] || info "removed the DevBootstrapper blocks from ~/.zshenv and ~/.zshrc"
  return 0
}

sync_zsh_blocks() {
  if zsh_opted_in; then ensure_zsh_blocks; else remove_zsh_blocks; fi
}

# ini_set FILE SECTION KEY VALUE - prints FILE with key=value set inside [section].
ini_set() {
  local file=$1 section=$2 key=$3 value=$4
  { [ -f "$file" ] && cat "$file"; } | awk -v s="[$section]" -v k="$key" -v v="$value" '
    /^[[:space:]]*\[.*\][[:space:]]*$/ {
      if (insec && !done) { print k "=" v; done = 1 }
      insec = ($0 == s); if (insec) seen = 1
      print; next
    }
    insec && $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { if (!done) { print k "=" v; done = 1 } next }
    { print }
    END {
      if (!done) { if (!seen) print s; print k "=" v }
    }
  '
}

ensure_wsl_conf() {
  is_wsl || return 0
  local tmp tmp2
  tmp=$(mktemp)
  tmp2=$(mktemp)
  ini_set /etc/wsl.conf boot systemd true >"$tmp"
  ini_set "$tmp" interop appendWindowsPath false >"$tmp2"
  if [ -f /etc/wsl.conf ] && cmp -s "$tmp2" /etc/wsl.conf; then
    ok "/etc/wsl.conf already set"
  else
    info "setting systemd=true and appendWindowsPath=false in /etc/wsl.conf (sudo)"
    as_root install -m 644 "$tmp2" /etc/wsl.conf
    mkdir -p "$DEV_TOOLS/state"
    touch "$DEV_TOOLS/state/needs-wsl-restart"
    warn "WSL must restart for /etc/wsl.conf; the installer does this, or run from Windows: wsl --terminate ${WSL_DISTRO_NAME:-<distro>}"
  fi
  rm -f "$tmp" "$tmp2"
}

# ---------------------------------------------------------------------------- first run

FIRST_RUN_SECTIONS=5

# Asks for the profile, proxy and certificate, shows the answers and asks again until they are
# right; only then writes .local/profile.env. Earlier answers are the defaults of a second pass.
ask_machine_settings() {
  local profile_file=$1 profile=${DEV_PROFILE:-home} url=${DEV_PROXY_URL:-} noproxy=${DEV_NO_PROXY:-}
  local cert=${DEV_CA_CERT:-} cert_path='' detected=${DEVBOOT_DETECTED_PROXY:-${HTTPS_PROXY:-${https_proxy:-}}}
  [ -n "$url" ] || url=$detected
  while :; do
    banner "1/$FIRST_RUN_SECTIONS  Machine profile" \
      "home is the desktop PC, work the work laptop." \
      "The profile decides the default git context and whether network questions follow."
    ask_choice profile "Machine profile (home or work)" "$profile" home work

    banner "2/$FIRST_RUN_SECTIONS  Network" \
      "A proxy and a corporate certificate are only needed on a corporate network."
    if [ "$profile" = work ] || [ -n "$url" ]; then
      ask url "Proxy URL, e.g. http://proxy.example:8080 (- for none)" "$url"
      [ "$url" != - ] || url=''
      if [ -n "$url" ]; then
        ask noproxy "Hosts that bypass the proxy (comma separated)" "${noproxy:-localhost,127.0.0.1,::1}"
      fi
    else
      info "no proxy detected; none needed on a home machine"
    fi
    if [ "$profile" = work ]; then
      while :; do
        ask cert "Corporate root certificate file, PEM, Windows or Linux path (- for none)" "${cert:--}"
        [ "$cert" != - ] || { cert_path=''; break; }
        cert_path=$cert
        case $cert_path in [A-Za-z]:*) have wslpath && cert_path=$(wslpath -u "$cert_path") ;; esac
        [ -r "$cert_path" ] && break
        warn "cannot read $cert_path"
      done
    else
      cert_path=''
    fi

    heading "Your answers"
    printf '  %-13s %s\n' profile "$profile" proxy "${url:-none}" >&2
    [ -z "$url" ] || printf '  %-13s %s\n' "no proxy for" "$noproxy" >&2
    printf '  %-13s %s\n' certificate "${cert_path:-none}" >&2
    confirm "Is this right?" y && break
    info "again, with your answers as the defaults"
  done

  set_env_value "$profile_file" DEV_PROFILE "$profile"
  set_env_value "$profile_file" DEV_PROXY_URL "$url"
  [ -z "$url" ] || set_env_value "$profile_file" DEV_NO_PROXY "$noproxy"
  local stored="$DEV_HOME/.local/certs/corporate-root.crt"
  if [ -n "$cert_path" ]; then
    mkdir -p "$DEV_HOME/.local/certs"
    [ "$(readlink -f "$cert_path")" = "$(readlink -f "$stored")" ] || cp "$cert_path" "$stored"
    set_env_value "$profile_file" DEV_CA_CERT "$stored"
  else
    set_env_value "$profile_file" DEV_CA_CERT ''
  fi
  ok "machine profile saved in .local/profile.env"
}

# Asks which interactive shell this machine uses; the answer is DEV_SHELL in .local/profile.env.
ask_shell() {
  local profile_file=$1 shell=${DEV_SHELL:-bash}
  ask_choice shell "Interactive shell (bash or zsh)" "$shell" bash zsh
  set_env_value "$profile_file" DEV_SHELL "$shell"
  DEV_SHELL=$shell
  ok "interactive shell: $shell"
}

first_run() {
  is_tty || die "devup --first-run is interactive; run it in a terminal"
  local profile_file="$DEV_HOME/.local/profile.env"
  if [ ! -f "$profile_file" ]; then
    mkdir -p "$DEV_HOME/.local"
    cp "$DEV_HOME/.local.example/profile.env" "$profile_file"
  fi
  load_env_file "$profile_file"
  ask_machine_settings "$profile_file"

  banner "3/$FIRST_RUN_SECTIONS  Shell and WSL" \
    ".secrets for your tokens, /etc/wsl.conf (asks for your sudo password) and two blocks in ~/.bashrc." \
    "bash is the default shell; zsh is an opt-in with the same tools and a themed prompt (docs/shell.md)."
  ask_shell "$profile_file"
  if [ ! -f "$DEV_HOME/.secrets" ]; then
    cp "$DEV_HOME/.secrets.example" "$DEV_HOME/.secrets"
    ok "created .secrets from .secrets.example"
  fi
  chmod 600 "$DEV_HOME/.secrets"
  ensure_wsl_conf
  ensure_bashrc
  sync_zsh_blocks

  # Reload the environment with the new profile before identities and tools.
  . "$DEV_HOME/bash/env.sh"
  DEVBOOT_SECTION="4/$FIRST_RUN_SECTIONS" "$DEV_HOME/bin/gitid" setup ||
    warn "git identity setup did not finish; run gitid setup later"

  banner "5/$FIRST_RUN_SECTIONS  Install" \
    "Every tool installs now; the first time takes a few minutes." \
    "Each step reports ok or FAILED, and a summary follows at the end."
}

# ---------------------------------------------------------------------------- steps

step_pull() {
  if ! git -C "$DEV_HOME" rev-parse --git-dir >/dev/null 2>&1; then
    info "the dev home is not a git clone; nothing to pull"
    return 0
  fi
  if ! git -C "$DEV_HOME" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    info "the dev home branch has no upstream; nothing to pull"
    return 0
  fi
  git -C "$DEV_HOME" fetch --quiet || return 1
  local behind before
  behind=$(git -C "$DEV_HOME" rev-list --count 'HEAD..@{u}')
  if [ "$behind" -eq 0 ]; then
    ok "dev home is up to date"
    return 0
  fi
  if [ -n "$(git -C "$DEV_HOME" status --porcelain --untracked-files=no)" ]; then
    warn "$behind new commit(s) not pulled: the dev home has local changes (git -C ~/development status)"
    return 0
  fi
  before=$(git -C "$DEV_HOME" rev-parse HEAD)
  if ! git -C "$DEV_HOME" merge --ff-only --quiet '@{u}'; then
    warn "the dev home has diverged from its upstream; not pulling (git -C ~/development status)"
    return 0
  fi
  ok "pulled $behind commit(s)"
  if [ "$REEXECED" -eq 0 ] && [ "$(git -C "$DEV_HOME" rev-parse HEAD)" != "$before" ]; then
    info "continuing with the updated devup"
    local args=(--reexeced --skip "pull${SKIP:+,$SKIP}")
    [ -n "$ONLY" ] && args+=(--only "$ONLY")
    [ "$DAILY" -eq 1 ] && args+=(--daily)
    exec bash "$DEV_HOME/install/devup.sh" "${args[@]}"
  fi
}

step_windows() {
  is_wsl || { info "not running in WSL"; return 0; }
  local win="${DEV_WINDOWS_TOOLS:-/mnt/c/development/tools}/launcher" f changed=0
  if [ ! -d "$win" ]; then
    info "no Windows launcher at $win yet (run windows/install.ps1 on Windows)"
    return 0
  fi
  for f in launcher.ps1 wezterm-stub.lua; do
    if ! cmp -s "$DEV_HOME/windows/$f" "$win/$f"; then
      cp "$DEV_HOME/windows/$f" "$win/$f" || return 1
      changed=1
    fi
  done
  if [ "$changed" -eq 1 ]; then ok "updated the Windows launcher files"; else ok "Windows launcher files are current"; fi
}

step_certs() {
  if [ -z "${DEV_CA_CERT:-}" ]; then
    info "no corporate certificate configured"
    return 0
  fi
  [ -r "$DEV_CA_CERT" ] || { err "cannot read DEV_CA_CERT=$DEV_CA_CERT"; return 1; }
  local target=/usr/local/share/ca-certificates/devbootstrapper-corporate.crt
  if cmp -s "$DEV_CA_CERT" "$target"; then
    ok "corporate certificate already trusted"
    return 0
  fi
  as_root install -m 644 "$DEV_CA_CERT" "$target" && as_root update-ca-certificates >/dev/null || return 1
  ok "corporate certificate added to Ubuntu's trust store"
}

step_apt() {
  have apt-get || { info "no apt-get on this system"; return 0; }
  local conf=/etc/apt/apt.conf.d/95devbootstrapper-proxy tmp
  if [ -n "${DEV_PROXY_URL:-}" ]; then
    tmp=$(mktemp)
    printf 'Acquire::http::Proxy "%s";\nAcquire::https::Proxy "%s";\n' "$DEV_PROXY_URL" "$DEV_PROXY_URL" >"$tmp"
    cmp -s "$tmp" "$conf" || as_root install -m 644 "$tmp" "$conf"
    rm -f "$tmp"
  elif [ -f "$conf" ]; then
    as_root rm -f "$conf"
  fi

  info "apt-get update (sudo)"
  as_root apt-get update -qq || return 1

  if ! grep -rqs 'git-core' /etc/apt/sources.list /etc/apt/sources.list.d/; then
    local codename
    codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
    if [ -n "$codename" ] && curl -fsI --max-time 10 "https://ppa.launchpadcontent.net/git-core/ppa/ubuntu/dists/$codename/Release" >/dev/null 2>&1; then
      info "adding the git-core PPA for the latest git"
      if as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq software-properties-common >/dev/null &&
        as_root add-apt-repository -y ppa:git-core/ppa >/dev/null &&
        as_root apt-get update -qq; then
        ok "git-core PPA added"
      else
        warn "could not add the git-core PPA; using Ubuntu's git"
      fi
    else
      info "the git-core PPA has no build for ${codename:-this release} yet; using Ubuntu's git"
    fi
  fi

  # apt-get install refuses the whole list over one unknown name, so offer only what exists.
  local pkgs=() pkg available=() unavailable=()
  mapfile -t pkgs < <(base_packages)
  for pkg in "${pkgs[@]}"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then available+=("$pkg"); else unavailable+=("$pkg"); fi
  done
  [ ${#unavailable[@]} -eq 0 ] || warn "not offered by this Ubuntu release, skipped: ${unavailable[*]}"
  info "installing base packages"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${available[@]}" >/dev/null || return 1
  info "upgrading packages"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq >/dev/null || return 1
  ok "apt packages installed and upgraded"
}

step_render() {
  local r
  r=$(render_template "$DEV_HOME/config/maven/settings.xml" "$DEV_HOME/.local/maven/settings.xml") || return 1
  [ "$r" = changed ] && info "rendered .local/maven/settings.xml"
  r=$(render_template "$DEV_HOME/config/npm/npmrc" "$DEV_HOME/.local/npm/npmrc") || return 1
  [ "$r" = changed ] && info "rendered .local/npm/npmrc"
  r=$(render_template "$DEV_HOME/config/tmux/tmux.conf" "$DEV_HOME/.local/tmux/tmux.conf") || return 1
  [ "$r" = changed ] && info "rendered .local/tmux/tmux.conf"
  ok "Maven, npm and tmux settings rendered"
}

# Every link devup manages: SOURCE|LINK|MODE
link_table() {
  cat <<EOF
$DEV_HOME/config/git/gitconfig|$HOME/.gitconfig|replace
$DEV_HOME/config/mise/config.toml|$HOME/.config/mise/conf.d/devbootstrapper.toml|replace
$DEV_HOME/.local/mise/config.toml|$HOME/.config/mise/config.toml|adopt
$DEV_TOOLS/mise|$HOME/.local/share/mise|replace
$DEV_TOOLS/cache|$HOME/.cache|replace
$DEV_HOME/.local/tmux/tmux.conf|$HOME/.tmux.conf|replace
$DEV_HOME/.local/maven/settings.xml|$HOME/.m2/settings.xml|replace
$DEV_HOME/.local/npm/npmrc|$HOME/.npmrc|replace
$DEV_HOME/config/claude/settings.json|$HOME/.claude/settings.json|adopt
$DEV_HOME/config/claude/CLAUDE.md|$HOME/.claude/CLAUDE.md|adopt
EOF
}

FIRA_CODE_VERSION=6.2
FIRA_CODE_URL="https://github.com/tonsky/FiraCode/releases/download/$FIRA_CODE_VERSION/Fira_Code_v$FIRA_CODE_VERSION.zip"

# Fira Code (SIL Open Font License) is the font of EDI's face in WezTerm; WezTerm finds it in
# .local/fonts without installing it in Windows (docs/wezterm.md).
step_fonts() {
  local dir="$DEV_HOME/.local/fonts" tmp
  if [ -f "$dir/FiraCode-Regular.ttf" ]; then
    ok "Fira Code is installed"
    return 0
  fi
  have unzip || { err "unzip is missing; run devup --only apt"; return 1; }
  tmp=$(mktemp -d)
  mkdir -p "$dir"
  if ! { curl -fsSL "$FIRA_CODE_URL" -o "$tmp/fira-code.zip" && unzip -qoj "$tmp/fira-code.zip" 'ttf/*.ttf' -d "$dir"; }; then
    rm -rf "$tmp"
    err "could not install Fira Code from $FIRA_CODE_URL"
    return 1
  fi
  rm -rf "$tmp"
  ok "installed Fira Code $FIRA_CODE_VERSION into .local/fonts"
}

step_links() {
  mkdir -p "$DEV_TOOLS/mise" "$DEV_TOOLS/cache" "$DEV_TOOLS/state"
  if [ ! -f "$DEV_HOME/.local/mise/config.toml" ]; then
    mkdir -p "$DEV_HOME/.local/mise"
    printf '%s\n%s\n' '# Machine-local tool defaults, written by use-version (docs/tools.md). Not shared.' '[tools]' \
      >"$DEV_HOME/.local/mise/config.toml"
  fi
  if [ ! -f "$DEV_HOME/.local/wezterm.lua" ]; then
    cp "$DEV_HOME/.local.example/wezterm.lua" "$DEV_HOME/.local/wezterm.lua"
    info "created .local/wezterm.lua from .local.example (WezTerm backgrounds)"
  fi
  local src link mode r count=0
  while IFS='|' read -r src link mode; do
    r=$(ensure_link "$src" "$link" "$mode") || return 1
    [ "$r" = changed ] && { info "linked ${link/#$HOME/~}"; count=$((count + 1)); }
  done < <(link_table)
  ensure_bashrc
  sync_zsh_blocks
  ok "links in place ($count changed)"
}

step_mise() {
  local mise="$DEV_TOOLS/bin/mise"
  if [ ! -x "$mise" ]; then
    info "installing mise into tools/bin"
    mkdir -p "$DEV_TOOLS/bin"
    curl -fsSL https://mise.run | MISE_INSTALL_PATH="$mise" sh || return 1
  else
    "$mise" self-update --yes >/dev/null 2>&1 || info "mise self-update skipped ($("$mise" --version 2>/dev/null))"
  fi
  "$mise" trust --quiet "$DEV_HOME/config/mise/config.toml" >/dev/null 2>&1 || true
  info "installing missing tools"
  "$mise" install --yes || return 1
  info "upgrading tools within their version lines"
  "$mise" upgrade --yes || return 1
  "$mise" prune --yes >/dev/null 2>&1 || true
  "$mise" reshim >/dev/null 2>&1 || true
  ok "mise tools are current"
}

step_certs_java() {
  [ -n "${DEV_CA_CERT:-}" ] || { info "no corporate certificate configured"; return 0; }
  local d store keytool count=0
  for d in "$MISE_DATA_DIR"/installs/java/*/; do
    d=${d%/}
    if [ ! -d "$d" ] || [ -L "$d" ]; then continue; fi
    store="$d/lib/security/cacerts"
    [ -f "$store" ] || store="$d/jre/lib/security/cacerts"
    keytool="$d/bin/keytool"
    if [ ! -f "$store" ] || [ ! -x "$keytool" ]; then continue; fi
    if "$keytool" -list -keystore "$store" -storepass changeit -alias devbootstrapper-corporate >/dev/null 2>&1; then
      continue
    fi
    "$keytool" -importcert -noprompt -keystore "$store" -storepass changeit \
      -alias devbootstrapper-corporate -file "$DEV_CA_CERT" >/dev/null || return 1
    count=$((count + 1))
  done
  ok "corporate certificate present in every JDK ($count updated)"
}

step_identities() {
  "$DEV_HOME/bin/gitid" sync || return 1
  ok "git identity config regenerated"
}

step_completions() {
  local bash_count zsh_count
  bash_count=$(generate_completions bash "$DEV_TOOLS/completions/completions" '' completion_commands)
  ok "bash completions generated for $bash_count tools"
  zsh_opted_in || return 0
  zsh_count=$(generate_completions zsh "$DEV_TOOLS/completions/zsh" _ zsh_completion_commands)
  rm -f "$DEV_TOOLS"/cache/zsh/zcompdump*
  ok "zsh completions generated for $zsh_count tools"
}

# generate_completions SHELL DIR PREFIX TABLE - writes the completion of every installed tool in
# TABLE to DIR/PREFIX<name> (a name ending in .zsh is a script to source and takes no prefix),
# keeping the previous file when a tool fails. Prints the count.
# Some tools, ng among them, write the completion for the shell in $SHELL, which is the login
# shell and not the one the file is for; so SHELL is set for each tool.
generate_completions() {
  local shell=$1 dir=$2 prefix=$3 table=$4 name command words file tmp n=0
  mkdir -p "$dir"
  tmp=$(mktemp)
  while IFS='|' read -r name command; do
    read -ra words <<<"${command//@SHELL@/$shell}"
    have "${words[0]}" || continue
    if SHELL="/usr/bin/$shell" timeout 30 "${words[@]}" </dev/null >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
      file=$prefix$name
      [[ $name == *.zsh ]] && file=$name
      cp "$tmp" "$dir/$file"
      n=$((n + 1))
    fi
  done < <("$table")
  rm -f "$tmp"
  echo "$n"
}

# NAME|COMMAND, one tool per line; @SHELL@ stands for the shell the completion is for.
completion_commands() {
  cat <<'LIST'
gh|gh completion -s @SHELL@
glab|glab completion -s @SHELL@
mise|mise completion @SHELL@
uv|uv generate-shell-completion @SHELL@
rg|rg --generate complete-@SHELL@
fd|fd --gen-completions @SHELL@
bat|bat --completion @SHELL@
delta|delta --generate-completion @SHELL@
xh|xh --generate complete-@SHELL@
glow|glow completion @SHELL@
yq|yq shell-completion @SHELL@
starship|starship completions @SHELL@
docker|docker completion @SHELL@
npm|npm completion
ng|ng completion script
LIST
}

# zsh takes the same tools as completion functions (_name), except npm, whose script is for
# bash only, and ng, whose script is sourced.
zsh_completion_commands() {
  completion_commands | grep -v -e '^npm|' -e '^ng|'
  echo 'ng.zsh|ng completion script'
}

step_doctor() {
  bash "$DEV_HOME/install/doctor.sh"
}

# ---------------------------------------------------------------------------- main

if [ "$UNLINK" -eq 1 ]; then
  while IFS='|' read -r _src link _mode; do remove_link "$link"; done < <(link_table)
  remove_bashrc_blocks
  remove_zsh_blocks
  info "DevBootstrapper links removed. To remove everything, also delete $DEV_HOME and, on Windows, C:\\development\\tools and the Start-menu shortcut."
  exit 0
fi

if [ "$FIRST_RUN" -eq 1 ]; then
  first_run
fi

[ "$DAILY" -eq 1 ] && banner "Daily DevBootstrapper update ($(today))"

RESULTS=()
FAILED=0
for step in "${STEPS[@]}"; do
  wanted "$step" || continue
  rule "$step"
  if "step_${step//-/_}"; then
    RESULTS+=("ok      $step")
  else
    RESULTS+=("FAILED  $step")
    FAILED=1
  fi
done

rule "Summary"
for r in "${RESULTS[@]}"; do
  case $r in FAILED*) printf '  %s%s%s\n' "$_c_red" "$r" "$_c_off" ;; *) printf '  %s\n' "$r" ;; esac
done

# Only a complete, successful run counts as today's update (a re-run after pulling skips pull).
complete_run=0
if [ -z "$ONLY" ]; then
  if [ -z "$SKIP" ] || { [ "$REEXECED" -eq 1 ] && [ "$SKIP" = pull ]; }; then complete_run=1; fi
fi
if [ "$FAILED" -eq 0 ] && [ "$complete_run" -eq 1 ]; then
  mkdir -p "$DEV_TOOLS/state"
  today >"$DEV_TOOLS/state/last-update"
fi
if [ -f "$DEV_TOOLS/state/needs-wsl-restart" ] && [ "$FIRST_RUN" -eq 0 ]; then
  warn "WSL still needs a restart for /etc/wsl.conf: from Windows run wsl --terminate ${WSL_DISTRO_NAME:-<distro>}"
fi
if [ "$FIRST_RUN" -eq 1 ]; then
  if [ "$FAILED" -eq 0 ]; then
    banner "DevBootstrapper is installed" \
      "1. Open a new shell (or run: reload), then: dev" \
      "2. Fill in your tokens: secrets, then check them: gitid doctor"
  else
    banner "Setup finished with failed steps" \
      "Fix the problems reported above, then run: devup" \
      "Your answers are saved; the questions are not asked again."
  fi
fi
exit "$FAILED"
