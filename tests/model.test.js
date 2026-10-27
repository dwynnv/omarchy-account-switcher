// Run: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

const ctx = {}
vm.createContext(ctx)
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8"), ctx)
const M = ctx

let failed = 0
function test(name, fn) {
  try { fn(); console.log("ok   " + name) }
  catch (e) { failed++; console.log("FAIL " + name + "\n     " + e.message) }
}
const eq = (a, b) => assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), b)

test("modes and ids", () => {
  eq(M.modeOf(3), "work"); eq(M.modeOf(13), "personal"); eq(M.modeOf(0), null); eq(M.modeOf(21), null)
  eq(M.otherMode("work"), "personal"); eq(M.slotOf(20), 10); eq(M.idFor("personal", 1), 11)
})
test("buttons show slots 1-5 plus existing ids of the mode", () => {
  eq(M.buttonIds("work", [2, 8, 13]), [1, 2, 3, 4, 5, 8])
  eq(M.buttonIds("personal", [2, 13, 19]), [11, 12, 13, 14, 15, 19])
  eq(M.labelFor(10), "0"); eq(M.labelFor(20), "0"); eq(M.labelFor(13), "3")
})
test("status and events", () => {
  eq(M.parseStatus("mode=personal peek=1 alerts=2\n"), { mode: "personal", peek: true, alerts: 2, share: false })
  eq(M.parseStatus("rubbish"), null)
  eq(M.parseEvent("account-switcher mode=work peek=0 alerts=0"), { mode: "work", peek: false, alerts: 0, share: false })
  eq(M.parseEvent("something else"), null)
})
test("status lines carry the share flag", () => {
  eq(M.parseStatus("mode=work peek=0 alerts=1 share=1"), { mode: "work", peek: false, alerts: 1, share: true })
  eq(M.parseEvent("account-switcher mode=personal peek=0 alerts=0 share=0"), { mode: "personal", peek: false, alerts: 0, share: false })
  eq(M.parseEvent("account-switcher-ask switch work"), null)
})
test("a share is the portal's stream node", () => {
  // As a real portal share showed (pw-dump, 2026-10-27): xdph's stream gets the program's name
  // as node.name; "xdph-streaming-<n>" is only its media.name.
  eq(M.sharingFrom([{ name: "alsa_output.pci-0000_00_1f.3.analog-stereo" }, { name: "xdg-desktop-portal-hyprland" }]), true)
  eq(M.sharingFrom([{ name: "xdph-streaming-5f2a" }]), true)
  eq(M.sharingFrom([{ name: "alsa_output.pci-0000_00_1f.3.analog-stereo" }, { name: "" }, null, {}]), false)
  eq(M.sharingFrom([{ name: "xdg-desktop-portal" }, { name: "xdg-desktop-portal-gtk" }]), false)
  eq(M.sharingFrom([]), false)
  eq(M.sharingFrom(null), false)
})
test("asks to switch while sharing", () => {
  eq(M.parseAsk("account-switcher-ask switch personal"), "personal")
  eq(M.parseAsk("account-switcher-ask switch work\n"), "work")
  eq(M.parseAsk("account-switcher-ask switch nowhere"), null)
  eq(M.parseAsk("account-switcher mode=work peek=0 alerts=0 share=1"), null)
  const S = String.fromCodePoint(0x25C9)
  eq(M.askCommand("personal", "/h/.local/bin/account-switcher", ""),
    ["omarchy-notification-send", "-p", "-u", "critical", "-g", S,
     "You're sharing your screen", "Click to switch to Personal anyway",
     "--exec", "/h/.local/bin/account-switcher", "switch", "personal", "--confirmed"])
  // When the share ends the toast is taken down through the shell (Omarchy keeps a toast on
  // screen after its sender closes it).
  eq(M.askDismissCommand(), ["omarchy-shell", "-q", "notifications", "dismiss", "You're sharing your screen"])
  // A second ask replaces the first toast instead of stacking another.
  eq(M.askCommand("work", "/b/account-switcher", "42"),
    ["omarchy-notification-send", "-p", "-r", "42", "-u", "critical", "-g", S,
     "You're sharing your screen", "Click to switch to Work anyway",
     "--exec", "/b/account-switcher", "switch", "work", "--confirmed"])
})
test("badge", () => {
  const W = String.fromCodePoint(0x25C6), P = String.fromCodePoint(0x25CF)
  eq(M.badgeText("work", false, 0), W + " WORK")
  eq(M.badgeText("personal", false, 3), P + " PERSONAL 3")
  eq(M.badgeText("work", true, 3), P + " PEEK PERSONAL")
  // Sharing adds the dot; held notifications add to the alert number.
  const S = String.fromCodePoint(0x25C9)
  eq(M.badgeText("work", false, 0, true, 0), W + " WORK " + S)
  eq(M.badgeText("personal", false, 1, false, 2), P + " PERSONAL 3")
  eq(M.badgeText("personal", false, 0, false, 4), P + " PERSONAL 4")
  eq(M.badgeText("work", false, 2, true, 1), W + " WORK 3 " + S)
  eq(M.badgeText("work", true, 0, true, 0), P + " PEEK PERSONAL " + S)
  eq(M.badgeColor("work", "#33CCFF"), "#33CCFF"); eq(M.badgeColor("personal", "#33CCFF"), "#FFB000")
  eq(M.badgeColor("personal", "#33CCFF", "#3366ff"), "#3366FF")
  eq(M.badgeColor("personal", "#33CCFF", "orange"), "#FFB000")
  eq(M.badgeColor("work", "#33CCFF", "#3366FF"), "#33CCFF")
})
test("settings and wallpaper", () => {
  const bar = { layout: { left: [{ id: "omarchy.menu" }, { id: "account-switcher", personalWallpaper: "~/Pictures/p.jpg" }], center: [], right: [] } }
  eq(M.entrySettings(bar, "account-switcher"), { personalWallpaper: "~/Pictures/p.jpg" })
  eq(M.entrySettings(bar, "nope"), {})
  eq(M.wallpaperFor({ personalWallpaper: "~/Pictures/p.jpg" }, "/home/u"), "/home/u/Pictures/p.jpg")
  eq(M.wallpaperFor({}, "/home/u"), "/home/u/.local/share/account-switcher/wallpapers/personal.jpg")
})

