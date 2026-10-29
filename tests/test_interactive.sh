#!/usr/bin/env bash
# The interactive first run and gitid setup, typed into a real terminal (script provides one):
# wrong answers are asked again, answers are reviewed before they are saved, and the review
# menu changes what was entered.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox

if ! command -v script >/dev/null 2>&1; then
  echo "  skipped: no script command to provide a terminal"
  finish
  exit
fi

# typed "command" answer... - runs a command on a terminal and types one answer per line.
typed() {
  local cmd=$1
  shift
  printf '%s\n' "$@" | run script -qec "$cmd" /dev/null 2>&1 | tr -d '\r'
}
ids() { run git config -f "$DEV/.local/git/identities.gitconfig" "$@"; }

out=$(typed "$DEV/bin/gitid setup" \
  "Home Me" "home@example.com" s \
  "" "nope" "work@example.com" e "Work Me" "" s \
  "" "GitHub" "github-personal" "gh" "github" "" "me" "" d \
  y "github-personal" "" "" "me" "" s "" \
  n \
  "" \
  e "" "" "" "me2" "" s \
  l "" "home work" \
  x d)

assert_contains "$out" "Git identities" "gitid setup opens with a banner"
assert_contains "$out" "does not look like an email address" "a wrong email is asked again"
assert_contains "$out" "use lowercase letters, digits and dashes" "a wrong account name is asked again"
assert_contains "$out" "answer one of: github gitlab other" "a wrong forge is asked again"
assert_contains "$out" "discarded account github-personal" "an account can be discarded before it is saved"
assert_contains "$out" "answer one of: a e r l c m d" "a wrong menu choice is asked again"
assert_eq "$(ids --get context.work.name)" "Work Me" "edit before saving changes the commit name"
assert_eq "$(ids --get context.work.email)" "work@example.com" "and keeps the answers not changed"
assert_eq "$(ids --get account.github-personal.user)" "me2" "the review menu edits a saved account"
assert_eq "$(ids --get-all context.home.account)" "github-personal" "the account is linked to home"
assert_eq "$(ids --get-all context.work.account)" "github-personal" "the review menu links it to work too"
assert_eq "$(ids --get defaults.context)" "home" "the machine default is set"
assert_contains "$(cat "$DEV/.secrets")" "GITHUB_PERSONAL_TOKEN=" "the saved account gets its token line in .secrets"

out=$(typed "$DEV/bin/gitid setup" "" r "" y d)
assert_contains "$out" "context home exists" "gitid setup runs again without errors"
assert_eq "$(ids --get account.github-personal.host)" "" "the review menu removes an account"
assert_eq "$(ids --get-all context.work.account)" "" "and unlinks it everywhere"

# devup --first-run: profile and network are reviewed before .local/profile.env is written.
rm -rf "$DEV/.local/git"
out=$(typed "bash $DEV/install/devup.sh --first-run --only render" \
  office work "http://proxy.example:3128" "" /nonexistent.pem - n \
  "" "" "" "" y \
  "Home Me" "home@example.com" s "Work Me" "work@example.com" s n "" d)
profile=$(cat "$DEV/.local/profile.env")
assert_contains "$out" "1/5  Machine profile" "the first run is split into numbered sections"
assert_contains "$out" "4/5  Git identities" "gitid setup continues the numbering"
assert_contains "$out" "5/5  Install" "the install has its own section"
assert_contains "$out" "answer one of: home work" "a wrong profile is asked again"
assert_contains "$out" "cannot read /nonexistent.pem" "an unreadable certificate is asked again"
assert_contains "$out" "again, with your answers as the defaults" "answering no to the summary goes through the questions again"
assert_contains "$profile" "DEV_PROFILE=work" "the profile is saved"
assert_contains "$profile" "DEV_PROXY_URL=http://proxy.example:3128" "the proxy is kept from the first pass"
assert_contains "$profile" "DEV_CA_CERT=" "no certificate is configured"
assert_eq "$(ids --get defaults.context)" "work" "the work profile suggests the work context as the default"
assert_contains "$out" "ok      render" "the install steps run after the questions"

finish
