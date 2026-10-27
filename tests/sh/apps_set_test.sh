#!/usr/bin/env bash
# `account-switcher apps-set`: the setup window's choice saved to config.json. Only the keys the
# window owns change; a config that wouldn't check out is never written.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
DM=$PLUGIN/bin/account-switcher
TMP=${TEST_TMPDIR:?run through tests/run.sh}/apps-set
export ACCOUNT_SWITCHER_WALK_ROOT=$$

entry() {
  local dir=$1 file=$2
  shift 2
  mkdir -p "$dir"
  printf '%s\n' '[Desktop Entry]' 'Type=Application' "$@" >"$dir/$file"
}
program() { mkdir -p "${1%/*}" && printf '#!/bin/sh\n' >"$1" && chmod +x "$1"; }

fresh() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.config/account-switcher" "$TMP/bin" "$TMP/fakes"
  export HOME=$TMP/home ACCOUNT_SWITCHER_SYSTEM_APPS=$TMP/sys ACCOUNT_SWITCHER_OMARCHY_APPS=$TMP/omarchy
  export XDG_DATA_DIRS=$TMP/none PATH=$TMP/bin:$PATH ACCOUNT_SWITCHER_GH=/opt/gh/bin/gh
  export ACCOUNT_SWITCHER_RUN_LOG=$TMP/run.log ACCOUNT_SWITCHER_FAKES=$TMP/fakes
  unset XDG_STATE_HOME XDG_DATA_HOME XDG_CONFIG_HOME ACCOUNT_SWITCHER_MODE HYPRLAND_INSTANCE_SIGNATURE
  jq '._note = "mine" | .holdApps = ["Example VPN"]' "$PLUGIN/tests/fixtures/config.test.json" >"$(CFG)"
  chmod 600 "$(CFG)"
  program "$TMP/bin/chat"
  program "$TMP/opt/browser-a/browser-a" && ln -s "$TMP/opt/browser-a/browser-a" "$TMP/bin/browser-a"
  program "$TMP/opt/browser-b/browser-b" && ln -s "$TMP/opt/browser-b/browser-b" "$TMP/bin/browser-b"
  entry "$TMP/sys" chat.desktop 'Name=Chat' 'Exec=chat %U'
  entry "$TMP/sys" browser-a.desktop 'Name=Browser A' 'Exec=browser-a %U' 'Categories=WebBrowser;'
  entry "$TMP/sys" browser-b.desktop 'Name=Browser B' 'Exec=browser-b %U' 'Categories=WebBrowser;'
  entry "$TMP/sys" envy.desktop 'Name=Envy' 'Exec=env FOO=1 chat'
  entry "$TMP/omarchy" 'Google Maps.desktop' 'Name=Google Maps' 'Exec=omarchy-launch-webapp https://maps.example/'
  "$DM" setup >/dev/null
}
CFG() { echo "$HOME/.config/account-switcher/config.json"; }
STATE() { echo "$HOME/.local/state/account-switcher"; }
OWNED='del(.work.browser, .personal.browser, .work.apps, .personal.apps, .work.webapps, .personal.webapps,
  .webappsFollowMode, .customApps, .customBrowsers, .clockInApps)'
CHOICE='{"work": {"browser": "browser-a", "apps": ["chat"], "webapps": []},
  "personal": {"browser": "browser-b", "apps": [], "webapps": ["Google Maps"]}, "follow": []}'
sums() { (cd "$HOME" && find .config .local/state -type f -exec sha256sum {} + | sort); }

t_sets_and_keeps_the_rest() {
  fresh
  local before out
  before=$(jq -S "$OWNED" "$(CFG)")
  out=$("$DM" apps-set <<<"$CHOICE")
  t_eq $? 0
  t_eq "$out" "account-switcher: saved; setup done"
  t_eq "$(jq -c '[.work.browser, .work.apps, .personal.browser, .personal.webapps, .webappsFollowMode]' "$(CFG)")" \
    '["browser-a",["chat"],"browser-b",["Google Maps"],[]]'
  t_eq "$(jq -c '.customApps.chat | [.label, .desktop, .class]' "$(CFG)")" '["Chat","chat.desktop","chat"]'
  t_eq "$(jq -c '.customBrowsers["browser-a"].exeDir' "$(CFG)")" "\"$TMP/opt/browser-a/\""
  t_eq "$(jq -S "$OWNED" "$(CFG)")" "$before" "everything the window doesn't own"
  t_ok test -n "$(find "$HOME/.config/account-switcher" -name 'config.json.bak.*')"
  t_ok grep -qxF 'class work chat' "$(STATE)/apps"
  t_eq "$(stat -c %a "$(CFG)")" 600
}
t_test "the window's choice is saved, and everything else in the config stays" t_sets_and_keeps_the_rest

t_clock_in_trimmed() {
  fresh
  "$DM" apps-set <<<"$CHOICE" >/dev/null
  t_eq "$(jq -c '.clockInApps' "$(CFG)")" '["browser","code"]'
}
t_test "clock in forgets an app that's no longer a Work app" t_clock_in_trimmed

t_keeps_hand_written() {
  fresh
  local c
  jq '.customApps.chat = {"label": "My Chat", "bin": "/usr/bin/chat", "class": "chat", "desktop": "chat.desktop", "execToken": "chat", "focusExisting": true}' \
    "$(CFG)" >"$TMP/c" && cat "$TMP/c" >"$(CFG)"
  c=$(jq -c '.customApps.chat' "$(CFG)")
  "$DM" apps-set <<<"$CHOICE" >/dev/null
  t_eq $? 0
  t_eq "$(jq -c '.customApps.chat' "$(CFG)")" "$c"
  t_eq "$(jq -c '.customApps.slack.desktop' "$(CFG)")" '"slack.desktop"' "a hand-written entry no mode uses stays too"
}
t_test "entries written by hand stay as written" t_keeps_hand_written

