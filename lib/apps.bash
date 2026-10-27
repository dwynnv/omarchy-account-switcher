# account-switcher: the setup window's side of the config. apps-list reads the installed launcher
# entries and says what each one needs in config.json, or why it can't be put in a mode;
# apps-set writes the window's choice. Sourced by bin/account-switcher after lib/install.bash.

# Launch commands that start something else: the window can't tell what runs behind them.
APPS_WRAPPERS='["env","flatpak","sh","bash","dash","zsh","fish","uwsm","uwsm-app","app2unit","systemd-run","snap"]'

# The launcher entries to look at, the ones that win first: the user's own (not the switcher's
# copies), what the switcher kept of theirs, Omarchy's, the other data folders, the system's.
apps_entry_files() {
  local d f
  local -a dirs
  for f in "$APPS"/*.desktop; do [[ -f $f ]] && ! is_managed "$f" && printf '%s\n' "$f"; done
  for f in "$ORIGINALS"/applications/*.desktop "$OMARCHY_APPS"/*.desktop; do [[ -f $f ]] && printf '%s\n' "$f"; done
  IFS=: read -ra dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  for d in "${dirs[@]}"; do
    [[ -d $d/applications && ! $d/applications -ef $SYSTEM_APPS ]] || continue
    for f in "$d"/applications/*.desktop; do [[ -f $f ]] && printf '%s\n' "$f"; done
  done
  for f in "$SYSTEM_APPS"/*.desktop; do [[ -f $f ]] && printf '%s\n' "$f"; done
}

# One JSON object per entry file: its path and the [Desktop Entry] keys the window uses.
apps_read_entries() {
  local -a files
  mapfile -t files < <(apps_entry_files)
  ((${#files[@]})) || return 0
  awk '
    FNR == 1 { if (path != "") emit(); path = FILENAME; group = ""; delete k }
    /^\[/ { group = $0; next }
    group == "[Desktop Entry]" && /^[A-Za-z]+=/ {
      i = index($0, "="); key = substr($0, 1, i - 1)
      if (!(key in k)) k[key] = substr($0, i + 1)
    }
    END { if (path != "") emit() }
    function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, " ", s); return "\"" s "\"" }
    function emit(  out, n, i, names) {
      split("Type Name Icon Exec StartupWMClass Categories NoDisplay Hidden OnlyShowIn NotShowIn", names, " ")
      out = "{\"path\":" esc(path)
      for (i = 1; i <= 10; i++) out = out ",\"" names[i] "\":" esc(names[i] in k ? k[names[i]] : "")
      print out "}"
    }' "${files[@]}"
}

# For each program name or path an entry starts: where it is, and the folder its real
# executable runs from (a script that only execs another program counts as that program).
apps_resolve() {
  local tok bin real next
  while IFS= read -r tok; do
    bin=
    if [[ $tok == /* ]]; then
      [[ -x $tok ]] && bin=$tok
    else
      bin=$(command -v -- "$tok" 2>/dev/null) || bin=
      [[ $bin == /* ]] || bin=
    fi
    real=
    if [[ -n $bin ]]; then
      real=$(readlink -f -- "$bin")
      if [[ $(head -c2 -- "$real" 2>/dev/null) == '#!' ]]; then
        next=$(sed -nE 's/^[[:space:]]*exec[[:space:]]+"?(\/[^" ]+).*/\1/p' -- "$real" | head -n1)
        [[ -n $next && -x $next ]] && real=$(readlink -f -- "$next")
      fi
    fi
    jq -cn --arg t "$tok" --arg b "$bin" --arg d "${real:+${real%/*}/}" '{($t): {bin: $b, exeDir: $d}}'
  done | jq -cs 'add // {}'
}

