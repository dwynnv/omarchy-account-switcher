# Account Switcher for Omarchy

Work and Personal on one machine, each a whole desk: its own workspaces, accounts, browser, apps, folders and look. One key switches every monitor at once.

**Work** is workspaces 1–10 and **Personal** is 11–20. Both stay open; each monitor remembers its last workspace in each mode.

| Key | Does |
|---|---|
| SUPER+` (tap) | Switch mode |
| SUPER+` (hold) | Peek at the other mode; let go to come back |
| SUPER+SHIFT+` | Send the focused window to the same number in the other mode |
| SUPER+1…0, SUPER+SHIFT(+ALT)+1…0, SUPER+TAB family, SUPER+wheel, SUPER+S | As before, inside the current mode |
| SUPER+RETURN, SUPER+SHIFT+F, SUPER+ALT+SHIFT+F, SUPER+SHIFT+CTRL+A | Terminal, file manager, agent — of the current mode |
| SUPER+SHIFT+B (and RETURN), SUPER+SHIFT+ALT+B | The current mode's browser |
| Omarchy's web-app keys | In the mode the config gives that web app, else the current one |
| PRINT, ALT+PRINT | Screenshots and recordings go to the mode's folders |
| Badge: left-click / right-click | Switch mode / open the panel |

## What you get

- **A badge** on the bar in place of Omarchy's workspace buttons: `◆ WORK` in the theme accent or `● PERSONAL` in amber (or your colour), the mode's workspaces, a count of what waits for you, and `◉` while you share your screen. Personal gets its own border colour and wallpaper. Windows keep their mode's border colour wherever they are.
- **Each mode's accounts.** Terminals, agents and VS Code opened in a mode keep that mode's git identity, GitHub (`gh`) account, shell history, `z` jumps and tmux/herdr servers, even after you switch. Personal sees empty AWS files. A commit made under the wrong address for the repo's owner is refused (one through on purpose: `git -c hook.account-switcher-guard.enabled=false commit …`).
- **A browser per mode** (two different browsers, so their windows and notifications can be told apart). Links open in the browser of the mode of whatever opened them, switching you there when you opened them yourself; a link from a program in the background opens without pulling the desk across.
- **Home apps**: apps that live in one mode (a work chat app, a game launcher, …) take you to their mode when you open them, and their windows never open in the other one.
- **Clicks across modes** (the dock, the bar, notification clicks, launch-or-focus): focusing a window of the other mode switches you there, unless it's an app with no accounts (it comes over to you) or the same app is open in your mode. A toast from a terminal or an agent takes you to its window, in either mode.
- **Apps can't pull you across by themselves**: a window of the other mode asking for attention waits as an alert on the badge.
- **Clock in / clock out** (the panel, or reminder toasts at times you set): Work and your work apps, each back where it last was; or Personal. Your own steps can run with them ([clock hooks](#clock-hooks)).
- **Screen-share guard**: while you share your screen, a switch asks first, the share picker offers only the current mode's windows, the other mode's windows are blacked out of shares, and notifications that aren't urgent wait.
- **Work waits for you**: in Personal, notifications from Work's apps and browser wait (calls too) and show when you're back in Work. Do not disturb still decides first.
- **Time in each mode**, today and this week, counted while you're at the keyboard.
- **The panel** (right-click the badge): the mode, clock in/out, time, what's waiting (with **Show now**), and every setting with the command that changes it (the Personal wallpaper is picked: **Browse…** / **Default**).
- **The setup window** (**Choose apps…** in the panel): each mode's browser, and which installed apps and web apps live in Work, in Personal or in either, picked from what's on the system, with no JSON to write.

## Requirements

- Omarchy 4 with the Lua Hyprland config (`~/.config/hypr/hyprland.lua`, Hyprland 0.56), Ghostty, jq.
- Two different Chromium-family browsers, chosen in the setup window.
- Optional: `gh` (a GitHub account per mode), VS Code (a profile per mode), tmux, herdr.

Tested on Omarchy 4.0 with Hyprland 0.56.

## Install

```bash
omarchy plugin add https://github.com/dwynnv/omarchy-account-switcher.git
~/.config/omarchy/plugins/account-switcher/bin/account-switcher install
```

If `omarchy plugin add` asks whether to enable the plugin now, either answer is fine. The first run of `install` writes `~/.config/account-switcher/config.json` from the example and stops. Put your own accounts and folders in it ([Config](#config)); install refuses to go on while any of the example's placeholders (`Your Name`, `you@…`, `your-…`) is left. Run `~/.config/omarchy/plugins/account-switcher/bin/account-switcher install` again (after that, `account-switcher` is on your PATH), then `omarchy restart shell`, then choose each mode's browser and apps in the setup window: **Choose apps…** in the badge's panel (right-click the badge), or `omarchy-shell account-switcher.apps open`. Until a mode has a browser, its links open in your default browser.

To remove it, run `account-switcher uninstall` before `omarchy plugin remove` ([Uninstall](#uninstall)): removing the folder alone leaves your launchers, links, screen sharing and notifications pointing at it.

Install backs up each file before its first change (`<file>.bak.<epoch>`) and does nothing twice:

- links the Hyprland side into `~/.config/hypr/` and adds one `require` line to `hyprland.lua`;
- gives each mode's terminals their own global git file, `~/.config/git/account-switcher-work` and `account-switcher-personal`: made once, it reads your `~/.config/git/config` and `~/.gitconfig`, then the mode's identity (`account-switcher-work.inc`, `account-switcher-personal.inc`, one per extra account; setup keeps these up to date). `git config --global` in a mode terminal writes to that mode's file and stays there. Adds the commit guard to `~/.config/git/config`;
- adds two lines to `~/.bashrc`, around Omarchy's rc line;
- makes xdph's share picker the switcher's (it hands the current mode's windows to the picker you had);
- writes launcher entries to `~/.local/share/applications` (marked `X-AccountSwitcher=managed`), links its commands into `~/.local/bin` and, with `"mailto": "gmail"`, sends `mailto:` links to Gmail compose. Anything of yours it replaces there under the same name (a command, a launcher entry, the mail handler) is kept and comes back when you uninstall;
- puts the badge on the bar in place of Omarchy's workspace buttons;
- builds `account-switcher.notifications`, a copy of Omarchy's notification plugin with "Work waits for you", and turns it on.

Then:

1. In a new terminal (one opened after install), sign each GitHub account in once with `gh auth login`; each mode then uses its own. Signed in somewhere else? Run `account-switcher setup` afterwards.
2. Sign each mode's browser into that mode's accounts, and out of the other mode's.
3. Open Personal's VS Code from a Personal terminal (`code`) and sign it in; it shares Work's settings, keys, snippets and extensions.
4. Optional: [clock hooks](#clock-hooks), the [prompt segment](#prompt) and the [capture menu](#capture-menu).

## Update

```bash
omarchy plugin update account-switcher
account-switcher install
omarchy restart shell
```

`install` is safe to run again (it does nothing twice): it re-derives your setup and picks up new commands, launcher entries and the Hyprland side.

## Config

`~/.config/account-switcher/config.json` stays on your machine. Browsers, apps and web apps are easiest in the setup window (**Choose apps…** in the badge's panel): it lists what's installed, works out what each needs, saves only those keys (backing the file up first, `config.json.bak.<epoch>`, keeping the newest five) and runs setup. Apps it can't place (an AppImage, a Flatpak, your own launcher entries, ones started through a wrapper) are greyed out with the reason; describe those by hand as below. After changing the file yourself, run `account-switcher setup`: it checks the file (one line per problem, naming the field: misspelt keys and leftover placeholders included), rewrites what's derived from it and the launcher entries. `account-switcher config check` only checks. Keys starting with `_` are comments. A filled-in example (every name in it is made up):

```json
{
  "work": {
    "git": { "name": "Alex Example", "email": "alex@work.example" },
    "github": "alex-work",
    "githubOwners": ["work-org"],
    "browser": "browser-a",
    "apps": ["chat"],
    "webapps": [],
    "folders": {
      "home": "~/Work", "agent": "~/Work", "files": "~/Work",
      "screenshots": "~/Work/Pictures", "recordings": "~/Work/Videos", "downloads": "~/Work/Downloads"
    }
  },
  "personal": {
    "git": { "name": "alex", "email": "alex@home.example" },
    "github": "alex",
    "githubOwners": [],
    "browser": "browser-b",
    "apps": [],
    "webapps": ["A Web App"],
    "folders": { "home": "~", "agent": "~/Projects" }
  },
  "accounts": [
    { "owner": "side-org", "mode": "personal", "github": "alex-side", "email": "alex@side.example", "folder": "~/Side" }
  ],
  "webappsFollowMode": [],
  "holdApps": [],
  "clockInApps": ["chat", "browser"],
  "mailto": "none",
  "customBrowsers": {
    "browser-a": {
      "label": "Browser A", "bin": "/usr/bin/browser-a", "exeDir": "/opt/browser-a/", "class": "browser-a",
      "desktop": "browser-a.desktop", "execToken": "/usr/bin/browser-a", "routeDesktop": false,
      "notify": ["Browser A"], "notifyEntries": ["browser-a"]
    },
    "browser-b": {
      "label": "Browser B", "bin": "/usr/bin/browser-b", "exeDir": "/usr/lib/browser-b/", "class": "browser-b",
      "desktop": "browser-b.desktop", "execToken": "browser-b", "routeDesktop": true,
      "notify": ["Browser B"], "notifyEntries": ["browser-b"]
    }
  },
  "customApps": {
    "chat": {
      "label": "Chat", "bin": "/usr/bin/chat", "class": "chat", "desktop": "chat.desktop",
      "execToken": "/usr/bin/chat", "notify": ["Chat"], "notifyEntries": ["chat"]
    }
  }
}
```

| Key | Means |
|---|---|
| `work`, `personal` | Each mode. Only `browser` is required, and the two must differ. |
| `.git.name`, `.git.email` | The mode's commit identity. |
| `.github` | The mode's `gh` account (and git's credentials for github.com). |
| `.githubOwners` | More GitHub owners whose repos commit with this mode's address (an organisation, say). |
| `.browser` | A name from `customBrowsers`. |
| `.apps` | Apps that live in this mode, by their names in `customApps`. An app can be in one mode only. |
| `.webapps` | Web apps that always open in this mode, by launcher name: Omarchy's, or ones you made with Omarchy's web-app installer. |
| `.folders` | `home`: where terminals start (default `~`); `agent` and `files` (default: `home`); `screenshots`, `recordings` (default: Omarchy's); `downloads` (made for you; point your browser there). `~`, `~/…`, absolute, or relative to `~`. |
| `accounts` | GitHub owners with an account and address of their own, in one mode: `gh` and git push use that account in their repos, and repos under `folder` commit with that address. |
| `webappsFollowMode` | Web apps that open in whichever mode you're in. Ones listed nowhere keep Omarchy's launcher. |
| `holdApps` | More app names whose notifications wait in Personal, beyond the Work apps and browser (a VPN client's, say). |
| `clockInApps` | What clock in starts when it isn't running: `browser` (Work's), `code`, and Work apps. Default: the Work apps and `browser`. |
| `mailto` | `none` (the mail handler you had stays; the default) or `gmail` (Gmail compose in the right mode's browser). |
| `customBrowsers`, `customApps` | Your browsers and apps, described as below. Nothing is built in. |

Each browser and app the config names is described in `customBrowsers` or `customApps`, as in the example. To find the values for one of yours, start it and look:

`exeDir` is the folder the browser's executable runs from (`readlink /proc/<pid>/exe`), `class` the window class (`hyprctl clients`), `desktop` its launcher entry in `/usr/share/applications`, `execToken` the first word of that entry's `Exec=` lines, `notify`/`notifyEntries` the app name and desktop entry its notifications carry. `routeDesktop` makes the browser's own launcher icon open it in its mode. An app with `"focusExisting": true` focuses its window instead of starting again, and `"classPrefixes"` adds window classes by prefix (for a launcher whose games open windows of their own, say).

## Settings

On the bar entry; change them with `omarchy bar set` (`''` clears one).

| Setting | Example | Unset |
|---|---|---|
| `clockInAt` | `omarchy bar set account-switcher clockInAt 09:00` | no clock-in reminder |
| `clockOutAt` | `omarchy bar set account-switcher clockOutAt 18:00` | no clock-out reminder |
| `clockDays` | `omarchy bar set account-switcher clockDays mon-fri` (or `sat,sun`, `fri-mon`) | Monday to Friday |
| `clockInApps` | `omarchy bar set account-switcher clockInApps browser,code` | the config's list |
| `personalWallpaper` | **Browse…** in the panel or the setup window (or `omarchy bar set account-switcher personalWallpaper ~/Pictures/a.jpg`) | one of Omarchy's backgrounds, copied at setup |
| `personalColor` | `omarchy bar set account-switcher personalColor '#FF6A00'` (quoted: `#` starts a shell comment) | amber |

