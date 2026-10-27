#!/usr/bin/env bash
# Home-mode apps and capture folders per mode, and the app entries desktop-apply writes.
# Commands are recorded (ACCOUNT_SWITCHER_RUN_LOG), never run.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
TMP=${TEST_TMPDIR:?run through tests/run.sh}/apps
export ACCOUNT_SWITCHER_WALK_ROOT=$$
DM=$PLUGIN/bin/account-switcher
SWITCH="hyprctl dispatch function() if account_switcher then account_switcher.switch"

fresh() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.local/state/account-switcher" "$TMP/fakes" "$TMP/sys"
  export HOME=$TMP/home ACCOUNT_SWITCHER_RUN_LOG=$TMP/run.log ACCOUNT_SWITCHER_FAKES=$TMP/fakes
  unset XDG_STATE_HOME XDG_DATA_HOME XDG_CONFIG_HOME ACCOUNT_SWITCHER_MODE OMARCHY_SCREENSHOT_DIR OMARCHY_SCREENRECORD_DIR
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  echo '[]' >"$TMP/fakes/hyprctl-clients.out"
  mkdir -p "$HOME/.config/account-switcher" && cp "$PLUGIN/tests/fixtures/config.full.json" "$HOME/.config/account-switcher/config.json"
  ACCOUNT_SWITCHER_GH=/opt/gh/bin/gh "$PLUGIN/bin/account-switcher" setup >/dev/null && : >"$ACCOUNT_SWITCHER_RUN_LOG"
}
config() { # JQ_FILTER: change the config and set it up again
  local c=$HOME/.config/account-switcher/config.json
  jq "$1" "$c" >"$c.new" && mv "$c.new" "$c" && "$DM" setup >/dev/null && : >"$ACCOUNT_SWITCHER_RUN_LOG"
}
desk() { echo "$1" >"$HOME/.local/state/account-switcher/mode"; }
last_line() { tail -n1 "$ACCOUNT_SWITCHER_RUN_LOG"; }

t_home_apps() {
  fresh
  desk personal
  "$DM" app slack
  t_eq "$(head -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "$SWITCH('work') end end"
  t_eq "$(last_line)" "setsid uwsm-app -- /usr/bin/slack"
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  desk work
  "$DM" app steam steam://open/games
  t_eq "$(head -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "$SWITCH('personal') end end"
  t_eq "$(last_line)" "setsid uwsm-app -- /usr/bin/steam steam://open/games"
  "$DM" app clickup
  t_eq "$(last_line)" "setsid uwsm-app -- /usr/bin/clickup"
}
t_test "a home-mode app takes the desk to its mode first" t_home_apps

t_filezilla() {
  fresh
  desk work
  echo '[{"class":"FileZilla","address":"0xf","workspace":{"id":4},"focusHistoryID":2}]' >"$TMP/fakes/hyprctl-clients.out"
  "$DM" app filezilla
  t_eq "$(last_line)" 'hyprctl dispatch hl.dsp.focus({ window = "address:0xf" })'
  t_none uwsm-app "$ACCOUNT_SWITCHER_RUN_LOG"
  echo '[]' >"$TMP/fakes/hyprctl-clients.out"
  "$DM" app filezilla
  t_eq "$(last_line)" "setsid uwsm-app -- /usr/bin/filezilla"
}
t_test "FileZilla focuses its window instead of starting a second copy" t_filezilla

t_capture() {
  fresh
  desk work
  "$DM" capture screenshot
  t_eq "$(last_line)" "env OMARCHY_SCREENSHOT_DIR=$HOME/Work/Pictures omarchy-capture-screenshot"
  t_ok test -d "$HOME/Work/Pictures"
  "$DM" capture record --with-desktop-audio
  t_eq "$(last_line)" "env OMARCHY_SCREENRECORD_DIR=$HOME/Work/Videos omarchy-capture-screenrecording --with-desktop-audio"
  t_ok test -d "$HOME/Work/Videos"
  "$DM" capture webcam
  t_eq "$(last_line)" "env OMARCHY_SCREENRECORD_DIR=$HOME/Work/Videos omarchy-capture-screenrecording-with-webcam"
  desk personal
  "$DM" capture screenshot --editor=x
  t_eq "$(last_line)" "env -u OMARCHY_SCREENSHOT_DIR omarchy-capture-screenshot --editor=x"
  "$DM" capture stop
  t_eq "$(last_line)" "env -u OMARCHY_SCREENRECORD_DIR omarchy-capture-screenrecording --stop-recording"
}
t_test "captures land in Work's folders in Work and the usual ones in Personal" t_capture

t_capture_toggle() {
  fresh
  desk work
  echo 1 >"$TMP/fakes/env.status"
  "$DM" capture toggle
  t_eq "$(head -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "env OMARCHY_SCREENRECORD_DIR=$HOME/Work/Videos omarchy-capture-screenrecording --stop-recording"
  t_eq "$(last_line)" "omarchy-menu toggle trigger.capture.screenrecord"
}
t_test "ALT+PRINT stops a recording, or opens the recording menu" t_capture_toggle

