#!/usr/bin/env bash
# Browsers, web apps and links per mode, and the link entries desktop-apply writes.
# Commands are recorded (ACCOUNT_SWITCHER_RUN_LOG), never run.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
TMP=${TEST_TMPDIR:?run through tests/run.sh}/browser
export ACCOUNT_SWITCHER_WALK_ROOT=$$
DM=$PLUGIN/bin/account-switcher
CHROME=/usr/bin/google-chrome-stable CHROMIUM=/usr/bin/chromium
SWITCH="hyprctl dispatch function() if account_switcher then account_switcher.switch"

fresh() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.local/state/account-switcher" "$TMP/fakes" "$TMP/sys" "$TMP/omarchy"
  export HOME=$TMP/home ACCOUNT_SWITCHER_RUN_LOG=$TMP/run.log ACCOUNT_SWITCHER_FAKES=$TMP/fakes
  unset XDG_STATE_HOME XDG_DATA_HOME XDG_CONFIG_HOME ACCOUNT_SWITCHER_MODE
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
log_has() { grep -qxF -- "$1" "$ACCOUNT_SWITCHER_RUN_LOG" || { echo "not run: $1"; cat "$ACCOUNT_SWITCHER_RUN_LOG"; exit 1; }; }
clients() { printf '%s\n' "$1" >"$TMP/fakes/hyprctl-clients.out"; }

t_browser() {
  fresh
  desk work
  "$DM" browser
  log_has "omarchy-cmd-browser-handoff $CHROME"
  "$DM" browser --private
  log_has "omarchy-cmd-browser-handoff $CHROME --incognito"
  desk personal
  "$DM" browser https://example.org
  log_has "omarchy-cmd-browser-handoff $CHROMIUM https://example.org"
  t_none "$SWITCH" "$ACCOUNT_SWITCHER_RUN_LOG"
}
t_test "the browser keys open the current mode's browser" t_browser

t_browser_cold() {
  fresh
  desk personal
  echo 1 >"$TMP/fakes/omarchy-cmd-browser-handoff.status"
  "$DM" browser https://example.org
  t_ok grep -qE "^systemd-run --user --quiet --collect --unit=account-switcher-browser-[0-9]+ --property=StandardOutput=null --property=StandardError=null uwsm-app -- $CHROMIUM https://example.org\$" "$ACCOUNT_SWITCHER_RUN_LOG"
}
t_test "a browser that isn't running is started like Omarchy does" t_browser_cold

t_browser_focus() {
  fresh
  desk work
  clients '[{"class":"google-chrome","address":"0xa","workspace":{"id":12},"focusHistoryID":0},
            {"class":"google-chrome","address":"0xb","workspace":{"id":2},"focusHistoryID":3},
            {"class":"google-chrome","address":"0xc","workspace":{"id":4},"focusHistoryID":1}]'
  "$DM" browser https://example.org
  log_has 'hyprctl dispatch hl.dsp.focus({ window = "address:0xc" })'
}
t_test "after opening a link, the mode's most recent browser window is focused" t_browser_focus

t_browser_other_mode() {
  fresh
  desk personal
  "$DM" browser --mode=work https://example.org
  t_eq "$(head -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "$SWITCH('work') end end"
  log_has "omarchy-cmd-browser-handoff $CHROME https://example.org"
}
t_test "a link of the other mode switches the desk first" t_browser_other_mode

t_webapp() {
  fresh
  desk work
  "$DM" webapp https://chatgpt.com
  log_has "omarchy-cmd-browser-handoff $CHROME --app=https://chatgpt.com"
  "$DM" webapp --mode=personal https://x.com/ --ignore-certificate-errors
  log_has "omarchy-cmd-browser-handoff $CHROMIUM --app=https://x.com/ --ignore-certificate-errors"
}
t_test "web apps open in the mode's browser" t_webapp

t_webapp_focus() {
  fresh
  desk personal
  clients '[{"class":"chrome-web.whatsapp.com__-Default","title":"WhatsApp","address":"0x1","workspace":{"id":2},"focusHistoryID":0},
            {"class":"chrome-web.whatsapp.com__-Default","title":"(3) WhatsApp","address":"0x2","workspace":{"id":13},"focusHistoryID":1}]'
  "$DM" webapp --mode=personal --focus=WhatsApp https://web.whatsapp.com/
  log_has 'hyprctl dispatch hl.dsp.focus({ window = "address:0x2" })'
  t_none handoff "$ACCOUNT_SWITCHER_RUN_LOG"
  clients '[{"class":"chrome-web.whatsapp.com__-Default","title":"WhatsApp","address":"0x1","workspace":{"id":2},"focusHistoryID":0}]'
  "$DM" webapp --mode=personal --focus=WhatsApp https://web.whatsapp.com/
  log_has "omarchy-cmd-browser-handoff $CHROMIUM --app=https://web.whatsapp.com/"
}
t_test "launch-or-focus web apps only focus a window of their own mode" t_webapp_focus

