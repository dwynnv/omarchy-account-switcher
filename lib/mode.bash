# account-switcher: the Work/Personal environment, shared by bin/account-switcher and the
# ~/.bashrc hook (shell/pre.bash). Sourced into interactive shells, so: functions
# only (dm_*), no exit, no output unless a function's job is to print.

# The desk's mode lives in Hyprland; the Hyprland side writes it here on every switch.
dm_state_dir() { printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/account-switcher"; }
dm_data_dir() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/account-switcher"; }

# This plugin's folder, from wherever this file was sourced.
DM_PLUGIN=${BASH_SOURCE[0]}
[[ $DM_PLUGIN == /* ]] || DM_PLUGIN=$PWD/$DM_PLUGIN
DM_PLUGIN=${DM_PLUGIN%/lib/mode.bash}

# The user's choices: accounts, browsers, apps, folders (README "Config"). Nothing reads it
# directly; `account-switcher setup` derives config.bash and the other files from it.
dm_config_path() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/account-switcher/config.json"; }

# The variables setup derived from the config (lib/config.jq), or empty ones before it ran.
dm_load_config() {
  local m
  DM_CONFIGURED=0
  for m in work personal; do
    printf -v "DM_LOGIN_$m" '%s' ''
    printf -v "DM_HOME_$m" '%s' "$HOME"
    printf -v "DM_AGENT_$m" '%s' "$HOME"
    printf -v "DM_FILES_$m" '%s' "$HOME"
    printf -v "DM_SHOTS_$m" '%s' ''
    printf -v "DM_RECS_$m" '%s' ''
    printf -v "DM_DOWNLOADS_$m" '%s' ''
    printf -v "DM_BROWSER_$m" '%s' ''
    printf -v "DM_BROWSER_BIN_$m" '%s' ''
    printf -v "DM_BROWSER_CLASS_$m" '%s' ''
    printf -v "DM_BROWSER_EXEDIR_$m" '%s' ''
  done
  declare -gA DM_APP_MODE=() DM_APP_BIN=() DM_APP_CLASS=() DM_APP_DESKTOP=() DM_APP_EXEC=() DM_APP_FOCUS=() \
    DM_WEBAPP_MODE=() DM_OWNER_EMAIL=() DM_OWNER_LOGIN=() DM_EMAIL_MODE=()
  declare -ga DM_ROUTE_BROWSERS=() DM_ACCOUNTS=()
  DM_OWN_EMAILS=' ' DM_CLOCK_APPS='' DM_MAILTO=gmail DM_GH=''
  local file=${XDG_STATE_HOME:-$HOME/.local/state}/account-switcher/config.bash
  # shellcheck source=/dev/null
  [[ -r $file ]] && source "$file"
  return 0
}

dm_valid_mode() { [[ ${1:-} == work || ${1:-} == personal ]]; }

dm_desk_mode() {
  local mode=
  { read -r mode <"${XDG_STATE_HOME:-$HOME/.local/state}/account-switcher/mode"; } 2>/dev/null
  if dm_valid_mode "$mode"; then printf '%s\n' "$mode"; else echo work; fi
}

# The gh account a mode's gh and git credentials use (the config's login), or nothing.
# Accounts' repos get their own (dm_owner_gh_dir).
dm_account() {
  local name=DM_LOGIN_$1
  dm_valid_mode "${1:-}" && printf '%s\n' "${!name-}"
}

# The gh folder for a repo of OWNER in MODE: a configured account's, or nothing.
dm_owner_gh_dir() {
  local entry owner mode login
  for entry in "${DM_ACCOUNTS[@]}"; do
    read -r owner mode login <<<"$entry"
    if [[ $owner == "${1,,}" && $mode == "${2:-}" ]]; then
      printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/account-switcher/gh/$login"
      return
    fi
  done
}

# Export everything a process of mode $1 needs. Unknown modes are Work, like anything
# started outside the switcher. Touches no files except the mode's tmux folder.
dm_env() {
  local mode=${1:-work} config=${XDG_CONFIG_HOME:-$HOME/.config} login
  local data=${XDG_DATA_HOME:-$HOME/.local/share}/account-switcher
  local state=${XDG_STATE_HOME:-$HOME/.local/state}/account-switcher
  dm_valid_mode "$mode" || mode=work
  export ACCOUNT_SWITCHER_MODE=$mode
  # The mode's git identity and gh account once setup has written them.
  if [[ -e $config/git/account-switcher-$mode ]]; then export GIT_CONFIG_GLOBAL=$config/git/account-switcher-$mode; else unset GIT_CONFIG_GLOBAL; fi
  login=DM_LOGIN_$mode
  login=${!login-}
  if [[ -n $login ]]; then export GH_CONFIG_DIR=$data/gh/$login; else unset GH_CONFIG_DIR; fi
  # Personal gets empty AWS files, so Work's profiles stay out of it.
  if [[ $mode == personal ]]; then
    export AWS_CONFIG_FILE=$data/aws/config AWS_SHARED_CREDENTIALS_FILE=$data/aws/credentials
  else
    unset AWS_CONFIG_FILE AWS_SHARED_CREDENTIALS_FILE
  fi
  export HISTFILE=$state/history/bash-$mode
  export _ZO_DATA_DIR=$data/zoxide/$mode
  export BROWSER=$HOME/.local/bin/account-switcher-open
  # tmux and herdr servers keep the environment of whoever started them: one each per mode.
  local run=${XDG_RUNTIME_DIR:-/run/user/$UID}/account-switcher
  export TMUX_TMPDIR=$run/tmux-$mode HERDR_SOCKET_PATH=$run/herdr-$mode.sock
  [[ -d $TMUX_TMPDIR ]] || mkdir -p -m 700 "$TMUX_TMPDIR" 2>/dev/null
}

DM_ENV_VARS=(ACCOUNT_SWITCHER_MODE GIT_CONFIG_GLOBAL GH_CONFIG_DIR AWS_CONFIG_FILE AWS_SHARED_CREDENTIALS_FILE HISTFILE _ZO_DATA_DIR BROWSER TMUX_TMPDIR HERDR_SOCKET_PATH)

# The current values of dm_env's variables as lines a shell can eval.
dm_print_env() {
  local name
  for name in "${DM_ENV_VARS[@]}"; do
    if [[ -n ${!name+x} ]]; then
      printf 'export %s=%q\n' "$name" "${!name}"
    else
      printf 'unset %s\n' "$name"
    fi
  done
}

# Browsers belong to one mode whatever started them: the configured ones, by the
# folder their executable lives in.
dm_exe_mode() {
  local m dir
  for m in work personal; do
    dir=DM_BROWSER_EXEDIR_$m
    dir=${!dir-}
    if [[ -n $dir && $1 == "$dir"* ]]; then
      echo "$m"
      return
    fi
  done
}

# The executable of a process (tests stand in their own with ACCOUNT_SWITCHER_FAKE_EXE="pid=exe").
dm_proc_exe() {
  if [[ -n ${ACCOUNT_SWITCHER_FAKE_EXE:-} && ${ACCOUNT_SWITCHER_FAKE_EXE%%=*} == "$1" ]]; then
    printf '%s\n' "${ACCOUNT_SWITCHER_FAKE_EXE#*=}"
    return
  fi
  readlink "/proc/$1/exe" 2>/dev/null
}

# The mode of a browser or VS Code process (VS Code by its data dir), or nothing.
dm_app_mode() {
  local exe
  exe=$(dm_proc_exe "$1")
  if [[ $exe == /usr/share/code/code ]]; then
    if tr '\0' '\n' <"/proc/$1/cmdline" 2>/dev/null | grep -q '/\.config/Code-Personal'; then echo personal; else echo work; fi
    return
  fi
  dm_exe_mode "$exe"
}

dm_parent() { sed -n 's/^PPid:[[:space:]]*//p' "/proc/$1/status" 2>/dev/null; }

# The mode of whoever asked. A browser or VS Code just above us (it ran xdg-open, which
# ran us) wins: browsers belong to one mode whatever environment started them. Then our
# own ACCOUNT_SWITCHER_MODE, then the nearest ancestor's (its exec-time environment) or browser,
# else the desk's mode. ACCOUNT_SWITCHER_WALK_ROOT stops the walks at that pid (tests).
dm_requester_mode() {
  local pid=$PPID steps=0 mode
  while [[ $pid =~ ^[0-9]+$ ]] && ((pid > 1 && steps < 3)); do
    [[ $pid == "${ACCOUNT_SWITCHER_WALK_ROOT:-0}" ]] && break
    mode=$(dm_app_mode "$pid")
    if [[ -n $mode ]]; then
      printf '%s\n' "$mode"
      return
    fi
    pid=$(dm_parent "$pid")
    steps=$((steps + 1))
  done
  if dm_valid_mode "${ACCOUNT_SWITCHER_MODE:-}"; then
    printf '%s\n' "$ACCOUNT_SWITCHER_MODE"
    return
  fi
  pid=$PPID steps=0
  while [[ $pid =~ ^[0-9]+$ ]] && ((pid > 1 && steps < 32)); do
    [[ $pid == "${ACCOUNT_SWITCHER_WALK_ROOT:-0}" ]] && break
    mode=$(dm_app_mode "$pid")
    [[ -n $mode ]] || mode=$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | sed -n 's/^ACCOUNT_SWITCHER_MODE=//p' | head -n1)
    if dm_valid_mode "$mode"; then
      printf '%s\n' "$mode"
      return
    fi
    pid=$(dm_parent "$pid")
    steps=$((steps + 1))
  done
  dm_desk_mode
}

# Whether the focused window's process is one of our ancestors, i.e. the request came from
# what the user is working in (a click or a command), not a program in the background.
dm_focused_is_ancestor() {
  local focused pid=$PPID steps=0
  focused=$(dm_run hyprctl activewindow -j 2>/dev/null | jq -r '.pid // empty' 2>/dev/null)
  [[ $focused =~ ^[0-9]+$ ]] && ((focused > 1)) || return 1
  while [[ $pid =~ ^[0-9]+$ ]] && ((pid > 1 && steps < 32)); do
    [[ $pid == "$focused" ]] && return 0
    [[ $pid == "${ACCOUNT_SWITCHER_WALK_ROOT:-0}" ]] && break
    pid=$(dm_parent "$pid")
    steps=$((steps + 1))
  done
  return 1
}

# Run an external command. With ACCOUNT_SWITCHER_RUN_LOG set (tests) the command line is
# recorded instead; $ACCOUNT_SWITCHER_FAKES/<name>[-<arg1>].out and .status stand in for
# its output and exit status.
dm_run() {
  if [[ -z ${ACCOUNT_SWITCHER_RUN_LOG:-} ]]; then
    "$@"
    return
  fi
  [[ -n ${ACCOUNT_SWITCHER_RUN_LOG_ENV:-} ]] &&
    printf 'env: ACCOUNT_SWITCHER_MODE=%s GIT_CONFIG_GLOBAL=%s GH_CONFIG_DIR=%s TMUX_TMPDIR=%s\n' "${ACCOUNT_SWITCHER_MODE:-}" \
      "${GIT_CONFIG_GLOBAL:-}" "${GH_CONFIG_DIR:-}" "${TMUX_TMPDIR:-}" >>"$ACCOUNT_SWITCHER_RUN_LOG"
  printf '%s\n' "$*" >>"$ACCOUNT_SWITCHER_RUN_LOG"
  local fakes=${ACCOUNT_SWITCHER_FAKES:-/nonexistent} key=${1##*/} arg=${2-} fake
  for fake in "$fakes/$key-${arg//\//_}" "$fakes/$key"; do
    if [[ -e $fake.out || -e $fake.status ]]; then
      [[ -r $fake.out ]] && cat "$fake.out"
      [[ -r $fake.status ]] && return "$(<"$fake.status")"
      return 0
    fi
  done
  return 0
}

# Hand the process over to a command (recorded and ended in tests).
dm_exec() {
  if [[ -n ${ACCOUNT_SWITCHER_RUN_LOG:-} ]]; then
    dm_run "$@"
    exit $?
  fi
  exec "$@"
}

# Ask Hyprland to switch the desk (account_switcher.switch). No-op when already there.
# While a screen share is live the desk asks instead, unless --confirmed (the ask toast's click).
dm_switch() {
  dm_valid_mode "${1:-}" || return 2
  [[ $(dm_desk_mode) == "$1" ]] && return 0
  local opts=
  [[ ${2:-} == --confirmed ]] && opts=", { confirmed = true }"
  dm_run hyprctl dispatch "function() if account_switcher then account_switcher.switch('$1'$opts) end end" >/dev/null
}

# Folders and files the environment points at. Idempotent; never overwrites a mode's
# own history or zoxide copy once it exists (spec feature 5: seeded once, then apart).
dm_setup() {
  local config=${XDG_CONFIG_HOME:-$HOME/.config} data state account mode entry owner
  local -a accounts=()
  data=$(dm_data_dir)
  state=$(dm_state_dir)
  # Each configured gh account gets a token-free copy of gh's settings (tokens stay in the keyring).
  for mode in work personal; do
    account=$(dm_account "$mode")
    [[ -n $account ]] && accounts+=("$account")
  done
  for entry in "${DM_ACCOUNTS[@]}"; do
    read -r owner mode account <<<"$entry"
    accounts+=("$account")
  done
  for account in $(printf '%s\n' "${accounts[@]}" | awk '!seen[$0]++'); do
    mkdir -p "$data/gh/$account"
    if [[ -r $config/gh/hosts.yml ]]; then
      sed -E -e '/^[[:space:]]*oauth_token:/d' -e "s/^([[:space:]]*user:).*/\\1 $account/" "$config/gh/hosts.yml" >"$data/gh/$account/hosts.yml.tmp" &&
        chmod 600 "$data/gh/$account/hosts.yml.tmp" &&
        mv -f "$data/gh/$account/hosts.yml.tmp" "$data/gh/$account/hosts.yml"
    fi
    ln -sfn "$config/gh/config.yml" "$data/gh/$account/config.yml"
  done
  mkdir -p "$data/aws"
  for name in config credentials; do
    [[ -e $data/aws/$name ]] || : >"$data/aws/$name"
    chmod 600 "$data/aws/$name"
  done
  mkdir -p "$state/history"
  local zoxide=${XDG_DATA_HOME:-$HOME/.local/share}/zoxide/db.zo
  for mode in work personal; do
    if [[ ! -e $state/history/bash-$mode ]]; then
      if [[ -r $HOME/.bash_history ]]; then cp "$HOME/.bash_history" "$state/history/bash-$mode"; else : >"$state/history/bash-$mode"; fi
      chmod 600 "$state/history/bash-$mode"
    fi
    mkdir -p "$data/zoxide/$mode"
    [[ -e $data/zoxide/$mode/db.zo || ! -r $zoxide ]] || cp "$zoxide" "$data/zoxide/$mode/db.zo"
  done
  # A Personal wallpaper to start with: one of Omarchy's own backgrounds (the personalWallpaper
  # setting picks another), never replacing one that's there.
  local wall=$data/wallpapers/personal.jpg src themes=${OMARCHY_PATH:-/usr/share/omarchy}/themes
  if [[ ! -e $wall ]]; then
    src=$themes/gruvbox/backgrounds/5-leaves.jpg
    [[ -r $src ]] || src=$(find "$themes" -path '*/backgrounds/*.jpg' 2>/dev/null | sort | head -n1)
    [[ -n $src ]] && mkdir -p "${wall%/*}" && cp "$src" "$wall"
  fi
  # Personal VS Code shares Work's settings, keys and snippets (extensions are shared anyway).
  [[ -x /usr/bin/code || -d $config/Code ]] || return 0
  local code=$config/Code/User personal=$config/Code-Personal/User name
  mkdir -p "$code" "$personal"
  [[ -e $code/keybindings.json ]] || echo '[]' >"$code/keybindings.json"
  [[ -e $code/settings.json ]] || echo '{}' >"$code/settings.json"
  mkdir -p "$code/snippets"
  for name in settings.json keybindings.json snippets; do
    [[ -e $personal/$name || -L $personal/$name ]] || ln -s "$code/$name" "$personal/$name"
  done
}

# Where a mode's terminals (home), agents and file manager start: the config's folders, else ~.
dm_mode_dir() {
  local kind name
  case ${2:-home} in
    agent) kind=AGENT ;;
    files) kind=FILES ;;
    *) kind=HOME ;;
  esac
  name=DM_${kind}_${1:-work}
  dm_valid_mode "${1:-}" || name=DM_${kind}_work
  printf '%s\n' "${!name:-$HOME}"
}

# The mode a terminal or agent window class stands for (Omarchy's own agents are Work).
dm_class_mode() {
  case $1 in
    org.omarchy.term-work | org.omarchy.agent-work | org.omarchy.agent) echo work ;;
    org.omarchy.term-personal | org.omarchy.agent-personal) echo personal ;;
  esac
}

# Whether a Ghostty instance owns this class (its D-Bus name).
dm_has_bus_name() {
  dm_run busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameHasOwner s "$1" 2>/dev/null |
    grep -q '^b true'
}

# A new terminal opens in the focused terminal's folder when that terminal is of the same
# mode, else in the mode's folder.
dm_terminal_dir() {
  local class cwd
  class=$(dm_run hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty' 2>/dev/null)
  if [[ $class == "org.omarchy.term-$1" ]]; then
    cwd=$(dm_run omarchy-cmd-terminal-cwd 2>/dev/null)
    if [[ -n $cwd && -d $cwd ]]; then
      printf '%s\n' "$cwd"
      return
    fi
  fi
  dm_mode_dir "$1" terminal
}

# The config-derived variables, for every shell and command that sources this file.
dm_load_config
