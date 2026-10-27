#!/usr/bin/env bash
# The commit guard in throwaway repos, with the example config's owners and addresses, and the
# per-mode git files setup generates from it.
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
GUARD=$PLUGIN/bin/account-switcher-commit-guard
TMP=${TEST_TMPDIR:?run through tests/run.sh}/git
W=alex@work.example G=alex@home.example S=alex@side.example

fresh() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.config/account-switcher"
  export HOME=$TMP/home ACCOUNT_SWITCHER_RUN_LOG=$TMP/run.log ACCOUNT_SWITCHER_GH=/opt/gh/bin/gh
  unset XDG_STATE_HOME XDG_DATA_HOME XDG_CONFIG_HOME HYPRLAND_INSTANCE_SIGNATURE
  cp "$PLUGIN/tests/fixtures/config.test.json" "$HOME/.config/account-switcher/config.json"
  "$PLUGIN/bin/account-switcher" setup >/dev/null
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=$TMP/global.config GIT_TERMINAL_PROMPT=0
  unset GIT_AUTHOR_EMAIL GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_NAME
  printf '[hook "account-switcher-guard"]\n\tevent = prepare-commit-msg\n\tcommand = "%s"\n[init]\n\tdefaultBranch = master\n[user]\n\tname = T\n' "$GUARD" >"$GIT_CONFIG_GLOBAL"
}
repo() { # name [origin url]
  git init -q "$TMP/$1" && cd "$TMP/$1" || exit 1
  [[ -n ${2:-} ]] && git remote add origin "$2"
  return 0
}
commit_as() { # email [git commit args…]
  local email=$1
  shift
  echo "$RANDOM" >>f && git add f && git -c user.email="$email" commit -q -m c "$@"
}

t_work_repo() {
  fresh
  repo w https://github.com/work-org/ops.git
  t_ok commit_as "$W"
  local err
  err=$(commit_as "$G" 2>&1) && t_eq ok refused "personal commit in a work repo"
  t_ok grep -q "$W" <<<"$err"
  t_ok grep -q "Work terminal" <<<"$err"
  t_ok grep -q "hook.account-switcher-guard.enabled=false" <<<"$err"
}
t_test "a work repo refuses the personal address and takes the work one" t_work_repo

t_side_repo() {
  fresh
  repo s https://github.com/side-org/tool.git
  t_ok commit_as "$S"
  commit_as "$G" 2>/dev/null && t_eq ok refused "personal commit in a side-account repo"
  return 0
}
t_test "an account's repo takes only that account's address" t_side_repo

t_noreply() {
  fresh
  repo p https://github.com/alex/notes.git
  t_ok commit_as 12345+alex@users.noreply.github.com
  t_ok commit_as alex@users.noreply.github.com
  repo w https://github.com/work-org/ops.git
  commit_as 12345+alex@users.noreply.github.com 2>/dev/null && t_eq ok refused "another login's no-reply address"
  t_ok commit_as 99+alex-work@users.noreply.github.com
}
t_test "the owner's login's GitHub no-reply address counts as its address" t_noreply

t_no_config() {
  fresh
  rm -f "$HOME/.local/state/account-switcher/config.bash"
  repo w https://github.com/work-org/ops.git
  t_ok commit_as "$G"
}
t_test "without a config the guard lets everything through" t_no_config

t_no_verify() {
  fresh
  repo w https://github.com/alex-work/tools.git
  commit_as "$G" --no-verify 2>/dev/null && t_eq ok refused "--no-verify"
  return 0
}
t_test "--no-verify doesn't skip the guard" t_no_verify

t_teammate_amend() {
  fresh
  repo p https://github.com/alex/notes.git
  t_ok commit_as "$G" --author="Mate <mate@example.com>"
  t_ok git -c user.email="$G" commit -q --amend --no-edit
  t_eq "$(git log -1 --format=%ae)" mate@example.com
}
t_test "a teammate's commit amended by the right person passes" t_teammate_amend

t_cherry_pick() {
  fresh
  repo w https://github.com/alex-work/tools.git
  commit_as "$W" && git checkout -q -b side
  commit_as "$W" --author="Mate <mate@example.com>" && local mate=$(git rev-parse HEAD)
  commit_as "$G" -c hook.account-switcher-guard.enabled=false 2>/dev/null ||
    git -c hook.account-switcher-guard.enabled=false -c user.email="$G" commit -q -m own
  local own=$(git rev-parse HEAD)
  git checkout -q master
  t_ok git -c user.email="$W" cherry-pick "$mate" >/dev/null
  git -c user.email="$W" cherry-pick "$own" >/dev/null 2>&1 && t_eq ok refused "own wrong-address commit"
  return 0
}
t_test "cherry-picks keep a teammate but refuse the user's own wrong address" t_cherry_pick

t_merge() {
  fresh
  repo w https://github.com/work-org/ops.git
  commit_as "$W" && git checkout -q -b side
  echo s >s && git add s && git -c user.email="$W" commit -q -m side
  git checkout -q master && commit_as "$W"
  local err
  err=$(git -c user.email="$G" merge --no-ff side -m m 2>&1) && t_eq ok refused "wrong merge committer"
  t_ok grep -q "account-switcher: commit refused" <<<"$err"
  git merge --abort
  t_ok git -c user.email="$W" merge -q --no-ff side -m m
}
t_test "a merge commit by the wrong committer is refused" t_merge