test("wallpaper calls go out one at a time and the newest wins", () => {
  const q = {}
  eq(M.wallpaperRequest(q, "/w.jpg"), "/w.jpg")
  eq(M.wallpaperRequest(q, "/p.jpg"), null)
  eq(M.wallpaperRequest(q, "/w.jpg"), null)
  eq(M.wallpaperFinished(q), null)
  eq(M.wallpaperRequest(q, "/p.jpg"), "/p.jpg")
  eq(M.wallpaperRequest(q, "/w.jpg"), null)
  eq(M.wallpaperFinished(q), "/w.jpg")
  eq(M.wallpaperFinished(q), null)
  eq(M.wallpaperRequest(q, "/w.jpg"), "/w.jpg")
})

// Local times, so the tests hold in any time zone. 2026-10-26 is a Monday.
const at = (y, mo, d, h, mi, sec) => new Date(y, mo - 1, d, h || 0, mi || 0, sec || 0).getTime()

test("day keys are local dates and change at midnight", () => {
  eq(M.dayKey(at(2026, 10, 26, 23, 59, 59)), "2026-10-26")
  eq(M.dayKey(at(2026, 10, 27, 0, 0, 1)), "2026-10-27")
  eq(M.dayKey(at(2026, 1, 5, 9)), "2026-01-05")
})
test("time adds up per day and mode", () => {
  const store = M.parseTime("")
  eq(store, { days: {} })
  eq(M.addTime(store, "2026-10-26", "work", 30), { days: { "2026-10-26": { work: 30, personal: 0 } } })
  M.addTime(store, "2026-10-26", "work", 30)
  M.addTime(store, "2026-10-26", "personal", 30)
  M.addTime(store, "2026-10-27", "personal", 30)
  M.addTime(store, "2026-10-27", null, 30)
  eq(store, { days: { "2026-10-26": { work: 60, personal: 30 }, "2026-10-27": { work: 0, personal: 30 } } })
  eq(M.parseTime(JSON.stringify(store)), { days: { "2026-10-26": { work: 60, personal: 30 }, "2026-10-27": { work: 0, personal: 30 } } })
  eq(M.parseTime("{not json"), { days: {} })
  eq(M.parseTime('{"days": []}'), { days: {} })
})
test("a tick counts the time since the last one, and nothing across a suspend", () => {
  const t = at(2026, 10, 26, 10)
  eq(M.tickSeconds(t, t + 30000, 90000), 30)
  eq(M.tickSeconds(t, t + 30400, 90000), 30)
  eq(M.tickSeconds(t, t + 95000, 90000), 0)
  eq(M.tickSeconds(t, t - 5000, 90000), 0)
  eq(M.tickSeconds(0, t, 90000), 0)
})
test("a tick just after midnight counts for the new day", () => {
  const store = { days: {} }
  const now = at(2026, 10, 27, 0, 0, 10)
  M.addTime(store, M.dayKey(now), "work", M.tickSeconds(now - 30000, now, 90000))
  eq(store, { days: { "2026-10-27": { work: 30, personal: 0 } } })
})
test("totals: today, and the week from Monday", () => {
  const store = { days: {
    "2026-10-25": { work: 100, personal: 7 },
    "2026-10-26": { work: 3600, personal: 60 },
    "2026-10-27": { work: 1800, personal: 0 },
    "2026-10-28": { work: 60, personal: 600 },
  } }
  eq(M.totals(store, at(2026, 10, 28, 10)), { today: { work: 60, personal: 600 }, week: { work: 5460, personal: 660 } })
  // Sunday still belongs to the week that started on Monday.
  eq(M.totals(store, at(2026, 11, 1, 23)), { today: { work: 0, personal: 0 }, week: { work: 5460, personal: 660 } })
  // Monday starts a new week; the Sunday before is last week's.
  eq(M.totals(store, at(2026, 10, 26, 0, 0, 5)), { today: { work: 3600, personal: 60 }, week: { work: 3600, personal: 60 } })
  eq(M.totals({ days: {} }, at(2026, 10, 28)), { today: { work: 0, personal: 0 }, week: { work: 0, personal: 0 } })
})
test("prune keeps the most recent days", () => {
  const store = { days: { "2026-10-24": { work: 1, personal: 0 }, "2026-10-26": { work: 2, personal: 0 }, "2026-09-01": { work: 3, personal: 0 } } }
  eq(M.prune(store, 2), { days: { "2026-10-24": { work: 1, personal: 0 }, "2026-10-26": { work: 2, personal: 0 } } })
  const many = { days: {} }
  for (let d = 1; d <= 70; d++) M.addTime(many, M.dayKey(at(2026, 7, d)), "work", 1)
  eq(Object.keys(M.prune(many).days).length, 60)
  eq(Object.keys(many.days).sort()[0], M.dayKey(at(2026, 7, 11)))
})
test("durations read as hours and minutes", () => {
  eq(M.formatDuration(0), "0m")
  eq(M.formatDuration(59), "0m")
  eq(M.formatDuration(60), "1m")
  eq(M.formatDuration(45 * 60), "45m")
  eq(M.formatDuration(3600), "1h 00m")
  eq(M.formatDuration(7 * 3600 + 5 * 60 + 59), "7h 05m")
  eq(M.formatDuration(100 * 3600), "100h 00m")
})
test("lock state from hyprctl", () => {
  eq(M.parseLocked('{\n    "locked": false\n}\n'), false)
  eq(M.parseLocked('{"locked": true}'), true)
  eq(M.parseLocked("error: no socket"), null)
  eq(M.parseLocked(""), null)
})

