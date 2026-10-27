#!/usr/bin/env bash
# desktop-check: noticing launcher entries that Omarchy (or a package) put back, and fixing them.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
TMP=${TEST_TMPDIR:?run through tests/run.sh}/check
DM=$PLUGIN/bin/account-switcher

fresh() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.config" "$TMP/fakes" "$TMP/sys" "$TMP/omarchy"
  export HOME=$TMP/home ACCOUNT_SWITCHER_RUN_LOG=$TMP/run.log ACCOUNT_SWITCHER_FAKES=$TMP/fakes
  export ACCOUNT_SWITCHER_SYSTEM_APPS=$TMP/sys ACCOUNT_SWITCHER_OMARCHY_APPS=$TMP/omarchy XDG_DATA_HOME=$TMP/data
  unset XDG_STATE_HOME XDG_CONFIG_HOME ACCOUNT_SWITCHER_MODE
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  cp "$PLUGIN"/tests/fixtures/omarchy/*.desktop "$TMP/omarchy/"
  local f
  for f in com.mitchellh.ghostty org.gnome.Nautilus chromium slack filezilla steam ClickUp; do
    cp "$PLUGIN/tests/fixtures/applications/$f.desktop" "$TMP/sys/"
  done
  mkdir -p "$HOME/.config/account-switcher" && cp "$PLUGIN/tests/fixtures/config.full.json" "$HOME/.config/account-switcher/config.json"
  ACCOUNT_SWITCHER_GH=/opt/gh/bin/gh "$DM" setup >/dev/null && : >"$ACCOUNT_SWITCHER_RUN_LOG"
}

t_quiet() {
  fresh
  "$DM" desktop-apply
  local out status
  out=$("$DM" desktop-check 2>&1)
  status=$?
  t_eq "$status|$out" "0|"
}
t_test "desktop-check is quiet when every entry is applied" t_quiet

t_reset() {
  fresh
  "$DM" desktop-apply
  cp "$TMP/omarchy/WhatsApp.desktop" "$TMP/omarchy/omarchy-browser.desktop" "$TMP/data/applications/"
  rm "$TMP/data/applications/org.omarchy.term-work.desktop"
  local out
  out=$("$DM" desktop-check) && t_eq ok "reported" "check passed with reset entries"
  t_ok grep -qx 'WhatsApp.desktop' <<<"$out"
  t_ok grep -qx 'omarchy-browser.desktop' <<<"$out"
  t_ok grep -qx 'org.omarchy.term-work.desktop' <<<"$out"
  t_eq "$(wc -l <<<"$out")" 3
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  "$DM" desktop-check --fix
  t_ok grep -q '^notify-send ' "$ACCOUNT_SWITCHER_RUN_LOG"
  out=$("$DM" desktop-check 2>&1)
  t_eq "$?|$out" "0|" "after --fix"
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  "$DM" desktop-check --fix
  t_none '^notify-send ' "$ACCOUNT_SWITCHER_RUN_LOG"
}
t_test "desktop-check names reset entries and --fix restores them, notifying once" t_reset


t_unpatchable() {
  fresh
  sed -i 's|^Exec=/usr/bin/ghostty --gtk-single-instance=true$|Exec=/usr/bin/ghostty --gtk-single-instance=true --new-flag|' "$TMP/sys/com.mitchellh.ghostty.desktop"
  "$DM" desktop-apply
  t_ok test ! -e "$TMP/data/applications/com.mitchellh.ghostty.desktop"
  local out
  out=$("$DM" desktop-check) && t_eq ok "reported" "check passed with an unpatchable entry"
  t_ok grep -qx "can't patch com.mitchellh.ghostty.desktop" <<<"$out"
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  "$DM" desktop-check --fix
  t_eq "$(grep -c '^notify-send ' "$ACCOUNT_SWITCHER_RUN_LOG")" 1
  t_ok grep -q "com.mitchellh.ghostty.desktop" "$ACCOUNT_SWITCHER_RUN_LOG"
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  "$DM" desktop-check --fix
  t_none '^notify-send ' "$ACCOUNT_SWITCHER_RUN_LOG"
}
t_test "an entry whose system file changed is reported once, never written half-patched" t_unpatchable

t_keeps_good_copy() {
  fresh
  "$DM" desktop-apply
  sed -i 's|^Exec=nautilus --new-window %U$|Exec=/usr/bin/nautilus --new-window %U|' "$TMP/sys/org.gnome.Nautilus.desktop"
  "$DM" desktop-apply
  t_ok grep -q "^Exec=$HOME/.local/bin/account-switcher files %U\$" "$TMP/data/applications/org.gnome.Nautilus.desktop"
}
t_test "a working entry is kept when its system file can no longer be patched" t_keeps_good_copy

t_done
