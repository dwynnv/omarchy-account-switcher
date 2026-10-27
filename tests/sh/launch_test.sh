#!/usr/bin/env bash
# Launching per mode: terminals, agents, the file manager, tmux, the Ghostty wrapper and the
# generated .desktop entries. Commands are recorded (ACCOUNT_SWITCHER_RUN_LOG), never run.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
TMP=${TEST_TMPDIR:?run through tests/run.sh}/launch
export ACCOUNT_SWITCHER_WALK_ROOT=$$
DM=$PLUGIN/bin/account-switcher

fresh() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.local/state/account-switcher" "$TMP/home/Work/Files" "$TMP/home/Projects" "$TMP/fakes" "$TMP/sys"
  export HOME=$TMP/home ACCOUNT_SWITCHER_RUN_LOG=$TMP/run.log ACCOUNT_SWITCHER_FAKES=$TMP/fakes
  unset XDG_STATE_HOME XDG_DATA_HOME XDG_CONFIG_HOME ACCOUNT_SWITCHER_MODE
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  mkdir -p "$HOME/.config/account-switcher" && cp "$PLUGIN/tests/fixtures/config.test.json" "$HOME/.config/account-switcher/config.json"
  ACCOUNT_SWITCHER_GH=/opt/gh/bin/gh "$PLUGIN/bin/account-switcher" setup >/dev/null && : >"$ACCOUNT_SWITCHER_RUN_LOG"
  echo '{"class":"google-chrome"}' >"$TMP/fakes/hyprctl-activewindow.out"
}
desk() { echo "$1" >"$HOME/.local/state/account-switcher/mode"; }
fake() { printf '%s\n' "$2" >"$TMP/fakes/$1.out"; }
last_line() { tail -n1 "$ACCOUNT_SWITCHER_RUN_LOG"; }
SWITCH="hyprctl dispatch function() if account_switcher then account_switcher.switch"

t_terminal_personal() {
  fresh
  desk personal
  "$DM" terminal
  t_eq "$(last_line)" "setsid uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.term-personal --dir=$HOME"
  t_none "$SWITCH" "$ACCOUNT_SWITCHER_RUN_LOG"
}
t_test "a Personal terminal opens in ~ with the Personal class" t_terminal_personal

t_terminal_cwd() {
  fresh
  desk work
  fake hyprctl-activewindow '{"class":"org.omarchy.term-work"}'
  fake omarchy-cmd-terminal-cwd "$HOME/Work/Files"
  "$DM" terminal
  t_eq "$(last_line)" "setsid uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.term-work --dir=$HOME/Work/Files"
  fake hyprctl-activewindow '{"class":"org.omarchy.term-personal"}'
  "$DM" terminal
  t_eq "$(last_line)" "setsid uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.term-work --dir=$HOME/Work" "other mode's terminal focused"
}
t_test "a terminal opens in the focused same-mode terminal's folder" t_terminal_cwd

t_terminal_other_mode() {
  fresh
  desk personal
  "$DM" terminal --mode=work
  t_eq "$(grep -c "$SWITCH('work')" "$ACCOUNT_SWITCHER_RUN_LOG")" 1
  t_eq "$(last_line)" "setsid uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.term-work --dir=$HOME/Work"
}
t_test "a terminal of the other mode switches the desk first" t_terminal_other_mode

t_agent() {
  fresh
  desk personal
  "$DM" agent
  t_eq "$(last_line)" "setsid uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.agent-personal --dir=$HOME/Projects -e omarchy-agent --inline"
  desk work
  "$DM" agent
  t_eq "$(last_line)" "setsid uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.agent-work --dir=$HOME/Work -e omarchy-agent --inline"
}
t_test "agents start in ~/Projects (Personal) or ~/Work (Work)" t_agent

t_files() {
  fresh
  desk work
  "$DM" files
  t_eq "$(last_line)" "env -u ACCOUNT_SWITCHER_MODE -u GIT_CONFIG_GLOBAL -u GH_CONFIG_DIR -u AWS_CONFIG_FILE -u AWS_SHARED_CREDENTIALS_FILE -u HISTFILE -u _ZO_DATA_DIR -u BROWSER -u TMUX_TMPDIR -u HERDR_SOCKET_PATH setsid uwsm-app -- nautilus --new-window $HOME/Work"
  desk personal
  "$DM" files
  t_eq "$(last_line)" "env -u ACCOUNT_SWITCHER_MODE -u GIT_CONFIG_GLOBAL -u GH_CONFIG_DIR -u AWS_CONFIG_FILE -u AWS_SHARED_CREDENTIALS_FILE -u HISTFILE -u _ZO_DATA_DIR -u BROWSER -u TMUX_TMPDIR -u HERDR_SOCKET_PATH setsid uwsm-app -- nautilus --new-window $HOME"
  fake omarchy-cmd-terminal-cwd "$HOME/Projects"
  "$DM" files --cwd
  t_eq "$(last_line)" "env -u ACCOUNT_SWITCHER_MODE -u GIT_CONFIG_GLOBAL -u GH_CONFIG_DIR -u AWS_CONFIG_FILE -u AWS_SHARED_CREDENTIALS_FILE -u HISTFILE -u _ZO_DATA_DIR -u BROWSER -u TMUX_TMPDIR -u HERDR_SOCKET_PATH setsid uwsm-app -- nautilus --new-window $HOME/Projects"
  "$DM" files /tmp file:///etc
  t_eq "$(last_line)" "env -u ACCOUNT_SWITCHER_MODE -u GIT_CONFIG_GLOBAL -u GH_CONFIG_DIR -u AWS_CONFIG_FILE -u AWS_SHARED_CREDENTIALS_FILE -u HISTFILE -u _ZO_DATA_DIR -u BROWSER -u TMUX_TMPDIR -u HERDR_SOCKET_PATH setsid uwsm-app -- nautilus --new-window /tmp file:///etc"
}
t_test "the file manager opens the mode's folder, or the terminal's with --cwd" t_files

