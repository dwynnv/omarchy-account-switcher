#!/usr/bin/env bash
# Clock in / clock out. Commands are recorded (ACCOUNT_SWITCHER_RUN_LOG), never run.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
TMP=${TEST_TMPDIR:?run through tests/run.sh}/clock
export ACCOUNT_SWITCHER_WALK_ROOT=$$
DM=$PLUGIN/bin/account-switcher
SWITCH="hyprctl dispatch function() if account_switcher then account_switcher.switch"
EXPECT="hyprctl dispatch function() if account_switcher then account_switcher.desk.expect"
LOG=$TMP/run.log

# Nothing running.
fresh() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.local/state/account-switcher" "$TMP/home/.config/omarchy" "$TMP/fakes"
  export HOME=$TMP/home ACCOUNT_SWITCHER_RUN_LOG=$LOG ACCOUNT_SWITCHER_FAKES=$TMP/fakes
  unset XDG_STATE_HOME XDG_DATA_HOME XDG_CONFIG_HOME ACCOUNT_SWITCHER_MODE ACCOUNT_SWITCHER_RUN_LOG_ENV
  : >"$LOG"
  echo '[]' >"$TMP/fakes/hyprctl-clients.out"
  echo 1 >"$TMP/fakes/pgrep--x.status"
  mkdir -p "$HOME/.config/account-switcher" && cp "$PLUGIN/tests/fixtures/config.test.json" "$HOME/.config/account-switcher/config.json"
  ACCOUNT_SWITCHER_GH=/opt/gh/bin/gh "$PLUGIN/bin/account-switcher" setup >/dev/null && : >"$LOG"
}
desk() { echo "$1" >"$HOME/.local/state/account-switcher/mode"; }
state() { cat "$HOME/.local/state/account-switcher/clock"; }
line_of() { grep -nxF -- "$1" "$LOG" | head -n1 | cut -d: -f1; }
# LINE is in the log, after the line BEFORE.
t_after() {
  local a b
  a=$(line_of "$1")
  b=$(line_of "$2")
  [[ -n $a && -n $b ]] && ((b > a)) && return 0
  echo "expected \"$2\" after \"$1\" in:"
  cat "$LOG"
  exit 1
}

t_in_launches_missing() {
  fresh
  desk personal
  "$DM" clock in
  t_eq "$(head -n1 "$LOG")" "$SWITCH('work') end end"
  t_after "$EXPECT('slack') end end" "setsid -f $DM app slack"
  t_after "$EXPECT('google-chrome') end end" "setsid -f $DM browser --mode=work"
  t_after "$EXPECT('com.microsoft.VSCode') end end" "setsid -f $PLUGIN/bin/code"
  t_ok grep -qxF "omarchy-shell -q notifications dismiss Time to clock in" "$LOG"
  t_none notification-send "$LOG"
  [[ $(state) =~ ^in\ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8} ]] || { echo "state: $(state)"; exit 1; }
}
t_test "clock in switches to Work and starts each missing app where it was last" t_in_launches_missing

t_in_work_env() {
  fresh
  desk work
  export ACCOUNT_SWITCHER_RUN_LOG_ENV=1
  "$DM" clock in
  t_eq "$(grep -B1 -xF "setsid -f $PLUGIN/bin/code" "$LOG" | head -n1 | cut -d' ' -f1-3)" \
    "env: ACCOUNT_SWITCHER_MODE=work GIT_CONFIG_GLOBAL=$HOME/.config/git/account-switcher-work"
}
t_test "clock in starts VS Code with Work's environment" t_in_work_env

