#!/usr/bin/env bash
# account-switcher install / uninstall against a scratch HOME shaped like a fresh Omarchy desk.
# Outside commands (hyprctl, systemctl, omarchy's) are recorded, never run.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
DM=$PLUGIN/bin/account-switcher
TMP=${TEST_TMPDIR:?run through tests/run.sh}/install
LOG=$TMP/run.log
export ACCOUNT_SWITCHER_WALK_ROOT=$$

fresh() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.config/hypr" "$TMP/home/.config/omarchy" "$TMP/home/.config/git" "$TMP/bin" "$TMP/fakes" "$TMP/sys" "$TMP/omarchy"
  export HOME=$TMP/home ACCOUNT_SWITCHER_RUN_LOG=$LOG ACCOUNT_SWITCHER_FAKES=$TMP/fakes ACCOUNT_SWITCHER_GH=/opt/gh/bin/gh
  export ACCOUNT_SWITCHER_SYSTEM_APPS=$TMP/sys ACCOUNT_SWITCHER_OMARCHY_APPS=$TMP/omarchy ACCOUNT_SWITCHER_PING_WAIT=0
  unset XDG_STATE_HOME XDG_DATA_HOME XDG_CONFIG_HOME ACCOUNT_SWITCHER_MODE HYPRLAND_INSTANCE_SIGNATURE
  : >"$LOG"
  local cmd
  for cmd in ghostty omarchy-shell; do printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/$cmd" && chmod +x "$TMP/bin/$cmd"; done
  export PATH=$TMP/bin:$PATH
  echo ok >"$TMP/fakes/omarchy-shell-notifications.out"
  echo '[{"id": "account-switcher.notifications"}]' >"$TMP/fakes/omarchy-plugin-list.out"
  cp "$PLUGIN"/tests/fixtures/applications/*.desktop "$TMP/sys/"
  cp "$PLUGIN"/tests/fixtures/omarchy/*.desktop "$TMP/omarchy/"
  printf -- '-- ~/.config/hypr files.\nrequire("hypr.bindings")\n' >"$HOME/.config/hypr/hyprland.lua"
  cat >"$HOME/.bashrc" <<'RC'
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
source "$OMARCHY_PATH/default/bash/rc"

# Add your own exports, aliases, and functions here.
alias p='python'
RC
  printf 'screencopy {\n    allow_token_by_default = true\n    custom_picker_binary = /usr/local/bin/my-picker\n}\n' >"$HOME/.config/hypr/xdph.conf"
  printf '[user]\n\tname = Alex\n' >"$HOME/.config/git/config"
  echo '{"bar":{"layout":{"left":[{"id":"omarchy.launcher"},{"id":"omarchy.workspaces"}],"center":[{"id":"omarchy.clock"}],"right":[]}},"plugins":[]}' \
    >"$HOME/.config/omarchy/shell.json"
}
configured() { mkdir -p "$HOME/.config/account-switcher" && cp "$PLUGIN/tests/fixtures/config.test.json" "$HOME/.config/account-switcher/config.json"; }
sums() { (cd "$HOME" && sha256sum .bashrc .config/hypr/hyprland.lua .config/hypr/xdph.conf .config/git/config .config/omarchy/shell.json); }
backups() { find "$HOME" -name '*.bak.*' | wc -l; }

t_fresh() {
  fresh
  local before out
  before=$(sums)
  out=$("$DM" install 2>&1)
  t_eq $? 0
  t_ok grep -q 'config.json' <<<"$out"
  t_ok grep -qF "$PLUGIN/bin/account-switcher install again" <<<"$out"
  t_eq "$(stat -c %a "$HOME/.config/account-switcher/config.json")" 600
  t_ok cmp -s "$PLUGIN/config.example.json" "$HOME/.config/account-switcher/config.json"
  t_eq "$(sums)" "$before" "nothing else touched"
}
t_test "without a config, install writes the example and stops" t_fresh

t_example_untouched() {
  fresh
  "$DM" install >/dev/null 2>&1
  local before out
  before=$(sums)
  out=$("$DM" install 2>&1) && t_eq ok refused "the untouched example"
  t_ok grep -q "still the example's" <<<"$out"
  t_eq "$(sums)" "$before" "nothing installed"
  t_ok test ! -e "$HOME/.config/git/account-switcher-work.inc"
}
t_test "the example as written is refused: install never applies its placeholder identity" t_example_untouched

t_install() {
  fresh
  configured
  local out
  out=$("$DM" install)
  t_eq $? 0
  # Next steps: gh in a terminal that has the switcher; how to remove it again.
  t_ok grep -q 'new terminal.*gh auth login' <<<"$out"
  t_ok grep -q 'account-switcher uninstall.*omarchy plugin remove' <<<"$out"
  local h=$HOME/.config/hypr bin=$HOME/.local/bin
  t_eq "$(readlink "$h/account-switcher.lua")" "$PLUGIN/hypr/account-switcher.lua"
  t_eq "$(readlink "$h/account-switcher")" "$PLUGIN/hypr/account-switcher"
  t_eq "$(grep -cxF 'require("default.hypr.require_optional").module("hypr.account-switcher")' "$h/hyprland.lua")" 1
  t_eq "$(git config --file "$HOME/.config/git/config" hook.account-switcher-guard.event)" prepare-commit-msg
  t_ok grep -qF "$bin/account-switcher-commit-guard" "$HOME/.config/git/config"
  # Before Omarchy's rc, and after it.
  local pre post rc
  pre=$(grep -n 'shell/pre.bash' "$HOME/.bashrc" | cut -d: -f1)
  rc=$(grep -n 'default/bash/rc' "$HOME/.bashrc" | cut -d: -f1)
  post=$(grep -n 'shell/post.bash' "$HOME/.bashrc" | cut -d: -f1)
  t_ok test -n "$pre" -a -n "$post"
  t_ok test "$pre" -lt "$rc" -a "$post" -gt "$rc"
  t_ok grep -qF "source \"$PLUGIN/shell/pre.bash\"" "$HOME/.bashrc"
  # A plugin under ~ (the usual ~/.config/omarchy/plugins) is written as $HOME/….
  t_eq "$(bash -c 'source "$1/lib/mode.bash"; source "$1/lib/config.bash"; source "$1/lib/install.bash"; DM_PLUGIN=$HOME/.config/omarchy/plugins/account-switcher; hook_line pre' _ "$PLUGIN")" \
    '[[ -r "$HOME/.config/omarchy/plugins/account-switcher/shell/pre.bash" ]] && source "$HOME/.config/omarchy/plugins/account-switcher/shell/pre.bash"'
  t_ok grep -qx "    custom_picker_binary = $bin/account-switcher-share-picker" "$h/xdph.conf"
  t_eq "$(cat "$HOME/.local/state/account-switcher/picker")" /usr/local/bin/my-picker
  t_ok grep -q 'systemctl --user try-restart xdg-desktop-portal-hyprland.service' "$LOG"
  t_eq "$(jq -c '[.bar.layout.left[].id]' "$HOME/.config/omarchy/shell.json")" '["omarchy.launcher","account-switcher"]'
  t_ok test -L "$bin/account-switcher"
  t_ok test -f "$HOME/.local/share/applications/omarchy-browser.desktop"
  t_ok test -f "$HOME/.config/omarchy/plugins/account-switcher.notifications/Service.qml"
  t_ok grep -qxF 'omarchy-plugin-enable account-switcher.notifications' "$LOG"
  # The shell finds the new copy before it's asked to turn it on.
  local rescan enable
  rescan=$(grep -nxF 'omarchy-shell shell rescanPlugins' "$LOG" | head -n1 | cut -d: -f1)
  enable=$(grep -nxF 'omarchy-plugin-enable account-switcher.notifications' "$LOG" | head -n1 | cut -d: -f1)
  t_ok test -n "$rescan" -a -n "$enable"
  t_ok test "${rescan:-99}" -lt "${enable:-0}"
  t_ok test -s "$HOME/.local/state/account-switcher/config.bash"
}
t_test "install puts every piece in place" t_install

t_enable_fails() {
  fresh
  configured
  echo 1 >"$TMP/fakes/omarchy-plugin-enable-account-switcher.notifications.status"
  local out
  out=$("$DM" install 2>&1)
  t_eq $? 0
  t_ok grep -qF 'omarchy plugin enable account-switcher.notifications' <<<"$out"
}
t_test "when the shell can't turn the notification copy on, install says how" t_enable_fails

t_no_shell_uninstall() {
  fresh
  configured
  "$DM" install >/dev/null
  local f=$HOME/.config/omarchy/shell.json
  # The copy on, as Omarchy records it; then uninstall runs with no shell to ask.
  jq '.plugins = [{"id": "account-switcher.notifications"}] | .disabledPlugins = ["omarchy.notifications"]
    | .cloneSourceRestores = ["account-switcher.notifications"]' "$f" >"$TMP/s" && mv "$TMP/s" "$f"
  echo 1 >"$TMP/fakes/omarchy-plugin-enable-omarchy.notifications.status"
  "$DM" uninstall >/dev/null 2>&1
  t_eq "$(jq -c '[.plugins[]?]' "$f")" '[]'
  t_eq "$(jq -c '.disabledPlugins // []' "$f")" '[]'
  t_eq "$(jq -c 'has("cloneSourceRestores")' "$f")" false
  t_ok test ! -e "$HOME/.config/omarchy/plugins/account-switcher.notifications"
}
t_test "uninstall with the shell down still leaves Omarchy's own notifications on" t_no_shell_uninstall

t_history() {
  fresh
  configured
  printf 'ls\ncd /tmp\n' >"$HOME/.bash_history"
  "$DM" install >/dev/null
  local h=$HOME/.local/state/account-switcher/history
  # Typed in each mode since install (each mode's file began as a copy of ~/.bash_history).
  printf 'git status\n' >>"$h/bash-work"
  printf 'steam\n' >>"$h/bash-personal"
  "$DM" uninstall --purge >/dev/null
  t_eq "$(cat "$HOME/.bash_history")" $'ls\ncd /tmp\ngit status\nsteam'
}
t_test "uninstall puts what was typed in each mode back into ~/.bash_history, before any purge" t_history

t_twice() {
  fresh
  configured
  "$DM" install >/dev/null
  local before n
  before=$(sums)
  n=$(backups)
  "$DM" install >/dev/null
  t_eq $? 0
  t_eq "$(sums)" "$before" "a second install changes nothing"
  t_eq "$(backups)" "$n" "and backs nothing up again"
  t_eq "$(grep -c 'shell/pre.bash' "$HOME/.bashrc")" 1
}
t_test "installing twice changes nothing the second time" t_twice

t_existing_dir() {
  fresh
  configured
  mkdir -p "$HOME/.config/hypr/account-switcher" && echo old >"$HOME/.config/hypr/account-switcher/desk.lua"
  "$DM" install >/dev/null
  t_ok test -L "$HOME/.config/hypr/account-switcher"
  local aside
  aside=$(ls -d "$HOME"/.config/hypr/account-switcher.bak.* 2>/dev/null | head -n1)
  t_eq "$(cat "$aside/desk.lua")" old
}
t_test "an old copy of the Hyprland side is moved aside, not lost" t_existing_dir

t_invalid_config() {
  fresh
  configured
  local before
  before=$(sums)
  echo '{"work": {}}' >"$HOME/.config/account-switcher/config.json"
  "$DM" install >/dev/null 2>&1 && t_eq ok refused "a broken config"
  t_eq "$(sums)" "$before"
  t_ok test ! -e "$HOME/.config/hypr/account-switcher.lua"
}
t_test "a broken config stops install before anything changes" t_invalid_config

t_uninstall() {
  fresh
  configured
  mkdir -p "$HOME/.config/hypr/account-switcher" && echo old >"$HOME/.config/hypr/account-switcher/desk.lua"
  local before shell
  before=$(cd "$HOME" && sha256sum .bashrc .config/hypr/hyprland.lua .config/hypr/xdph.conf .config/git/config)
  shell=$(jq -S .bar "$HOME/.config/omarchy/shell.json")
  "$DM" install >/dev/null
  # What `omarchy plugin enable account-switcher.notifications` (recorded, not run) would have done.
  jq '.plugins = [{"id": "account-switcher.notifications"}]' "$HOME/.config/omarchy/shell.json" >"$TMP/s" && mv "$TMP/s" "$HOME/.config/omarchy/shell.json"
  "$DM" uninstall >/dev/null
  t_eq $? 0
  t_eq "$(cd "$HOME" && sha256sum .bashrc .config/hypr/hyprland.lua .config/hypr/xdph.conf .config/git/config)" "$before"
  t_eq "$(jq -S .bar "$HOME/.config/omarchy/shell.json")" "$shell"
  t_ok test ! -e "$HOME/.config/hypr/account-switcher.lua"
  t_eq "$(cat "$HOME/.config/hypr/account-switcher/desk.lua")" old "the old copy is back"
  t_ok test ! -e "$HOME/.local/bin/account-switcher"
  t_eq "$(grep -l '^X-AccountSwitcher=managed' "$HOME"/.local/share/applications/*.desktop 2>/dev/null | wc -l)" 0
  t_ok test ! -e "$HOME/.config/omarchy/plugins/account-switcher.notifications"
  t_ok grep -qxF 'omarchy-plugin-enable omarchy.notifications' "$LOG"
  # Kept without --purge.
  t_ok test -f "$HOME/.config/account-switcher/config.json"
  "$DM" uninstall --purge >/dev/null
  t_ok test ! -e "$HOME/.config/account-switcher"
  t_ok test ! -e "$HOME/.local/state/account-switcher"
  t_ok test ! -e "$HOME/.config/git/account-switcher-work.inc"
  t_ok test ! -e "$HOME/.config/git/account-switcher-work"
}
t_test "uninstall takes back exactly what install did; --purge also the config and state" t_uninstall

t_purge_git_settings() {
  fresh
  configured
  "$DM" install >/dev/null
  local g=$HOME/.config/git out
  # Set with `git config --global` in a Personal terminal.
  GIT_CONFIG_GLOBAL=$g/account-switcher-personal git config --global alias.co checkout
  out=$("$DM" uninstall --purge 2>&1)
  t_ok test ! -e "$g/account-switcher-personal.inc"
  t_ok test ! -e "$g/account-switcher-work"
  t_eq "$(git config -f "$g/account-switcher-personal" alias.co)" checkout "kept: it holds the user's own settings"
  t_ok grep -qF 'account-switcher-personal' <<<"$out"
}
t_test "--purge keeps a mode's global git file once the user has put settings in it, and says so" t_purge_git_settings

t_no_picker() {
  fresh
  configured
  printf 'screencopy {\n    allow_token_by_default = true\n}\n' >"$HOME/.config/hypr/xdph.conf"
  local before
  before=$(sha256sum <"$HOME/.config/hypr/xdph.conf")
  "$DM" install >/dev/null
  t_ok grep -qx "    custom_picker_binary = $HOME/.local/bin/account-switcher-share-picker" "$HOME/.config/hypr/xdph.conf"
  t_eq "$(cat "$HOME/.local/state/account-switcher/picker")" ""
  "$DM" uninstall >/dev/null
  t_eq "$(sha256sum <"$HOME/.config/hypr/xdph.conf")" "$before"
  # No xdph.conf at all.
  fresh
  configured
  rm "$HOME/.config/hypr/xdph.conf"
  "$DM" install >/dev/null
  t_ok grep -q "custom_picker_binary = $HOME/.local/bin/account-switcher-share-picker" "$HOME/.config/hypr/xdph.conf"
  "$DM" uninstall >/dev/null
  t_ok test ! -e "$HOME/.config/hypr/xdph.conf"
}
t_test "the share picker: added to xdph.conf and taken out again, whatever was there" t_no_picker

t_own_files() {
  fresh
  configured
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
  printf '#!/bin/sh\nexec /usr/bin/code --ozone-platform=wayland "$@"\n' >"$HOME/.local/bin/code"
  chmod +x "$HOME/.local/bin/code"
  printf '[Desktop Entry]\nName=Chromium\nType=Application\nExec=chromium --my-flag %%U\n' >"$HOME/.local/share/applications/chromium.desktop"
  printf '[Default Applications]\nx-scheme-handler/mailto=HEY.desktop\n' >"$HOME/.config/hyprland-mimeapps.list"
  local code chromium mime
  code=$(cat "$HOME/.local/bin/code") chromium=$(cat "$HOME/.local/share/applications/chromium.desktop")
  mime=$(cat "$HOME/.config/hyprland-mimeapps.list")
  "$DM" install >/dev/null
  t_ok test -L "$HOME/.local/bin/code"
  t_ok grep -qx 'x-scheme-handler/mailto=account-switcher-mailto.desktop' "$HOME/.config/hyprland-mimeapps.list"
  "$DM" uninstall >/dev/null
  t_eq "$(cat "$HOME/.local/bin/code")" "$code" "the user's own code wrapper is back"
  t_ok test ! -L "$HOME/.local/bin/code"
  t_eq "$(cat "$HOME/.local/share/applications/chromium.desktop")" "$chromium" "their own Chromium entry is back"
  t_eq "$(cat "$HOME/.config/hyprland-mimeapps.list")" "$mime" "and their mail handler"
}
t_test "install keeps a user's own command, launcher entry and mail handler, and uninstall puts them back" t_own_files

t_enabled_widget() {
  fresh
  configured
  # "Enable now?" said yes during omarchy plugin add: the badge is already on the bar.
  echo '{"bar":{"layout":{"left":[{"id":"omarchy.launcher"},{"id":"omarchy.workspaces"}],"center":[],"right":[{"id":"account-switcher"}]}},"plugins":[]}' \
    >"$HOME/.config/omarchy/shell.json"
  "$DM" install >/dev/null
  t_eq "$(jq -c '[.bar.layout[][].id]' "$HOME/.config/omarchy/shell.json")" '["omarchy.launcher","account-switcher"]'
  "$DM" uninstall >/dev/null
  t_eq "$(jq -c '[.bar.layout[][].id]' "$HOME/.config/omarchy/shell.json")" '["omarchy.launcher","omarchy.workspaces"]'
}
t_test "with the badge already enabled, Omarchy's workspace buttons still give way (and come back)" t_enabled_widget

t_no_workspaces() {
  fresh
  configured
  echo '{"bar":{"layout":{"left":[{"id":"omarchy.launcher"}],"center":[],"right":[]}},"plugins":[]}' >"$HOME/.config/omarchy/shell.json"
  "$DM" install >/dev/null
  t_eq "$(jq -c '[.bar.layout[][].id]' "$HOME/.config/omarchy/shell.json")" '["account-switcher","omarchy.launcher"]'
  "$DM" uninstall >/dev/null
  t_eq "$(jq -c '[.bar.layout[][].id]' "$HOME/.config/omarchy/shell.json")" '["omarchy.launcher"]' "nothing the user never had"
}
t_test "a bar without Omarchy's workspace buttons gets the badge, and gets nothing extra back" t_no_workspaces

t_symlinked() {
  fresh
  configured
  # Dotfiles kept elsewhere and linked in (stow and friends).
  local dots=$TMP/dotfiles f
  mkdir -p "$dots"
  for f in .bashrc .config/hypr/hyprland.lua .config/hypr/xdph.conf .config/git/config .config/omarchy/shell.json; do
    mv "$HOME/$f" "$dots/${f//\//_}" && ln -s "$dots/${f//\//_}" "$HOME/$f"
  done
  local before
  before=$(cd "$dots" && sha256sum .bashrc .config_hypr_hyprland.lua .config_hypr_xdph.conf .config_git_config)
  "$DM" install >/dev/null
  for f in .bashrc .config/hypr/hyprland.lua .config/hypr/xdph.conf .config/git/config .config/omarchy/shell.json; do
    t_ok test -L "$HOME/$f"
  done
  t_ok grep -q 'shell/pre.bash' "$dots/.bashrc"
  t_ok grep -q 'account-switcher-guard' "$dots/.config_git_config"
  t_ok grep -q 'account-switcher-share-picker' "$dots/.config_hypr_xdph.conf"
  "$DM" uninstall >/dev/null
  for f in .bashrc .config/hypr/hyprland.lua .config/hypr/xdph.conf .config/git/config .config/omarchy/shell.json; do
    t_ok test -L "$HOME/$f"
  done
  t_eq "$(cd "$dots" && sha256sum .bashrc .config_hypr_hyprland.lua .config_hypr_xdph.conf .config_git_config)" "$before"
}
t_test "linked dotfiles stay linked, and their real files get the edits and lose them again" t_symlinked

t_odd_bar() {
  fresh
  configured
  local f=$HOME/.config/omarchy/shell.json
  # A section that isn't a list (Omarchy's bar copes with that).
  jq '.bar.layout.center = null' "$f" >"$TMP/s" && mv "$TMP/s" "$f"
  "$DM" install >/dev/null 2>&1
  t_eq "$(jq -c '[.bar.layout[]?[]?.id]' "$f")" '["omarchy.launcher","account-switcher"]'
  t_ok test ! -e "$f.new"
  "$DM" uninstall >/dev/null 2>&1
  t_ok jq -e .bar "$f"
  t_eq "$(jq -c '[.bar.layout[]?[]?.id]' "$f")" '["omarchy.launcher","omarchy.workspaces"]'
  t_eq "$(jq -c '.bar.layout.center' "$f")" null
  t_ok test ! -e "$f.new"
}
t_test "a bar section that isn't a list doesn't stop install, and uninstall never empties shell.json" t_odd_bar

t_install_without_browser() {
  fresh
  configured
  jq 'del(.work.browser, .personal.browser)' "$HOME/.config/account-switcher/config.json" >"$TMP/c" && cat "$TMP/c" >"$HOME/.config/account-switcher/config.json"
  local out
  out=$("$DM" install 2>&1)
  t_eq $? 0 "install with no browser chosen yet"
  t_ok grep -qF "Choose apps" <<<"$out"
}
t_test "install finishes before any browser is chosen, and says where to choose them" t_install_without_browser

t_done
