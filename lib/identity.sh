# shellcheck shell=bash
# Git identities and forge accounts (docs/identities.md).
# Requires lib/common.sh. Every function is safe to call without an identities file.
#
# Storage: .local/git/identities.gitconfig, in git config syntax:
#   [defaults]           context = work
#   [account "<name>"]   forge, host, user, auth (https|ssh), tokenVar, sshKey
#   [context "<name>"]   name, email, signingKey, account (multi-valued, one per host)

ID_DIR="$DEV_HOME/.local/git"
ID_FILE="$ID_DIR/identities.gitconfig"
ID_ROUTING="$ID_DIR/routing.gitconfig"
ID_CONTEXTS_DIR="$ID_DIR/contexts"
ID_SOURCES="$DEV_HOME/sources"

# Lookups print nothing for a missing value and still succeed, so callers under `set -e` can
# use them in assignments.
id_get() { [ -f "$ID_FILE" ] && git config -f "$ID_FILE" --get "$1" 2>/dev/null; return 0; }
id_get_all() { [ -f "$ID_FILE" ] && git config -f "$ID_FILE" --get-all "$1" 2>/dev/null; return 0; }
id_set() { mkdir -p "$ID_DIR" && git config -f "$ID_FILE" "$1" "$2"; }
id_unset() { [ -f "$ID_FILE" ] && git config -f "$ID_FILE" --unset-all "$1" 2>/dev/null; return 0; }

id_valid_name() { [[ $1 =~ ^[a-z0-9][a-z0-9-]*$ ]]; }

# Lists names for a section ("account" or "context") by a key every entry has.
_id_names() {
  local section=$1 key=$2
  [ -f "$ID_FILE" ] || return 0
  git config -f "$ID_FILE" --name-only --get-regexp "^$section\\..*\\.$key\$" 2>/dev/null |
    sed -E "s/^$section\\.(.*)\\.$key\$/\\1/"
}
id_accounts() { _id_names account host; }
id_contexts() { _id_names context email; }

id_account_exists() { [ -n "$(id_get "account.$1.host")" ]; }
id_context_exists() { [ -n "$(id_get "context.$1.email")" ]; }

id_default_context() { id_get defaults.context; }

id_context_accounts() { id_get_all "context.$1.account"; }

_id_host_eq() {
  local a=${1,,} b=${2,,}
  [ "$a" = "$b" ] || [ "${a%%:*}" = "${b%%:*}" ]
}

# Prints the account a context uses for a host, if any.
id_context_account_for_host() {
  local ctx=$1 host=$2 acc
  while IFS= read -r acc; do
    [ -n "$acc" ] || continue
    if _id_host_eq "$(id_get "account.$acc.host")" "$host"; then
      printf '%s\n' "$acc"
      return 0
    fi
  done < <(id_context_accounts "$ctx")
  return 1
}

_id_realpath() { (cd "$1" 2>/dev/null && pwd -P); }