t_in_skips_running() {
  fresh
  desk work
  echo 0 >"$TMP/fakes/pgrep--x.status"
  echo '[{"class":"google-chrome","address":"0xa","workspace":{"id":12},"focusHistoryID":1}]' >"$TMP/fakes/hyprctl-clients.out"
  mkdir -p "$HOME/.config/Code"
  echo $$ >"$HOME/.config/Code/code.lock"
  "$DM" clock in
  t_none 'setsid' "$LOG"
  t_none 'desk.expect' "$LOG"
  t_none 'account_switcher.switch' "$LOG"
  # A lock left behind by a VS Code that's gone doesn't count.
  : >"$LOG"
  echo 4194999 >"$HOME/.config/Code/code.lock"
  "$DM" clock in
  t_ok grep -qxF "setsid -f $PLUGIN/bin/code" "$LOG"
  t_none "app slack" "$LOG"
}
t_test "clock in never starts a second Slack, Chrome or VS Code" t_in_skips_running

t_in_setting() {
  fresh
  desk work
  echo '{"bar":{"layout":{"left":[{"id":"account-switcher","clockInApps":"slack, code"}],"center":[],"right":[]}}}' \
    >"$HOME/.config/omarchy/shell.json"
  "$DM" clock in
  t_ok grep -qxF "setsid -f $DM app slack" "$LOG"
  t_ok grep -qxF "setsid -f $PLUGIN/bin/code" "$LOG"
  t_none browser "$LOG"
  : >"$LOG"
  echo '{"bar":{"layout":{"left":[],"center":[],"right":[{"id":"account-switcher","clockInApps":["chrome","zoom"]}]}}}' \
    >"$HOME/.config/omarchy/shell.json"
  "$DM" clock in
  t_eq "$(grep -c 'setsid' "$LOG")" 1
  t_ok grep -qxF "setsid -f $DM browser --mode=work" "$LOG"
}
t_test "the clockInApps setting picks the apps" t_in_setting

t_out() {
  fresh
  desk work
  "$DM" clock out
  t_eq "$(head -n1 "$LOG")" "$SWITCH('personal') end end"
  t_ok grep -qxF "omarchy-shell -q notifications dismiss Time to clock out" "$LOG"
  t_none setsid "$LOG"
  [[ $(state) =~ ^out\ [0-9]{4}-[0-9]{2}-[0-9]{2}T ]] || { echo "state: $(state)"; exit 1; }
}
t_test "clock out switches to Personal and records it" t_out

hook() { # NAME: one of the user's clock hooks, executable
  mkdir -p "$HOME/.config/account-switcher/hooks"
  printf '#!/bin/sh\nexit 0\n' >"$HOME/.config/account-switcher/hooks/$1"
  chmod +x "$HOME/.config/account-switcher/hooks/$1"
}

t_hooks() {
  fresh
  hook clock-in
  hook clock-out
  desk personal
  "$DM" clock in
  t_after "$SWITCH('work') end end" "setsid -f $HOME/.config/account-switcher/hooks/clock-in"
  : >"$LOG"
  desk work
  "$DM" clock out
  t_after "$SWITCH('personal') end end" "setsid -f $HOME/.config/account-switcher/hooks/clock-out"
}
t_test "clock in and clock out run the user's hooks once they've switched" t_hooks

t_no_hooks() {
  fresh
  desk work
  "$DM" clock out
  t_none setsid "$LOG"
  # A hook that can't be run is left alone.
  mkdir -p "$HOME/.config/account-switcher/hooks" && printf 'echo hi\n' >"$HOME/.config/account-switcher/hooks/clock-out"
  : >"$LOG"
  "$DM" clock out
  t_none setsid "$LOG"
}
t_test "without a hook (or with one that isn't executable) clock out runs nothing else" t_no_hooks

t_status() {
  fresh
  t_eq "$("$DM" clock status)" "none"
  echo "in 2026-10-26T09:02:11+00:00" >"$HOME/.local/state/account-switcher/clock"
  t_eq "$("$DM" clock status)" "in 2026-10-26T09:02:11+00:00"
  "$DM" clock sideways 2>/dev/null
  t_eq $? 2
}
t_test "clock status prints the last clock in or out" t_status

t_done
