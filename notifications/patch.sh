#!/usr/bin/env bash
# patch.sh SERVICE_QML: adds "Work waits for you" (account-switcher) and toast clicks that reach
# terminal and agent windows to a fresh copy of
# omarchy.notifications' Service.qml. Run by `account-switcher notifications-sync`,
# never on the packaged file. Each anchor is a whole line that must occur exactly once; if
# one doesn't, nothing is written and the exit status is 1.
#
# Written against Omarchy 4.5's notification daemon (Store.js, Delivery.js, a `toasts` model
# keyed by the daemon's own row keys, clicks through activate()).
set -uo pipefail

file=${1:?usage: patch.sh SERVICE_QML}
marker='// ---------------------------------------------------- account-switcher: Work waits for you'
blocks=$(mktemp -d) || exit 1
trap 'rm -rf "$blocks"' EXIT

if grep -qF -- "$marker" "$file"; then
  echo "patch.sh: $file is already patched" >&2
  exit 1
fi

cat >"$blocks/imports" <<'EOF'
import "HoldLogic.js" as HoldLogic
EOF

cat >"$blocks/note" <<'EOF'
    // account-switcher: which terminal or agent this toast came from (see noteModeWindow).
    service.noteModeWindow(notification, row)
EOF

cat >"$blocks/gate" <<'EOF'
    // account-switcher: Work waits for you (see holdIfNeeded). Do not disturb has decided first.
    if (service.holdIfNeeded(notification, key, row)) return

EOF

