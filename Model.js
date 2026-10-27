// Pure logic for the mode widget and service. Plain JS (no .pragma library) so the
// QML engine reloads it on save and node can load it for tests.

var OFFSET = { work: 0, personal: 10 }

// Badge glyphs, built from code points (U+25C6 black diamond, U+25CF black circle).
var GLYPH = { work: String.fromCodePoint(0x25C6), personal: String.fromCodePoint(0x25CF) }
// The sharing dot (U+25C9 fisheye), on the badge and on the ask toast.
var SHARE_GLYPH = String.fromCodePoint(0x25C9)
var ASK_TITLE = "You're sharing your screen"

function modeOf(id) {
  if (id >= 1 && id <= 10) return "work"
  if (id >= 11 && id <= 20) return "personal"
  return null
}

function otherMode(mode) {
  return mode === "work" ? "personal" : "work"
}

function slotOf(id) {
  return (id - 1) % 10 + 1
}

function idFor(mode, slot) {
  return OFFSET[mode] + slot
}

// Like the stock widget: slots 1-5 always, plus any other workspace of the mode that exists.
function buttonIds(mode, existingIds) {
  var ids = []
  for (var slot = 1; slot <= 5; slot++) ids.push(idFor(mode, slot))
  for (var i = 0; i < existingIds.length; i++) {
    var id = existingIds[i]
    if (modeOf(id) === mode && ids.indexOf(id) < 0) ids.push(id)
  }
  return ids.sort(function(a, b) { return a - b })
}

function labelFor(id) {
  return String(slotOf(id) % 10)
}

// "mode=<work|personal> peek=<0|1> alerts=<n> share=<0|1>", from the status file or the custom
// event. Lines written before the share flag existed read as not sharing.
function parseStatus(text) {
  var m = /mode=(work|personal) peek=([01]) alerts=(\d+)(?: share=([01]))?/.exec(String(text || ""))
  if (!m) return null
  return { mode: m[1], peek: m[2] === "1", alerts: parseInt(m[3], 10), share: m[4] === "1" }
}

// Hyprland's custom event data, "account-switcher <status line>".
function parseEvent(data) {
  var s = String(data || "")
  if (s.indexOf("account-switcher ") !== 0) return null
  return parseStatus(s.slice("account-switcher ".length))
}

// "account-switcher-ask switch <mode>": a switch the desk refused while sharing; returns the mode.
function parseAsk(data) {
  var m = /^account-switcher-ask switch (work|personal)\s*$/.exec(String(data || ""))
  return m ? m[1] : null
}

// xdph's PipeWire stream lives exactly as long as a portal share. Its node.name (what
// PwNode.name reads) is the portal's program name; "xdph-streaming-<n>" is only its media.name,
// still matched in case a PipeWire config ever sets node.name from it.
function sharingFrom(nodes) {
  if (!nodes) return false
  for (var i = 0; i < nodes.length; i++) {
    var name = String((nodes[i] && nodes[i].name) || "")
    if (name === "xdg-desktop-portal-hyprland" || name.indexOf("xdph-streaming") === 0) return true
  }
  return false
}

// The ask toast: critical, so it neither expires nor waits behind do-not-disturb; clicking it
// runs the switch with --confirmed. replaceId (the last toast's id, or "") replaces that toast.
function askCommand(mode, bin, replaceId) {
  var title = mode.charAt(0).toUpperCase() + mode.slice(1)
  var argv = ["omarchy-notification-send", "-p"]
  if (replaceId) argv.push("-r", String(replaceId))
  return argv.concat(["-u", "critical", "-g", SHARE_GLYPH,
    ASK_TITLE, "Click to switch to " + title + " anyway",
    "--exec", bin, "switch", mode, "--confirmed"])
}

// Omarchy keeps a toast on screen after its sender closes it, so the shell takes it down.
function askDismissCommand() {
  return ["omarchy-shell", "-q", "notifications", "dismiss", ASK_TITLE]
}