Reminders come once a day: "Time to clock in" at the clock-in time unless you already did, "Time to clock out" while you're clocked in. A new wallpaper shows at the next switch; a new colour at once.

## Notifications

In Personal, notifications from Work's apps and browser (and `holdApps`) wait; during a screen share, everything but urgent ones waits until it ends. Held notifications survive a shell restart. **Show now** in the panel (or `omarchy-shell notifications releaseHeld`) shows them all.

This runs in `account-switcher.notifications`, a copy of Omarchy's notification plugin with a small patch (`notifications/patch.sh`, logic in `notifications/HoldLogic.js`). When Omarchy's plugin changes, the copy is rebuilt and checked before it replaces the old one; if the patch no longer fits, or the copy doesn't answer after the shell starts, Omarchy's own notifications come back with a toast saying so, and whatever was waiting is handed to them. A rebuilt copy takes effect at the next shell restart. Back to Omarchy's own by hand: `omarchy plugin enable omarchy.notifications`.

## Time in each mode

Counted for the desk's mode while the screen is unlocked and you've used the keyboard or mouse in the last 5 minutes. The panel shows today and this week; `omarchy-shell account-switcher time` prints the same two totals. The day-by-day record (the last 60 days with use) is in `~/.local/state/account-switcher/time.json`.

