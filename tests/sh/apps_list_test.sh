#!/usr/bin/env bash
# `account-switcher apps-list`: the installed apps, browsers and web apps the setup window offers,
# what each needs in the config, and why one can't be put in a mode. Entries and programs are
# made up in a scratch folder.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
DM=$PLUGIN/bin/account-switcher
TMP=${TEST_TMPDIR:?run through tests/run.sh}/apps-list
export ACCOUNT_SWITCHER_WALK_ROOT=$$

entry() { # DIR FILE LINE…: a launcher entry
  local dir=$1 file=$2
  shift 2
  mkdir -p "$dir"
  printf '%s\n' '[Desktop Entry]' 'Type=Application' "$@" >"$dir/$file"
}
program() { # PATH: an executable that does nothing
  mkdir -p "${1%/*}" && printf '#!/bin/sh\n' >"$1" && chmod +x "$1"
}

fresh() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.config/account-switcher" "$TMP/bin"
  export HOME=$TMP/home ACCOUNT_SWITCHER_SYSTEM_APPS=$TMP/sys ACCOUNT_SWITCHER_OMARCHY_APPS=$TMP/omarchy
  export XDG_DATA_DIRS=$TMP/flat/exports/share:$TMP/usr-share PATH=$TMP/bin:$PATH
  unset XDG_STATE_HOME XDG_DATA_HOME XDG_CONFIG_HOME ACCOUNT_SWITCHER_MODE
  cp "$PLUGIN/tests/fixtures/config.full.json" "$HOME/.config/account-switcher/config.json"
  program "$TMP/bin/chat"
  # A browser started through a link into its own folder, and one through a wrapper script
  # (the way google-chrome-stable starts /opt/google/chrome/google-chrome).
  program "$TMP/opt/browser-b/browser-b" && ln -s "$TMP/opt/browser-b/browser-b" "$TMP/bin/browser-b"
  program "$TMP/opt/browser-a/real"
  printf '#!/bin/bash\nexec "%s" "$@"\n' "$TMP/opt/browser-a/real" >"$TMP/bin/browser-a" && chmod +x "$TMP/bin/browser-a"
  local S=$TMP/sys
  entry "$S" chat.desktop 'Name=Chat' 'Name[de]=Plaudern' 'Exec=chat %U' 'Icon=chat' 'StartupWMClass=ChatApp'
  entry "$S" browser-b.desktop 'Name=Browser B' 'Exec=browser-b %U' 'Categories=Network;WebBrowser;'
  entry "$S" browser-a.desktop 'Name=Browser A' 'Exec=browser-a %U' 'Categories=WebBrowser;' 'StartupWMClass=Browser-A'
  entry "$S" hidden.desktop 'Name=Hidden' 'Exec=chat' 'NoDisplay=true'
  entry "$S" kde.desktop 'Name=KDE Only' 'Exec=chat' 'OnlyShowIn=KDE;'
  entry "$S" envy.desktop 'Name=Envy' 'Exec=env FOO=1 chat'
  entry "$S" flat.desktop 'Name=Flat' 'Exec=flatpak run org.x.Y'
  entry "$S" shy.desktop 'Name=Shy' "Exec=sh -c 'chat --quiet'"
  entry "$S" spaced.desktop 'Name=Spaced' 'Exec="/opt/My App/app" %U'
  entry "$S" missing.desktop 'Name=Missing' 'Exec=nothere'
  entry "$TMP/omarchy" 'Google Maps.desktop' 'Name=Google Maps' 'Exec=omarchy-launch-webapp https://maps.example/' 'Icon=maps'
  entry "$TMP/omarchy" foot.desktop 'Name=Foot' 'Exec=chat'
  entry "$TMP/flat/exports/share/applications" org.x.Y.desktop 'Name=Flatty' 'Exec=/usr/bin/flatpak run org.x.Y'
  entry "$HOME/.local/share/applications" mine.desktop 'Name=Mine' 'Exec=chat'
  entry "$HOME/.local/share/applications" Notes.desktop 'Name=Notes' 'Exec=omarchy-launch-webapp https://notes.example/'
  # The switcher's own copy of chat's entry stands in for nothing: the system's is listed.
  entry "$HOME/.local/share/applications" chat.desktop 'X-AccountSwitcher=managed' 'Name=Chat' "Exec=$HOME/.local/bin/account-switcher app chat %U"
}
list() { "$DM" apps-list; }
one() { list | jq -c --arg id "$1" ".entries[] | select(.id == \$id) | $2"; }

