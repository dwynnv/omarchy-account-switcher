#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
TEST_TMPDIR="$(mktemp -d)"; export TEST_TMPDIR
# Per-mode tmux/herdr folders go under the runtime folder: a scratch one, never the session's.
XDG_RUNTIME_DIR="$TEST_TMPDIR/run"; export XDG_RUNTIME_DIR
mkdir -p -m 700 "$XDG_RUNTIME_DIR"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# Tests must not inherit the mode of the terminal running them.
unset ACCOUNT_SWITCHER_MODE ACCOUNT_SWITCHER_WORK ACCOUNT_SWITCHER_PERSONAL GIT_CONFIG_GLOBAL GH_CONFIG_DIR AWS_CONFIG_FILE \
  AWS_SHARED_CREDENTIALS_FILE HISTFILE _ZO_DATA_DIR BROWSER HYPRLAND_INSTANCE_SIGNATURE XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME
status=0
for f in lua/*_test.lua; do echo "== $f"; lua "$f" || status=1; done
for f in sh/*_test.sh; do echo "== $f"; bash "$f" || status=1; done
for f in *.test.js; do [ -e "$f" ] || continue; echo "== $f"; node "$f" || status=1; done
exit $status
