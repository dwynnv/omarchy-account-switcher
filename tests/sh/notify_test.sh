#!/usr/bin/env bash
# The account-switcher.notifications clone: built from a copy of Omarchy's
# notification plugin. Copies, patches and lints for real; enable/notify calls are recorded.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
TMP=${TEST_TMPDIR:?run through tests/run.sh}/notify
export ACCOUNT_SWITCHER_WALK_ROOT=$$
DM=$PLUGIN/bin/account-switcher
STOCK=${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/notifications
LOG=$TMP/run.log

fresh() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.local/state/account-switcher" "$TMP/home/.config/omarchy/plugins" "$TMP/src" "$TMP/fakes"
  cp -aL "$STOCK/." "$TMP/src/"
  export HOME=$TMP/home ACCOUNT_SWITCHER_RUN_LOG=$LOG ACCOUNT_SWITCHER_NOTIFY_SRC=$TMP/src ACCOUNT_SWITCHER_FAKES=$TMP/fakes
  export ACCOUNT_SWITCHER_PING_WAIT=0
  unset XDG_STATE_HOME XDG_DATA_HOME XDG_CONFIG_HOME ACCOUNT_SWITCHER_MODE
  : >"$LOG"
  echo '{"plugins":[],"disabledPlugins":[]}' >"$HOME/.config/omarchy/shell.json"
}
CLONE() { echo "$HOME/.config/omarchy/plugins/account-switcher.notifications"; }
enabled() { echo '{"plugins":[{"id":"account-switcher.notifications"}],"disabledPlugins":["omarchy.notifications"]}' >"$HOME/.config/omarchy/shell.json"; }
count() { grep -cF -- "$1" "$(CLONE)/Service.qml"; }

t_sync() {
  fresh
  "$DM" notifications-sync
  t_eq $? 0
  t_eq "$(jq -r '.id' "$(CLONE)/manifest.json")" account-switcher.notifications
  t_eq "$(jq -r '.omarchy.clonedFrom' "$(CLONE)/manifest.json")" omarchy.notifications
  t_eq "$(jq -r '.entryPoints.service' "$(CLONE)/manifest.json")" Service.qml
  t_ok cmp -s "$PLUGIN/notifications/HoldLogic.js" "$(CLONE)/HoldLogic.js"
  t_ok cmp -s "$TMP/src/NotificationLogic.js" "$(CLONE)/NotificationLogic.js"
  t_ok test -f "$(CLONE)/components/NotificationCard.qml"
  t_eq "$(count 'import "HoldLogic.js" as HoldLogic')" 1
  t_eq "$(count 'import Quickshell.Hyprland')" 1
  t_eq "$(count 'if (service.holdIfNeeded(notification, snapshot)) return')" 1
  t_eq "$(count '  function holdIfNeeded(notification, snapshot) {')" 1
  t_eq "$(count '    function heldCount(): string')" 1
  # Toast clicks: each new toast's class is noted as it arrives, and a click looks first.
  t_eq "$(grep -A2 -xF '    var snapshot = snapshotOf(notification)' "$(CLONE)/Service.qml" | grep -cxF '    service.noteModeWindow(notification, snapshot)')" 1
  t_eq "$(grep -A2 -xF '  function invokePopupDefault(index) {' "$(CLONE)/Service.qml" | grep -cxF '    if (service.clickModeWindow(index)) return')" 1
  t_eq "$(count '  function clickModeWindow(index) {')" 1
  t_eq "$(count 'service.noteToastClass(entry, HoldLogic.modeWindowClass(item.desktopEntry))')" 1
  # Which apps are Work's comes from setup's hold.json, read live.
  t_eq "$(count 'path: service.holdDir + "hold.json"')" 1
  t_eq "$(count '      service.holdState, service.holdApps)')" 1
  t_eq "$(count 'HoldLogic.partition(service.heldItems, service.holdState, force, service.holdApps)')" 1
  # Only additions: every line of Omarchy's file is still there, in order.
  t_eq "$(diff "$TMP/src/Service.qml" "$(CLONE)/Service.qml" | grep -c '^<')" 0
  t_ok /usr/lib/qt6/bin/qmllint "$(CLONE)/Service.qml"
  t_ok test -s "$HOME/.local/state/account-switcher/notifications.source"
  t_eq "$(find "$HOME/.config/omarchy/plugins" -maxdepth 1 -name '.*' -not -name . | wc -l)" 0
  t_none 'plugin-enable' "$LOG"
}
t_test "the sync builds the clone from Omarchy's plugin with each patch applied once" t_sync

