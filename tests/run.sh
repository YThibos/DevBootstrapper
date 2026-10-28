#!/usr/bin/env bash
# Runs every test file and shellcheck. Usage: tests/run.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
status=0
if command -v shellcheck >/dev/null 2>&1; then
  echo "== shellcheck"
  mapfile -t files < <(grep -rlE '^#!/usr/bin/env bash|^# shellcheck shell=bash' bash bin install lib tests)
  if shellcheck -x -P SCRIPTDIR -s bash "${files[@]}"; then echo "  clean (${#files[@]} files)"; else status=1; fi
else
  echo "== shellcheck not installed; skipped"
fi
for t in tests/test_*.sh; do
  echo "== $t"
  bash "$t" || status=1
done
exit "$status"
