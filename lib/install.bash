# account-switcher: `account-switcher install` and `uninstall` (README "Install"). Install leaves what is
# already in place alone, backs a file up (<file>.bak.<epoch>) before its first change, and
# adds blocks uninstall can find and take out again; a file it moved aside is listed in
# $(dm_state_dir)/install and put back. Sourced by bin/account-switcher after lib/mode.bash and
# lib/config.bash.

REQUIRE_LINE='require("default.hypr.require_optional").module("hypr.account-switcher")'
REQUIRE_MARK='-- account-switcher: Work/Personal modes (account-switcher uninstall takes these two lines out)'
PRE_COMMENT="# account-switcher: this terminal's Work/Personal accounts, history and z jumps (before Omarchy's rc)"
POST_COMMENT="# account-switcher: the agent command per mode (after Omarchy's aliases)"
GUARD_SECTION=hook.account-switcher-guard
COMMANDS=(account-switcher account-switcher-ghostty account-switcher-open account-switcher-commit-guard account-switcher-share-picker code)
INSTALL_EPOCH=$(date +%s)
declare -A INSTALL_BACKED_UP=()

say() { echo "account-switcher: $*"; }
short() { printf '%s\n' "${1/#"$HOME"/\~}"; }

# A copy of FILE's content next to it, once per run, before its first change.
backup_once() {
  [[ -e $1 && -z ${INSTALL_BACKED_UP[$1]-} ]] || return 0
  cp -aL "$1" "$1.bak.$INSTALL_EPOCH" && INSTALL_BACKED_UP[$1]=1
}

# The file a path names, through any symlinks: edits go there, so linked dotfiles stay linked.
real_path() { readlink -f -- "$1" 2>/dev/null || printf '%s\n' "$1"; }