## Optional extras

### Clock hooks

Clock in and clock out run `~/.config/account-switcher/hooks/clock-in` and `clock-out` when they exist and are executable: on their own, right after the switch (clock in's with Work's environment). Use them for steps of your own, such as connecting a VPN when you clock in and disconnecting it when you clock out:

```bash
mkdir -p ~/.config/account-switcher/hooks
printf '#!/bin/sh\nexec my-vpn up\n' >~/.config/account-switcher/hooks/clock-in
printf '#!/bin/sh\nexec my-vpn down\n' >~/.config/account-switcher/hooks/clock-out
chmod +x ~/.config/account-switcher/hooks/clock-*
```

### Prompt

Terminals export `ACCOUNT_SWITCHER_WORK=1` or `ACCOUNT_SWITCHER_PERSONAL=1`. For starship, add `${env_var.ACCOUNT_SWITCHER_WORK}${env_var.ACCOUNT_SWITCHER_PERSONAL}` to the front of `format` in `~/.config/starship.toml`, and:

```toml
[env_var.ACCOUNT_SWITCHER_WORK]
variable = "ACCOUNT_SWITCHER_WORK"
format = "[◆ work]($style) "
style = "bold cyan"

[env_var.ACCOUNT_SWITCHER_PERSONAL]
variable = "ACCOUNT_SWITCHER_PERSONAL"
format = "[● personal]($style) "
style = "bold #FFB000"
```

