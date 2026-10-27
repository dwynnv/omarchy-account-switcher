#!/usr/bin/env bash
# The ~/.bashrc hook (shell/pre.bash, shell/post.bash) in scratch interactive shells set up
# with the example config.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
TMP=${TEST_TMPDIR:?run through tests/run.sh}/shell
H=$TMP/home

fresh() {
  rm -rf "$TMP"
  mkdir -p "$H/Projects" "$H/elsewhere" "$TMP/bin"
  # Omarchy's rc defines the stock `a` alias between the two hook files.
  cat >"$H/.bashrc" <<RC
[[ \$- != *i* ]] && return
source "$PLUGIN/shell/pre.bash"
alias a='omarchy-agent --inline'
source "$PLUGIN/shell/post.bash"
RC
  printf '#!/bin/sh\necho "$PWD $*"\n' >"$TMP/bin/omarchy-agent"
  chmod +x "$TMP/bin/omarchy-agent"
  mkdir -p "$H/.config/account-switcher" && cp "$PLUGIN/tests/fixtures/config.test.json" "$H/.config/account-switcher/config.json"
  env -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_DATA_HOME -u HYPRLAND_INSTANCE_SIGNATURE HOME="$H" \
    ACCOUNT_SWITCHER_GH=/opt/gh/bin/gh ACCOUNT_SWITCHER_RUN_LOG="$TMP/run.log" "$PLUGIN/bin/account-switcher" setup >/dev/null
}
# An interactive shell in the scratch HOME; extra args are env assignments.
shell_run() {
  local dir=$1 script=$2
  shift 2
  (cd "$dir" && env -i HOME="$H" PATH="$TMP/bin:/usr/bin:/bin" TERM=dumb XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" "$@" bash --rcfile "$H/.bashrc" -i -c "$script" 2>/dev/null)
}
VARS='printf "%s|%s|%s|%s|%s|%s\n" "$ACCOUNT_SWITCHER_MODE" "$HISTFILE" "$_ZO_DATA_DIR" "$BROWSER" "${ACCOUNT_SWITCHER_WORK-}" "${ACCOUNT_SWITCHER_PERSONAL-}"'

t_personal() {
  fresh
  t_eq "$(shell_run "$H" "$VARS" ACCOUNT_SWITCHER_MODE=personal)" \
    "personal|$H/.local/state/account-switcher/history/bash-personal|$H/.local/share/account-switcher/zoxide/personal|$H/.local/bin/account-switcher-open||1"
  t_eq "$(shell_run "$H" 'echo "$GIT_CONFIG_GLOBAL|$AWS_CONFIG_FILE"' ACCOUNT_SWITCHER_MODE=personal)" \
    "$H/.config/git/account-switcher-personal|$H/.local/share/account-switcher/aws/config"
}
t_test "a Personal terminal gets Personal history, z jumps, links and prompt" t_personal

t_outside() {
  fresh
  t_eq "$(shell_run "$H" "$VARS")" \
    "work|$H/.local/state/account-switcher/history/bash-work|$H/.local/share/account-switcher/zoxide/work|$H/.local/bin/account-switcher-open|1|"
  t_eq "$(shell_run "$H" 'echo "$ACCOUNT_SWITCHER_MODE"' ACCOUNT_SWITCHER_MODE=banana)" work
}
t_test "a terminal started outside the switcher acts as Work" t_outside

t_agent() {
  fresh
  t_eq "$(shell_run "$H" 'type -t a')" function
  t_eq "$(shell_run "$H" 'a' ACCOUNT_SWITCHER_MODE=personal)" "$H/Projects --inline"
  t_eq "$(shell_run "$H/elsewhere" 'a' ACCOUNT_SWITCHER_MODE=personal)" "$H/elsewhere --inline"
  t_eq "$(shell_run "$H" 'a' ACCOUNT_SWITCHER_MODE=work)" "$H/Work --inline"
  t_eq "$(shell_run "$H" 'a; pwd' ACCOUNT_SWITCHER_MODE=personal)" "$H/Projects --inline
$H" "the shell itself stays put"
}
t_test "a starts the agent in the mode's agent folder from a shell in ~" t_agent

t_side_owner_gh() {
  fresh
  printf '#!/bin/sh\necho "$GH_CONFIG_DIR"\n' >"$TMP/bin/gh" && chmod +x "$TMP/bin/gh"
  git init -q "$H/side" && git -C "$H/side" remote add origin https://github.com/side-org/tool.git
  git init -q "$H/own" && git -C "$H/own" remote add origin git@github.com:alex/notes.git
  local gh=$H/.local/share/account-switcher/gh
  t_eq "$(shell_run "$H/side" 'gh api user' ACCOUNT_SWITCHER_MODE=personal)" "$gh/alex-side"
  t_eq "$(shell_run "$H/own" 'gh api user' ACCOUNT_SWITCHER_MODE=personal)" "$gh/alex"
  t_eq "$(shell_run "$H/side" 'gh api user' ACCOUNT_SWITCHER_MODE=work)" "$gh/alex-work"
}
t_test "gh in a repo of a configured account acts as that account in its mode, like git push" t_side_owner_gh

t_gh_auth_shared() {
  fresh
  printf '#!/bin/sh\necho "$GH_CONFIG_DIR $*"\n' >"$TMP/bin/gh" && chmod +x "$TMP/bin/gh"
  mkdir -p "$H/.local/bin" && printf '#!/bin/sh\necho "setup $*" >>"%s/setup.log"\n' "$TMP" >"$H/.local/bin/account-switcher" && chmod +x "$H/.local/bin/account-switcher"
  t_eq "$(shell_run "$H" 'gh auth login --hostname github.com' ACCOUNT_SWITCHER_MODE=personal)" "$H/.config/gh auth login --hostname github.com"
  t_eq "$(cat "$TMP/setup.log")" "setup setup"
  local out
  out=$(shell_run "$H" 'gh auth switch 2>&1; echo "rc=$?"' ACCOUNT_SWITCHER_MODE=work)
  t_ok grep -q 'rc=1' <<<"$out"
  t_ok grep -q 'follow the mode' <<<"$out"
}
t_test "gh auth login works on the shared accounts; gh auth switch explains instead" t_gh_auth_shared

t_herdr_alias() {
  fresh
  printf '#!/bin/sh\necho "herdr $*"\n' >"$TMP/bin/herdr" && chmod +x "$TMP/bin/herdr"
  t_eq "$(shell_run "$H" 'h' ACCOUNT_SWITCHER_MODE=personal)" "herdr --session personal"
  t_eq "$(shell_run "$H" 'h status' ACCOUNT_SWITCHER_MODE=personal)" "herdr status"
}
t_test "h opens the mode's own herdr session" t_herdr_alias

t_code() {
  fresh
  # Omarchy puts ~/.local/bin after the system's folders, so the system's `code` comes first.
  printf '#!/bin/sh\necho system-code\n' >"$TMP/bin/code" && chmod +x "$TMP/bin/code"
  : >"$TMP/run.log"
  t_eq "$(shell_run "$H/Projects" 'code .' ACCOUNT_SWITCHER_MODE=personal ACCOUNT_SWITCHER_RUN_LOG="$TMP/run.log")" ""
  t_eq "$(tail -n1 "$TMP/run.log")" "/usr/bin/code --user-data-dir $H/.config/Code-Personal ."
}
t_test "code in a terminal is the mode's VS Code, whatever comes first on PATH" t_code

t_done