# The bash lines that source the hooks; the plugin under ~ is written as $HOME/….
hook_line() {
  local path=$DM_PLUGIN/shell/$1.bash
  [[ $path == "$HOME"/* ]] && path='$HOME'${path#"$HOME"}
  printf '[[ -r "%s" ]] && source "%s"\n' "$path" "$path"
}
# Exactly what install puts in ~/.bashrc: the pre hook and a blank line before Omarchy's rc
# line, a blank line and the post hook after it. Uninstall takes out the same text.
pre_text() { printf '%s\n%s\n\n' "$PRE_COMMENT" "$(hook_line pre)"; }
post_text() { printf '\n%s\n%s\n' "$POST_COMMENT" "$(hook_line post)"; }
# set_text VAR COMMAND…: VAR=$(COMMAND…) without losing trailing newlines.
set_text() { local t; t=$("${@:2}"; echo .); printf -v "$1" '%s' "${t%.}"; }

# ---------------------------------------------------------------- steps

install_check() {
  local missing=() cmd
  [[ -f $CONFIG/hypr/hyprland.lua ]] || missing+=("Hyprland's Lua config ($(short "$CONFIG/hypr/hyprland.lua"))")
  for cmd in ghostty jq omarchy-shell; do command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd"); done
  ((${#missing[@]} == 0)) && return 0
  printf 'account-switcher install: missing %s\n' "${missing[@]}" >&2
  return 1
}

# No config yet: the example goes in place, to be edited before installing for real.
install_config() {
  local file
  file=$(dm_config_path)
  [[ -e $file ]] && return 0
  mkdir -p "${file%/*}" && cp "$DM_PLUGIN/config.example.json" "$file" && chmod 600 "$file" || return 1
  say "wrote $(short "$file") from the example. Put your own accounts, browsers, apps and folders in it, then run $(short "$DM_PLUGIN/bin/account-switcher") install again."
  return 2
}

# LINK -> TARGET; anything else at LINK is moved aside first (and listed for uninstall).
install_link() {
  local link=$1 target=$2 aside
  [[ -L $link && $(readlink "$link") == "$target" ]] && return 0
  if [[ -e $link || -L $link ]]; then
    aside=$link.bak.$INSTALL_EPOCH
    mv "$link" "$aside" || return 1
    printf 'aside %s %s\n' "$link" "$aside" >>"$(dm_state_dir)/install"
    say "moved $(short "$link") aside to $(short "$aside")"
  fi
  mkdir -p "${link%/*}" && ln -s "$target" "$link"
}

install_hypr() {
  local lua=$CONFIG/hypr/hyprland.lua
  install_link "$CONFIG/hypr/account-switcher.lua" "$DM_PLUGIN/hypr/account-switcher.lua" &&
    install_link "$CONFIG/hypr/account-switcher" "$DM_PLUGIN/hypr/account-switcher" || return 1
  if ! grep -qxF "$REQUIRE_LINE" "$lua"; then
    backup_once "$lua"
    printf '\n%s\n%s\n' "$REQUIRE_MARK" "$REQUIRE_LINE" >>"$lua"
    say "Hyprland loads the switcher ($(short "$lua"))"
  fi
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && dm_run hyprctl reload >/dev/null 2>&1
  return 0
}

install_git() {
  local cfg=$CONFIG/git/config
  git config --file "$cfg" --get "$GUARD_SECTION.command" >/dev/null 2>&1 && return 0
  mkdir -p "${cfg%/*}"
  [[ -e $cfg ]] || printf 'created %s\n' "$cfg" >>"$(dm_state_dir)/install"
  backup_once "$cfg"
  cfg=$(real_path "$cfg")
  git config --file "$cfg" "$GUARD_SECTION.event" prepare-commit-msg &&
    git config --file "$cfg" "$GUARD_SECTION.command" \
      "test -x $BIN/account-switcher-commit-guard || exit 0; $BIN/account-switcher-commit-guard" || return 1
  say "git checks each commit's address ($(short "$cfg"))"
}

# The pre hook goes before Omarchy's rc and the post hook after it (at the end when there is
# no such line).
install_bash() {
  local rc=$HOME/.bashrc
  [[ -e $rc ]] || : >"$rc"
  grep -qF '/shell/pre.bash' "$rc" && return 0
  backup_once "$rc"
  local pre post
  set_text pre pre_text
  set_text post post_text
  if grep -q 'default/bash/rc' "$rc"; then
    local real
    real=$(real_path "$rc")
    PRE=$pre POST=$post awk '
      !done && /default\/bash\/rc/ { printf "%s%s\n%s", ENVIRON["PRE"], $0, ENVIRON["POST"]; done = 1; next }
      { print }' "$real" >"$real.new" && mv -f "$real.new" "$real"
  else
    [[ ! -s $rc || $(tail -c1 "$rc") == "" ]] || echo >>"$rc"
    printf '%s%s' "$pre" "$post" >>"$rc"
  fi
  say "terminals get their mode's accounts ($(short "$rc"))"
}

# xdph's share picker becomes the switcher's, which hands the current mode's windows to the
# one that was there (kept in $(dm_state_dir)/picker; empty: xdph's own).
install_picker() {
  local conf=$CONFIG/hypr/xdph.conf ours=$BIN/account-switcher-share-picker current
  current=$(sed -n 's/^[[:space:]]*custom_picker_binary[[:space:]]*=[[:space:]]*//p' "$conf" 2>/dev/null | tail -n1)
  [[ $current == "$ours" ]] && return 0
  printf '%s\n' "$current" >"$(dm_state_dir)/picker"
  if [[ ! -e $conf ]]; then
    printf 'created %s\n' "$conf" >>"$(dm_state_dir)/install"
    printf 'screencopy {\n    custom_picker_binary = %s\n}\n' "$ours" >"$conf"
  else
    backup_once "$conf"
    local real
    real=$(real_path "$conf")
    if [[ -n $current ]]; then
      OURS=$ours awk '/^[[:space:]]*custom_picker_binary[[:space:]]*=/ { sub(/=.*/, "= " ENVIRON["OURS"]) } { print }' \
        "$real" >"$real.new" && mv -f "$real.new" "$real"
    elif grep -q '^[[:space:]]*screencopy[[:space:]]*{' "$conf"; then
      OURS=$ours awk '{ print } /^[[:space:]]*screencopy[[:space:]]*{/ && !done { print "    custom_picker_binary = " ENVIRON["OURS"]; done = 1 }' \
        "$real" >"$real.new" && mv -f "$real.new" "$real"
    else
      printf '\nscreencopy {\n    custom_picker_binary = %s\n}\n' "$ours" >>"$conf"
    fi
  fi
  dm_run systemctl --user try-restart xdg-desktop-portal-hyprland.service >/dev/null 2>&1
  say "screen shares offer only the current mode's windows ($(short "$conf"))"
}

# The badge takes the place of Omarchy's workspace buttons (it draws the mode's own). What it did
# is recorded ("bar replaced", "bar removed SECTION INDEX" when both were there because the badge
# was enabled while adding the plugin, "bar added") so uninstall can undo exactly that.
# jq: sections(F) runs F on each bar section that is a list (Omarchy's bar takes other shapes too).
SECTIONS='def sections(f): .bar.layout |= with_entries(.value |= (if type == "array" then f else . end));'

install_bar() {
  local f=$CONFIG/omarchy/shell.json mode ws where did=
  [[ -f $f ]] || return 0
  mode=$(jq '[.bar.layout[]?[]? | select(.id? == "account-switcher")] | length' "$f" 2>/dev/null)
  ws=$(jq '[.bar.layout[]?[]? | select(.id? == "omarchy.workspaces")] | length' "$f" 2>/dev/null)
  ((${mode:-0} > 0 && ${ws:-0} == 0)) && return 0
  backup_once "$f"
  f=$(real_path "$f")
  if ((${mode:-0} > 0)); then
    where=$(jq -r 'first(.bar.layout | to_entries[] | .key as $s | .value | arrays | to_entries[]
      | select(.value.id? == "omarchy.workspaces") | "\($s) \(.key)")' "$f")
    jq "$SECTIONS"' sections(map(select(.id? != "omarchy.workspaces")))' "$f" >"$f.new" && did="removed $where"
  elif ((${ws:-0} > 0)); then
    jq "$SECTIONS"' sections(map(if .id? == "omarchy.workspaces" then {"id": "account-switcher"} else . end))' \
      "$f" >"$f.new" && did=replaced
  else
    jq '.bar.layout.left = [{"id": "account-switcher"}] + ((.bar.layout.left | arrays) // [])' "$f" >"$f.new" && did=added
  fi
  if [[ -n $did ]] && mv -f "$f.new" "$f"; then
    printf 'bar %s\n' "$did" >>"$(dm_state_dir)/install"
    say "the mode badge is on the bar ($(short "$f"))"
  else
    rm -f "$f.new"
    say "couldn't edit $(short "$f"); put the badge on the bar with: omarchy bar put account-switcher"
  fi
}

# The copy is a new plugin folder, so the shell has to find it before it can turn it on (as
# omarchy-plugin-clone does). When it can't, install says how to do it later.
install_notifications() {
  local i
  notifications_sync || return 1
  notifications_enabled && return 0
  dm_run omarchy-shell shell rescanPlugins >/dev/null 2>&1
  for ((i = 0; i < 40; i++)); do
    dm_run omarchy-plugin-list --json 2>/dev/null | jq -e --arg id "$NOTIFY_ID" 'any(.[]; .id == $id)' >/dev/null 2>&1 && break
    sleep 0.05
  done
  dm_run omarchy-plugin-enable "$NOTIFY_ID" >/dev/null 2>&1 ||
    say "couldn't turn on $NOTIFY_ID (\"Work waits for you\"); after omarchy restart shell, run: omarchy plugin enable $NOTIFY_ID"
  return 0
}

# dm_install: every step in order; a config that doesn't check out stops it before any change.
dm_install() {
  install_check || return 1
  install_config
  case $? in 0) ;; 2) return 0 ;; *) return 1 ;; esac
  setup_all || return 1
  mkdir -p "$(dm_state_dir)"
  install_links
  install_hypr && install_git && install_bash && install_picker || return 1
  desktop_apply
  install_bar && install_notifications || return 1
  cat <<EOF