### Capture menu

PRINT and ALT+PRINT already save to the mode's folders. For Omarchy's capture menu to do the same, add to `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"trigger.capture.screenshot": {"icon": "", "label": "Screenshot", "action": "account-switcher capture screenshot"},
"trigger.capture.screenrecord.stop": {"icon": "", "label": "Stop Screenrecording", "when": "pgrep -f '^gpu-screen-recorder'", "action": "account-switcher capture stop"},
"trigger.capture.screenrecord.no-audio": {"icon": "", "label": "With no audio", "action": "account-switcher capture record"},
"trigger.capture.screenrecord.desktop-audio": {"icon": "", "label": "With desktop audio", "action": "account-switcher capture record --with-desktop-audio"},
"trigger.capture.screenrecord.microphone": {"icon": "", "label": "With desktop + microphone audio", "action": "account-switcher capture record --with-desktop-audio --with-microphone-audio"},
"trigger.capture.screenrecord.webcam": {"icon": "", "label": "With desktop + microphone audio + webcam", "when": "omarchy-hw-webcam", "action": "account-switcher capture webcam"}
```

## Commands

`account-switcher` (in `~/.local/bin`): `install`, `uninstall [--purge]`, `setup`, `config check|path`, `current`, `env [MODE]`, `resolve`, `switch MODE [--confirmed]`, `terminal [--mode=M]`, `agent`, `files [--cwd]`, `tmux`, `herdr`, `browser [--mode=M] [--private] [URL]`, `webapp [--mode=M] [--name=NAME] [--focus=TEXT] URL`, `open [--mode=M] URL`, `mailto URL`, `zoom [URL]`, `app ID`, `capture screenshot|record|stop|webcam|toggle`, `clock in|out|status`, `notifications-sync`, `notifications-check [--ping]`, `desktop-apply`, `desktop-check [--fix]`.

