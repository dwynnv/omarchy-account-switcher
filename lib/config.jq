# account-switcher: checks config.json and derives what each side reads (lib/config.bash runs
# it). Nothing is built in: every browser and app is described in the config. Arguments:
# --arg what errors|derive, --slurpfile cfg CONFIG, --arg home, --arg data (the data folder), --arg gh (gh's path or
# ""), --arg cfgpath (the config path shown in generated files).

def modes: ["work", "personal"];
def cfg: $cfg[0];
def objectish: if type == "object" then . else {} end;
def browsers: cfg.customBrowsers // {} | objectish;
def apps: cfg.customApps // {} | objectish;
# What an unknown name gets told: the names it could have been, and where to describe it.
def known($all; $key): if ($all | length) == 0 then "describe it in \($key)"
  else "known: \($all | keys | join(", ")); or describe it in \($key)" end;

# The example's placeholders, so an unedited copy is never applied as someone's identity.
def placeholder: . == "Your Name" or . == "you@work.example" or . == "you@home.example"
  or . == "your-work-login" or . == "your-login" or . == "your-work-browser" or . == "your-personal-browser";

def is_text: type == "string" and length > 0;
def matches($re): if type == "string" then test($re) else false end;
def is_login: matches("^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$");
def is_email: matches("^[^@\\s\"\\\\]+@[^@\\s\"\\\\]+$");
def is_path: matches("^[^\"\\\\\\n]+$");
def is_name: matches("^[^/\\n\\t]+$");
def strs: if type == "array" then all(.[]; is_text) else false end;
def argv: if type == "array" and length > 0 then all(.[]; is_text) else false end;
def check($ok; $msg): if $ok then empty else $msg end;
def opt($obj; $key; $ok; $msg): if ($obj | type) == "object" and ($obj | has($key)) then check($ok; $msg) else empty end;
def uniq: reduce .[] as $x ([]; if index($x) != null then . else . + [$x] end);
# Keys an object may have; ones starting with _ are comments.
def unknown_keys($where; $allowed):
  if type == "object" then
    keys[] | select(startswith("_") | not) | select(. as $k | $allowed | index($k) == null) | "\($where)\(.): unknown key"
  else empty end;
def MODE_KEYS: ["git", "github", "githubOwners", "browser", "apps", "webapps", "folders"];
def FOLDER_KEYS: ["home", "agent", "files", "screenshots", "recordings", "downloads"];

# ---------------------------------------------------------------- checks

