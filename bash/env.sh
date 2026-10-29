# shellcheck shell=bash
# Environment layer (docs/shell.md): loaded for every bash shell, interactive or not, through
# the top block in ~/.bashrc. It must stay silent, fast, and free of network calls and sudo.

DEV_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEV_TOOLS="$DEV_HOME/tools"
export DEV_HOME DEV_TOOLS

__devboot_path_prepend() {
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1${PATH:+:$PATH}" ;;
  esac
}

__devboot_load() {
  [ -r "$1" ] || return 0
  local had_a=0
  case $- in *a*) had_a=1 ;; esac
  set -a
  # shellcheck disable=SC1090
  . "$1"
  [ "$had_a" -eq 1 ] || set +a
}

# Machine profile (home or work, proxy, mirrors, certificate), then credentials.
__devboot_load "$DEV_HOME/.local/profile.env"
__devboot_load "$DEV_HOME/.secrets"

# Every cache and every mise-managed tool lives under tools/.
export XDG_CACHE_HOME="$DEV_TOOLS/cache"
export MISE_DATA_DIR="$DEV_TOOLS/mise"
export MISE_CACHE_DIR="$DEV_TOOLS/cache/mise"
export GRADLE_USER_HOME="$DEV_TOOLS/cache/gradle"
export npm_config_cache="$DEV_TOOLS/cache/npm"
export BASH_COMPLETION_USER_DIR="$DEV_TOOLS/completions"
export STARSHIP_CONFIG="$DEV_HOME/config/starship.toml"
export STARSHIP_CACHE="$DEV_TOOLS/cache/starship"
export DOCKER_CLI_HINTS=false
export NG_CLI_ANALYTICS=false

# PATH, highest priority first: wrappers, DevBootstrapper commands, tool binaries, mise shims.
__devboot_path_prepend "$MISE_DATA_DIR/shims"
__devboot_path_prepend "$DEV_TOOLS/bin"
__devboot_path_prepend "$DEV_HOME/bin"
__devboot_path_prepend "$DEV_HOME/bin/wrappers"
export PATH

# Corporate proxy (docs/network.md): one setting, every tool.
if [ -n "${DEV_PROXY_URL:-}" ]; then
  export HTTP_PROXY="$DEV_PROXY_URL" HTTPS_PROXY="$DEV_PROXY_URL"
  export http_proxy="$DEV_PROXY_URL" https_proxy="$DEV_PROXY_URL"
  export NO_PROXY="${DEV_NO_PROXY:-localhost,127.0.0.1,::1}"
  export no_proxy="$NO_PROXY"
  __devboot_hp=${DEV_PROXY_URL#*://}
  __devboot_hp=${__devboot_hp#*@}
  __devboot_hp=${__devboot_hp%%/*}
  export DEV_PROXY_HOST=${__devboot_hp%%:*}
  case $__devboot_hp in
    *:*) export DEV_PROXY_PORT=${__devboot_hp##*:} ;;
    *) export DEV_PROXY_PORT=80 ;;
  esac
  # Maven and Java want "|" separated host patterns with "*" wildcards.
  __devboot_np=$(printf '%s' "$NO_PROXY" | tr ',' '\n' | sed -e 's/^ *//' -e 's/^\./*./' | paste -sd '|' -)
  export DEV_MAVEN_NON_PROXY_HOSTS="$__devboot_np"
  export JAVA_TOOL_OPTIONS="-Dhttp.proxyHost=$DEV_PROXY_HOST -Dhttp.proxyPort=$DEV_PROXY_PORT -Dhttps.proxyHost=$DEV_PROXY_HOST -Dhttps.proxyPort=$DEV_PROXY_PORT -Dhttp.nonProxyHosts=$__devboot_np"
  unset __devboot_hp __devboot_np
fi

# Corporate root certificate: Node reads it directly; others use the system bundle it was added to.
if [ -n "${DEV_CA_CERT:-}" ] && [ -r "$DEV_CA_CERT" ]; then
  export NODE_EXTRA_CA_CERTS="$DEV_CA_CERT"
  export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
  export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
fi

if [ -n "${DEV_NPM_REGISTRY:-}" ]; then
  __devboot_reg=${DEV_NPM_REGISTRY#*://}
  export DEV_NPM_REGISTRY_AUTH_PATH="${__devboot_reg%/}/"
  unset __devboot_reg
fi
: "${DEV_MAVEN_MIRROR_OF:=*}"
export DEV_MAVEN_MIRROR_OF

# WSL: open links and files with Windows.
if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -e /proc/sys/fs/binfmt_misc/WSLInterop ]; then
  export DEV_IS_WSL=1
  if [ -z "${BROWSER:-}" ]; then
    export BROWSER="$DEV_HOME/bin/winopen"
  fi
fi

unset -f __devboot_path_prepend __devboot_load