// While peeking the badge names the mode on screen. The number counts what waits for you:
// hidden windows that asked for attention plus held notifications. Sharing adds the dot.
function badgeText(mode, peek, alerts, share, held) {
  var text
  if (peek) {
    var shown = otherMode(mode)
    text = GLYPH[shown] + " PEEK " + shown.toUpperCase()
  } else {
    text = GLYPH[mode] + " " + mode.toUpperCase()
    var waiting = (alerts || 0) + (held || 0)
    if (waiting > 0) text += " " + waiting
  }
  return share ? text + " " + SHARE_GLYPH : text
}

var PERSONAL_COLOR = "#FFB000"

// The personalColor setting as "#RRGGBB", or "" when it isn't one.
function validColor(text) {
  var m = /^#?([0-9a-fA-F]{6})$/.exec(String(text || "").trim())
  return m ? "#" + m[1].toUpperCase() : ""
}

function badgeColor(mode, accent, personalColor) {
  if (mode !== "personal") return accent
  return validColor(personalColor) || PERSONAL_COLOR
}

// ~/.local/state/account-switcher/look, which Hyprland's side reads at every load.
function lookText(color) {
  return color ? "personal_color=" + color + "\n" : ""
}

function modeTitle(mode) {
  return mode === "personal" ? "Personal" : "Work"
}

// The widget's inline settings: its bar entry minus "id".
function entrySettings(barConfig, id) {
  var layout = (barConfig && barConfig.layout) || {}
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = layout[sections[s]] || []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (entry && entry.id === id) {
        var copy = {}
        for (var key in entry) if (key !== "id") copy[key] = entry[key]
        return copy
      }
    }
  }
  return {}
}

function wallpaperFor(settings, home) {
  var path = String((settings && settings.personalWallpaper) || "")
  if (path === "") return home + "/.local/share/account-switcher/wallpapers/personal.jpg"
  return path.indexOf("~/") === 0 ? home + path.slice(1) : path
}

// Wallpaper calls go out one at a time, so a slow one can't land after a newer one. A request
// made while one is running waits; only the newest waiting request is sent, and only if it
// differs from the one that just ran. q is { running, sent, wanted }; each returns the path
// to send now, or null.
function wallpaperRequest(q, path) {
  q.wanted = path
  if (q.running) return null
  q.running = true
  q.sent = path
  return path
}

function wallpaperFinished(q) {
  q.running = false
  if (!q.wanted || q.wanted === q.sent) return null
  q.running = true
  q.sent = q.wanted
  return q.wanted
}

// Time in each mode, kept as { days: { "YYYY-MM-DD": { work: s, personal: s } } } (local dates).
function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function dayKey(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

// time.json's text; anything unreadable starts an empty store.
function parseTime(text) {
  var data = null
  try { data = JSON.parse(String(text || "")) } catch (e) { data = null }
  var store = { days: {} }
  var days = data && data.days
  if (!days || typeof days !== "object" || Array.isArray(days)) return store
  for (var key in days) {
    var day = days[key]
    if (!/^\d{4}-\d{2}-\d{2}$/.test(key) || !day) continue
    store.days[key] = { work: Number(day.work) || 0, personal: Number(day.personal) || 0 }
  }
  return store
}

function addTime(store, key, mode, seconds) {
  if ((mode !== "work" && mode !== "personal") || !(seconds > 0)) return store
  var day = store.days[key] || (store.days[key] = { work: 0, personal: 0 })
  day[mode] += seconds
  return store
}

// Seconds since the last tick: 0 for the first tick, a clock that went back, or a gap longer
// than capMs (a suspend, or a stalled shell).
function tickSeconds(lastMs, nowMs, capMs) {
  var gap = nowMs - lastMs
  if (!(lastMs > 0) || gap <= 0 || gap > capMs) return 0
  return Math.round(gap / 1000)
}

// Today, and the week so far (weeks start on Monday).
function totals(store, nowMs) {
  var days = (store && store.days) || {}
  var out = { today: { work: 0, personal: 0 }, week: { work: 0, personal: 0 } }
  var now = new Date(nowMs)
  var sinceMonday = (now.getDay() + 6) % 7
  for (var i = 0; i <= sinceMonday; i++) {
    var day = days[dayKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() - i).getTime())]
    if (!day) continue
    out.week.work += day.work || 0
    out.week.personal += day.personal || 0
    if (i === 0) {
      out.today.work = day.work || 0
      out.today.personal = day.personal || 0
    }
  }
  return out
}