test("clock state from the clock file", () => {
  eq(M.parseClock("in 2026-10-26T09:02:11+00:00\n"), { kind: "in", day: "2026-10-26" })
  eq(M.parseClock("out 2026-10-26T18:00:00+00:00"), { kind: "out", day: "2026-10-26" })
  eq(M.parseClock("none"), { kind: "", day: "" })
  eq(M.parseClock(""), { kind: "", day: "" })
})
test("no reminders until times are set", () => {
  eq(M.dueReminder({}, at(2026, 10, 26, 9, 30), {}, ""), "")
  eq(M.dueReminder({ clockInAt: "", clockOutAt: "" }, at(2026, 10, 26, 18, 30), {}, "in 2026-10-26T09:00:00+00:00"), "")
  eq(M.dueReminder({ clockInAt: "25:00" }, at(2026, 10, 26, 23, 30), {}, ""), "")
  eq(M.dueReminder(null, at(2026, 10, 26, 9, 30), null, null), "")
})
test("the clock-in reminder: from its time on a clock day, once a day, unless clocked in today", () => {
  const s = { clockInAt: "09:00", clockOutAt: "18:00" }
  eq(M.dueReminder(s, at(2026, 10, 26, 8, 59), {}, ""), "")
  eq(M.dueReminder(s, at(2026, 10, 26, 9, 0), {}, ""), "in")
  eq(M.dueReminder(s, at(2026, 10, 26, 9, 30), { in: "2026-10-26" }, ""), "")
  eq(M.dueReminder(s, at(2026, 10, 26, 9, 30), { in: "2026-10-23" }, "out 2026-10-23T18:01:00+00:00"), "in")
  eq(M.dueReminder(s, at(2026, 10, 26, 9, 30), {}, "in 2026-10-26T08:50:00+00:00"), "")
  // Still clocked in from Friday: today's reminder still comes.
  eq(M.dueReminder(s, at(2026, 10, 26, 9, 30), {}, "in 2026-10-23T09:10:00+00:00"), "in")
  // Not after the work day is over, and not on Sunday.
  eq(M.dueReminder(s, at(2026, 10, 26, 18, 30), {}, ""), "")
  eq(M.dueReminder(s, at(2026, 10, 25, 9, 30), {}, ""), "")
  eq(M.dueReminder({ clockInAt: "9:05" }, at(2026, 10, 26, 22, 0), {}, ""), "in")
})
test("the clock-out reminder: from its time, once a day, only while clocked in", () => {
  const s = { clockInAt: "09:00", clockOutAt: "18:00" }
  const inToday = "in 2026-10-26T09:01:00+00:00"
  eq(M.dueReminder(s, at(2026, 10, 26, 17, 59), {}, inToday), "")
  eq(M.dueReminder(s, at(2026, 10, 26, 18, 0), {}, inToday), "out")
  eq(M.dueReminder(s, at(2026, 10, 26, 18, 5), { out: "2026-10-26" }, inToday), "")
  eq(M.dueReminder(s, at(2026, 10, 26, 18, 5), {}, "out 2026-10-26T17:30:00+00:00"), "")
  eq(M.dueReminder(s, at(2026, 10, 26, 18, 5), {}, ""), "")
  eq(M.dueReminder({ clockOutAt: "18:00" }, at(2026, 10, 26, 18, 5), {}, inToday), "out")
})
test("clock days", () => {
  eq(M.dueReminder({ clockInAt: "09:00", clockDays: "sat,sun" }, at(2026, 10, 25, 9, 30), {}, ""), "in")
  eq(M.dueReminder({ clockInAt: "09:00", clockDays: "sat,sun" }, at(2026, 10, 26, 9, 30), {}, ""), "")
  eq(M.dueReminder({ clockInAt: "09:00", clockDays: ["fri", "Mon"] }, at(2026, 10, 26, 9, 30), {}, ""), "in")
  eq(M.dueReminder({ clockInAt: "09:00", clockDays: "fri-mon" }, at(2026, 10, 25, 9, 30), {}, ""), "in")
  eq(M.dueReminder({ clockInAt: "09:00", clockDays: "fri-mon" }, at(2026, 10, 28, 9, 30), {}, ""), "")
  eq(M.dueReminder({ clockInAt: "09:00", clockDays: "nonsense" }, at(2026, 10, 26, 9, 30), {}, ""), "in")
  eq(M.dueReminder({ clockInAt: "09:00", clockDays: "nonsense" }, at(2026, 10, 25, 9, 30), {}, ""), "")
})
test("reminder toasts and what fired when", () => {
  const W = String.fromCodePoint(0x25C6), P = String.fromCodePoint(0x25CF)
  eq(M.reminderCommand("in", "/b/account-switcher"), ["omarchy-notification-send", "-u", "critical", "-g", W,
    "Time to clock in", "Click to switch to Work and open your work apps", "--exec", "/b/account-switcher", "clock", "in"])
  eq(M.reminderCommand("out", "/b/account-switcher"), ["omarchy-notification-send", "-u", "critical", "-g", P,
    "Time to clock out", "Click to switch to Personal", "--exec", "/b/account-switcher", "clock", "out"])
  eq(M.parseFired('{"in": "2026-10-26", "out": 3, "x": "2026-10-26"}'), { in: "2026-10-26" })
  eq(M.parseFired("garbage"), {})
})

