#!/usr/bin/env bash
# The per-mode environment and the account-switcher command, against a scratch HOME.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
TMP=${TEST_TMPDIR:?run through tests/run.sh}/mode
# The parent walk stops here, so the real session above the tests can't answer.
export ACCOUNT_SWITCHER_WALK_ROOT=$$

fresh() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.config/gh" "$TMP/home/.local/share/zoxide" "$TMP/fakes"
  export HOME=$TMP/home ACCOUNT_SWITCHER_RUN_LOG=$TMP/run.log ACCOUNT_SWITCHER_FAKES=$TMP/fakes ACCOUNT_SWITCHER_GH=/opt/gh/bin/gh
  unset XDG_STATE_HOME XDG_DATA_HOME XDG_CONFIG_HOME ACCOUNT_SWITCHER_MODE GIT_CONFIG_GLOBAL GH_CONFIG_DIR \
    AWS_CONFIG_FILE AWS_SHARED_CREDENTIALS_FILE HISTFILE _ZO_DATA_DIR BROWSER HYPRLAND_INSTANCE_SIGNATURE
  printf 'github.com:\n    git_protocol: https\n    users:\n        alex:\n        alex-work:\n        alex-side:\n    user: alex-work\n' >"$HOME/.config/gh/hosts.yml"
  printf 'version: 1\n' >"$HOME/.config/gh/config.yml"
  echo "echo old" >"$HOME/.bash_history"
  echo zo >"$HOME/.local/share/zoxide/db.zo"
  # Omarchy's stock backgrounds, for the default Personal wallpaper.
  mkdir -p "$TMP/omarchy/themes/gruvbox/backgrounds" && echo leaves >"$TMP/omarchy/themes/gruvbox/backgrounds/5-leaves.jpg"
  export OMARCHY_PATH=$TMP/omarchy
  # The example config, set up (tests of the unconfigured case remove config.bash).
  mkdir -p "$HOME/.config/account-switcher" && cp "$PLUGIN/tests/fixtures/config.test.json" "$HOME/.config/account-switcher/config.json"
  "$PLUGIN/bin/account-switcher" setup >/dev/null
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  source "$PLUGIN/lib/mode.bash"
}
unconfigured() {
  rm -f "$HOME/.local/state/account-switcher/config.bash" "$HOME/.config/git/account-switcher-work" "$HOME/.config/git/account-switcher-personal"
  dm_load_config
}

desk() { mkdir -p "$HOME/.local/state/account-switcher" && echo "$1" >"$HOME/.local/state/account-switcher/mode"; }

t_desk_mode() {
  fresh
  t_eq "$(dm_desk_mode)" work "no state file"
  desk personal
  t_eq "$(dm_desk_mode)" personal
  desk banana
  t_eq "$(dm_desk_mode)" work "bad state file"
}
t_test "desk mode defaults to work and follows the state file" t_desk_mode

t_personal_env() {
  fresh
  dm_env personal
  t_eq "$ACCOUNT_SWITCHER_MODE" personal
  t_eq "$GIT_CONFIG_GLOBAL" "$HOME/.config/git/account-switcher-personal"
  t_eq "$GH_CONFIG_DIR" "$HOME/.local/share/account-switcher/gh/alex"
  t_eq "$AWS_CONFIG_FILE" "$HOME/.local/share/account-switcher/aws/config"
  t_eq "$AWS_SHARED_CREDENTIALS_FILE" "$HOME/.local/share/account-switcher/aws/credentials"
  t_eq "$HISTFILE" "$HOME/.local/state/account-switcher/history/bash-personal"
  t_eq "$_ZO_DATA_DIR" "$HOME/.local/share/account-switcher/zoxide/personal"
  t_eq "$BROWSER" "$HOME/.local/bin/account-switcher-open"
  t_eq "$(bash -c 'echo "$GIT_CONFIG_GLOBAL|$_ZO_DATA_DIR|$AWS_CONFIG_FILE"')" \
    "$GIT_CONFIG_GLOBAL|$_ZO_DATA_DIR|$AWS_CONFIG_FILE" "exported to children"
}
t_test "the Personal environment" t_personal_env

t_work_env() {
  fresh
  dm_env personal
  dm_env work
  t_eq "$ACCOUNT_SWITCHER_MODE" work
  t_eq "$GH_CONFIG_DIR" "$HOME/.local/share/account-switcher/gh/alex-work"
  t_eq "$GIT_CONFIG_GLOBAL" "$HOME/.config/git/account-switcher-work"
  t_eq "${AWS_CONFIG_FILE-unset}|${AWS_SHARED_CREDENTIALS_FILE-unset}" "unset|unset"
  dm_env banana
  t_eq "$ACCOUNT_SWITCHER_MODE" work "an unknown mode is Work"
}
t_test "the Work environment drops the AWS files" t_work_env