cat >"$blocks/hold" <<'EOF'
  // ---------------------------------------------------- account-switcher: Work waits for you
  //
  // Added to this copy of omarchy.notifications by `account-switcher notifications-sync` (the
  // account-switcher plugin's notifications/patch.sh). While the desk is in Personal, Work apps'
  // notifications wait, whatever their urgency; while a screen share is live, everything but
  // critical ones waits. Do-not-disturb still decides first. A held notification keeps its live
  // slot and its sender, so an in-place update comes back through handleNotification and lands
  // on the held copy, and its click still works later. (Omarchy's "dismiss all" closes every
  // live slot, held ones included: the copy stays here and shows later as a restored card.)
  // The list is kept in ~/.local/state/account-switcher/held.json, stored the way Omarchy stores
  // its own rows (no codes, links or images), which the mode badge counts and which brings the
  // items back after a shell restart. When its reason ends an item takes the normal path: a live
  // one is handled again from the top; one its sender closed, or one from before a restart,
  // shows as a restored card. Named to stay clear of the daemon's own `held`/releaseHeld(),
  // which are the cards waiting while the deck is open.
  readonly property string holdDir: Quickshell.env("HOME") + "/.local/state/account-switcher/"
  property var holdState: ({ mode: "", share: false })
  property var heldItems: []
  property bool heldLoaded: false
  // Which apps are Work's (hold.json); nothing is released for them before it is read.
  property var holdApps: ({ names: [], entries: [] })
  property bool holdAppsLoaded: false
  // Set while a released notification goes through handleNotification again.
  property bool releasingHeld: false

  function heldIndexFor(key) {
    for (var i = 0; i < service.heldItems.length; i++) {
      var item = service.heldItems[i]
      if (item.ref && item.entry && item.entry.key === key) return i
    }
    return -1
  }

  // True when the notification waits. A card already on screen is updated where it is.
  function holdIfNeeded(notification, key, row) {
    if (service.releasingHeld || service.rowIndexFor(key) >= 0) return false
    var desktopEntry = ""
    try {
      desktopEntry = String(notification.desktopEntry || "")
    } catch (e) {
      desktopEntry = ""
    }
    var reason = HoldLogic.holdReason({ app: row.app, desktopEntry: desktopEntry, urgency: row.urgency },
      service.holdState, service.holdApps)
    var at = service.heldIndexFor(key)
    if (reason === "") {
      // An update that no longer waits (a call turned critical during a share): shown now.
      if (at >= 0) {
        service.heldItems = service.heldItems.filter(function(item, i) { return i !== at })
        service.writeHeld()
      }
      return false
    }
    if (at >= 0) {
      var current = service.heldItems[at]
      current.reason = reason
      current.desktopEntry = desktopEntry
      current.entry = row
      if (current.ref !== notification) service.watchHeld(notification, current)
      service.writeHeld()
      return true
    }
    var item = { reason: reason, desktopEntry: desktopEntry, entry: row, ref: null }
    service.watchHeld(notification, item)
    service.heldItems = service.heldItems.concat([item])
    service.writeHeld()
    return true
  }

  // Once its sender closes it, the held copy is all that's left.
  function watchHeld(notification, item) {
    item.ref = notification
    notification.closed.connect(function() {
      if (item.ref === notification) item.ref = null
    })
  }

  function writeHeld() {
    if (!service.heldLoaded) return
    var out = []
    for (var i = 0; i < service.heldItems.length; i++) {
      var item = service.heldItems[i]
      out.push({ reason: item.reason, desktopEntry: item.desktopEntry, entry: Store.persistable(item.entry) })
    }
    heldFile.setText(HoldLogic.serializeHeld(out) + "\n")
  }

  function setHoldState(state) {
    if (!state) return
    service.holdState = state
    service.releaseWaiting(false)
  }

  // Shows the held items whose reason has ended, or all of them with force; returns how many.
  function releaseWaiting(force) {
    if (!service.heldLoaded || (!force && (service.holdState.mode === "" || !service.holdAppsLoaded))) return 0
    var split = HoldLogic.partition(service.heldItems, service.holdState, force, service.holdApps)
    service.heldItems = split.keep
    service.writeHeld()
    for (var i = 0; i < split.release.length; i++) service.showHeld(split.release[i])
    return split.release.length
  }

  function showHeld(item) {
    var ref = item.ref
    var key = String((item.entry && item.entry.key) || "")
    var live = false
    try {
      live = !!ref && ref.tracked === true && key !== "" && service.refs[key] === ref
    } catch (e) {
      live = false
    }
    if (live) {
      service.releasingHeld = true
      try {
        service.handleNotification(ref)
      } finally {
        service.releasingHeld = false
      }
      return
    }
    var entry = {}
    for (var k in item.entry) entry[k] = item.entry[k]
    // A copy from before Omarchy 4.5 kept its time in ms as `timestamp`, and had no key.
    if (!entry.ts && Number(entry.timestamp) > 0) entry.ts = Number(entry.timestamp) / 1000
    if (!entry.key || service.liveKeys[entry.key]) entry.key = service.nextKey()
    var row = Store.restored(entry)
    if (!row) return
    service.noteToastClass(row, HoldLogic.modeWindowClass(item.desktopEntry))
    if (Delivery.quietReason(row, service.doNotDisturb)) {
      if (!Delivery.isEphemeral(row)) service.storeRecord(row, "silenced")
      return
    }
    if (!service.reserveLive(row.key)) return
    service.storePut(row)
    service.showRow(row)
  }

  function loadHeld(text) {
    if (service.heldLoaded) return
    service.heldItems = HoldLogic.parseHeld(text).concat(service.heldItems)
    service.heldLoaded = true
    service.writeHeld()
    service.releaseWaiting(false)
  }

  FileView {
    id: heldFile
    path: service.holdDir + "held.json"
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadHeld(text())
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) service.loadHeld("")
    }
  }

  // Work's apps, by the names and desktop entries they notify with, as `account-switcher setup` wrote
  // them from the config; read again whenever setup rewrites the file.
  FileView {
    path: service.holdDir + "hold.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: service.setHoldApps(text())
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) service.setHoldApps("")
    }
  }

  function setHoldApps(text) {
    service.holdApps = HoldLogic.parseHoldApps(text)
    service.holdAppsLoaded = true
    service.releaseWaiting(false)
  }

  // The desk's mode and share: its status file once, then its "account-switcher" events. Without
  // the switcher (no status file) nothing waits.
  FileView {
    path: service.holdDir + "status"
    printErrors: false
    onLoaded: service.setHoldState(HoldLogic.parseState(text()))
    onLoadFailed: service.setHoldState({ mode: "work", share: false })
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom") return
      var data = String(event.data)
      if (data.indexOf("account-switcher ") === 0) service.setHoldState(HoldLogic.parseState(data))
    }
  }

EOF

