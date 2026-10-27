// Run: node tests/apps.test.js
const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

const ctx = {}
vm.createContext(ctx)
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "AppsModel.js"), "utf8"), ctx)
const A = ctx

let failed = 0
function test(name, fn) {
  try { fn(); console.log("ok   " + name) }
  catch (e) { failed++; console.log("FAIL " + name + "\n     " + e.message) }
}
const eq = (a, b) => assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), b)

// What `account-switcher apps-list` prints, made up.
const LIST = {
  entries: [
    { id: "browser-a.desktop", name: "Browser A", icon: "a", kind: "browser", usable: true, reason: "", key: "browser-a" },
    { id: "browser-b.desktop", name: "Browser B", icon: "b", kind: "browser", usable: true, reason: "", key: "browser-b" },
    { id: "chat.desktop", name: "Chat", icon: "chat", kind: "app", usable: true, reason: "", key: "chat" },
    { id: "games.desktop", name: "Games", icon: "games", kind: "app", usable: true, reason: "", key: "games" },
    { id: "notes.desktop", name: "notes", icon: "", kind: "app", usable: true, reason: "", key: "notes" },
    { id: "odd.desktop", name: "Odd", icon: "", kind: "app", usable: false, reason: "not from the system app folder", key: "odd" },
    { id: "Maps.desktop", name: "Maps", icon: "", kind: "webapp", usable: true, reason: "", key: "Maps" },
    { id: "Mail.desktop", name: "Mail", icon: "", kind: "webapp", usable: true, reason: "", key: "Mail" },
  ],
  assigned: {
    work: { browser: "browser-a", apps: ["chat"], webapps: ["Mail"] },
    personal: { browser: "browser-b", apps: ["games"], webapps: [] },
    follow: [],
  },
}
const names = (xs) => xs.map((e) => e.name)

test("columns follow the config", () => {
  const c = A.columns(A.initState(LIST), "")
  eq(names(c.work), ["Chat", "Mail"])
  eq(names(c.personal), ["Games"])
  eq(names(c.either), ["Maps", "notes", "Odd"])
  eq(names(c.browsers), ["Browser A", "Browser B"])
})
test("search matches name or key, case-insensitive", () => {
  const c = A.columns(A.initState(LIST), "CHA")
  eq(names(c.work), ["Chat"]); eq(c.personal, []); eq(c.either, [])
  eq(names(A.columns(A.initState(LIST), "browser-b").browsers), ["Browser B"])
})
test("moving an app between columns", () => {
  let s = A.move(A.initState(LIST), "chat", "personal")
  eq(s.assigned.work.apps, []); eq(s.assigned.personal.apps, ["games", "chat"])
  s = A.move(s, "games", "either")
  eq(s.assigned.personal.apps, ["chat"])
  eq(LIST.assigned.work.apps, ["chat"], "the list it came from is untouched")
})
test("moving a web app to Either makes it follow the mode", () => {
  const s = A.move(A.initState(LIST), "Mail", "either")
  eq(s.assigned.work.webapps, []); eq(s.assigned.follow, ["Mail"])
  eq(A.move(s, "Mail", "personal").assigned.follow, [])
})
test("unusable entries don't move", () => {
  const s = A.initState(LIST)
  eq(A.move(s, "odd", "work").assigned, JSON.parse(JSON.stringify(s.assigned)))
})
test("browsers are chosen per mode, or none yet", () => {
  let s = A.setBrowser(A.initState(LIST), "work", null)
  eq(s.assigned.work.browser, null)
  eq(A.missingBrowsers(s), ["work"])
  s = A.setBrowser(s, "work", "browser-a")
  eq(A.missingBrowsers(s), [])
})
test("same browser in both modes is refused", () => {
  const s = A.setBrowser(A.initState(LIST), "personal", "browser-a")
  eq(A.problems(s), ["Work and Personal need different browsers"])
  eq(A.payload(s), null)
})
test("the payload round-trips", () => {
  eq(A.payload(A.initState(LIST)), LIST.assigned)
})

if (failed) { console.log("\n" + failed + " failed"); process.exit(1) }
console.log("\nall passed")
