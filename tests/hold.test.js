// Run: node tests/hold.test.js
// Which notifications wait: notifications/HoldLogic.js.
const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

const ctx = {}
vm.createContext(ctx)
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "notifications", "HoldLogic.js"), "utf8"), ctx)
const H = ctx

let failed = 0
function test(name, fn) {
  try { fn(); console.log("ok   " + name) }
  catch (e) { failed++; console.log("FAIL " + name + "\n     " + e.message) }
}
const eq = (a, b) => assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), b)

const LOW = 0, NORMAL = 1, CRITICAL = 2
const PERSONAL = { mode: "personal", share: false }
const WORK = { mode: "work", share: false }
const SHARING = { mode: "work", share: true }
// What setup writes to hold.json for a config with Slack and FileZilla in Work, Chrome as
// Work's browser and "Example VPN" among holdApps.
const APPS = H.parseHoldApps(JSON.stringify({ version: 1,
  names: ["slack", "filezilla", "google chrome", "example vpn"], entries: ["slack", "filezilla", "google-chrome"] }))

test("Work apps by app name or desktop entry", () => {
  eq(H.isWorkApp("Slack", "", APPS), true)
  eq(H.isWorkApp("", "slack", APPS), true)
  eq(H.isWorkApp("Google Chrome", "", APPS), true)
  eq(H.isWorkApp("", "google-chrome", APPS), true)
  eq(H.isWorkApp("FileZilla", "", APPS), true)
  eq(H.isWorkApp("", "filezilla", APPS), true)
  eq(H.isWorkApp("Example VPN", "", APPS), true)
  eq(H.isWorkApp("Chromium", "chromium", APPS), false)
  eq(H.isWorkApp("KDE Connect", "org.kde.kdeconnect.daemon", APPS), false)
  eq(H.isWorkApp("omarchy-action", "", APPS), false)
  eq(H.isWorkApp(undefined, null, APPS), false)
})

test("hold.json: lowercase names and entries, and nothing without it", () => {
  eq(H.parseHoldApps('{"version":1,"names":["Slack"],"entries":["Slack"]}'), { names: ["slack"], entries: ["slack"] })
  eq(H.parseHoldApps("not json"), { names: [], entries: [] })
  eq(H.parseHoldApps(""), { names: [], entries: [] })
  eq(H.isWorkApp("Slack", "slack", H.parseHoldApps("")), false)
  eq(H.isWorkApp("Slack", "slack", undefined), false)
  eq(H.holdReason({ app: "Slack", desktopEntry: "slack", urgency: NORMAL }, PERSONAL, undefined), "")
})

test("in Personal, a Work app's notification waits, whatever its urgency", () => {
  eq(H.holdReason({ app: "Slack", desktopEntry: "slack", urgency: NORMAL }, PERSONAL, APPS), "mode")
  eq(H.holdReason({ app: "Slack", urgency: CRITICAL }, PERSONAL, APPS), "mode")
  eq(H.holdReason({ app: "Example VPN", urgency: CRITICAL }, PERSONAL, APPS), "mode")
  eq(H.holdReason({ app: "Chromium", desktopEntry: "chromium", urgency: NORMAL }, PERSONAL, APPS), "")
  eq(H.holdReason({ app: "Slack", urgency: NORMAL }, WORK, APPS), "")
  // Before the desk's mode is known nothing waits.
  eq(H.holdReason({ app: "Slack", urgency: NORMAL }, { mode: "", share: false }, APPS), "")
  eq(H.holdReason({ app: "Slack", urgency: NORMAL }, null, APPS), "")
})

test("while sharing, everything but critical waits", () => {
  eq(H.holdReason({ app: "KDE Connect", urgency: NORMAL }, SHARING, APPS), "share")
  eq(H.holdReason({ app: "omarchy-action", urgency: LOW }, SHARING, APPS), "share")
  eq(H.holdReason({ app: "omarchy-action", urgency: CRITICAL }, SHARING, APPS), "")
  eq(H.holdReason({ app: "Slack", urgency: CRITICAL }, SHARING, APPS), "")
  // A Work app in Personal waits for Work even when the share ends first.
  eq(H.holdReason({ app: "Slack", urgency: NORMAL }, { mode: "personal", share: true }, APPS), "mode")
})

test("state from the desk's status line and its custom event", () => {
  eq(H.parseState("mode=personal peek=0 alerts=2 share=1\n"), { mode: "personal", share: true })
  eq(H.parseState("account-switcher mode=work peek=1 alerts=0 share=0"), { mode: "work", share: false })
  eq(H.parseState("mode=work peek=0 alerts=0"), { mode: "work", share: false })
  eq(H.parseState("account-switcher-ask switch work"), null)
  eq(H.parseState(""), null)
})

const slack = (id, urgency) => ({ reason: "mode", desktopEntry: "slack",
  entry: { id: id, originalId: id, app: "Slack", summary: "msg " + id, urgency: urgency, timestamp: 1000 + id } })