account-switcher: installed. Next:
  1. omarchy restart shell
  2. Choose each mode's browser and apps: "Choose apps…" in the badge's panel (right-click it),
     or omarchy-shell account-switcher.apps open.
  3. In a new terminal, sign each GitHub account in once with gh auth login; every mode uses its own.
  4. Sign each mode's browser into that mode's accounts.
To remove it later: account-switcher uninstall first, then omarchy plugin remove account-switcher.
EOF
}

# ---------------------------------------------------------------- uninstall

# What was typed in each mode goes back to ~/.bash_history, Work's then Personal's (bash keeps no
# times to interleave them by). Each mode's file began as a copy of it; only what came after is
# added (all of a file that no longer starts that way). The mode files go: they're in it now.
history_merge() {
  local main=$HOME/.bash_history dir f n seed
  dir=$(dm_state_dir)/history
  [[ -s $dir/bash-work || -s $dir/bash-personal ]] || return 0
  seed=$(mktemp) || return 1
  cat "$main" >"$seed" 2>/dev/null
  n=$(wc -l <"$seed")
  for f in "$dir/bash-work" "$dir/bash-personal"; do
    [[ -s $f ]] || continue
    if cmp -s <(head -n "$n" "$f") "$seed"; then tail -n +"$((n + 1))" "$f"; else cat "$f"; fi
  done >>"$main" && rm -f "$dir/bash-work" "$dir/bash-personal"
  rm -f "$seed"
}