t_lists_and_derives() {
  fresh
  t_ok list >/dev/null
  t_eq "$(one chat.desktop '[.name, .kind, .usable, .key, .icon]')" '["Chat","app",true,"chat","chat"]'
  t_eq "$(one chat.desktop '.def')" "$(jq -c -n --arg b "$TMP/bin/chat" \
    '{label: "Chat", bin: $b, class: "ChatApp", desktop: "chat.desktop", execToken: "chat", notify: ["Chat"], notifyEntries: ["chat"]}')"
  t_eq "$(one browser-b.desktop '[.kind, .usable, .def.class, .def.exeDir, .def.routeDesktop]')" \
    "[\"browser\",true,\"browser-b\",\"$TMP/opt/browser-b/\",true]"
  t_eq "$(one browser-a.desktop '.def.exeDir')" "\"$TMP/opt/browser-a/\""
  t_eq "$(list | jq -c '[.entries[].id] | map(select(. == "hidden.desktop" or . == "kde.desktop")) | length')" 0
  t_eq "$(list | jq '[.entries[] | select(.id == "chat.desktop")] | length')" 1
}
t_test "installed apps and browsers, with what each needs worked out from its entry" t_lists_and_derives

t_unusable_reasons() {
  fresh
  local wrap="launched through a wrapper (flatpak, env, sh)" away="not from the system app folder"
  t_eq "$(one envy.desktop '[.usable, .reason]')" "[false,\"$wrap\"]"
  t_eq "$(one flat.desktop '.reason')" "\"$wrap\""
  t_eq "$(one shy.desktop '.reason')" "\"$wrap\""
  t_eq "$(one mine.desktop '[.usable, .reason]')" "[false,\"$away\"]"
  t_eq "$(one org.x.Y.desktop '.reason')" "\"$away\""
  t_eq "$(one foot.desktop '.reason')" "\"$away\""
  t_eq "$(one missing.desktop '[.usable, .reason]')" "[false,\"its program isn't installed\"]"
}
t_test "an app that can't be put in a mode says why" t_unusable_reasons

t_awkward_entries() {
  fresh
  t_eq "$(one spaced.desktop '[.def.bin, .def.execToken, .reason]')" "[\"/opt/My App/app\",\"/opt/My App/app\",\"its program isn't installed\"]"
  t_eq "$(one 'Google Maps.desktop' '[.kind, .usable, .key, .name]')" '["webapp",true,"Google Maps","Google Maps"]'
  t_eq "$(one Notes.desktop '[.kind, .usable, .key]')" '["webapp",true,"Notes"]'
}
t_test "quoted paths, field codes and names with spaces" t_awkward_entries

t_assigned() {
  fresh
  local c=$HOME/.config/account-switcher/config.json
  t_eq "$(list | jq -c '.assigned')" "$(jq -c '{work: {browser: .work.browser, apps: (.work.apps // []), webapps: (.work.webapps // [])},
    personal: {browser: .personal.browser, apps: (.personal.apps // []), webapps: (.personal.webapps // [])},
    follow: (.webappsFollowMode // [])}' "$c")"
  jq 'del(.work.browser)' "$c" >"$c.new" && mv "$c.new" "$c"
  t_eq "$(list | jq -c '.assigned.work.browser')" null
}
t_test "what the config gives each mode now" t_assigned

t_hand_written_wins() {
  fresh
  local c=$HOME/.config/account-switcher/config.json
  jq '.customApps.mychat = {"label": "My Chat", "bin": "/usr/bin/chat", "class": "chat", "desktop": "chat.desktop", "execToken": "chat", "focusExisting": true}' \
    "$c" >"$c.new" && mv "$c.new" "$c"
  t_eq "$(one chat.desktop '[.key, .def.label, .def.focusExisting]')" '["mychat","My Chat",true]'
}
t_test "an app the config already describes keeps its name and description" t_hand_written_wins

t_done