test("release: what no longer has a reason goes, the rest waits for its new reason", () => {
  const items = [slack(1, NORMAL), slack(2, CRITICAL),
    { reason: "share", desktopEntry: "", entry: { id: 3, originalId: 3, app: "KDE Connect", urgency: NORMAL, timestamp: 1003 } }]
  // Switching to Work while still sharing: the critical Slack and nothing else is shown.
  let split = H.partition(items, SHARING, false, APPS)
  eq(split.release.map((i) => i.entry.id), [2])
  eq(split.keep.map((i) => [i.entry.id, i.reason]), [[1, "share"], [3, "share"]])
  // The share ends in Personal: KDE Connect is shown, Slack keeps waiting for Work.
  split = H.partition(items, { mode: "personal", share: false }, false, APPS)
  eq(split.release.map((i) => i.entry.id), [3])
  eq(split.keep.map((i) => [i.entry.id, i.reason]), [[1, "mode"], [2, "mode"]])
  // Forced (the panel's "show now"): everything, oldest first.
  split = H.partition(items, PERSONAL, true, APPS)
  eq(split.release.map((i) => i.entry.id), [1, 2, 3])
  eq(split.keep, [])
})

test("held.json round-trips without the live objects", () => {
  const item = slack(7, NORMAL)
  item.ref = { tracked: true }
  const text = H.serializeHeld([item])
  eq("ref" in JSON.parse(text).items[0], false)
  const back = H.parseHeld(text)
  eq(back.length, 1)
  eq(back[0].reason, "mode")
  eq(back[0].desktopEntry, "slack")
  eq(back[0].entry.summary, "msg 7")
  eq(back[0].ref, null)
  eq(H.parseHeld("not json"), [])
  eq(H.parseHeld('{"items": [{"reason": "mode"}, {"entry": {"app": "Slack"}}, null]}'), [])
  eq(H.heldCount(text), 1)
  eq(H.heldCount(""), 0)
})

// Toast clicks: terminals and agents are Ghostty, whose toasts carry only the window class.
test("the terminal and agent classes are the ones a click can find", () => {
  for (const cls of ["org.omarchy.term-work", "org.omarchy.term-personal", "org.omarchy.agent-work",
    "org.omarchy.agent-personal", "org.omarchy.agent"]) eq(H.modeWindowClass(cls), cls)
  eq(H.modeWindowClass("com.mitchellh.ghostty"), "")
  eq(H.modeWindowClass("slack"), "")
  eq(H.modeWindowClass("ORG.OMARCHY.TERM-WORK"), "")
  eq(H.modeWindowClass("org.omarchy.term-work') os.exit() --"), "")
  eq(H.modeWindowClass(undefined), "")
})

test("a desk call names only a known function and a known class", () => {
  eq(H.deskCall("toast_clicked", "org.omarchy.agent-personal"),
    "function() if account_switcher and account_switcher.desk and account_switcher.desk.toast_clicked then " +
    "account_switcher.desk.toast_clicked('org.omarchy.agent-personal') end end")
  eq(H.deskCall("focus_class", "org.omarchy.term-work"),
    "function() if account_switcher and account_switcher.desk and account_switcher.desk.focus_class then " +
    "account_switcher.desk.focus_class('org.omarchy.term-work') end end")
  eq(H.deskCall("focus_class", "slack"), "")
  eq(H.deskCall("focus_class", "org.omarchy.term-work'); os.exit() --"), "")
  eq(H.deskCall("switch", "org.omarchy.term-work"), "")
})

test("toast classes are kept by file name, newest first, up to the limit", () => {
  let classes = {}
  for (let i = 1; i <= 45; i++) classes = H.noteClass(classes, (1000 + i) + "-" + i + ".json", "org.omarchy.term-work")
  const names = Object.keys(classes)
  eq(names.length, 40)
  eq(names.includes("1001-1.json"), false)
  eq(names.includes("1045-45.json"), true)
  // Noting doesn't change the map it was given.
  const before = H.noteClass({}, "1-1.json", "org.omarchy.agent")
  H.noteClass(before, "2-2.json", "org.omarchy.agent")
  eq(before, { "1-1.json": "org.omarchy.agent" })
  // Only terminal and agent classes are kept.
  eq(H.noteClass({}, "3-3.json", "slack"), {})
  const text = H.serializeClasses({ "5-1.json": "org.omarchy.agent-work" })
  eq(H.parseClasses(text), { "5-1.json": "org.omarchy.agent-work" })
  eq(H.parseClasses('{"version":1,"classes":{"5-1.json":"slack","6-1.json":"org.omarchy.agent","x":7}}'),
    { "6-1.json": "org.omarchy.agent" })
  eq(H.parseClasses("not json"), {})
  eq(H.parseClasses(""), {})
})

if (failed) { console.log("\n" + failed + " failed"); process.exit(1) }
console.log("\nall passed")
