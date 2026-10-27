// Which notifications wait (account-switcher), and which window a
// terminal's or agent's toast belongs to. Copied into the account-switcher.notifications clone by
// `account-switcher notifications-sync`; plain JS (no .pragma library) so node can load it for tests.

var NORMAL = 1
var CRITICAL = 2

// Work's apps, by the app name or desktop entry they send with, from hold.json (`account-switcher
// setup` writes it from config.json: the Work apps, the Work browser and holdApps).
// { names: [...], entries: [...] }, lowercase; empty lists when there is none.
function parseHoldApps(text) {
  var data = null
  try { data = JSON.parse(String(text || "")) } catch (e) { data = null }
  function lower(list) {
    var out = []
    if (!Array.isArray(list)) return out
    for (var i = 0; i < list.length; i++) if (typeof list[i] === "string") out.push(list[i].toLowerCase())
    return out
  }
  return { names: lower(data && data.names), entries: lower(data && data.entries) }
}

function isWorkApp(appName, desktopEntry, apps) {
  var a = apps || {}
  var app = String(appName || "").toLowerCase()
  var entry = String(desktopEntry || "").toLowerCase()
  return (Array.isArray(a.names) && app !== "" && a.names.indexOf(app) >= 0) ||
    (Array.isArray(a.entries) && entry !== "" && a.entries.indexOf(entry) >= 0)
}

// item: { app, desktopEntry, urgency }; state: { mode, share } from the desk; apps from hold.json.
// "mode": a Work app while the desk is in Personal, whatever its urgency (calls included);
// "share": anything but a critical notification while a screen share is live; "" to show it.
function holdReason(item, state, apps) {
  var s = state || {}
  var i = item || {}
  if (s.mode === "personal" && isWorkApp(i.app, i.desktopEntry, apps)) return "mode"
  if (s.share === true && Number(i.urgency) !== CRITICAL) return "share"
  return ""
}

// The desk's status line ("mode=… peek=… alerts=… share=…"), alone or as the data of its
// "account-switcher <line>" event.
function parseState(text) {
  var m = /mode=(work|personal) peek=[01] alerts=\d+(?: share=([01]))?/.exec(String(text || ""))
  return m ? { mode: m[1], share: m[2] === "1" } : null
}

// Splits held items into those to show now and those that keep waiting, each kept item
// taking its current reason. force shows everything. Order is kept (oldest first).
function partition(items, state, force, apps) {
  var keep = []
  var release = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    var entry = item.entry || {}
    var reason = force ? "" : holdReason({ app: entry.app, desktopEntry: item.desktopEntry, urgency: entry.urgency }, state, apps)
    if (reason === "") {
      release.push(item)
    } else {
      item.reason = reason
      keep.push(item)
    }
  }
  return { keep: keep, release: release }
}

// held.json: the held items without their live notification objects.
function serializeHeld(items) {
  var out = []
  for (var i = 0; i < items.length; i++) {
    out.push({ reason: items[i].reason, desktopEntry: items[i].desktopEntry || "", entry: items[i].entry })
  }
  return JSON.stringify({ version: 1, items: out })
}

// Items read back from held.json have no live object (ref null): they show as restored toasts.
function parseHeld(text) {
  var data = null
  try { data = JSON.parse(String(text || "")) } catch (e) { data = null }
  var list = data && Array.isArray(data.items) ? data.items : []
  var items = []
  for (var i = 0; i < list.length; i++) {
    var raw = list[i]
    if (!raw || typeof raw.reason !== "string" || !raw.entry || typeof raw.entry !== "object") continue
    items.push({ reason: raw.reason, desktopEntry: String(raw.desktopEntry || ""), entry: raw.entry, ref: null })
  }
  return items
}

function heldCount(text) {
  return parseHeld(text).length
}

// Terminals and agents are Ghostty, whose toasts carry no app name, only the window class as
// the desktop entry: these are the classes the desk can find a window for.
var MODE_WINDOW_CLASSES = ["org.omarchy.term-work", "org.omarchy.term-personal",
  "org.omarchy.agent-work", "org.omarchy.agent-personal", "org.omarchy.agent"]

function modeWindowClass(desktopEntry) {
  var cls = String(desktopEntry || "")
  return MODE_WINDOW_CLASSES.indexOf(cls) >= 0 ? cls : ""
}

// The Hyprland dispatch calling the desk's NAME with CLASS, or "" for anything else: only a
// known class ever reaches the Lua text.
var DESK_CALLS = ["toast_clicked", "focus_class"]

function deskCall(name, cls) {
  if (DESK_CALLS.indexOf(name) < 0 || modeWindowClass(cls) === "") return ""
  var fn = "account_switcher.desk." + name
  return "function() if account_switcher and account_switcher.desk and " + fn + " then " + fn + "('" + cls + "') end end"
}

// toasts.json: each terminal or agent toast's class by its file name (Omarchy's timestamp-id
// stem, which history and restores keep), the newest TOAST_CLASSES_KEPT only. Returns a new
// map; an empty FILE_NAME only cleans and trims.
var TOAST_CLASSES_KEPT = 40

function noteClass(classes, fileName, cls) {
  var all = classes || {}
  var merged = {}
  var names = []
  for (var name in all) {
    if (modeWindowClass(all[name]) === "") continue
    merged[name] = all[name]
    names.push(name)
  }
  if (fileName && modeWindowClass(cls) !== "") {
    if (!(fileName in merged)) names.push(fileName)
    merged[fileName] = cls
  }
  names.sort(function(a, b) { return (parseInt(b, 10) || 0) - (parseInt(a, 10) || 0) })
  var kept = {}
  for (var i = 0; i < names.length && i < TOAST_CLASSES_KEPT; i++) kept[names[i]] = merged[names[i]]
  return kept
}

function parseClasses(text) {
  var data = null
  try { data = JSON.parse(String(text || "")) } catch (e) { data = null }
  return noteClass(data && typeof data.classes === "object" ? data.classes : {}, "", "")
}

function serializeClasses(classes) {
  return JSON.stringify({ version: 1, classes: noteClass(classes, "", "") })
}