def errors_custom($kind; $fields; $lists; $bools):
  (cfg[$kind] // {}) as $x
  | if ($x | type) != "object" then "\($kind): must be an object"
    else ($x | to_entries[] | .key as $k | .value as $e
      | if ($e | type) != "object" then "\($kind).\($k): must be an object"
        else
          ($e | unknown_keys("\($kind).\($k)."; ["label"] + ($fields | keys) + $lists + $bools)),
          check($k | matches("^[a-z0-9][a-z0-9._-]*$"); "\($kind).\($k): the name may use lowercase letters, digits, . _ -"),
          ($fields | to_entries[] | .key as $f | .value as $re
            | check($e[$f] | matches($re); "\($kind).\($k): needs \($f)")),
          ($lists[] as $f | select(($e | has($f)) and (($e[$f] | strs) | not)) | "\($kind).\($k).\($f): must be a list"),
          ($bools[] as $f | select(($e | has($f)) and (($e[$f] | type) != "boolean")) | "\($kind).\($k).\($f): must be true or false")
        end)
    end;

def errors_mode($m):
  cfg[$m] as $c
  | if ($c | type) != "object" then "\($m): missing (it needs at least a browser)"
    else
      ($c | unknown_keys("\($m)."; MODE_KEYS)),
      (if ($c.git | type) == "object" then ($c.git | unknown_keys("\($m).git."; ["name", "email"])) else empty end),
      (if ($c.folders | type) == "object" then ($c.folders | unknown_keys("\($m).folders."; FOLDER_KEYS)) else empty end),
      (if ($c.browser | type) != "string" then "\($m).browser: missing"
       elif $c.browser | placeholder then empty
       elif (browsers | has($c.browser)) | not then "\($m).browser: unknown browser \"\($c.browser)\" (\(known(browsers; "customBrowsers")))"
       else empty end),
      (if $c | has("git") then
         if ($c.git | type) != "object" then "\($m).git: must be an object with name and email"
         else
           opt($c.git; "name"; $c.git.name | is_text; "\($m).git.name: must be text"),
           opt($c.git; "email"; $c.git.email | is_email; "\($m).git.email: not an email address")
         end
       else empty end),
      opt($c; "github"; $c.github | is_login; "\($m).github: not a GitHub login"),
      opt($c; "githubOwners"; ($c.githubOwners | type) == "array" and all($c.githubOwners[]; is_login);
        "\($m).githubOwners: must be a list of GitHub logins"),
      (if $c | has("apps") then
         if ($c.apps | strs) | not then "\($m).apps: must be a list of app names"
         else ($c.apps[] | select(. as $a | (apps | has($a)) | not)
           | "\($m).apps: unknown app \"\(.)\" (\(known(apps; "customApps")))")
         end
       else empty end),
      opt($c; "webapps"; ($c.webapps | type) == "array" and all($c.webapps[]; is_name);
        "\($m).webapps: must be a list of launcher names"),
      (if $c | has("folders") then
         if ($c.folders | type) != "object" then "\($m).folders: must be an object"
         else ($c.folders | to_entries[] | select(.key as $k | FOLDER_KEYS | index($k) != null)
           | select((.value | is_path) | not) | "\($m).folders.\(.key): must be a path")
         end
       else empty end)
    end;

def errors_cross:
  (if (cfg.work.browser | type) == "string" and cfg.work.browser == cfg.personal.browser then
     "personal.browser: must differ from work.browser (\(cfg.work.browser))" else empty end),
  ((cfg.work.apps // []) as $w
    | (cfg.personal.apps // []) | if type == "array" and ($w | type) == "array" then
        (.[] | select(. as $a | $w | index($a) != null) | "personal.apps: \"\(.)\" is already a work app")
      else empty end),
  ([(cfg.work.webapps // []), (cfg.personal.webapps // []), (cfg.webappsFollowMode // [])]
    | map(if type == "array" then . else [] end) | add | group_by(.) | map(select(length > 1) | .[0])[]
    | "webapps: \"\(.)\" is listed more than once");

def errors_top:
  (if cfg | has("accounts") then
     if (cfg.accounts | type) != "array" then "accounts: must be a list"
     else (cfg.accounts | to_entries[] | .key as $i | .value as $a
       | if ($a | type) != "object" then "accounts[\($i)]: must be an object"
         else
           ($a | unknown_keys("accounts[\($i)]."; ["owner", "mode", "github", "email", "folder"])),
           check($a.owner | is_login; "accounts[\($i)].owner: not a GitHub owner"),
           check($a.mode == "work" or $a.mode == "personal"; "accounts[\($i)].mode: must be work or personal"),
           check($a.github | is_login; "accounts[\($i)].github: not a GitHub login"),
           check($a.email | is_email; "accounts[\($i)].email: not an email address"),
           opt($a; "folder"; $a.folder | is_path; "accounts[\($i)].folder: must be a path")
         end)
     end
   else empty end),
  opt(cfg; "webappsFollowMode"; (cfg.webappsFollowMode | type) == "array" and all(cfg.webappsFollowMode[]; is_name);
    "webappsFollowMode: must be a list of launcher names"),
  opt(cfg; "holdApps"; cfg.holdApps | strs; "holdApps: must be a list of app names"),
  (if cfg | has("clockInApps") then
     if (cfg.clockInApps | strs) | not then "clockInApps: must be a list"
     else (cfg.clockInApps[] | select(. as $n | (["browser", "chrome", "code"] | index($n)) == null
         and ((cfg.work.apps // []) | if type == "array" then index($n) else null end) == null)
       | "clockInApps: \"\(.)\" isn't browser, code or one of work.apps")
     end
   else empty end),
  opt(cfg; "mailto"; cfg.mailto == "gmail" or cfg.mailto == "none"; "mailto: must be gmail or none"),
  errors_custom("customBrowsers";
    {bin: "^/[A-Za-z0-9/._+-]+$", exeDir: "^/[A-Za-z0-9/._+-]+/$", class: "^[A-Za-z0-9._+-]+$",
     desktop: "^[A-Za-z0-9._+-]+\\.desktop$", execToken: "^[A-Za-z0-9/._+-]+$"};
    ["notify", "notifyEntries"]; ["routeDesktop"]),
  errors_custom("customApps";
    {bin: "^/[A-Za-z0-9/._+-]+$", class: "^[A-Za-z0-9._+-]+$",
     desktop: "^[A-Za-z0-9._+-]+\\.desktop$", execToken: "^[A-Za-z0-9/._+-]+$"};
    ["classPrefixes", "notify", "notifyEntries"]; ["focusExisting"]);

def errors_example($m):
  cfg[$m] as $c
  | if ($c | type) != "object" then empty
    else
      (if ($c.git | type) == "object" then
         ($c.git.name | select(type == "string" and placeholder) | "\($m).git.name: still the example's; put your own"),
         ($c.git.email | select(type == "string" and placeholder) | "\($m).git.email: still the example's; put your own")
       else empty end),
      ($c.github | select(type == "string" and placeholder) | "\($m).github: still the example's; put your own"),
      ($c.browser | select(type == "string" and placeholder)
        | "\($m).browser: still the example's; describe your browser in customBrowsers and name it here")
    end;

def errors:
  if (cfg | type) != "object" then "config.json: must be a JSON object"
  else (cfg | unknown_keys(""; ["work", "personal", "accounts", "webappsFollowMode", "holdApps", "clockInApps",
      "mailto", "customBrowsers", "customApps"])),
    errors_top, (modes[] as $m | errors_mode($m), errors_example($m)), errors_cross
  end;

# ---------------------------------------------------------------- derived files

def expand:
  (if . == "~" then $home elif startswith("~/") then $home + .[1:] elif startswith("/") then . else $home + "/" + . end)
  | if length > 1 then rtrimstr("/") else . end;
def folder($m; $k):
  (cfg[$m].folders // {}) as $f
  | if $k == "home" then ($f.home // "~") | expand
    elif $k == "agent" or $k == "files" then ($f[$k] // $f.home // "~") | expand
    else ($f[$k] // "") | if . == "" then "" else expand end
    end;

def app($id): apps[$id] | {bin, class: (.class | ascii_downcase), desktop, execToken,
  focus: (if .focusExisting == true then 1 else 0 end), prefixes: (.classPrefixes // []),
  notify: (.notify // []), entries: (.notifyEntries // [])};
def browser($m): browsers[cfg[$m].browser] | . + {class: (.class | ascii_downcase),
  routeDesktop: (.routeDesktop == true), notify: (.notify // []), notifyEntries: (.notifyEntries // [])};
def mode_apps: [modes[] as $m | (cfg[$m].apps // [])[] | {id: ., mode: $m}];

# The GitHub owners each address commits for: a mode's own login and its githubOwners (when
# the mode has an address), then the accounts.
def owners:
  [ (modes[] as $m | cfg[$m] as $c
      | select(($c.git.email // "") != "")
      | ([$c.github // empty] + ($c.githubOwners // []))[]
      | {owner: ascii_downcase, email: ($c.git.email | ascii_downcase), login: ($c.github // "")}),
    ((cfg.accounts // [])[] | {owner: (.owner | ascii_downcase), email: (.email | ascii_downcase), login: .github}) ];
def emails:
  [ (modes[] as $m | cfg[$m].git.email // empty | {email: ascii_downcase, mode: $m}),
    ((cfg.accounts // [])[] | {email: (.email | ascii_downcase), mode: .mode}) ];
def clock_apps:
  (cfg.clockInApps // ((cfg.work.apps // []) + ["browser"])) | map(if . == "chrome" then "browser" else . end);

def sh_var($name; $v): "\($name)=\($v | tostring | @sh)";
def sh_assoc($name; $pairs): "declare -gA \($name)=(" + ([$pairs[] | "[\(.key | @sh)]=\(.value | tostring | @sh)"] | join(" ")) + ")";
def sh_array($name; $items): "declare -ga \($name)=(" + ([$items[] | @sh] | join(" ")) + ")";

def bash_text:
  [ "# account-switcher: generated by `account-switcher setup` from \($cfgpath); sourced by lib/mode.bash.",
    "DM_CONFIGURED=1",
    (modes[] as $m | cfg[$m] as $c | browser($m) as $b
      | sh_var("DM_LOGIN_\($m)"; $c.github // ""),
        sh_var("DM_HOME_\($m)"; folder($m; "home")),
        sh_var("DM_AGENT_\($m)"; folder($m; "agent")),
        sh_var("DM_FILES_\($m)"; folder($m; "files")),
        sh_var("DM_SHOTS_\($m)"; folder($m; "screenshots")),
        sh_var("DM_RECS_\($m)"; folder($m; "recordings")),
        sh_var("DM_DOWNLOADS_\($m)"; folder($m; "downloads")),
        sh_var("DM_BROWSER_\($m)"; $c.browser),
        sh_var("DM_BROWSER_BIN_\($m)"; $b.bin),
        sh_var("DM_BROWSER_CLASS_\($m)"; $b.class),
        sh_var("DM_BROWSER_EXEDIR_\($m)"; $b.exeDir)),
    sh_assoc("DM_APP_MODE"; [mode_apps[] | {key: .id, value: .mode}]),
    sh_assoc("DM_APP_BIN"; [mode_apps[] | {key: .id, value: app(.id).bin}]),
    sh_assoc("DM_APP_CLASS"; [mode_apps[] | {key: .id, value: app(.id).class}]),
    sh_assoc("DM_APP_DESKTOP"; [mode_apps[] | {key: .id, value: app(.id).desktop}]),
    sh_assoc("DM_APP_EXEC"; [mode_apps[] | {key: .id, value: app(.id).execToken}]),
    sh_assoc("DM_APP_FOCUS"; [mode_apps[] | {key: .id, value: app(.id).focus}]),
    sh_array("DM_ROUTE_BROWSERS"; [modes[] as $m | browser($m) | select(.routeDesktop) | "\($m) \(.desktop) \(.execToken)"]),
    sh_assoc("DM_WEBAPP_MODE"; [((cfg.work.webapps // [])[] | {key: ., value: "work"}),
      ((cfg.personal.webapps // [])[] | {key: ., value: "personal"}),
      ((cfg.webappsFollowMode // [])[] | {key: ., value: "follow"})]),
    sh_array("DM_ACCOUNTS"; [(cfg.accounts // [])[] | "\(.owner | ascii_downcase) \(.mode) \(.github)"]),
    sh_assoc("DM_OWNER_EMAIL"; [owners[] | {key: .owner, value: .email}]),
    sh_assoc("DM_OWNER_LOGIN"; [owners[] | {key: .owner, value: .login}]),
    sh_assoc("DM_EMAIL_MODE"; [emails[] | {key: .email, value: .mode}]),
    sh_var("DM_OWN_EMAILS"; " " + ([emails[].email] | uniq | join(" ")) + " "),
    sh_var("DM_CLOCK_APPS"; clock_apps | join(" ")),
    sh_var("DM_MAILTO"; cfg.mailto // "none"),
    sh_var("DM_GH"; $gh) ]
  | join("\n") + "\n";

def apps_text:
  [ "# account-switcher: generated by `account-switcher setup` from \($cfgpath); read by the Hyprland side.",
    (modes[] as $m | "exe \($m) \(browser($m).exeDir)"),
    (modes[] as $m | "class \($m) \(browser($m).class)"),
    (mode_apps[] | "class \(.mode) \(app(.id).class)"),
    (mode_apps[] | .mode as $m | app(.id).prefixes[] | "prefix \($m) \(.)"),
    (modes[] as $m | "browser \(browser($m).class)"),
    (mode_apps[] | "home \(app(.id).class)"),
    (mode_apps[] | app(.id).prefixes[] | "home-prefix \(.)"),
    ((cfg.work.apps // [])[] | "place \(app(.).class)"),
    "place \(browser("work").class)",
    "place com.microsoft.vscode" ]
  | join("\n") + "\n";

def hold_text:
  [(cfg.work.apps // [])[] | app(.)] as $wa
  | browser("work") as $wb
  | {version: 1,
     names: (([$wa[].notify[]] + $wb.notify + (cfg.holdApps // [])) | map(ascii_downcase) | uniq),
     entries: (([$wa[].entries[]] + $wb.notifyEntries) | map(ascii_downcase) | uniq)}
  | tojson + "\n";

# A git config value, quoted only when git would misread it.
def gitval:
  if test("[\"\\\\#;]") or test("^\\s") or test("\\s$")
  then "\"" + (gsub("\\\\"; "\\\\") | gsub("\""; "\\\"")) + "\"" else . end;
def shq: if test("^[A-Za-z0-9/._+=:-]+$") then . else @sh end;
def helper($login): "!GH_CONFIG_DIR=\("\($data)/gh/\($login)" | shq) \($gh | shq) auth git-credential";
def git_header: "# Generated by account-switcher setup from \($cfgpath); edits are overwritten.";

# The mode's identity, which its global git file (made once, then the user's) includes last.
def git_mode($m):
  cfg[$m] as $c
  | ($c.github // "") as $login
  | [(cfg.accounts // [])[] | select(.mode == $m)] as $accounts
  | [ git_header,
      (if ($c.git.name // "") != "" or ($c.git.email // "") != "" then
         "[user]",
         (if ($c.git.name // "") != "" then "\tname = \($c.git.name | gitval)" else empty end),
         (if ($c.git.email // "") != "" then "\temail = \($c.git.email | gitval)" else empty end)
       else empty end),
      ($accounts[] | select((.folder // "") != "")
        | "[includeIf \"gitdir:\(.folder | expand)/\"]", "\tpath = account-switcher-owner-\(.owner | ascii_downcase).inc"),
      (if $gh != "" and $login != "" then
         ("https://github.com", "https://gist.github.com") as $u
         | "[credential \"\($u)\"]", "\thelper =", "\thelper = \(helper($login) | gitval)"
       else empty end),
      (if $gh != "" then
         ($accounts[] | "[credential \"https://github.com/\(.owner)\"]", "\thelper =", "\thelper = \(helper(.github) | gitval)")
       else empty end) ]
  | join("\n") + "\n";

def git_files:
  {"account-switcher-work.inc": git_mode("work"), "account-switcher-personal.inc": git_mode("personal")}
  + ([(cfg.accounts // [])[] | select((.folder // "") != "")
      | {key: "account-switcher-owner-\(.owner | ascii_downcase).inc",
         value: ([git_header, "[user]", "\temail = \(.email | gitval)"] | join("\n") + "\n")}] | from_entries);

if $what == "errors" then errors
else {"config.bash": bash_text, "apps": apps_text, "hold.json": hold_text, "git": git_files}
end