t_idempotent() {
  fresh
  "$DM" notifications-sync
  cp -a "$(CLONE)" "$TMP/first"
  touch -d '2000-01-01' "$(CLONE)/Service.qml"
  "$DM" notifications-sync
  t_eq $? 0
  t_ok diff -r "$TMP/first" "$(CLONE)"
  # Nothing was swapped in: the old timestamp is still there.
  t_eq "$(date -r "$(CLONE)/Service.qml" +%Y)" 2000
}
t_test "a second sync changes nothing" t_idempotent

t_missing_anchor() {
  fresh
  "$DM" notifications-sync
  cp -a "$(CLONE)" "$TMP/first"
  enabled
  sed -i '/function ping(): string/d' "$TMP/src/Service.qml"
  "$DM" notifications-sync 2>/dev/null
  t_eq $? 1
  t_ok diff -r "$TMP/first" "$(CLONE)"
  t_eq "$(find "$HOME/.config/omarchy/plugins" -maxdepth 1 -name '.*' -not -name . | wc -l)" 0
  t_ok grep -qxF "omarchy-plugin-enable omarchy.notifications" "$LOG"
  t_ok grep -qF "omarchy-notification-send" "$LOG"
  # Not enabled: nothing to switch back.
  fresh
  "$DM" notifications-sync
  sed -i '/function ping(): string/d' "$TMP/src/Service.qml"
  "$DM" notifications-sync 2>/dev/null
  t_eq $? 1
  t_none 'plugin-enable' "$LOG"
}
t_test "a missing anchor leaves the clone as it was and switches back to Omarchy's own" t_missing_anchor

t_twice() {
  fresh
  # An anchor that appears twice is as bad as a missing one.
  sed -i 's|^    persistPopupFile(snapshot)$|    persistPopupFile(snapshot)\n    persistPopupFile(snapshot)|' "$TMP/src/Service.qml"
  "$DM" notifications-sync 2>/dev/null
  t_eq $? 1
  t_ok test ! -e "$(CLONE)"
}
t_test "an anchor found twice fails too" t_twice

t_lint() {
  fresh
  "$DM" notifications-sync
  cp -a "$(CLONE)" "$TMP/first"
  echo 'Item { broken' >>"$TMP/src/Service.qml"
  "$DM" notifications-sync 2>/dev/null
  t_eq $? 1
  t_ok diff -r "$TMP/first" "$(CLONE)"
}
t_test "a copy that doesn't lint never replaces the clone" t_lint

t_check() {
  fresh
  "$DM" notifications-check
  t_ok test ! -e "$(CLONE)"
  "$DM" notifications-sync
  touch -d '2000-01-01' "$(CLONE)/Service.qml"
  "$DM" notifications-check
  t_eq "$(date -r "$(CLONE)/Service.qml" +%Y)" 2000
  echo '// changed upstream' >>"$TMP/src/NotificationLogic.js"
  "$DM" notifications-check
  t_ok grep -qxF '// changed upstream' "$(CLONE)/NotificationLogic.js"
}
t_test "the check re-syncs only an installed clone, and only when the source changed" t_check