# apps-list: {entries: [...], assigned: {work, personal, follow}} (see the plan's interface).
apps_list() {
  local cfg entries resolved
  cfg=$(dm_config_path)
  [[ -r $cfg ]] || { echo "account-switcher apps-list: no config at $cfg" >&2; return 1; }
  entries=$(apps_read_entries | jq -cs '
    def tokens: [scan("\"((?:[^\"\\\\]|\\\\.)*)\"|'"'"'([^'"'"']*)'"'"'|(\\S+)") | map(select(. != null))[0]
      | gsub("\\\\(?<c>.)"; .c)] | map(select(test("^%[A-Za-z]$") | not));
    map(. + {id: (.path | sub(".*/"; "")), argv: (.Exec | tokens)})')
  resolved=$(jq -r '.[] | .argv[0] // empty' <<<"$entries" | sort -u | apps_resolve)
  # Lists this long go to jq as files: an argument is capped at 128 KiB.
  jq -n --slurpfile entries <(printf '%s' "$entries") --slurpfile res <(printf '%s' "$resolved") \
    --argjson wrappers "$APPS_WRAPPERS" \
    --slurpfile cfg "$cfg" --arg user "$APPS/" --arg kept "$ORIGINALS/applications/" \
    --arg omarchy "$OMARCHY_APPS/" --arg system "$SYSTEM_APPS/" '
    $cfg[0] as $c | $entries[0] as $entries | $res[0] as $res
    | def base: sub(".*/"; "");
      def origin: if (.path | startswith($system)) then "system"
        elif (.path | startswith($user)) or (.path | startswith($kept)) then "user"
        elif (.path | startswith($omarchy)) then "omarchy" else "other" end;
      def kind: if ((.argv[0] // "") | base) == "omarchy-launch-webapp" then "webapp"
        elif (.Categories | split(";") | index("WebBrowser")) then "browser" else "app" end;
      def shown: .Type == "Application" and .NoDisplay != "true" and .Hidden != "true"
        and (.OnlyShowIn == "" or (.OnlyShowIn | split(";") | index("Hyprland")))
        and ((.NotShowIn | split(";") | index("Hyprland")) | not);
      def key_of: ascii_downcase | sub("\\.desktop$"; "") | gsub("[^a-z0-9._-]"; "-") | sub("^[^a-z0-9]+"; "");
      # What config.jq accepts in a description (errors_custom).
      def holdable: (.bin | test("^/[A-Za-z0-9/._+-]+$")) and (.class | test("^[A-Za-z0-9._+-]+$"))
        and (.desktop | test("^[A-Za-z0-9._+-]+\\.desktop$")) and (.execToken | test("^[A-Za-z0-9/._+-]+$"))
        and ((.exeDir // "/x/") | test("^/[A-Za-z0-9/._+-]+/$"));
      def described($kind; $id): ($c[if $kind == "browser" then "customBrowsers" else "customApps" end] // {})
        | to_entries | map(select(.value.desktop == $id)) | first;
    [ $entries | map(. + {origin: origin, kind: kind}) | group_by(.id)[]
      # A web app wins wherever it is; any other app is the system entry desktop-apply takes over.
      | (map(select(.kind == "webapp")) | first) // (map(select(.origin == "system")) | first) // first ]
    | map(select(shown))
    | map(. as $e
      | ($e.argv[0] // "") as $tok
      | ($res[$tok] // {bin: "", exeDir: ""}) as $r
      | (if $e.StartupWMClass != "" then $e.StartupWMClass else (if $r.bin != "" then $r.bin else $tok end | base) end) as $class
      | ({label: $e.Name, bin: (if $r.bin != "" then $r.bin else $tok end), class: $class, desktop: $e.id,
          execToken: $tok, notify: [$e.Name], notifyEntries: [$e.id | sub("\\.desktop$"; "")]}
         + if $e.kind == "browser" then {exeDir: $r.exeDir, routeDesktop: true} else {} end) as $def
      | described($e.kind; $e.id) as $own
      | {id: $e.id, name: $e.Name, icon: $e.Icon, kind: $e.kind}
        + if $e.kind == "webapp" then {usable: ($e.argv | length > 1), reason: (if ($e.argv | length > 1) then "" else "it has no address" end), key: $e.Name, def: null}
          else
            (if $e.origin != "system" then "not from the system app folder"
             elif ($wrappers | index($tok | base)) then "launched through a wrapper (flatpak, env, sh)"
             elif $r.bin == "" then "its program isn'"'"'t installed"
             elif $class == "" then "its window class can'"'"'t be worked out"
             elif ($def | holdable | not) then "its path has characters the config can'"'"'t hold"
             else "" end) as $found_why
            # An app the config already describes can always be moved: its description is the user'"'"'s.
            | (if $own != null then "" else $found_why end) as $why
            | {usable: ($why == ""), reason: $why, key: ($own.key // ($e.id | key_of)), def: ($own.value // $def),
               scanned: $def}
          end)
    | sort_by(.name | ascii_downcase)
    | {entries: .,
       assigned: {work: {browser: ($c.work.browser // null), apps: ($c.work.apps // []), webapps: ($c.work.webapps // [])},
                  personal: {browser: ($c.personal.browser // null), apps: ($c.personal.apps // []), webapps: ($c.personal.webapps // [])},
                  follow: ($c.webappsFollowMode // [])}}'
}

# apps-set [JSON]: the window's choice ({work: {browser, apps, webapps}, personal: {…}, follow}),
# as the argument or on stdin,
# saved to config.json. Only the keys the window owns change; entries it described itself come
# and go with the apps, entries written by hand stay. Nothing is written unless the result checks
# out. Status 2: a request it can't use (named); 1: the result wouldn't check out.
apps_set() {
  local cfg real payload list result tmp
  cfg=$(dm_config_path)
  real=$(readlink -f -- "$cfg")
  if ! payload=$({ if (($#)); then printf '%s' "$1"; else cat; fi; } |
    jq -ce 'select(type == "object" and (.work | type) == "object" and (.personal | type) == "object")' 2>/dev/null); then
    echo "account-switcher apps-set: expected {work: {...}, personal: {...}, follow: [...]} on stdin" >&2
    return 2
  fi
  list=$(apps_list) || return 1
  result=$(jq -n --argjson p "$payload" --slurpfile l <(printf '%s' "$list") --slurpfile cfg "$real" '
    $cfg[0] as $c | $l[0] as $l
    | ($l.entries | map({key: .key, value: .}) | from_entries) as $found
    | def entry($kind; $k): if $kind == "browser" then ($c.customBrowsers // {})[$k] else ($c.customApps // {})[$k] end;
      def check($kind; $k):
        if entry($kind; $k) != null then empty
        elif ($found[$k] | not) or $found[$k].kind != $kind then "\"\($k)\" isn'"'"'t an installed \(if $kind == "app" then "app" else $kind end)"
        elif ($found[$k].usable | not) then "\"\($k)\" can'"'"'t be put in a mode yet: \($found[$k].reason)"
        else empty end;
      def check_web($n):
        if ([$c.work.webapps, $c.personal.webapps, $c.webappsFollowMode] | map(. // []) | add | index($n)) then empty
        elif ($found[$n] | not) or $found[$n].kind != "webapp" then "\"\($n)\" isn'"'"'t an installed web app"
        else empty end;
    [ ("work", "personal") as $m | $p[$m] as $x
      | ($x.browser | select(. != null) | check("browser"; .)),
        (($x.apps // [])[] | check("app"; .)),
        (($x.webapps // [])[] | check_web(.)) ]
    + [($p.follow // [])[] | check_web(.)] as $errors
    | if ($errors | length) > 0 then {errors: $errors}
      else
        [$p.work.browser, $p.personal.browser | select(. != null)] as $browsers
        | ([$p.work.apps, $p.personal.apps] | map(. // []) | add) as $apps
        # Ours: exactly what the scan would write for that name today. Hand-written entries differ.
        | def ours($k; $e): $found[$k].scanned != null and $e == $found[$k].scanned;
          def keep($all; $used): ($all // {}) | with_entries(select((.key as $k | $used | index($k)) or (ours(.key; .value) | not)));
          def add_new($all; $used; $kind): reduce ($used[] | select(entry($kind; .) == null)) as $k ($all // {}; .[$k] = $found[$k].scanned);
        {config: ($c
          | (if $p.work.browser == null then del(.work.browser) else .work.browser = $p.work.browser end)
          | (if $p.personal.browser == null then del(.personal.browser) else .personal.browser = $p.personal.browser end)
          | .work.apps = ($p.work.apps // []) | .personal.apps = ($p.personal.apps // [])
          | .work.webapps = ($p.work.webapps // []) | .personal.webapps = ($p.personal.webapps // [])
          | .webappsFollowMode = ($p.follow // [])
          | .customBrowsers = add_new(keep($c.customBrowsers; $browsers); $browsers; "browser")
          | .customApps = add_new(keep($c.customApps; $apps); $apps; "app")
          | if has("clockInApps") then
              .clockInApps |= map(select(. as $n | (["browser", "chrome", "code"] | index($n)) or ($p.work.apps // [] | index($n))))
              | if (.clockInApps | length) == 0 then del(.clockInApps) else . end
            else . end)}
      end') || return 1
  if jq -e '.errors' <<<"$result" >/dev/null; then
    jq -r '.errors[] | "account-switcher apps-set: " + .' <<<"$result" >&2
    return 2
  fi
  tmp=$(mktemp "${real%/*}/.config.json.XXXXXX") || return 1
  jq '.config' <<<"$result" >"$tmp"
  if ! config_check "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! { cp -a -- "$real" "$real.bak.$(date +%s)" && cat "$tmp" >"$real"; } 2>/dev/null; then
    rm -f "$tmp"
    echo "account-switcher apps-set: couldn't write $real" >&2
    return 1
  fi
  rm -f "$tmp"
  setup_all >/dev/null || return 1
  echo "account-switcher: saved; setup done"
}