t_unconfigured() {
  fresh
  unconfigured
  dm_env personal
  t_eq "$ACCOUNT_SWITCHER_MODE" personal
  t_eq "${GH_CONFIG_DIR-unset}|${GIT_CONFIG_GLOBAL-unset}" "unset|unset"
  t_eq "$HISTFILE" "$HOME/.local/state/account-switcher/history/bash-personal"
  t_eq "$(dm_mode_dir work home)" "$HOME"
  t_eq "$(dm_mode_dir personal agent)" "$HOME"
  t_eq "$(dm_exe_mode /opt/google/chrome/chrome)" ""
  t_eq "$(dm_account work)" ""
}
t_test "before setup: no accounts, folders at home, no browser rules" t_unconfigured

t_mode_dirs() {
  fresh
  t_eq "$(dm_mode_dir work home)" "$HOME/Work"
  t_eq "$(dm_mode_dir work terminal)" "$HOME/Work"
  t_eq "$(dm_mode_dir work files)" "$HOME/Work"
  t_eq "$(dm_mode_dir personal home)" "$HOME"
  t_eq "$(dm_mode_dir personal agent)" "$HOME/Projects"
  t_eq "$(dm_mode_dir personal files)" "$HOME"
  t_eq "$(dm_account work)|$(dm_account personal)" "alex-work|alex"
}
t_test "each mode's folders and account come from the config" t_mode_dirs

t_owner_gh_dir() {
  fresh
  t_eq "$(dm_owner_gh_dir side-org personal)" "$HOME/.local/share/account-switcher/gh/alex-side"
  t_eq "$(dm_owner_gh_dir Side-Org personal)" "$HOME/.local/share/account-switcher/gh/alex-side"
  t_eq "$(dm_owner_gh_dir side-org work)" ""
  t_eq "$(dm_owner_gh_dir work-org work)" ""
}
t_test "an account's owner gets its own gh folder, in its mode only" t_owner_gh_dir

t_print_env() {
  fresh
  eval "$("$PLUGIN/bin/account-switcher" env personal)"
  t_eq "$ACCOUNT_SWITCHER_MODE|$GH_CONFIG_DIR" "personal|$HOME/.local/share/account-switcher/gh/alex"
  eval "$("$PLUGIN/bin/account-switcher" env work)"
  t_eq "$ACCOUNT_SWITCHER_MODE|${AWS_CONFIG_FILE-unset}" "work|unset"
}
t_test "account-switcher env prints lines a shell can eval" t_print_env

t_exe_mode() {
  fresh
  t_eq "$(dm_exe_mode /opt/google/chrome/chrome)" work
  t_eq "$(dm_exe_mode /usr/lib/chromium/chromium)" personal
  t_eq "$(dm_exe_mode /usr/bin/bash)" ""
}
t_test "browser executables map to their modes" t_exe_mode

t_requester_own() {
  fresh
  t_eq "$(ACCOUNT_SWITCHER_MODE=personal dm_requester_mode)" personal
}
t_test "the requester's own mode wins" t_requester_own

t_requester_parent() {
  fresh
  local lib=$PLUGIN/lib/mode.bash
  t_eq "$(env ACCOUNT_SWITCHER_MODE=personal bash -c "unset ACCOUNT_SWITCHER_MODE; bash -c 'source $lib; dm_requester_mode'; true")" personal
}
t_test "a mode in an ancestor's environment is found" t_requester_parent

t_requester_desk() {
  fresh
  desk personal
  t_eq "$(env -u ACCOUNT_SWITCHER_MODE bash -c "source $PLUGIN/lib/mode.bash; dm_requester_mode")" personal
}
t_test "with no requester mode, the desk mode is used" t_requester_desk

t_switch() {
  fresh
  desk work
  "$PLUGIN/bin/account-switcher" switch work
  t_eq "$(cat "$ACCOUNT_SWITCHER_RUN_LOG")" "" "already in work"
  "$PLUGIN/bin/account-switcher" switch personal
  t_eq "$(cat "$ACCOUNT_SWITCHER_RUN_LOG")" "hyprctl dispatch function() if account_switcher then account_switcher.switch('personal') end end"
  t_ok test "$("$PLUGIN/bin/account-switcher" switch banana; echo $?)" = 2
}
t_test "switching dispatches only when the mode changes" t_switch