t_ping() {
  fresh
  "$DM" notifications-sync
  # Omarchy's own in use: nothing to ask.
  "$DM" notifications-check --ping
  t_eq $? 0
  t_none ping "$LOG"
  enabled
  echo ok >"$TMP/fakes/omarchy-shell-notifications.out"
  "$DM" notifications-check --ping
  t_eq $? 0
  t_none plugin-enable "$LOG"
  rm "$TMP/fakes/omarchy-shell-notifications.out"
  : >"$LOG"
  "$DM" notifications-check --ping
  t_eq $? 1
  t_ok grep -qxF "omarchy-plugin-enable omarchy.notifications" "$LOG"
  # Three tries for the copy before switching back (the pings after it wait for Omarchy's own).
  t_eq "$(sed -n '/^omarchy-plugin-enable omarchy.notifications$/q;p' "$LOG" | grep -cxF 'omarchy-shell notifications ping')" 3
}
t_test "a clone in use that doesn't answer hands back to Omarchy's own" t_ping

HELD() { echo "$HOME/.local/state/account-switcher/held.json"; }
held_two() {
  cat >"$(HELD)" <<'JSON'
{"version":1,"items":[
 {"reason":"mode","desktopEntry":"slack","entry":{"id":4,"originalId":4,"app":"Slack","appIcon":"slack","summary":"Ana","body":"standup?","urgency":1,"timestamp":1000}},
 {"reason":"mode","desktopEntry":"","entry":{"id":5,"originalId":5,"app":"Slack","appIcon":"","summary":"-Call from Ana","body":"","urgency":2,"timestamp":1001}}
]}
JSON
}

t_handoff() {
  fresh
  "$DM" notifications-sync
  held_two
  echo ok >"$TMP/fakes/omarchy-shell-notifications.out"
  # Omarchy's own is the one in use (turned back on by hand): it never reads held.json, so what
  # the copy was holding is sent to it, and the list empties.
  "$DM" notifications-check
  t_ok grep -qxF "omarchy-notification-send --app-name Slack -u normal -i slack Ana standup?" "$LOG"
  t_ok grep -qxF "omarchy-notification-send --app-name Slack -u critical -Call from Ana" "$LOG"
  t_eq "$(jq '.items | length' "$(HELD)")" 0
}
t_test "with Omarchy's own in use, what the copy held is handed over" t_handoff

t_no_handoff() {
  fresh
  "$DM" notifications-sync
  held_two
  echo ok >"$TMP/fakes/omarchy-shell-notifications.out"
  enabled
  "$DM" notifications-check
  t_none notification-send "$LOG"
  t_eq "$(jq '.items | length' "$(HELD)")" 2
  # No daemon answering: kept for the next check.
  rm "$TMP/fakes/omarchy-shell-notifications.out"
  echo '{"plugins":[],"disabledPlugins":[]}' >"$HOME/.config/omarchy/shell.json"
  "$DM" notifications-check
  t_none notification-send "$LOG"
  t_eq "$(jq '.items | length' "$(HELD)")" 2
}
t_test "the copy keeps its list while it's in use, or while no daemon answers" t_no_handoff

t_fallback_handoff() {
  fresh
  "$DM" notifications-sync
  enabled
  held_two
  echo ok >"$TMP/fakes/omarchy-shell-notifications.out"
  sed -i '/function ping(): string/d' "$TMP/src/Service.qml"
  "$DM" notifications-sync 2>/dev/null
  t_eq $? 1
  t_after() { local a b; a=$(grep -nF -- "$1" "$LOG" | head -n1 | cut -d: -f1); b=$(grep -nF -- "$2" "$LOG" | head -n1 | cut -d: -f1); [[ -n $a && -n $b ]] && ((b > a)) || { echo "\"$2\" not after \"$1\""; cat "$LOG"; exit 1; }; }
  t_after "omarchy-plugin-enable omarchy.notifications" "Work notifications no longer wait"
  t_after "Work notifications no longer wait" "--app-name Slack -u normal -i slack Ana standup?"
  t_eq "$(jq '.items | length' "$(HELD)")" 0
}
t_test "switching back to Omarchy's own after a failed sync hands the held ones over" t_fallback_handoff

t_done