// Keeps the keepDays (default 60) most recent days; days without use aren't stored.
function prune(store, keepDays) {
  var keys = Object.keys(store.days).sort()
  for (var i = 0; i < keys.length - (keepDays || 60); i++) delete store.days[keys[i]]
  return store
}

function formatDuration(seconds) {
  var minutes = Math.floor((seconds || 0) / 60)
  if (minutes < 60) return minutes + "m"
  return Math.floor(minutes / 60) + "h " + pad2(minutes % 60) + "m"
}

// `hyprctl locked -j`: true or false, or null when it didn't answer.
function parseLocked(text) {
  try {
    var data = JSON.parse(String(text || ""))
    return typeof data.locked === "boolean" ? data.locked : null
  } catch (e) {
    return null
  }
}

// The clock file (account-switcher clock): "in <ISO time>" or "out <ISO time>", in local time, so
// its date is the local day.
function parseClock(text) {
  var m = /^(in|out) (\d{4}-\d{2}-\d{2})/.exec(String(text || "").trim())
  return m ? { kind: m[1], day: m[2] } : { kind: "", day: "" }
}

// "HH:MM" (or "H:MM") as minutes after midnight; null when unset or not a time.
function clockMinutes(text) {
  var m = /^(\d{1,2}):(\d{2})$/.exec(String(text || "").trim())
  if (!m) return null
  var hours = parseInt(m[1], 10), minutes = parseInt(m[2], 10)
  return hours < 24 && minutes < 60 ? hours * 60 + minutes : null
}

var DAY_NAMES = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

// The clockDays setting: day names and ranges ("mon-fri", "sat,sun", ["fri", "mon"]); a range
// can wrap past Sunday. Anything unreadable is Monday to Friday. Seven booleans, Sunday first.
function clockDays(value) {
  var parts = Array.isArray(value) ? value : String(value || "").split(",")
  var days = [false, false, false, false, false, false, false]
  var any = false
  for (var i = 0; i < parts.length; i++) {
    var range = String(parts[i]).trim().toLowerCase().split("-")
    var from = DAY_NAMES.indexOf(range[0].slice(0, 3))
    var to = range.length > 1 ? DAY_NAMES.indexOf(range[1].slice(0, 3)) : from
    if (from < 0 || to < 0 || range.length > 2) continue
    for (var d = from; ; d = (d + 1) % 7) {
      days[d] = true
      any = true
      if (d === to) break
    }
  }
  return any ? days : [false, true, true, true, true, true, false]
}

// The clock reminder due now: "in", "out" or "". Each fires at most once a day (fired holds the
// day each last fired), on clock days, from its time on: clock in until the clock-out time and
// only when not clocked in today; clock out only while clocked in.
function dueReminder(settings, nowMs, fired, clockText) {
  var s = settings || {}
  var last = fired || {}
  var now = new Date(nowMs)
  var today = dayKey(nowMs)
  if (!clockDays(s.clockDays)[now.getDay()]) return ""
  var minutes = now.getHours() * 60 + now.getMinutes()
  var inAt = clockMinutes(s.clockInAt), outAt = clockMinutes(s.clockOutAt)
  var clock = parseClock(clockText)
  if (outAt !== null && minutes >= outAt && last.out !== today && clock.kind === "in") return "out"
  var dayOver = outAt !== null && inAt !== null && outAt > inAt && minutes >= outAt
  if (inAt !== null && minutes >= inAt && !dayOver && last.in !== today
      && !(clock.kind === "in" && clock.day === today)) return "in"
  return ""
}