t_open() {
  fresh
  desk work
  ACCOUNT_SWITCHER_MODE=personal "$DM" open https://a.example https://b.example
  log_has "omarchy-cmd-browser-handoff $CHROMIUM https://a.example"
  log_has "omarchy-cmd-browser-handoff $CHROMIUM https://b.example"
  "$DM" open --mode=work https://c.example
  log_has "omarchy-cmd-browser-handoff $CHROME https://c.example"
}
t_test "links open in the requester's mode" t_open

t_mailto() {
  fresh
  desk work
  "$DM" mailto 'mailto:a@b.c?subject=Hi there'
  log_has "omarchy-cmd-browser-handoff $CHROME https://mail.google.com/mail/?extsrc=mailto&url=mailto%3Aa%40b.c%3Fsubject%3DHi%20there"
}
t_test "mailto opens Gmail compose" t_mailto

t_zoom() {
  fresh
  desk work
  "$DM" zoom 'zoommtg://zoom.us/join?action=join&confno=123&pwd=abc'
  log_has "omarchy-cmd-browser-handoff $CHROME --app=https://app.zoom.us/wc/join/123?pwd=abc"
  "$DM" zoom
  log_has "omarchy-cmd-browser-handoff $CHROME --app=https://app.zoom.us/wc/home"
}
t_test "Zoom links open the Zoom web client" t_zoom

