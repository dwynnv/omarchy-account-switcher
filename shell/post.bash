# account-switcher, sourced from ~/.bashrc after Omarchy's rc. `a` starts the agent here; a shell
# sitting in ~ starts it in the mode's agent folder instead (omarchy-agent would turn ~ into
# ~/Work), without moving the shell itself.
unalias a 2>/dev/null
a() {
  local dir
  dir=$(dm_mode_dir "${ACCOUNT_SWITCHER_MODE:-work}" agent)
  if [[ $PWD == "$HOME" && $dir != "$HOME" ]]; then
    (cd "$dir" && omarchy-agent --inline "$@")
  else
    omarchy-agent --inline "$@"
  fi
}

# gh inside a repo of a configured account (config.json "accounts") acts as that account in
# its mode, the way the mode's git config already sends its pushes there.
# Signing in and out changes the shared accounts (~/.config/gh), and each mode's settings are
# then rebuilt from them; switching the active account would only change this terminal's
# mode's account, which follows the mode instead.
gh() {
  case "${1:-} ${2:-}" in
    "auth login" | "auth logout")
      GH_CONFIG_DIR=$HOME/.config/gh command gh "$@"
      local rc=$?
      "$HOME/.local/bin/account-switcher" setup >/dev/null 2>&1
      return $rc
      ;;
    "auth switch")
      local entry owner mode login accounts=
      for entry in "${DM_ACCOUNTS[@]}"; do
        read -r owner mode login <<<"$entry"
        accounts+="; ${mode^} $owner repos: $login"
      done
      echo "gh accounts follow the mode here (Work: $(dm_account work); Personal: $(dm_account personal)$accounts)." >&2
      echo "Use a terminal of the other mode, or for one command: GH_CONFIG_DIR=~/.local/share/account-switcher/gh/<account> gh …" >&2
      return 1
      ;;
  esac
  local url dir=
  url=$(git config --get remote.origin.url 2>/dev/null)
  [[ $url =~ github\.com[:/]([^/]+)/ ]] && dir=$(dm_owner_gh_dir "${BASH_REMATCH[1]}" "${ACCOUNT_SWITCHER_MODE:-work}")
  if [[ -n $dir ]]; then
    GH_CONFIG_DIR=$dir command gh "$@"
  else
    command gh "$@"
  fi
}

# Omarchy's `h`: the mode's own herdr session (and server, through HERDR_SOCKET_PATH).
unalias h 2>/dev/null
h() {
  if (($#)); then herdr "$@"; else herdr --session "${ACCOUNT_SWITCHER_MODE:-work}"; fi
}

# `code` is the mode's VS Code (bin/code), whatever comes first on PATH: Omarchy puts
# ~/.local/bin, where install links it, after the system's /usr/bin/code.
code() { "$DM_PLUGIN/bin/code" "$@"; }