# The first of the TEXTs found in FILE taken out, exactly as install put it there.
remove_text() {
  local file=$1 text
  shift
  [[ -s $file ]] || return 0
  file=$(real_path "$file")
  for text in "$@"; do
    TEXT=$text perl -0777 -ne 'exit(index($_, $ENV{TEXT}) >= 0 ? 0 : 1)' "$file" || continue
    TEXT=$text perl -0777 -i -pe 's/\Q$ENV{TEXT}\E//' "$file"
    return
  done
  return 0
}

dm_uninstall() {
  local purge=${1:-} state kind path aside name f bar= bar_where=
  local -a asides=() created=()
  state=$(dm_state_dir)
  while read -r kind path aside; do
    case $kind in
      aside) asides+=("$path" "$aside") ;;
      created) created+=("$path") ;;
      bar) bar=$path bar_where=$aside ;;
    esac
  done < <(cat "$state/install" 2>/dev/null)
  # The commands first, so the running bar service can't put launcher entries back meanwhile;
  # a command of the user's own under the same name returns. Ours point into this checkout,
  # whatever its folder is called (a git clone's is omarchy-account-switcher).
  local target
  for name in "${COMMANDS[@]}"; do
    target=$(readlink "$BIN/$name" 2>/dev/null)
    [[ -L $BIN/$name ]] && [[ $target == "$DM_PLUGIN/bin/$name" || $target == */account-switcher/bin/"$name" ]] && rm -f "$BIN/$name"
    [[ -e $ORIGINALS/bin/$name || -L $ORIGINALS/bin/$name ]] && [[ ! -e $BIN/$name ]] && mv -f "$ORIGINALS/bin/$name" "$BIN/$name"
  done
  # Notifications: Omarchy's own again, with what the copy was holding. With no shell to ask,
  # shell.json is changed the way the shell would have (it reads it when it next starts).
  if notifications_enabled; then
    if dm_run omarchy-plugin-enable omarchy.notifications >/dev/null 2>&1; then
      notifications_ready && notifications_handoff
    else
      f=$(real_path "$CONFIG/omarchy/shell.json")
      jq --arg clone "$NOTIFY_ID" --arg source omarchy.notifications '
        def id: if type == "object" then .id else . end;
        (if has("plugins") then .plugins |= map(select(id != $clone)) else . end)
        | (if has("disabledPlugins") then .disabledPlugins |= map(select(. != $source)) else . end)
        | (if has("cloneSourceRestores") then .cloneSourceRestores |= map(select(. != $clone)) else . end)
        | if .disabledPlugins == [] then del(.disabledPlugins) else . end
        | if .cloneSourceRestores == [] then del(.cloneSourceRestores) else . end' "$f" >"$f.new" &&
        mv -f "$f.new" "$f" || rm -f "$f.new"
    fi
  fi
  rm -rf "$CONFIG/omarchy/plugins/$NOTIFY_ID"
  # The bar, as install found it.
  f=$(real_path "$CONFIG/omarchy/shell.json")
  if [[ -f $f ]] && jq -e '[.bar.layout[]?[]? | select(.id? == "account-switcher")] | length > 0' "$f" >/dev/null 2>&1; then
    local ws
    ws=$(jq '[.bar.layout[]?[]? | select(.id? == "omarchy.workspaces")] | length' "$f" 2>/dev/null)
    local edited=1
    case $bar in
      removed)
        read -r kind name <<<"$bar_where"
        jq --arg s "${kind:-left}" --argjson i "${name:-0}" "$SECTIONS"' sections(map(select(.id? != "account-switcher")))
          | .bar.layout[$s] = (((.bar.layout[$s] | arrays) // []) | .[:$i] + [{"id": "omarchy.workspaces"}] + .[$i:])' \
          "$f" >"$f.new" || edited=
        ;;
      added) jq "$SECTIONS"' sections(map(select(.id? != "account-switcher")))' "$f" >"$f.new" || edited= ;;
      *)
        if ((${ws:-0} > 0)); then
          jq "$SECTIONS"' sections(map(select(.id? != "account-switcher")))' "$f" >"$f.new" || edited=
        else
          jq "$SECTIONS"' sections(map(if .id? == "account-switcher" then {"id": "omarchy.workspaces"} else . end))' \
            "$f" >"$f.new" || edited=
        fi
        ;;
    esac
    if [[ -n $edited ]]; then
      mv -f "$f.new" "$f"
    else
      rm -f "$f.new"
      say "couldn't edit $(short "$f"); the badge is still on the bar (take account-switcher out of it by hand)"
    fi
  fi
  # The share picker: the previous one back, or our line out.
  f=$(real_path "$CONFIG/hypr/xdph.conf")
  if grep -qF "custom_picker_binary = $BIN/account-switcher-share-picker" "$f" 2>/dev/null; then
    local previous
    previous=$(cat "$state/picker" 2>/dev/null)
    if [[ -n $previous ]]; then
      PREV=$previous awk '/^[[:space:]]*custom_picker_binary[[:space:]]*=/ { sub(/=.*/, "= " ENVIRON["PREV"]) } { print }' \
        "$f" >"$f.new" && mv -f "$f.new" "$f"
    else
      local ours=$BIN/account-switcher-share-picker
      remove_text "$f" $'\nscreencopy {\n    custom_picker_binary = '"$ours"$'\n}\n' \
        $'screencopy {\n    custom_picker_binary = '"$ours"$'\n}\n' "    custom_picker_binary = $ours"$'\n'
    fi
    dm_run systemctl --user try-restart xdg-desktop-portal-hyprland.service >/dev/null 2>&1
  fi
  # Launcher entries: the user's own versions back, the switcher's own gone; the mail handler
  # that was there before (`omarchy refresh applications` brings back Omarchy's own entries).
  for f in "$APPS"/*.desktop; do
    is_managed "$f" || continue
    name=${f##*/}
    if [[ -f $ORIGINALS/applications/$name ]]; then mv -f "$ORIGINALS/applications/$name" "$f"; else rm -f "$f"; fi
  done
  for f in "$ORIGINALS"/applications/*.desktop; do
    [[ -f $f && ! -e $APPS/${f##*/} ]] && mv -f "$f" "$APPS/${f##*/}"
  done
  mime_restore x-scheme-handler/mailto account-switcher-mailto.desktop
  dm_run update-desktop-database "$APPS" >/dev/null 2>&1
  # Shells, git, Hyprland.
  local text
  set_text text pre_text
  remove_text "$HOME/.bashrc" "$text"
  set_text text post_text
  remove_text "$HOME/.bashrc" "$text"
  history_merge
  git config --file "$(real_path "$CONFIG/git/config")" --remove-section "$GUARD_SECTION" >/dev/null 2>&1
  remove_text "$CONFIG/hypr/hyprland.lua" $'\n'"$REQUIRE_MARK"$'\n'"$REQUIRE_LINE"$'\n' "$REQUIRE_LINE"$'\n'
  for path in "$CONFIG/hypr/account-switcher.lua" "$CONFIG/hypr/account-switcher"; do
    [[ -L $path && $(readlink "$path") == "$DM_PLUGIN"/* ]] && rm -f "$path"
  done
  # What install moved aside goes back; files it created go when empty.
  local i
  for ((i = 0; i < ${#asides[@]}; i += 2)); do
    [[ -e ${asides[i]} || ! -e ${asides[i + 1]} ]] || mv "${asides[i + 1]}" "${asides[i]}"
  done
  for path in "${created[@]}"; do [[ -s $path ]] || rm -f "$path"; done
  rm -f "$state/install"
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && dm_run hyprctl reload >/dev/null 2>&1
  # A mode's global git file holding settings of the user's own stays, with a word on where.
  local m
  for m in work personal; do
    f=$CONFIG/git/account-switcher-$m
    [[ -f $f ]] || continue
    if cmp -s <(git_global_text "$m") "$f"; then
      [[ $purge == --purge ]] && rm -f "$f"
    else
      say "what you set with git config --global in ${m^} terminals stays in $(short "$f"); copy what you want into ~/.config/git/config"
    fi
  done
  if [[ $purge == --purge ]]; then
    for f in "$CONFIG"/git/account-switcher-*.inc; do
      [[ -e $f ]] && head -n1 "$f" | grep -q '^# Generated by account-switcher setup' && rm -f "$f"
    done
    rm -rf "$(dirname "$(dm_config_path)")" "$state" "$(dm_data_dir)"
  fi
  say "uninstalled. Run omarchy refresh applications to get Omarchy's own launcher entries back, then omarchy restart shell."
}