# Prints the context for a directory and why, as "<context> <source>".
# Sources: env (DEVBOOT_CONTEXT), pinned (gitid use), folder (sources/<context>/), default.
id_resolve_context_with_source() {
  local dir=${1:-$PWD} real sources rel ctx
  if [ -n "${DEVBOOT_CONTEXT:-}" ]; then
    printf '%s env\n' "$DEVBOOT_CONTEXT"
    return 0
  fi
  ctx=$(git -C "$dir" config --local --get devboot.pinned 2>/dev/null || true)
  if [ -n "$ctx" ]; then
    printf '%s pinned\n' "$ctx"
    return 0
  fi
  real=$(_id_realpath "$dir")
  sources=$(_id_realpath "$ID_SOURCES")
  if [ -n "$real" ] && [ -n "$sources" ]; then
    case $real/ in
      "$sources"/?*/*)
        rel=${real#"$sources"/}
        ctx=${rel%%/*}
        if id_context_exists "$ctx"; then
          printf '%s folder\n' "$ctx"
          return 0
        fi
        ;;
    esac
  fi
  ctx=$(id_default_context)
  if [ -n "$ctx" ]; then
    printf '%s default\n' "$ctx"
    return 0
  fi
  return 1
}

id_resolve_context() {
  local r
  r=$(id_resolve_context_with_source "$@") || return 1
  printf '%s\n' "${r%% *}"
}

# Prints the account for a host in the resolved context.
# DEVBOOT_ACCOUNT (set by `gitid as`) wins when its host matches.
id_resolve_account() {
  local ctx=$1 host=$2
  if [ -n "${DEVBOOT_ACCOUNT:-}" ] && _id_host_eq "$(id_get "account.$DEVBOOT_ACCOUNT.host")" "$host"; then
    printf '%s\n' "$DEVBOOT_ACCOUNT"
    return 0
  fi
  [ -n "$ctx" ] || return 1
  id_context_account_for_host "$ctx" "$host"
}

# Prints an account's token from the environment, falling back to reading .secrets
# in a subshell so non-interactive callers work too.
id_account_token() {
  local acc=$1 var value
  var=$(id_get "account.$acc.tokenVar")
  [ -n "$var" ] || return 1
  [[ $var =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
  value=${!var:-}
  if [ -z "$value" ] && [ -r "$DEV_HOME/.secrets" ]; then
    value=$(
      set -a
      # shellcheck disable=SC1091
      . "$DEV_HOME/.secrets" >/dev/null 2>&1
      printf '%s' "${!var:-}"
    )
  fi
  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

id_expand_path() {
  local p=$1
  # A literal "~/" stored in the identities file is expanded here on purpose.
  # shellcheck disable=SC2088
  case $p in "~/"*) p="$HOME/${p#"~/"}" ;; esac
  printf '%s' "$p"
}

# Regenerates routing.gitconfig and one gitconfig per context.
id_sync() {
  local ctx def file tmp
  mkdir -p "$ID_CONTEXTS_DIR"
  find "$ID_CONTEXTS_DIR" -maxdepth 1 -name '*.gitconfig' -delete
  while IFS= read -r ctx; do
    [ -n "$ctx" ] || continue
    file="$ID_CONTEXTS_DIR/$ctx.gitconfig"
    : >"$file"
    git config -f "$file" user.name "$(id_get "context.$ctx.name")"
    git config -f "$file" user.email "$(id_get "context.$ctx.email")"
    local key
    key=$(id_get "context.$ctx.signingKey")
    if [ -n "$key" ]; then
      git config -f "$file" user.signingKey "$key"
      git config -f "$file" gpg.format ssh
      git config -f "$file" commit.gpgSign true
      git config -f "$file" tag.gpgSign true
    fi
    git config -f "$file" devboot.context "$ctx"
  done < <(id_contexts)

  tmp=$(mktemp)
  {
    echo "# Generated by gitid from identities.gitconfig. Edits here are overwritten."
    def=$(id_default_context)
    if [ -n "$def" ] && [ -f "$ID_CONTEXTS_DIR/$def.gitconfig" ]; then
      printf '[include]\n\tpath = %s\n' "$ID_CONTEXTS_DIR/$def.gitconfig"
    fi
    while IFS= read -r ctx; do
      [ -n "$ctx" ] || continue
      printf '[includeIf "gitdir:%s/%s/"]\n\tpath = %s\n' "$ID_SOURCES" "$ctx" "$ID_CONTEXTS_DIR/$ctx.gitconfig"
    done < <(id_contexts)
  } >"$tmp"
  mkdir -p "$ID_DIR"
  cat "$tmp" >"$ID_ROUTING"
  rm -f "$tmp"
}

# Finds the real executable for a command, skipping the wrapper directory.
devboot_find_real() {
  local cmd=$1 dir wrappers
  wrappers="$DEV_HOME/bin/wrappers"
  local IFS=:
  for dir in $PATH; do
    [ -n "$dir" ] || continue
    [ "$dir" = "$wrappers" ] && continue
    if [ -x "$dir/$cmd" ] && [ ! -d "$dir/$cmd" ]; then
      printf '%s\n' "$dir/$cmd"
      return 0
    fi
  done
  return 1
}