The setup window's side: `apps-list` (installed apps, browsers and web apps as JSON), `apps-set [JSON]` (the choice, as the argument or on stdin), `apps-missing` (modes with no browser yet).

From the bar side: `omarchy-shell account-switcher status|time|switchMode|reapply`, `omarchy-shell account-switcher.apps open|close`, `omarchy-shell account-switcher.panel toggle`, `omarchy-shell notifications heldCount|releaseHeld`.

## Files

- This folder: the bar widget, panel and service (`BarWidget.qml`, `Panel.qml`, `Service.qml`, `Model.js`), the setup window (`AppsWindow.qml`, `AppsModel.js`), the Hyprland side (`hypr/`), commands (`bin/`), `lib/` (the environment, config, installer and the setup window's `apps.bash`), `config.example.json`, `notifications/`, `shell/` (the `~/.bashrc` hooks), `tests/`.
- `~/.config/account-switcher/config.json`: your config.
- `~/.local/state/account-switcher/`: the mode and per-monitor memory, what setup derived from the config (`config.bash`, `apps`, `hold.json`), shell histories, clock and reminder state, time, held notifications.
- `~/.local/share/account-switcher/`: the Personal wallpaper, token-free `gh` settings per account (tokens stay in the keyring), Personal's empty AWS files, `z` data per mode.
- `~/.config/omarchy/plugins/account-switcher.notifications/`: the generated notification copy (don't edit it).

## Uninstall

1. Move what you want to keep from workspaces 11–20 (and Personal's scratchpad, SUPER+S) to 1–10.
2. `account-switcher uninstall` takes back everything install did, and adds what you typed in each mode to `~/.bash_history`. `--purge` also removes the config (with your clock hooks), state, data and the per-mode git files (a mode's global git file you've put settings in stays, and uninstall says where); `z` jumps learned since install go with the data. `~/.config/Code-Personal` (Personal's VS Code) stays either way.
3. `omarchy refresh applications` (Omarchy's own launcher entries), then `omarchy restart shell`.
4. `omarchy plugin remove account-switcher`.

Removed the folder first? Add the plugin back (`omarchy plugin add …`, same as installing), then run `account-switcher uninstall`.

## Tests

```bash
~/.config/omarchy/plugins/account-switcher/tests/run.sh
```

Lua 5.5 (Hyprland's Lua) runs the desk against a small model of Hyprland; the shell tests use a scratch home and record commands instead of running them, except the notification-copy tests, which build a real copy of Omarchy's plugin and lint it with `qmllint`; node runs the JS.

## Limits

- Per-mode terminals and agents need Ghostty.
- The workspace ranges are fixed: Work 1–10, Personal 11–20.
- Nothing is built in: every browser and app is described in the config.

## License

MIT