cat >"$blocks/clicks" <<'EOF'
  // ---------------------------------------------------- account-switcher: toast clicks
  //
  // Terminals and agents are Ghostty, whose toasts carry no app name, only the window class
  // as the desktop entry, so Omarchy's fallbacks (the sender's window by pid, then the app by
  // name) find nothing. A live toast's click still goes to Ghostty, which brings its exact
  // window forward; the desk is told first, so a window in the other mode takes you there
  // instead of raising an alert. A toast with no live sender (shown again from history, or
  // restored after a shell restart) focuses its class's most recent window. A row doesn't keep
  // the class, so each toast's is kept by its row key in ~/.local/state/account-switcher/toasts.json.
  property var toastClasses: ({})
  property bool toastClassesLoaded: false

  function noteModeWindow(notification, row) {
    var cls = ""
    try {
      cls = HoldLogic.modeWindowClass(notification.desktopEntry)
    } catch (e) {
      cls = ""
    }
    service.noteToastClass(row, cls)
  }

  function noteToastClass(row, cls) {
    var key = String((row && row.key) || "")
    if (cls === "" || key === "" || service.toastClasses[key] === cls) return
    service.toastClasses = HoldLogic.noteClass(service.toastClasses, key, cls)
    if (service.toastClassesLoaded) toastClassFile.setText(HoldLogic.serializeClasses(service.toastClasses) + "\n")
  }

  function loadToastClasses(text) {
    if (service.toastClassesLoaded) return
    var merged = HoldLogic.parseClasses(text)
    for (var name in service.toastClasses) merged = HoldLogic.noteClass(merged, name, service.toastClasses[name])
    service.toastClasses = merged
    service.toastClassesLoaded = true
    toastClassFile.setText(HoldLogic.serializeClasses(merged) + "\n")
  }

  // True when it took the click: a terminal's or agent's toast without a command of its own.
  function clickModeWindow(key, instant) {
    var at = service.rowIndexFor(key)
    if (at < 0) return false
    var row = toasts.get(at)
    if (!row || Security.parseExecArgv(row.execArgv)) return false
    var ref = row.restored ? null : service.refs[key]
    var cls = ""
    var action = null
    if (ref) {
      try {
        cls = HoldLogic.modeWindowClass(ref.desktopEntry)
        for (var i = 0; cls !== "" && ref.actions && i < ref.actions.length; i++) {
          if (ref.actions[i] && String(ref.actions[i].identifier) === "default") {
            action = ref.actions[i]
            break
          }
        }
      } catch (e) {
        action = null
      }
    } else {
      cls = HoldLogic.modeWindowClass(service.toastClasses[key])
    }
    if (cls === "") return false
    if (action) {
      Hyprland.dispatch(HoldLogic.deskCall("toast_clicked", cls))
      try {
        action.invoke()
      } catch (e) {
        action = null
      }
    }
    if (!action) Hyprland.dispatch(HoldLogic.deskCall("focus_class", cls))
    service.closeToast(key, "activated", instant)
    return true
  }

  FileView {
    id: toastClassFile
    path: service.holdDir + "toasts.json"
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadToastClasses(text())
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) service.loadToastClasses("")
    }
  }

EOF

cat >"$blocks/click" <<'EOF'
    // account-switcher: a terminal's or agent's toast takes you to its window (see clickModeWindow).
    if (service.clickModeWindow(key, instant)) return

EOF

cat >"$blocks/ipc" <<'EOF'
    // account-switcher: notifications waiting for Work or for a screen share to end.
    function heldCount(): string { return String(service.heldItems.length) }
    function releaseHeld(): string { return String(service.releaseWaiting(true)) }

EOF

# insert BEFORE|AFTER ANCHOR BLOCK: the block's lines go next to the one line equal to ANCHOR.
insert() {
  local where=$1 anchor=$2 block=$3 count
  count=$(grep -cxF -- "$anchor" "$file.new")
  if [[ $count != 1 ]]; then
    echo "patch.sh: anchor found $count times: $anchor" >&2
    return 1
  fi
  ANCHOR=$anchor WHERE=$where BLOCK=$block awk '
    $0 == ENVIRON["ANCHOR"] && ENVIRON["WHERE"] == "before" { while ((getline line < ENVIRON["BLOCK"]) > 0) print line }
    { print }
    $0 == ENVIRON["ANCHOR"] && ENVIRON["WHERE"] == "after" { while ((getline line < ENVIRON["BLOCK"]) > 0) print line }
  ' "$file.new" >"$file.next" && mv "$file.next" "$file.new"
}

cp "$file" "$file.new" || exit 1
if insert after 'import "Delivery.js" as Delivery' "$blocks/imports" &&
  insert after '    var row = Store.snapshot(notification, key, NotificationUrgency)' "$blocks/note" &&
  insert before '    storePut(row)' "$blocks/gate" &&
  insert before '  function handleNotification(notification) {' "$blocks/hold" &&
  insert before '  function activate(key, instant) {' "$blocks/clicks" &&
  insert after '  function activate(key, instant) {' "$blocks/click" &&
  insert before '    function ping(): string { return "ok" }' "$blocks/ipc"; then
  mv "$file.new" "$file"
else
  rm -f "$file.new" "$file.next"
  exit 1
fi
