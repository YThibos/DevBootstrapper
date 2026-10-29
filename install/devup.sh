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
#   render       render Maven and npm settings from templates into .local/
#   links        link tool configs into place, and the ~/.bashrc blocks
#   mise         install or update mise and every tool in the manifest, prune old versions
#   certs-java   import the corporate root certificate into every installed JDK
#   identities   regenerate the git identity config (gitid sync)
#   completions  generate bash completions for installed tools
#   doctor       health report
set -uo pipefail

# shellcheck source=lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"
# shellcheck source=lib/links.sh
. "$DEV_HOME/lib/links.sh"
# shellcheck source=lib/render.sh
. "$DEV_HOME/lib/render.sh"

STEPS=(pull windows certs apt render links mise certs-java identities completions doctor)
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
                /etc/wsl.conf, ~/.bashrc and git identities. Run once by the installer.
  --daily       The daily update started by WezTerm (same steps).
  --skip LIST   Skip steps, comma separated.
  --only LIST   Run only these steps, comma separated.
  --unlink      Remove every link and the ~/.bashrc blocks DevBootstrapper created.
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

bootstrap_ref() {
  if [ "$DEV_HOME" = "$HOME/development" ]; then
    # Written literally so ~/.bashrc keeps working if the Linux user name changes.
    # shellcheck disable=SC2016
    printf '%s' '$HOME/development/bash/bootstrap.sh'
  else
    printf '%s' "$DEV_HOME/bash/bootstrap.sh"
  fi
}

ensure_bashrc() {
  local rc="$HOME/.bashrc" ref tmp changed=0
  ref=$(bootstrap_ref)
  touch "$rc"
  if ! grep -qF "$BASHRC_TOP_BEGIN" "$rc"; then
    tmp=$(mktemp)
    {
      echo "$BASHRC_TOP_BEGIN"
      echo "# Environment for every shell, also non-interactive ones (docs/shell.md)."
      echo "[ -f \"$ref\" ] && . \"$ref\" env"
      echo "$BASHRC_TOP_END"
      cat "$rc"
    } >"$tmp"
    cat "$tmp" >"$rc"
    rm -f "$tmp"
    changed=1
  fi
  if ! grep -qF "$BASHRC_BOTTOM_BEGIN" "$rc"; then
    {
      echo "$BASHRC_BOTTOM_BEGIN"
      echo "# Interactive setup: aliases, functions, completions, prompt (docs/shell.md)."
      echo "[ -f \"$ref\" ] && . \"$ref\""
      echo "$BASHRC_BOTTOM_END"
    } >>"$rc"
    changed=1
  fi
  [ "$changed" -eq 1 ] && info "added the DevBootstrapper blocks to ~/.bashrc"
  return 0
}

remove_bashrc_blocks() {
  local rc="$HOME/.bashrc" tmp
  [ -f "$rc" ] || return 0
  tmp=$(mktemp)
  awk -v b1="$BASHRC_TOP_BEGIN" -v e1="$BASHRC_TOP_END" -v b2="$BASHRC_BOTTOM_BEGIN" -v e2="$BASHRC_BOTTOM_END" '
    $0 == b1 || $0 == b2 { skip = 1; next }
    $0 == e1 || $0 == e2 { skip = 0; next }
    !skip { print }
  ' "$rc" >"$tmp"
  cat "$tmp" >"$rc"
  rm -f "$tmp"
  info "removed the DevBootstrapper blocks from ~/.bashrc"
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

first_run() {
  is_tty || die "devup --first-run is interactive; run it in a terminal"
  heading "First-run setup"
  local profile_file="$DEV_HOME/.local/profile.env"
  if [ ! -f "$profile_file" ]; then
    mkdir -p "$DEV_HOME/.local"
    cp "$DEV_HOME/.local.example/profile.env" "$profile_file"
  fi
  [ -f "$DEV_HOME/.local/wezterm.lua" ] || cp "$DEV_HOME/.local.example/wezterm.lua" "$DEV_HOME/.local/wezterm.lua"
  load_env_file "$profile_file"

  local profile url noproxy cert
  ask profile "Machine profile: home (desktop PC) or work (work laptop)" "${DEV_PROFILE:-home}"
  case $profile in home | work) ;; *) die "profile must be home or work" ;; esac
  set_env_value "$profile_file" DEV_PROFILE "$profile"

  local detected=${DEVBOOT_DETECTED_PROXY:-${HTTPS_PROXY:-${https_proxy:-}}}
  if [ "$profile" = work ] || [ -n "$detected" ] || [ -n "${DEV_PROXY_URL:-}" ]; then
    ask url "Proxy URL, e.g. http://proxy.example:8080 (empty for none)" "${DEV_PROXY_URL:-$detected}"
    set_env_value "$profile_file" DEV_PROXY_URL "$url"
    if [ -n "$url" ]; then
      ask noproxy "Hosts that bypass the proxy (comma separated)" "${DEV_NO_PROXY:-localhost,127.0.0.1,::1}"
      set_env_value "$profile_file" DEV_NO_PROXY "$noproxy"
    fi
  fi

  if [ "$profile" = work ]; then
    ask cert "Corporate root certificate file, PEM, Windows or Linux path (empty for none)" ""
    if [ -n "$cert" ]; then
      case $cert in [A-Za-z]:*) have wslpath && cert=$(wslpath -u "$cert") ;; esac
      [ -r "$cert" ] || die "cannot read $cert"
      mkdir -p "$DEV_HOME/.local/certs"
      cp "$cert" "$DEV_HOME/.local/certs/corporate-root.crt"
      set_env_value "$profile_file" DEV_CA_CERT "$DEV_HOME/.local/certs/corporate-root.crt"
    fi
  fi
  ok "machine profile saved in .local/profile.env"

  if [ ! -f "$DEV_HOME/.secrets" ]; then
    cp "$DEV_HOME/.secrets.example" "$DEV_HOME/.secrets"
    ok "created .secrets from .secrets.example"
  fi
  chmod 600 "$DEV_HOME/.secrets"

  ensure_wsl_conf
  ensure_bashrc

  # Reload the environment with the new profile before identities and tools.
  . "$DEV_HOME/bash/env.sh"
  "$DEV_HOME/bin/gitid" setup || warn "git identity setup did not finish; run gitid setup later"
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