t_desktop_links() {
  fresh
  cp "$PLUGIN"/tests/fixtures/omarchy/*.desktop "$TMP/omarchy/"
  cp "$PLUGIN/tests/fixtures/applications/chromium.desktop" "$TMP/sys/"
  mkdir -p "$HOME/.config"
  printf '[Default Applications]\nx-scheme-handler/http=omarchy-browser.desktop\nx-scheme-handler/https=omarchy-browser.desktop\n' >"$HOME/.config/hyprland-mimeapps.list"
  local env=(ACCOUNT_SWITCHER_SYSTEM_APPS=$TMP/sys ACCOUNT_SWITCHER_OMARCHY_APPS=$TMP/omarchy XDG_DATA_HOME=$TMP/data)
  env "${env[@]}" "$DM" desktop-apply
  env "${env[@]}" "$DM" desktop-apply
  local apps=$TMP/data/applications bin=$HOME/.local/bin
  t_ok grep -qx "Exec=$bin/account-switcher open %U" "$apps/omarchy-browser.desktop"
  t_ok grep -qx 'NoDisplay=true' "$apps/omarchy-browser.desktop"
  t_ok grep -qx 'MimeType=x-scheme-handler/http;x-scheme-handler/https;' "$apps/omarchy-browser.desktop"
  t_ok grep -qx "Exec=$bin/account-switcher webapp --mode=personal https://web.whatsapp.com/" "$apps/WhatsApp.desktop"
  t_ok grep -qx "Exec=$bin/account-switcher webapp --mode=personal https://discord.com/channels/@me" "$apps/Discord.desktop"
  t_ok grep -qx "Exec=$bin/account-switcher webapp https://youtube.com/" "$apps/YouTube.desktop"
  t_ok grep -qx "Exec=$bin/account-switcher webapp https://maps.google.com" "$apps/Google Maps.desktop"
  t_ok grep -qx "Exec=$bin/account-switcher zoom %u" "$apps/Zoom.desktop"
  local f
  for f in Discord WhatsApp "Google Photos" "Google Maps" YouTube HEY Zoom omarchy-browser; do
    t_ok grep -qx 'X-AccountSwitcher=managed' "$apps/$f.desktop"
  done
  for f in X "Google Messages" "Google Contacts" Basecamp; do t_ok test ! -e "$apps/$f.desktop"; done
  t_ok grep -qx "Exec=$bin/account-switcher browser --mode=personal %U" "$apps/chromium.desktop"
  t_ok grep -qx "Exec=$bin/account-switcher browser --mode=personal --new-window" "$apps/chromium.desktop"
  t_ok grep -qx "Exec=$bin/account-switcher browser --mode=personal --private" "$apps/chromium.desktop"
  t_ok grep -qx 'StartupWMClass=chromium' "$apps/chromium.desktop"
  t_ok grep -qx "Exec=$bin/account-switcher mailto %u" "$apps/account-switcher-mailto.desktop"
  t_eq "$(grep -c '^x-scheme-handler/mailto=account-switcher-mailto.desktop$' "$HOME/.config/hyprland-mimeapps.list")" 1
  t_ok grep -qx 'x-scheme-handler/https=omarchy-browser.desktop' "$HOME/.config/hyprland-mimeapps.list"
}
t_test "desktop-apply routes links, web apps, Zoom, mailto and Chromium" t_desktop_links


t_background_link() {
  fresh
  desk personal
  echo '{"pid":1}' >"$TMP/fakes/hyprctl-activewindow.out"
  ACCOUNT_SWITCHER_MODE=work "$DM" open https://work.example
  t_none "$SWITCH" "$ACCOUNT_SWITCHER_RUN_LOG"
  log_has "omarchy-cmd-browser-handoff $CHROME https://work.example"
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  echo "{\"pid\":$BASHPID}" >"$TMP/fakes/hyprctl-activewindow.out"
  ACCOUNT_SWITCHER_MODE=work "$DM" open https://work.example
  t_eq "$(head -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "hyprctl activewindow -j"
  t_ok grep -q "$SWITCH('work')" "$ACCOUNT_SWITCHER_RUN_LOG"
}
t_test "a link from a background program opens without pulling the desk across" t_background_link

t_background_link_no_focus() {
  fresh
  desk personal
  echo '[{"class":"google-chrome","address":"0xc","workspace":{"id":2},"focusHistoryID":3}]' >"$TMP/fakes/hyprctl-clients.out"
  echo '{"pid":1}' >"$TMP/fakes/hyprctl-activewindow.out"
  ACCOUNT_SWITCHER_MODE=work "$DM" open https://work.example
  log_has "omarchy-cmd-browser-handoff $CHROME https://work.example"
  # Focusing Work's Chrome from Personal would take the desk across after all.
  t_none "hl.dsp.focus" "$ACCOUNT_SWITCHER_RUN_LOG"
  t_none "$SWITCH" "$ACCOUNT_SWITCHER_RUN_LOG"
  # From the window you're in, the link still brings its browser window forward.
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  echo "{\"pid\":$BASHPID}" >"$TMP/fakes/hyprctl-activewindow.out"
  ACCOUNT_SWITCHER_MODE=work "$DM" open https://work.example
  t_ok grep -qF 'hl.dsp.focus({ window = "address:0xc" })' "$ACCOUNT_SWITCHER_RUN_LOG"
}
t_test "a background link doesn't focus the other mode's browser either" t_background_link_no_focus

t_router_refuses_flags() {
  fresh
  desk work
  "$DM" open --load-extension=/tmp/evil https://ok.example 2>/dev/null
  t_none "load-extension" "$ACCOUNT_SWITCHER_RUN_LOG"
  log_has "omarchy-cmd-browser-handoff $CHROME https://ok.example"
}
t_test "the link router never passes options to the browser" t_router_refuses_flags

t_swapped() {
  fresh
  config '.work.browser = "chromium" | .personal.browser = "google-chrome"'
  desk work
  clients '[{"class":"chromium","address":"0xd","workspace":{"id":3},"focusHistoryID":0}]'
  "$DM" browser https://example.org
  log_has "omarchy-cmd-browser-handoff $CHROMIUM https://example.org"
  log_has 'hyprctl dispatch hl.dsp.focus({ window = "address:0xd" })'
  desk personal
  "$DM" browser
  log_has "omarchy-cmd-browser-handoff $CHROME"
}
t_test "each mode's browser is the configured one, whichever way round" t_swapped

t_mailto_none() {
  fresh
  config '.mailto = "none"'
  cp "$PLUGIN/tests/fixtures/applications/chromium.desktop" "$TMP/sys/"
  ACCOUNT_SWITCHER_SYSTEM_APPS=$TMP/sys ACCOUNT_SWITCHER_OMARCHY_APPS=$TMP/omarchy XDG_DATA_HOME=$TMP/data "$DM" desktop-apply
  t_ok test ! -e "$TMP/data/applications/account-switcher-mailto.desktop"
  t_none mailto "$HOME/.config/hyprland-mimeapps.list"
  t_ok test -e "$TMP/data/applications/omarchy-browser.desktop"
}
t_test "mailto none leaves mail links alone" t_mailto_none

t_user_webapp() {
  fresh
  config '.personal.webapps += ["Gmail", "Nope"]'
  local apps=$TMP/data/applications err
  mkdir -p "$apps"
  printf '[Desktop Entry]\nName=Gmail\nExec=omarchy-launch-webapp https://mail.google.com/\nType=Application\n' >"$apps/Gmail.desktop"
  err=$(ACCOUNT_SWITCHER_SYSTEM_APPS=$TMP/sys ACCOUNT_SWITCHER_OMARCHY_APPS=$TMP/omarchy XDG_DATA_HOME=$TMP/data "$DM" desktop-apply 2>&1 >/dev/null)
  t_ok grep -qx "Exec=$HOME/.local/bin/account-switcher webapp --mode=personal https://mail.google.com/" "$apps/Gmail.desktop"
  t_ok grep -qx 'X-AccountSwitcher=managed' "$apps/Gmail.desktop"
  t_ok grep -q 'Nope' <<<"$err"
  # Applied again (and checked) from the user's own copy, kept aside.
  ACCOUNT_SWITCHER_SYSTEM_APPS=$TMP/sys ACCOUNT_SWITCHER_OMARCHY_APPS=$TMP/omarchy XDG_DATA_HOME=$TMP/data "$DM" desktop-apply 2>/dev/null
  t_ok grep -qx "Exec=$HOME/.local/bin/account-switcher webapp --mode=personal https://mail.google.com/" "$apps/Gmail.desktop"
  t_ok grep -qx 'Exec=omarchy-launch-webapp https://mail.google.com/' "$HOME/.local/state/account-switcher/originals/applications/Gmail.desktop"
}
t_test "a user's own web app in the config opens in its mode too; an unknown name is reported" t_user_webapp

t_done
