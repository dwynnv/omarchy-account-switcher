#!/usr/bin/env bash
# The share-picker filter: only the current mode's windows reach the picker.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
TMP=${TEST_TMPDIR:?run through tests/run.sh}/share
WRAP=$PLUGIN/bin/account-switcher-share-picker

fresh() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.local/state/account-switcher" "$TMP/fakes"
  export HOME=$TMP/home ACCOUNT_SWITCHER_RUN_LOG=$TMP/run.log ACCOUNT_SWITCHER_FAKES=$TMP/fakes ACCOUNT_SWITCHER_SHARE_PICKER=/opt/picker
  unset XDG_STATE_HOME ACCOUNT_SWITCHER_MODE
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  cat >"$TMP/fakes/hyprctl-clients.out" <<'JSON'
[{"address":"0x10","workspace":{"id":2,"name":"2"},"tags":[]},
 {"address":"0x20","workspace":{"id":13,"name":"13"},"tags":[]},
 {"address":"0x30","workspace":{"id":-98,"name":"special:scratchpad"},"tags":["dwm-from-work"]},
 {"address":"0x40","workspace":{"id":-97,"name":"special:minimized"},"tags":["dwm-from-personal"]},
 {"address":"0x5a5a00c0ffee","workspace":{"id":3,"name":"3"},"tags":[]}]
JSON
}
desk() { echo "$1" >"$HOME/.local/state/account-switcher/mode"; }
rec() { printf '%s[HC>]%s[HT>]%s[HE>]%s[HA>]' "$1" "$2" "$3" "$4"; }
LIST=$(rec 1 code "Work, thing" 16)$(rec 2 chromium "Personal" 32)$(rec 3 slack "Slack" 48)$(rec 4 steam "Steam" 64)$(rec 5 x "Unknown" 80)$(rec 6 y "No address" 0)$(rec 7 term "Big address" 99342606204910)

t_work() {
  fresh
  desk work
  XDPH_WINDOW_SHARING_LIST=$LIST "$WRAP" --allow-token
  t_eq "$(tail -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "env XDPH_WINDOW_SHARING_LIST=$(rec 1 code "Work, thing" 16)$(rec 3 slack "Slack" 48)$(rec 7 term "Big address" 99342606204910) /opt/picker --allow-token"
}
t_test "in Work the picker lists only Work's windows" t_work

t_personal() {
  fresh
  desk personal
  XDPH_WINDOW_SHARING_LIST=$LIST "$WRAP"
  t_eq "$(tail -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "env XDPH_WINDOW_SHARING_LIST=$(rec 2 chromium "Personal" 32)$(rec 4 steam "Steam" 64) /opt/picker"
}
t_test "in Personal the picker lists only Personal's windows" t_personal

t_empty() {
  fresh
  desk work
  XDPH_WINDOW_SHARING_LIST= "$WRAP" -a
  t_eq "$(tail -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "env XDPH_WINDOW_SHARING_LIST= /opt/picker -a"
}
t_test "an empty list stays empty and the arguments pass through" t_empty

t_recorded_picker() {
  fresh
  unset ACCOUNT_SWITCHER_SHARE_PICKER
  desk personal
  echo /usr/local/bin/my-picker >"$HOME/.local/state/account-switcher/picker"
  XDPH_WINDOW_SHARING_LIST= "$WRAP"
  t_eq "$(tail -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "env XDPH_WINDOW_SHARING_LIST= /usr/local/bin/my-picker"
  : >"$HOME/.local/state/account-switcher/picker"
  XDPH_WINDOW_SHARING_LIST= "$WRAP"
  t_eq "$(tail -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "env XDPH_WINDOW_SHARING_LIST= hyprland-share-picker"
  rm "$HOME/.local/state/account-switcher/picker"
  XDPH_WINDOW_SHARING_LIST= "$WRAP"
  t_eq "$(tail -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "env XDPH_WINDOW_SHARING_LIST= hyprland-share-picker"
}
t_test "the filtered list goes to the picker install found, else xdph's own" t_recorded_picker

t_done