t_ghostty_plain() {
  fresh
  desk personal
  fake busctl 'b false'
  "$PLUGIN/bin/account-switcher-ghostty"
  t_eq "$(last_line)" "/usr/bin/ghostty --gtk-single-instance=true --class=org.omarchy.term-personal --working-directory=$HOME"
  fake busctl 'b true'
  "$PLUGIN/bin/account-switcher-ghostty" --working-directory=/tmp
  t_eq "$(last_line)" "/usr/bin/ghostty +new-window --class=org.omarchy.term-personal --working-directory=/tmp"
}
t_test "a classless Ghostty launch becomes a terminal of the mode" t_ghostty_plain

t_ghostty_class() {
  fresh
  desk work
  "$PLUGIN/bin/account-switcher-ghostty" --class=org.omarchy.btop -e btop
  t_eq "$(last_line)" "/usr/bin/ghostty --gtk-single-instance=true --class=org.omarchy.btop -e btop"
  t_none busctl "$ACCOUNT_SWITCHER_RUN_LOG"
  fake busctl 'b true'
  "$PLUGIN/bin/account-switcher-ghostty" --class=org.omarchy.term-work --working-directory=/tmp --title=x
  t_eq "$(last_line)" "/usr/bin/ghostty +new-window --class=org.omarchy.term-work --working-directory=/tmp --title=x"
}
t_test "with a class, Ghostty starts or joins its own instance" t_ghostty_class

t_desktop_terminals() {
  fresh
  cp "$PLUGIN/tests/fixtures/applications/com.mitchellh.ghostty.desktop" "$PLUGIN/tests/fixtures/applications/org.gnome.Nautilus.desktop" "$TMP/sys/"
  ACCOUNT_SWITCHER_SYSTEM_APPS=$TMP/sys XDG_DATA_HOME=$TMP/data "$DM" desktop-apply
  local apps=$TMP/data/applications g n
  g=$apps/com.mitchellh.ghostty.desktop
  t_eq "$(grep -c "^Exec=$HOME/.local/bin/account-switcher-ghostty\$" "$g")" "$(grep -c '^Exec=' "$TMP/sys/com.mitchellh.ghostty.desktop")" "every Ghostty Exec"
  t_eq "$(grep -c '^DBusActivatable' "$g")" 0
  t_ok grep -q '^X-TerminalArgAppId=--class=$' "$g"
  t_ok grep -q '^Categories=.*TerminalEmulator' "$g"
  t_ok grep -q '^StartupWMClass=com.mitchellh.ghostty$' "$g"
  t_ok grep -q '^X-AccountSwitcher=managed$' "$g"
  n=$apps/org.gnome.Nautilus.desktop
  t_ok grep -q "^Exec=$HOME/.local/bin/account-switcher files %U\$" "$n"
  t_ok grep -q "^Exec=$HOME/.local/bin/account-switcher files\$" "$n"
  t_eq "$(grep -c '^DBusActivatable' "$n")" 0
  t_ok grep -q '^MimeType=inode/directory;' "$n"
  local m
  for m in term-work term-personal agent-work agent-personal; do
    t_ok grep -q "^StartupWMClass=org.omarchy.$m\$" "$apps/org.omarchy.$m.desktop"
    t_ok grep -q '^NotShowIn=Hyprland;$' "$apps/org.omarchy.$m.desktop"
    t_ok grep -q '^Categories=System;$' "$apps/org.omarchy.$m.desktop"
    t_eq "$(grep -c '^NoDisplay' "$apps/org.omarchy.$m.desktop")" 0
  done
  t_ok grep -q "^Exec=$HOME/.local/bin/account-switcher agent --mode=personal\$" "$apps/org.omarchy.agent-personal.desktop"
  t_ok grep -q "^update-desktop-database $apps\$" "$ACCOUNT_SWITCHER_RUN_LOG"
  local w
  for w in account-switcher account-switcher-ghostty account-switcher-open account-switcher-commit-guard account-switcher-share-picker code; do
    t_ok test -x "$HOME/.local/bin/$w"
    t_eq "$(readlink -f "$HOME/.local/bin/$w")" "$PLUGIN/bin/$w"
  done
}
t_test "desktop-apply writes the terminal and file-manager entries" t_desktop_terminals