apt_packages() {
  local line pkg tag
  while IFS= read -r line; do
    line=${line%%#*}
    read -r pkg tag <<<"$line"
    [ -n "$pkg" ] || continue
    if [ "$tag" = "[wsl]" ] && ! is_wsl; then continue; fi
    printf '%s\n' "$pkg"
  done <"$DEV_HOME/install/apt-packages.txt"
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

  local pkgs=()
  mapfile -t pkgs < <(apt_packages)
  info "installing base packages"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}" >/dev/null || return 1
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
  ok "Maven and npm settings rendered"
}

# Every link devup manages: SOURCE|LINK|MODE
link_table() {
  cat <<EOF
$DEV_HOME/config/git/gitconfig|$HOME/.gitconfig|replace
$DEV_HOME/config/mise/config.toml|$HOME/.config/mise/conf.d/devbootstrapper.toml|replace
$DEV_HOME/.local/mise/config.toml|$HOME/.config/mise/config.toml|adopt
$DEV_TOOLS/mise|$HOME/.local/share/mise|replace
$DEV_TOOLS/cache|$HOME/.cache|replace
$DEV_HOME/config/tmux/tmux.conf|$HOME/.tmux.conf|replace
$DEV_HOME/.local/maven/settings.xml|$HOME/.m2/settings.xml|replace
$DEV_HOME/.local/npm/npmrc|$HOME/.npmrc|replace
$DEV_HOME/config/claude/settings.json|$HOME/.claude/settings.json|adopt
$DEV_HOME/config/claude/CLAUDE.md|$HOME/.claude/CLAUDE.md|adopt
EOF
}

step_links() {
  mkdir -p "$DEV_TOOLS/mise" "$DEV_TOOLS/cache" "$DEV_TOOLS/state"
  if [ ! -f "$DEV_HOME/.local/mise/config.toml" ]; then
    mkdir -p "$DEV_HOME/.local/mise"
    printf '%s\n%s\n' '# Machine-local tool defaults, written by use-version (docs/tools.md). Not shared.' '[tools]' \
      >"$DEV_HOME/.local/mise/config.toml"
  fi
  local src link mode r count=0
  while IFS='|' read -r src link mode; do
    r=$(ensure_link "$src" "$link" "$mode") || return 1
    [ "$r" = changed ] && { info "linked ${link/#$HOME/~}"; count=$((count + 1)); }
  done < <(link_table)
  ensure_bashrc
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
  local dir="$DEV_TOOLS/completions/completions" tmp n=0
  mkdir -p "$dir"
  tmp=$(mktemp)
  gen() {
    local name=$1
    shift
    have "$1" || return 0
    if timeout 30 "$@" </dev/null >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
      cp "$tmp" "$dir/$name"
      n=$((n + 1))
    fi
  }
  gen gh gh completion -s bash
  gen glab glab completion -s bash
  gen mise mise completion bash
  gen uv uv generate-shell-completion bash
  gen rg rg --generate complete-bash
  gen fd fd --gen-completions bash
  gen bat bat --completion bash
  gen delta delta --generate-completion bash
  gen xh xh --generate complete-bash
  gen glow glow completion bash
  gen yq yq shell-completion bash
  gen starship starship completions bash
  gen docker docker completion bash
  gen npm npm completion
  gen ng ng completion script
  rm -f "$tmp"
  ok "bash completions generated for $n tools"
}

step_doctor() {
  bash "$DEV_HOME/install/doctor.sh"
}

# ---------------------------------------------------------------------------- main

if [ "$UNLINK" -eq 1 ]; then
  while IFS='|' read -r _src link _mode; do remove_link "$link"; done < <(link_table)
  remove_bashrc_blocks
  info "DevBootstrapper links removed. To remove everything, also delete $DEV_HOME and, on Windows, C:\\development\\tools and the Start-menu shortcut."
  exit 0
fi

if [ "$FIRST_RUN" -eq 1 ]; then
  first_run
fi

[ "$DAILY" -eq 1 ] && heading "Daily DevBootstrapper update ($(today))"

RESULTS=()
FAILED=0
for step in "${STEPS[@]}"; do
  wanted "$step" || continue
  heading "$step"
  if "step_${step//-/_}"; then
    RESULTS+=("ok      $step")
  else
    RESULTS+=("FAILED  $step")
    FAILED=1
  fi
done

heading "Summary"
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
if [ "$FIRST_RUN" -eq 1 ] && [ "$FAILED" -eq 0 ]; then
  echo
  ok "DevBootstrapper is installed. Open a new shell (or run: reload), then: dev"
fi
exit "$FAILED"
