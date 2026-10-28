# shellcheck shell=bash
# Managed symlinks from tool default locations into the dev home.
# Requires lib/common.sh.

# The backup directory for files replaced by a link, one per day.
backup_dir() { printf '%s/tmp/backup-%s' "$DEV_HOME" "$(today)"; }

_backup_path() {
  local path=$1 rel dest
  rel=${path#"$HOME"/}
  dest="$(backup_dir)/$rel"
  mkdir -p "$(dirname "$dest")"
  mv "$path" "$dest"
  warn "moved existing $path to $dest"
}

# ensure_link SOURCE LINK [MODE]
#   MODE "replace" (default): an existing real file at LINK is backed up, then linked.
#   MODE "adopt": an existing real file at LINK is copied over SOURCE first, so a change
#   made by the tool itself lands in the dev home (as a git diff for tracked files).
# Prints "changed" or "unchanged".
ensure_link() {
  local src=$1 link=$2 mode=${3:-replace}
  mkdir -p "$(dirname "$link")"
  if [ -L "$link" ]; then
    if [ "$(readlink "$link")" = "$src" ]; then
      echo unchanged
      return 0
    fi
    rm -f "$link"
  elif [ -e "$link" ]; then
    if [ "$mode" = adopt ] && [ -f "$link" ]; then
      if ! cmp -s "$link" "$src"; then
        mkdir -p "$(dirname "$src")"
        cp "$link" "$src"
        warn "adopted $link into $src - review it before committing"
      fi
      rm -f "$link"
    else
      _backup_path "$link"
    fi
  fi
  ln -s "$src" "$link"
  echo changed
}

# remove_link LINK - removes LINK only when it is a symlink into the dev home.
remove_link() {
  local link=$1 target
  [ -L "$link" ] || return 0
  target=$(readlink "$link")
  case $target in
    "$DEV_HOME"/*) rm -f "$link" && info "removed $link" ;;
  esac
}