t_code() {
  fresh
  local C=$PLUGIN/bin/code
  "$C" --list-extensions
  t_eq "$(last_line)" "/usr/bin/code --list-extensions"
  "$C" --install-extension foo.bar
  t_eq "$(last_line)" "/usr/bin/code --install-extension foo.bar"
  ACCOUNT_SWITCHER_MODE=personal "$C" notes.md
  t_eq "$(last_line)" "/usr/bin/code --user-data-dir $HOME/.config/Code-Personal notes.md"
  ACCOUNT_SWITCHER_MODE=work "$C" -- notes.md
  t_eq "$(last_line)" "/usr/bin/code -- notes.md"
  ACCOUNT_SWITCHER_MODE=personal "$C" --user-data-dir /tmp/x a
  t_eq "$(last_line)" "/usr/bin/code --user-data-dir /tmp/x a" "an explicit data dir is kept"
  desk personal
  "$C" --open-url vscode://file/x
  t_eq "$(last_line)" "/usr/bin/code --user-data-dir $HOME/.config/Code-Personal --open-url vscode://file/x" "no requester: the desk's mode"
}
t_test "code opens the VS Code of the requester's mode" t_code

t_code_setup() {
  fresh
  mkdir -p "$HOME/.config/Code/User/snippets" && echo '{}' >"$HOME/.config/Code/User/settings.json"
  "$DM" setup
  local u=$HOME/.config/Code-Personal/User
  t_eq "$(readlink "$u/settings.json")" "$HOME/.config/Code/User/settings.json"
  t_eq "$(readlink "$u/keybindings.json")" "$HOME/.config/Code/User/keybindings.json"
  t_eq "$(readlink "$u/snippets")" "$HOME/.config/Code/User/snippets"
  t_eq "$(cat "$HOME/.config/Code/User/keybindings.json")" "[]" "Work's keybindings file created to share"
}
t_test "setup gives Personal VS Code Work's settings, keys and snippets" t_code_setup


env_line() { grep '^env: ' "$ACCOUNT_SWITCHER_RUN_LOG" | tail -n1; }

t_agent_class_is_work() {
  fresh
  desk personal
  ACCOUNT_SWITCHER_RUN_LOG_ENV=1 ACCOUNT_SWITCHER_MODE=personal "$PLUGIN/bin/account-switcher-ghostty" --class=org.omarchy.agent -e claude
  t_ok grep -q '^env: ACCOUNT_SWITCHER_MODE=work ' "$ACCOUNT_SWITCHER_RUN_LOG"
  t_eq "$(last_line)" "/usr/bin/ghostty --gtk-single-instance=true --class=org.omarchy.agent -e claude"
  ACCOUNT_SWITCHER_RUN_LOG_ENV=1 "$PLUGIN/bin/account-switcher-ghostty" --class=org.omarchy.term-personal
  t_ok grep -q 'ACCOUNT_SWITCHER_MODE=personal GIT_CONFIG_GLOBAL=.*account-switcher-personal' <<<"$(env_line)"
}
t_test "an agent from Omarchy's own paths gets Work's identity, like its window" t_agent_class_is_work

t_files_clean_env() {
  fresh
  desk work
  ACCOUNT_SWITCHER_MODE=personal GIT_CONFIG_GLOBAL=/x "$DM" files
  t_eq "$(last_line)" "env -u ACCOUNT_SWITCHER_MODE -u GIT_CONFIG_GLOBAL -u GH_CONFIG_DIR -u AWS_CONFIG_FILE -u AWS_SHARED_CREDENTIALS_FILE -u HISTFILE -u _ZO_DATA_DIR -u BROWSER -u TMUX_TMPDIR -u HERDR_SOCKET_PATH setsid uwsm-app -- nautilus --new-window $HOME/Work"
}
t_test "the file manager starts without the caller's mode" t_files_clean_env

t_tmux_key() {
  fresh
  desk personal
  "$DM" tmux
  t_eq "$(last_line)" "setsid uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.term-personal --dir=$HOME -e bash -c tmux attach || tmux new -s Personal"
}
t_test "the tmux key attaches to the mode's own server" t_tmux_key

t_webapp_name() {
  fresh
  desk work
  "$DM" webapp --name=WhatsApp https://web.whatsapp.com/
  t_eq "$(head -n1 "$ACCOUNT_SWITCHER_RUN_LOG")" "$SWITCH('personal') end end"
  t_ok grep -q "omarchy-cmd-browser-handoff /usr/bin/chromium --app=https://web.whatsapp.com/" "$ACCOUNT_SWITCHER_RUN_LOG"
  : >"$ACCOUNT_SWITCHER_RUN_LOG"
  "$DM" webapp --name=ChatGPT https://chatgpt.com
  t_none "$SWITCH" "$ACCOUNT_SWITCHER_RUN_LOG"
  t_ok grep -q "omarchy-cmd-browser-handoff /usr/bin/google-chrome-stable --app=https://chatgpt.com" "$ACCOUNT_SWITCHER_RUN_LOG"
}
t_test "a web app named in the config opens in its mode; others follow the desk" t_webapp_name

t_done