// The clock file's time as `date -Iseconds` writes it: local time with its offset.
const iso = (ms) => {
  const d = new Date(ms), off = -d.getTimezoneOffset(), p = (n) => String(Math.abs(n)).padStart(2, "0")
  return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + "T" + p(d.getHours()) + ":" +
    p(d.getMinutes()) + ":" + p(d.getSeconds()) + (off >= 0 ? "+" : "-") + p(Math.trunc(off / 60)) + ":" + p(off % 60)
}

test("panel: the clock line", () => {
  const now = at(2026, 10, 27, 10, 0)
  eq(M.clockLine("", now), "Not clocked in yet")
  eq(M.clockLine("none", now), "Not clocked in yet")
  eq(M.clockLine("in " + iso(at(2026, 10, 27, 9, 2, 11)), now), "Clocked in since 09:02")
  eq(M.clockLine("in " + iso(at(2026, 10, 23, 9, 10)), now), "Clocked in since Fri 09:10")
  eq(M.clockLine("out " + iso(at(2026, 10, 27, 8, 0)), now), "Clocked out at 08:00")
  eq(M.clockLine("out " + iso(at(2026, 10, 26, 18, 1)), now), "Clocked out Mon 18:01")
})
test("panel: time in each mode and what's waiting", () => {
  eq(M.timeLine({ work: 3 * 3600 + 5 * 60, personal: 45 * 60 }), "Work 3h 05m · Personal 45m")
  eq(M.timeLine({ work: 0, personal: 0 }), "Work 0m · Personal 0m")
  eq(M.waitingLine(0, 0), "Nothing waiting")
  eq(M.waitingLine(2, 0), "Waiting: 2 notifications")
  eq(M.waitingLine(1, 1), "Waiting: 1 notification and 1 window")
  eq(M.waitingLine(0, 3), "Waiting: 3 windows")
})
test("panel: the mode line", () => {
  // Short: the panel's header line is one line.
  eq(M.modeLine("work", false, false), "Click the badge to switch")
  eq(M.modeLine("personal", true, false), "Peeking at Work")
  eq(M.modeLine("work", false, true), "Sharing: switches ask first")
})
test("panel: settings and the commands that change them", () => {
  const rows = M.settingsRows({})
  eq(rows.map((r) => [r.label, r.value]), [
    ["Clock-in reminder", "not set"],
    ["Clock-out reminder", "not set"],
    ["Reminder days", "mon-fri"],
    ["Clock-in apps", "Work apps, browser"],
    ["Personal wallpaper", "default"],
    ["Personal colour", "#FFB000"],
  ])
  eq(rows[0].command, "omarchy bar set account-switcher clockInAt 09:00")
  eq(rows[3].command, "omarchy bar set account-switcher clockInApps browser,code")
  eq(rows[5].command, "omarchy bar set account-switcher personalColor '#FFB000'")
  eq(rows.map((r) => r.picker === true), [false, false, false, false, true, false])
  eq(rows[4].command, "", "the wallpaper is picked in the panel")
  const set = M.settingsRows({ clockInAt: "9:00", clockOutAt: "25:00", clockDays: ["sat", "sun"],
    clockInApps: ["slack", "code"], personalWallpaper: "~/Pictures/p.jpg", personalColor: "#FF6600" })
  eq(set.map((r) => r.value), ["9:00", "25:00 (not a time)", "sat, sun", "slack, code", "~/Pictures/p.jpg", "#FF6600"])
})

test("panel: which modes still need a browser", () => {
  eq(M.missingBrowsersLine(["work", "personal"]), "Choose a browser for Work and Personal")
  eq(M.missingBrowsersLine(["personal"]), "Choose a browser for Personal")
  eq(M.missingBrowsersLine([]), "Browsers, apps and web apps for each mode")
})

test("colours and the look file", () => {
  eq(M.validColor("#ff6600"), "#FF6600")
  eq(M.validColor(" FF6600 "), "#FF6600")
  eq(M.validColor("#f60"), "")
  eq(M.validColor("orange"), "")
  eq(M.validColor(undefined), "")
  eq(M.lookText("#3366FF"), "personal_color=#3366FF\n")
  eq(M.lookText(""), "")
  eq(M.settingsRows({ personalColor: "orange" })[5].value, "orange (not a colour)")
  eq(M.settingsRows({ personalColor: "#3366ff" })[5].value, "#3366ff")
})

if (failed) { console.log("\n" + failed + " failed"); process.exit(1) }
console.log("\nall passed")