t_generated_removed() {
  fresh
  "$DM" apps-set <<<"$CHOICE" >/dev/null
  "$DM" apps-set <<<"$(jq -c '.work.apps = []' <<<"$CHOICE")" >/dev/null
  t_eq "$(jq -c '.customApps | has("chat")' "$(CFG)")" false
}
t_test "an entry the window added goes when no mode uses it" t_generated_removed

t_symlinked_config() {
  fresh
  mkdir -p "$HOME/real"
  mv "$(CFG)" "$HOME/real/config.json"
  ln -s ../../real/config.json "$(CFG)"
  "$DM" apps-set <<<"$CHOICE" >/dev/null
  t_eq $? 0
  t_ok test -L "$(CFG)"
  t_eq "$(jq -c '.work.apps' "$HOME/real/config.json")" '["chat"]'
  t_ok test -n "$(find "$HOME/real" -name 'config.json.bak.*')"
  t_eq "$(stat -c %a "$HOME/real/config.json")" 600
}
t_test "a config that's a link stays a link; the file it points to is changed and backed up" t_symlinked_config

t_refused_writes_nothing() {
  fresh
  local before out
  before=$(sums)
  out=$("$DM" apps-set <<<"$(jq -c '.personal.browser = "browser-a"' <<<"$CHOICE")" 2>&1)
  t_eq $? 1
  t_ok grep -qF 'personal.browser: must differ from work.browser' <<<"$out"
  t_eq "$(sums)" "$before" "nothing written"
}
t_test "a choice that wouldn't check out is refused, and nothing is written" t_refused_writes_nothing

t_bad_payload() {
  fresh
  local before out
  before=$(sums)
  out=$("$DM" apps-set <<<"$(jq -c '.work.apps = ["envy"]' <<<"$CHOICE")" 2>&1)
  t_eq $? 2
  t_ok grep -qF '"envy"' <<<"$out"
  out=$("$DM" apps-set <<<"$(jq -c '.work.apps = ["nope"]' <<<"$CHOICE")" 2>&1)
  t_eq $? 2
  t_ok grep -qF '"nope"' <<<"$out"
  "$DM" apps-set <<<'{not json' >/dev/null 2>&1
  t_eq $? 2
  t_eq "$(sums)" "$before" "nothing written"
}
t_test "an unknown or unusable app, or a broken request, is refused by name" t_bad_payload

t_noop() {
  fresh
  local before
  "$DM" apps-set <<<"$CHOICE" >/dev/null
  before=$(jq -S . "$(CFG)")
  "$DM" apps-list | jq -c '.assigned' | "$DM" apps-set >/dev/null
  t_eq $? 0
  t_eq "$(jq -S . "$(CFG)")" "$before"
}
t_test "saving what's already there changes nothing" t_noop

t_argument() {
  fresh
  "$DM" apps-set "$CHOICE" </dev/null >/dev/null
  t_eq $? 0
  t_eq "$(jq -c '.work.apps' "$(CFG)")" '["chat"]'
}
t_test "the choice can come as an argument instead of on stdin" t_argument

t_hand_written_survives_moving_out() {
  fresh
  jq '.customApps.chat = {"label": "My Chat", "bin": "/usr/bin/chat", "class": "chat", "desktop": "chat.desktop", "execToken": "chat", "focusExisting": true}
    | .customBrowsers["browser-a"] = {"label": "Tuned A", "bin": "/usr/bin/browser-a", "exeDir": "/opt/tuned/", "class": "browser-a", "desktop": "browser-a.desktop", "execToken": "browser-a", "notify": ["A", "A2"]}' \
    "$(CFG)" >"$TMP/c" && cat "$TMP/c" >"$(CFG)"
  local app browser
  app=$(jq -c '.customApps.chat' "$(CFG)") browser=$(jq -c '.customBrowsers["browser-a"]' "$(CFG)")
  "$DM" apps-set <<<"$CHOICE" >/dev/null
  "$DM" apps-set <<<"$(jq -c '.work.apps = [] | .work.browser = null' <<<"$CHOICE")" >/dev/null
  t_eq $? 0
  t_eq "$(jq -c '.customApps.chat' "$(CFG)")" "$app" "hand-written app kept after moving it out"
  t_eq "$(jq -c '.customBrowsers["browser-a"]' "$(CFG)")" "$browser" "hand-written browser kept after unsetting it"
}
t_test "entries written by hand survive their app moving out of every mode" t_hand_written_survives_moving_out

t_write_failure() {
  fresh
  local out
  chmod 400 "$(CFG)"
  out=$("$DM" apps-set <<<"$CHOICE" 2>&1)
  t_eq $? 1
  t_ok grep -qF "couldn't write" <<<"$out"
  t_none "saved" <<<"$out"
  chmod 600 "$(CFG)"
  t_eq "$(jq -c '.work.apps' "$(CFG)")" '["slack"]'
  t_eq "$(find "$HOME/.config/account-switcher" -name '.config.json.*' | wc -l)" 0 "no temp file left"
}
t_test "a config that can't be written is reported, not called saved" t_write_failure

t_done