// The reminder toast: critical, so it waits for you; clicking it clocks in or out.
function reminderCommand(kind, bin) {
  var clockIn = kind === "in"
  return ["omarchy-notification-send", "-u", "critical", "-g", clockIn ? GLYPH.work : GLYPH.personal,
    clockIn ? "Time to clock in" : "Time to clock out",
    clockIn ? "Click to switch to Work and open your work apps" : "Click to switch to Personal",
    "--exec", bin, "clock", kind]
}

// reminders.json: the day each reminder last fired.
function parseFired(text) {
  var out = {}
  try {
    var data = JSON.parse(String(text || ""))
    var kinds = ["in", "out"]
    for (var i = 0; i < kinds.length; i++) {
      var day = data && data[kinds[i]]
      if (typeof day === "string" && /^\d{4}-\d{2}-\d{2}$/.test(day)) out[kinds[i]] = day
    }
  } catch (e) {}
  return out
}

// ---------------------------------------------------- the panel

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var DOT = " \u00B7 "

// From the clock file: when you last clocked in or out (the weekday when it wasn't today).
function clockLine(clockText, nowMs) {
  var m = /^(in|out) (\S+)/.exec(String(clockText || "").trim())
  var when = m ? new Date(m[2]) : null
  if (!when || isNaN(when.getTime())) return "Not clocked in yet"
  var time = pad2(when.getHours()) + ":" + pad2(when.getMinutes())
  var today = dayKey(when.getTime()) === dayKey(nowMs)
  if (m[1] === "in") return "Clocked in since " + (today ? "" : WEEKDAYS[when.getDay()] + " ") + time
  return "Clocked out " + (today ? "at " : WEEKDAYS[when.getDay()] + " ") + time
}

function timeLine(t) {
  return "Work " + formatDuration(t.work) + DOT + "Personal " + formatDuration(t.personal)
}

function plural(n, word) {
  return n + " " + word + (n === 1 ? "" : "s")
}

// Held notifications and other-mode windows that asked for attention.
function waitingLine(held, alerts) {
  var parts = []
  if (held > 0) parts.push(plural(held, "notification"))
  if (alerts > 0) parts.push(plural(alerts, "window"))
  return parts.length ? "Waiting: " + parts.join(" and ") : "Nothing waiting"
}

// The panel's header line (one short line).
function modeLine(mode, peek, share) {
  if (share) return "Sharing: switches ask first"
  if (peek) return "Peeking at " + modeTitle(otherMode(mode))
  return "Click the badge to switch"
}

// The panel's settings summary: each setting's value (or what applies while it's unset)
// and an example of the command that changes it.
var SETTING_ROWS = [
  { key: "clockInAt", label: "Clock-in reminder", unset: "not set", example: "09:00", time: true },
  { key: "clockOutAt", label: "Clock-out reminder", unset: "not set", example: "18:00", time: true },
  { key: "clockDays", label: "Reminder days", unset: "mon-fri", example: "mon-fri" },
  { key: "clockInApps", label: "Clock-in apps", unset: "Work apps, browser, code", example: "slack,browser,code" },
  { key: "personalWallpaper", label: "Personal wallpaper", unset: "default", example: "~/Pictures/a.jpg" },
  // Quoted: an unquoted # starts a shell comment.
  { key: "personalColor", label: "Personal colour", unset: PERSONAL_COLOR, example: "'" + PERSONAL_COLOR + "'", colour: true },
]

function settingsRows(settings) {
  var s = settings || {}
  var rows = []
  for (var i = 0; i < SETTING_ROWS.length; i++) {
    var row = SETTING_ROWS[i]
    var raw = s[row.key]
    var value = Array.isArray(raw) ? raw.join(", ") : String(raw === undefined || raw === null ? "" : raw).trim()
    if (value === "") value = row.unset
    else if (row.time && clockMinutes(value) === null) value += " (not a time)"
    else if (row.colour && validColor(value) === "") value += " (not a colour)"
    rows.push({ label: row.label, value: value, command: "omarchy bar set account-switcher " + row.key + " " + row.example })
  }
  return rows
}