t_setup() {
  fresh
  local gh=$HOME/.local/share/account-switcher/gh
  t_eq "$(grep -E '^ +user:' "$gh/alex/hosts.yml")" "    user: alex"
  t_eq "$(grep -E '^ +user:' "$gh/alex-side/hosts.yml")" "    user: alex-side"
  t_eq "$(grep -E '^ +user:' "$gh/alex-work/hosts.yml")" "    user: alex-work"
  t_eq "$(grep -c '^        ' "$gh/alex-side/hosts.yml")" 3 "users map kept"
  t_eq "$(cat "$gh"/*/hosts.yml | grep -ci token)" 0 "no tokens"
  t_eq "$(ls "$gh" | tr '\n' ' ')" "alex alex-side alex-work " "only the configured accounts"
  t_eq "$(readlink "$gh/alex/config.yml")" "$HOME/.config/gh/config.yml"
  t_eq "$(stat -c %a "$HOME/.local/share/account-switcher/aws/config") $(stat -c %s "$HOME/.local/share/account-switcher/aws/credentials")" "600 0"
  t_eq "$(cat "$HOME/.local/state/account-switcher/history/bash-personal")" "echo old"
  t_eq "$(cat "$HOME/.local/share/account-switcher/zoxide/work/db.zo")" zo
  t_ok test -d "$HOME/Work/Downloads" -a -d "$HOME/Work/Pictures" -a -d "$HOME/Work/Videos"
  t_eq "$(cat "$HOME/.local/share/account-switcher/wallpapers/personal.jpg")" leaves "a Personal wallpaper to start with"
  echo mine >"$HOME/.local/share/account-switcher/wallpapers/personal.jpg"
  echo "echo new" >"$HOME/.bash_history"
  "$PLUGIN/bin/account-switcher" setup
  t_eq "$(cat "$HOME/.local/state/account-switcher/history/bash-work")" "echo old" "seeded only once"
  t_eq "$(cat "$HOME/.local/share/account-switcher/wallpapers/personal.jpg")" mine "never replaced"
}
t_test "setup makes token-free gh dirs, empty AWS files and seeds history once" t_setup


t_tmux_per_mode() {
  fresh
  export XDG_RUNTIME_DIR=$TMP/run
  mkdir -p "$XDG_RUNTIME_DIR"
  dm_env work
  local work=$TMUX_TMPDIR
  dm_env personal
  t_eq "$TMUX_TMPDIR" "$XDG_RUNTIME_DIR/account-switcher/tmux-personal"
  t_eq "$work" "$XDG_RUNTIME_DIR/account-switcher/tmux-work"
  t_ok test -d "$TMUX_TMPDIR"
  t_eq "$(stat -c %a "$TMUX_TMPDIR")" 700
  t_eq "$HERDR_SOCKET_PATH" "$XDG_RUNTIME_DIR/account-switcher/herdr-personal.sock"
}
t_test "each mode gets its own tmux and herdr servers" t_tmux_per_mode

t_browser_beats_stray_env() {
  fresh
  local lib=$PLUGIN/lib/mode.bash
  # The test shell plays a Chrome that was started with a Personal terminal's environment;
  # xdg-open (bash) inherited that, and the link handler asks who is calling.
  export ACCOUNT_SWITCHER_FAKE_EXE="$BASHPID=/opt/google/chrome/chrome"
  t_eq "$(env ACCOUNT_SWITCHER_MODE=personal bash -c "bash -c 'unset ACCOUNT_SWITCHER_MODE; source $lib; ACCOUNT_SWITCHER_MODE=personal dm_requester_mode'; true")" work
}
t_test "a browser that started the request wins over a mode it inherited" t_browser_beats_stray_env

t_setup_drops_tokens() {
  fresh
  printf '    oauth_token: gho_secret\n' >>"$HOME/.config/gh/hosts.yml"
  "$PLUGIN/bin/account-switcher" setup
  t_ok compgen -G "$HOME/.local/share/account-switcher/gh/*/hosts.yml"
  t_eq "$(cat "$HOME"/.local/share/account-switcher/gh/*/hosts.yml | grep -c oauth_token)" 0
}
t_test "setup never copies a token line" t_setup_drops_tokens

t_focused_ancestor() {
  fresh
  echo "{\"pid\":$BASHPID}" >"$TMP/fakes/hyprctl-activewindow.out"
  t_ok bash -c "source $PLUGIN/lib/mode.bash; dm_focused_is_ancestor"
  echo '{"pid":1}' >"$TMP/fakes/hyprctl-activewindow.out"
  bash -c "source $PLUGIN/lib/mode.bash; dm_focused_is_ancestor" && t_eq ok "not an ancestor" "pid 1 counted"
  return 0
}
t_test "whether the focused window's process started the request" t_focused_ancestor

t_switch_confirmed() {
  fresh
  desk work
  "$PLUGIN/bin/account-switcher" switch personal --confirmed
  t_eq "$(cat "$ACCOUNT_SWITCHER_RUN_LOG")" "hyprctl dispatch function() if account_switcher then account_switcher.switch('personal', { confirmed = true }) end end"
}
t_test "a confirmed switch goes through a screen share" t_switch_confirmed

t_done