t_rebase() {
  fresh
  repo w https://github.com/work-org/ops.git
  commit_as "$W" && git checkout -q -b side
  git -c hook.account-switcher-guard.enabled=false -c user.email="$G" commit -q --allow-empty -m own
  git checkout -q master && commit_as "$W" && git checkout -q side
  git -c user.email="$W" rebase -q master >/dev/null 2>&1 && t_eq ok refused "rebase replaying an own wrong-address commit"
  git rebase --abort 2>/dev/null
  return 0
}
t_test "a rebase replaying the user's own wrong-address commit stops" t_rebase

t_unknown() {
  fresh
  repo none
  t_ok commit_as "$G"
  repo other https://github.com/someone-else/project.git
  t_ok commit_as "$G"
  repo lab https://gitlab.com/work-org/ops.git
  t_ok commit_as "$G"
}
t_test "repos without a GitHub remote, or with an unknown owner, pass" t_unknown

t_override() {
  fresh
  repo w https://github.com/work-org/ops.git
  echo x >f && git add f
  t_ok git -c hook.account-switcher-guard.enabled=false -c user.email="$G" commit -q -m once
}
t_test "the one-off override lets one wrong commit through" t_override

t_owner_parsing() {
  t_eq "$("$GUARD" --owner-of https://github.com/side-org/tool.git)" side-org
  t_eq "$("$GUARD" --owner-of https://alex-side@github.com/side-org/tool.git)" side-org
  t_eq "$("$GUARD" --owner-of git@github.com:Alex/x.git)" alex
  t_eq "$("$GUARD" --owner-of ssh://git@github.com/work-org/ops)" work-org
  t_eq "$("$GUARD" --owner-of https://evil.example/github.com/work-org/x)" ""
  t_eq "$("$GUARD" --owner-of /home/someone/x)" ""
}
t_test "owners are read from https, ssh and scp-style GitHub URLs" t_owner_parsing

t_generated_files() {
  fresh
  unset GIT_CONFIG_NOSYSTEM
  local personal=$HOME/.config/git/account-switcher-personal work=$HOME/.config/git/account-switcher-work
  git init -q "$HOME/Side/tool" && git init -q "$HOME/notes"
  t_ok grep -q "<$S>" <<<"$(GIT_CONFIG_GLOBAL=$personal git -C "$HOME/Side/tool" var GIT_COMMITTER_IDENT)"
  t_ok grep -q "^alex <$G>" <<<"$(GIT_CONFIG_GLOBAL=$personal git -C "$HOME/notes" var GIT_COMMITTER_IDENT)"
  t_ok grep -q "^Alex Example <$W>" <<<"$(GIT_CONFIG_GLOBAL=$work git -C "$HOME/Side/tool" var GIT_COMMITTER_IDENT)"
  # ~/.gitconfig still counts in a mode's terminal, but the mode's identity wins.
  printf '[alias]\n\tst = status\n[user]\n\temail = old@example.com\n' >"$HOME/.gitconfig"
  t_eq "$(GIT_CONFIG_GLOBAL=$work git config alias.st)" status
  t_ok grep -q "<$W>" <<<"$(GIT_CONFIG_GLOBAL=$work git -C "$HOME/notes" var GIT_COMMITTER_IDENT)"
}
t_test "the generated per-mode git files give each folder its identity" t_generated_files

t_global_writes() {
  fresh
  unset GIT_CONFIG_NOSYSTEM
  local work=$HOME/.config/git/account-switcher-work c=$HOME/.config/account-switcher/config.json
  git init -q "$HOME/notes"
  # `git config --global` in a Work terminal, then a setup that changes the Work identity.
  t_ok env GIT_CONFIG_GLOBAL="$work" git config --global alias.co checkout
  jq '.work.git.email = "alex@new-work.example"' "$c" >"$c.new" && mv "$c.new" "$c"
  "$PLUGIN/bin/account-switcher" setup >/dev/null
  t_eq "$(GIT_CONFIG_GLOBAL=$work git config alias.co)" checkout
  t_ok grep -q "<alex@new-work.example>" <<<"$(GIT_CONFIG_GLOBAL=$work git -C "$HOME/notes" var GIT_COMMITTER_IDENT)"
}
t_test "what a mode terminal writes with git config --global outlives the next setup" t_global_writes

t_own_split() {
  rm -rf "$TMP"
  mkdir -p "$TMP/home/.config/account-switcher" "$TMP/home/.config/git"
  export HOME=$TMP/home ACCOUNT_SWITCHER_RUN_LOG=$TMP/run.log ACCOUNT_SWITCHER_GH=/opt/gh/bin/gh
  unset XDG_STATE_HOME XDG_DATA_HOME XDG_CONFIG_HOME HYPRLAND_INSTANCE_SIGNATURE GIT_CONFIG_NOSYSTEM
  cp "$PLUGIN/tests/fixtures/config.test.json" "$HOME/.config/account-switcher/config.json"
  # A hand-made work/personal split, with the names people often give it.
  local g=$HOME/.config/git before
  printf '[user]\n\tname = Alex\n[includeIf "gitdir:~/Work/"]\n\tpath = config-work\n' >"$g/config"
  printf '[user]\n\temail = me@corp.example\n' >"$g/config-work"
  before=$(sha256sum <"$g/config-work")
  "$PLUGIN/bin/account-switcher" setup >/dev/null
  t_eq "$(sha256sum <"$g/config-work")" "$before" "the user's own config-work"
  git init -q "$HOME/Work/proj"
  t_eq "$(env -u GIT_CONFIG_GLOBAL git -C "$HOME/Work/proj" config user.email)" me@corp.example
  t_ok env GIT_CONFIG_GLOBAL="$g/account-switcher-work" git -C "$HOME/Work/proj" status --short
}
t_test "a user's own config-work split is left alone and still works" t_own_split

t_done