t_desktop_apps() {
  fresh
  local f
  for f in slack filezilla steam ClickUp; do cp "$PLUGIN/tests/fixtures/applications/$f.desktop" "$TMP/sys/"; done
  ACCOUNT_SWITCHER_SYSTEM_APPS=$TMP/sys ACCOUNT_SWITCHER_OMARCHY_APPS=$TMP/none XDG_DATA_HOME=$TMP/data "$DM" desktop-apply
  local apps=$TMP/data/applications bin=$HOME/.local/bin
  t_ok grep -qx "Exec=$bin/account-switcher app slack %U" "$apps/slack.desktop"
  t_ok grep -qx "Exec=$bin/account-switcher app filezilla" "$apps/filezilla.desktop"
  t_ok grep -qx "Exec=$bin/account-switcher app clickup %U" "$apps/ClickUp.desktop"
  t_ok grep -qx "Exec=$bin/account-switcher app steam steam://store" "$apps/steam.desktop"
  t_eq "$(grep -c "^Exec=$bin/account-switcher app steam" "$apps/steam.desktop")" "$(grep -c '^Exec=' "$TMP/sys/steam.desktop")"
  t_ok grep -qx 'MimeType=x-scheme-handler/slack;' "$apps/slack.desktop"
  t_ok grep -qx 'StartupWMClass=ClickUp' "$apps/ClickUp.desktop"
  for f in slack filezilla steam ClickUp; do t_ok grep -qx 'X-AccountSwitcher=managed' "$apps/$f.desktop"; done
}
t_test "desktop-apply sends the home-mode apps through account-switcher" t_desktop_apps

t_custom_app() {
  fresh
  config '.customApps.foo = {"label": "Foo", "bin": "/usr/bin/foo", "class": "foo", "desktop": "foo.desktop", "execToken": "/usr/bin/foo", "notify": ["Foo"]} | .work.apps += ["foo"]'
  printf '[Desktop Entry]\nName=Foo\nType=Application\nExec=/usr/bin/foo %%U\n' >"$TMP/sys/foo.desktop"
  desk personal
  "$DM" app foo --flag
  t_eq "$(head -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "$SWITCH('work') end end"
  t_eq "$(last_line)" "setsid uwsm-app -- /usr/bin/foo --flag"
  ACCOUNT_SWITCHER_SYSTEM_APPS=$TMP/sys ACCOUNT_SWITCHER_OMARCHY_APPS=$TMP/none XDG_DATA_HOME=$TMP/data "$DM" desktop-apply
  t_ok grep -qx "Exec=$HOME/.local/bin/account-switcher app foo %U" "$TMP/data/applications/foo.desktop"
  "$DM" app nope 2>/dev/null && t_eq ok usage "an app the config doesn't have"
  return 0
}
t_test "an app from the config's own list works like a built-in one" t_custom_app

t_entries_unchanged() {
  fresh
  local fx=$PLUGIN/tests/fixtures f name
  ACCOUNT_SWITCHER_SYSTEM_APPS=$fx/applications ACCOUNT_SWITCHER_OMARCHY_APPS=$fx/omarchy XDG_DATA_HOME=$TMP/data "$DM" desktop-apply
  t_eq "$(cd "$TMP/data/applications" && ls *.desktop | sort)" "$(cd "$fx/entries" && ls *.desktop | sort)"
  for f in "$fx"/entries/*.desktop; do
    name=${f##*/}
    t_eq "$(cat "$TMP/data/applications/$name")" "$(sed "s|@HOME@|$HOME|g" "$f")" "$name"
  done
  t_eq "$(cat "$HOME/.config/hyprland-mimeapps.list")" "$(sed "s|@HOME@|$HOME|g" "$fx/entries/hyprland-mimeapps.list")"
}
t_test "the launcher entries for the full test config are exactly the fixture's" t_entries_unchanged

t_prune() {
  fresh
  local fx=$PLUGIN/tests/fixtures apps=$TMP/data/applications
  local env=(ACCOUNT_SWITCHER_SYSTEM_APPS=$fx/applications ACCOUNT_SWITCHER_OMARCHY_APPS=$fx/omarchy XDG_DATA_HOME=$TMP/data)
  env "${env[@]}" "$DM" desktop-apply
  t_ok grep -q "account-switcher app steam" "$apps/steam.desktop"
  config '.personal.apps -= ["steam"]'
  # The check notices the entry the config no longer has; apply takes it away.
  env "${env[@]}" "$DM" desktop-check >"$TMP/check" && t_eq ok reported "a stale entry passed the check"
  t_ok grep -q 'steam.desktop' "$TMP/check"
  env "${env[@]}" "$DM" desktop-apply
  t_ok test ! -e "$apps/steam.desktop"
  t_ok test -e "$apps/slack.desktop"
  env "${env[@]}" "$DM" desktop-check >/dev/null
  t_eq $? 0 "clean afterwards"
}
t_test "launcher entries follow the config: one it no longer has goes away" t_prune

t_setup_applies() {
  fresh
  local fx=$PLUGIN/tests/fixtures apps=$TMP/data/applications
  mkdir -p "$HOME/.local/bin" && ln -s "$DM" "$HOME/.local/bin/account-switcher"
  ACCOUNT_SWITCHER_SYSTEM_APPS=$fx/applications ACCOUNT_SWITCHER_OMARCHY_APPS=$fx/omarchy XDG_DATA_HOME=$TMP/data "$DM" setup >/dev/null
  t_ok grep -q "account-switcher app slack" "$apps/slack.desktop"
}
t_test "once installed, setup re-applies the launcher entries" t_setup_applies

t_done
