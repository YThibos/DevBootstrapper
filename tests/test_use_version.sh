#!/usr/bin/env bash
# use-version, mvnuse and jdkuse: machine-local defaults that never touch the shared manifest.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox

uv() { run "$DEV/bin/use-version" "$@" 2>&1; }
local_cfg="$DEV/.local/mise/config.toml"

out=$(uv maven)
assert_contains "$out" "* 3.10" "Maven 3.10 is the shared default"
assert_not_contains "$(grep '^maven' "$DEV/config/mise/config.toml")" '"4"' "no Maven 4 line until 4.0.0 is released"

out=$(run "$DEV/bin/mvnuse" 4.0.0-rc-7 2>&1)
assert_contains "$out" "not in the shared manifest" "a Maven 4 release candidate is allowed on one machine"
assert_eq "$(grep '^maven' "$local_cfg")" 'maven = ["4.0.0-rc-7", "3.10"]' "mvnuse writes a machine-local default that keeps 3.10 installed"
assert_true "the shared manifest is unchanged" cmp -s "$DEV/config/mise/config.toml" "$REPO/config/mise/config.toml"
assert_contains "$(uv maven)" "* 4.0.0-rc-7" "use-version shows it as this machine's default"
assert_contains "$(uv maven)" "shared default: 3.10" "and names the shared default"

run "$DEV/bin/jdkuse" 21 >/dev/null 2>&1
assert_eq "$(grep '^java' "$local_cfg")" \
  'java = ["temurin-21", "temurin-25", "temurin-17", "temurin-11", "temurin-8"]' "jdkuse 21 picks temurin-21 and keeps every JDK"
assert_eq "$(grep -c '^maven' "$local_cfg")" 1 "switching another tool keeps the Maven override"

out=$(run "$DEV/bin/jdkuse" 22 2>&1)
assert_contains "$out" "not in the shared manifest" "an unlisted version is allowed with a warning"
assert_contains "$(grep '^java' "$local_cfg")" '["temurin-22", "temurin-25"' "the unlisted version gets the vendor prefix"

run "$DEV/bin/mvnuse" --reset >/dev/null 2>&1
assert_eq "$(grep -c '^maven' "$local_cfg")" 0 "mvnuse --reset removes the override"
assert_contains "$(uv maven)" "* 3.10" "after reset the shared default applies"
assert_contains "$(head -2 "$local_cfg")" "[tools]" "the machine file keeps its [tools] table"

assert_eq "$(run "$DEV/bin/use-version" --list-values java | paste -sd ' ' -)" "25 21 17 11 8" "completion values are short versions"
all=$(uv)
assert_contains "$all" "java" "use-version lists java"
assert_contains "$all" "maven" "use-version lists maven"
assert_contains "$(uv nosuchtool 1 || true)" "not in the tool manifest" "unknown tools are refused"

finish
