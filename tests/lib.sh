# shellcheck shell=bash
# Test helpers: every test runs against a copy of the repository in a throwaway HOME, with a
# clean environment, so neither the machine running the tests nor the repository changes.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL  %s\n' "$1"
  [ -z "${2:-}" ] || printf '        %s\n' "$2"
}
assert_eq() { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3" "expected [$2] got [$1]"; fi; }
assert_contains() { case $1 in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in: $1" ;; esac; }
assert_not_contains() { case $1 in *"$2"*) fail "$3" "[$2] unexpectedly in: $1" ;; *) pass "$3" ;; esac; }
assert_true() {
  local name=$1
  shift
  if "$@"; then pass "$name"; else fail "$name" "command failed: $*"; fi
}

# Creates the sandbox: $HOME, $DEV (the dev home copy) and $FAKEBIN for stand-in tools.
new_sandbox() {
  SANDBOX=$(mktemp -d)
  HOME="$SANDBOX/home"
  DEV="$HOME/development"
  FAKEBIN="$SANDBOX/fakebin"
  mkdir -p "$DEV" "$FAKEBIN"
  # Ubuntu's /etc/bash.bashrc prints a sudo hint in interactive shells of sudo-group users whose
  # home lacks this marker, which would leak into the output of the interactive-shell tests.
  touch "$HOME/.sudo_as_admin_successful"
  (cd "$REPO" && git ls-files -co --exclude-standard -z | xargs -0 cp --parents -t "$DEV/")
  TPATH="$DEV/bin/wrappers:$DEV/bin:$FAKEBIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  export SANDBOX HOME DEV FAKEBIN TPATH
}

# Runs a command with a minimal environment inside the sandbox.
run() {
  env -i HOME="$HOME" PATH="$TPATH" TERM=dumb LANG=C.UTF-8 NO_COLOR=1 \
    GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 DEVBOOT_NO_REMINDER=1 USER=tester \
    "$@"
}

finish() {
  rm -rf "$SANDBOX"
  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
