# shellcheck shell=bash
# Shared helpers for DevBootstrapper commands and install scripts.
# Sourced, never executed; callers set `set -euo pipefail` themselves.

# DEV_HOME is the directory that contains lib/, resolved from this file's location.
DEV_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEV_TOOLS="$DEV_HOME/tools"
export DEV_HOME DEV_TOOLS

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  _c_red=$'\033[31m' _c_yellow=$'\033[33m' _c_green=$'\033[32m' _c_blue=$'\033[34m' _c_bold=$'\033[1m' _c_off=$'\033[0m'
else
  _c_red='' _c_yellow='' _c_green='' _c_blue='' _c_bold='' _c_off=''
fi

info() { printf '%s\n' "${_c_blue}::${_c_off} $*" >&2; }
ok() { printf '%s\n' "${_c_green}ok${_c_off} $*" >&2; }
warn() { printf '%s\n' "${_c_yellow}warning:${_c_off} $*" >&2; }
err() { printf '%s\n' "${_c_red}error:${_c_off} $*" >&2; }
die() { err "$*"; exit 1; }
heading() { printf '\n%s\n' "${_c_bold}$*${_c_off}" >&2; }

# repeat CHAR COUNT - prints CHAR COUNT times.
repeat() { printf '%*s' "$2" '' | tr ' ' "$1"; }

# banner "Title" ["Explanation"...] - opens a part of an interactive setup, set apart by blank lines.
banner() {
  local title=$1 line
  shift
  line=$(repeat '=' 64)
  printf '\n\n%s\n  %s\n%s\n' "$_c_bold$line" "$title" "$line$_c_off" >&2
  [ $# -eq 0 ] || printf '  %s\n' "$@" >&2
  printf '\n' >&2
}

# rule "Title" - a lighter heading for each step of a run.
rule() {
  local title="-- $1 " pad
  pad=$((64 - ${#title}))
  [ "$pad" -ge 3 ] || pad=3
  printf '\n%s\n' "$_c_bold$title$(repeat '-' "$pad")$_c_off" >&2
}

have() { command -v "$1" >/dev/null 2>&1; }

is_wsl() { [ -n "${WSL_DISTRO_NAME:-}" ] || [ -e /proc/sys/fs/binfmt_misc/WSLInterop ]; }

is_tty() { [ -t 0 ] && [ -t 1 ]; }

today() { date +%Y-%m-%d; }

# Runs a command as root: directly when already root, otherwise through sudo.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

# ask VAR "Question" [default] - reads a line from the terminal into VAR.
# Returns 1 only at the end of input with nothing typed, so loops that ask again can stop.
ask() {
  local __var=$1 __q=$2 __def=${3:-} __ans __eof=0
  if [ -n "$__def" ]; then
    read -r -p "$__q [$__def]: " __ans || __eof=1
  else
    read -r -p "$__q: " __ans || __eof=1
  fi
  printf -v "$__var" '%s' "${__ans:-$__def}"
  [ "$__eof" -eq 0 ] || [ -n "$__ans" ]
}

# ask_required VAR "Question" [default] - asks again until the answer is not empty.
ask_required() {
  local __v=$1 __q=$2 __d=${3:-}
  while :; do
    ask "$__v" "$__q" "$__d" || die "no answer for: $__q"
    [ -z "${!__v}" ] || return 0
    warn "an answer is required"
  done
}

# ask_choice VAR "Question" default choice... - asks again until the answer is one of the choices.
ask_choice() {
  local __v=$1 __q=$2 __d=$3 __c
  shift 3
  while :; do
    ask "$__v" "$__q" "$__d" || die "no answer for: $__q"
    for __c in "$@"; do
      [ "${!__v}" = "$__c" ] && return 0
    done
    warn "answer one of: $*"
  done
}

# choose VAR "Question" default letters - a one-letter menu answer, such as "sed" for
# save, edit or discard; asked again until valid. The end of input picks the default.
choose() {
  local __v=$1 __q=$2 __d=$3 __l=$4 __a
  while :; do
    ask __a "$__q" "$__d" || __a=$__d
    __a=${__a:0:1}
    __a=${__a,,}
    if [ -n "$__a" ] && [[ $__l == *"$__a"* ]]; then
      printf -v "$__v" '%s' "$__a"
      return 0
    fi
    warn "answer one of: $(printf '%s' "$__l" | sed 's/./& /g')"
  done
}

# confirm "Question" [y|n] - returns 0 for yes.
confirm() {
  local q=$1 def=${2:-n} ans hint='[y/N]'
  [ "$def" = y ] && hint='[Y/n]'
  read -r -p "$q $hint " ans || true
  ans=${ans:-$def}
  case $ans in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# Prints the base apt packages for this system from install/apt-packages.txt.
base_packages() {
  local line pkg tag
  while IFS= read -r line; do
    line=${line%%#*}
    read -r pkg tag <<<"$line"
    [ -n "$pkg" ] || continue
    if [ "$tag" = "[wsl]" ] && ! is_wsl; then continue; fi
    printf '%s\n' "$pkg"
  done <"$DEV_HOME/install/apt-packages.txt"
}

# Loads a KEY=value file into the environment without enabling allexport for the caller.
load_env_file() {
  [ -r "$1" ] || return 0
  local had_a=0
  case $- in *a*) had_a=1 ;; esac
  set -a
  # shellcheck disable=SC1090
  . "$1"
  [ "$had_a" -eq 1 ] || set +a
}

# Quotes a value for a KEY=value file that is sourced by the shell; plain values stay bare.
shell_quote() {
  local v=$1
  if [ -z "$v" ] || [[ $v =~ ^[A-Za-z0-9_./:@,+=%-]+$ ]]; then
    printf '%s' "$v"
  else
    printf "'%s'" "${v//\'/\'\\\'\'}"
  fi
}

# Sets KEY=value in a KEY=value file, replacing an existing line or appending one.
set_env_value() {
  local file=$1 key=$2 tmp
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp=$(mktemp)
  SEV_LINE="$key=$(shell_quote "$3")" awk -v k="$key" '
    BEGIN { done = 0; line = ENVIRON["SEV_LINE"] }
    $0 ~ "^" k "=" { print line; done = 1; next }
    { print }
    END { if (!done) print line }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}
