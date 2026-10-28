# shellcheck shell=bash
# Shell functions. Annotate each with a "#: usage | description" line for dev cheat.

#: mkcd <dir> | create a folder and enter it
mkcd() { mkdir -p -- "$1" && cd -- "$1" || return; }

#: clone <url> [context] | clone into sources/<context>/<repo> with that context's account, then cd into it
clone() {
  local url=${1:-} ctx=${2:-} name dest
  [ -n "$url" ] || { echo "usage: clone <url> [context]" >&2; return 2; }
  [ -n "$ctx" ] || ctx=$(gitid prompt)
  [ -n "$ctx" ] || { echo "no context; run gitid setup or pass one" >&2; return 1; }
  name=${url%/}
  name=${name%.git}
  name=${name##*/}
  name=${name##*:}
  dest="$DEV_HOME/sources/$ctx/$name"
  mkdir -p "$DEV_HOME/sources/$ctx"
  (cd "$DEV_HOME/sources/$ctx" && git clone "$url" "$dest") && cd "$dest" || return
}

#: repo [query] | jump to a repository under sources/ (fuzzy with fzf)
repo() {
  local list pick
  list=$(find "$DEV_HOME/sources" -mindepth 2 -maxdepth 4 -type d -name .git -prune 2>/dev/null |
    sed -e 's|/\.git$||' -e "s|^$DEV_HOME/sources/||" | sort)
  [ -n "$list" ] || { echo "no repositories under sources/ yet" >&2; return 1; }
  if command -v fzf >/dev/null 2>&1; then
    pick=$(printf '%s\n' "$list" | fzf --height 40% --reverse --select-1 --query "${1:-}")
  else
    pick=$(printf '%s\n' "$list" | grep -i -- "${1:-}" | head -1)
  fi
  [ -n "$pick" ] && cd "$DEV_HOME/sources/$pick" || return
}

#: tmpd [name] | create a scratch folder under tmp/ and enter it
tmpd() {
  local d="$DEV_HOME/tmp/${1:-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$d" && cd "$d" || return
}

#: secrets | edit .secrets, then reload it into this shell
secrets() {
  local f="$DEV_HOME/.secrets"
  [ -f "$f" ] || { touch "$f" && chmod 600 "$f"; }
  # shellcheck disable=SC1090
  "${EDITOR:-nano}" "$f" && set -a && . "$f" && set +a
}

#: reload | reload the DevBootstrapper shell setup
reload() {
  __devboot_env_loaded=''
  # shellcheck disable=SC1091
  . "$DEV_HOME/bash/bootstrap.sh"
}

#: port <n> | show what listens on a TCP port
port() { ss -ltnp 2>/dev/null | awk -v p=":$1" 'NR==1 || index($4, p)'; }

#: serve [port] | serve the current folder over HTTP (default 8000)
serve() { python3 -m http.server "${1:-8000}"; }

#: extract <archive> | unpack any common archive
extract() {
  case $1 in
    *.tar.gz | *.tgz) tar xzf "$1" ;;
    *.tar.xz) tar xJf "$1" ;;
    *.tar.bz2) tar xjf "$1" ;;
    *.tar) tar xf "$1" ;;
    *.zip | *.jar | *.war) unzip "$1" ;;
    *.gz) gunzip "$1" ;;
    *) echo "extract: unknown archive type: $1" >&2; return 1 ;;
  esac
}
