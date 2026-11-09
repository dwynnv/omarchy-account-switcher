-- The plugin's own modules (hypr/...) and test helpers, wherever the tests run from.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
package.path = here .. "/../../?.lua;" .. here .. "/?.lua;" .. package.path
local t = require("t")
local L = require("hypr.account-switcher.logic")

-- The rules setup writes for tests/fixtures/config.full.json (config_test keeps them in step).
local function read(path)
  local f = assert(io.open(path, "r"))
  local text = f:read("a")
  f:close()
  return text
end
local FIXTURE = read(here .. "/../fixtures/apps")
L.configure(L.parse_apps(FIXTURE))

-- Every monitor owns a block of ten per mode, numbered like Omarchy's per-monitor
-- workspaces: Work on block b is b*10+1..b*10+10, Personal is 100 above it.
t.test("mode_of ranges", function()
  t.eq(L.mode_of(1), "work"); t.eq(L.mode_of(10), "work"); t.eq(L.mode_of(11), "work"); t.eq(L.mode_of(100), "work")
  t.eq(L.mode_of(101), "personal"); t.eq(L.mode_of(120), "personal"); t.eq(L.mode_of(200), "personal")
  t.eq(L.mode_of(0), nil); t.eq(L.mode_of(201), nil); t.eq(L.mode_of(-98), nil); t.eq(L.mode_of("3"), nil)
end)
t.test("slot, block and id", function()
  t.eq(L.slot_of(3), 3); t.eq(L.slot_of(13), 3); t.eq(L.slot_of(10), 10); t.eq(L.slot_of(120), 10)
  t.eq(L.block_of(3), 0); t.eq(L.block_of(13), 1); t.eq(L.block_of(20), 1); t.eq(L.block_of(103), 0); t.eq(L.block_of(121), 2)
  t.eq(L.id_for("work", 3), 3); t.eq(L.id_for("personal", 3), 103)
  t.eq(L.id_for("work", 3, 2), 23); t.eq(L.id_for("personal", 10, 1), 120)
  t.eq(L.other("work"), "personal"); t.eq(L.other("personal"), "work")
end)
t.test("send_target keeps the monitor and the number", function()
  t.eq(L.send_target(3), 103); t.eq(L.send_target(103), 3)
  t.eq(L.send_target(24), 124); t.eq(L.send_target(124), 24); t.eq(L.send_target(250), nil)
end)
t.test("next_in_mode wraps inside the mode", function()
  local ids = { 1, 3, 102, 104, 7 }
  t.eq(L.next_in_mode(ids, 3, "work", 1), 7); t.eq(L.next_in_mode(ids, 7, "work", 1), 1)
  t.eq(L.next_in_mode(ids, 1, "work", -1), 7)
  t.eq(L.next_in_mode(ids, 102, "personal", 1), 104); t.eq(L.next_in_mode(ids, 104, "personal", 1), 102)
  t.eq(L.next_in_mode({ 5 }, 5, "work", 1), 5)
  t.eq(L.next_in_mode({ 2, 4 }, 9, "work", 1), 2); t.eq(L.next_in_mode({ 2, 4 }, 9, "work", -1), 4)
  t.eq(L.next_in_mode({ 2 }, 2, "personal", 1), nil)
end)
t.test("status line", function()
  t.eq(L.status_line("personal", false, 2), "mode=personal peek=0 alerts=2 share=0")
  t.eq(L.status_line("work", true, 0), "mode=work peek=1 alerts=0 share=0")
end)
t.test("memory round trip", function()
  local m = { work = { ["Laptop Panel 0x0001"] = 3 }, personal = { ["Desk Monitor 4K 0x0002"] = 114 } }
  local back = L.parse_memory(L.format_memory(m))
  t.eq(back.work["Laptop Panel 0x0001"], 3)
  t.eq(back.personal["Desk Monitor 4K 0x0002"], 114)
end)
t.test("memory ignores bad lines and wrong-mode ids", function()
  local m = L.parse_memory("garbage\nwork\tX\tnope\npersonal\tY\t5\npersonal\tW\t15\npersonal\tZ\t115\n")
  t.eq(m.work, {}); t.eq(m.personal, { Z = 115 })
end)

local E = function() return { work = {}, personal = {} } end
-- The laptop on block 0, a desk monitor on block 1.
t.test("first switch maps each monitor to the same number on its own block", function()
  local mons = { { name = "DP-1", desc = "A", block = 1, active = 12, focused = false }, { name = "eDP-1", desc = "B", block = 0, active = 3, focused = true } }
  t.eq(L.plan_switch(mons, E(), "personal"), { { name = "DP-1", workspace = 112 }, { name = "eDP-1", workspace = 103 } })
  t.eq(L.plan_switch({ { name = "DP-1", desc = "A", block = 1, active = 112, focused = true } }, E(), "work"),
    { { name = "DP-1", workspace = 12 } })
end)
t.test("memory wins over the same number", function()
  local mons = { { name = "eDP-1", desc = "B", block = 0, active = 3, focused = true } }
  t.eq(L.plan_switch(mons, { work = {}, personal = { B = 105 } }, "personal"), { { name = "eDP-1", workspace = 105 } })
end)
t.test("the focused monitor goes last", function()
  local mons = { { name = "eDP-1", desc = "B", block = 0, active = 3, focused = true }, { name = "DP-1", desc = "A", block = 1, active = 12, focused = false } }
  t.eq(L.plan_switch(mons, E(), "personal"), { { name = "DP-1", workspace = 112 }, { name = "eDP-1", workspace = 103 } })
end)
t.test("each monitor only gets a workspace of its own block", function()
  local mons = { { name = "DP-1", desc = "A", block = 1, active = 12, focused = false }, { name = "eDP-1", desc = "B", block = 0, active = 3, focused = true } }
  -- Memory and the shown workspace from another monitor's block are both ignored.
  t.eq(L.plan_switch(mons, { work = {}, personal = { A = 103, B = 103 } }, "personal"),
    { { name = "DP-1", workspace = 112 }, { name = "eDP-1", workspace = 103 } })
  t.eq(L.plan_switch({ { name = "DP-1", desc = "A", block = 1, active = 4, focused = true } }, E(), "work"),
    { { name = "DP-1", workspace = 14 } })
end)
t.test("a monitor already in the target mode keeps its workspace", function()
  local mons = { { name = "DP-1", desc = "A", block = 1, active = 114, focused = false }, { name = "eDP-1", desc = "B", block = 0, active = 3, focused = true } }
  t.eq(L.plan_switch(mons, { work = {}, personal = { A = 112 } }, "personal"),
    { { name = "DP-1", workspace = 114 }, { name = "eDP-1", workspace = 103 } })
end)
t.test("a monitor outside both modes gets its block's first workspace", function()
  t.eq(L.plan_switch({ { name = "HDMI-A-1", desc = "C", block = 2, active = 0, focused = true } }, E(), "personal"),
    { { name = "HDMI-A-1", workspace = 121 } })
  t.eq(L.plan_switch({ { name = "HDMI-A-1", desc = "C", active = 0, focused = true } }, E(), "personal"),
    { { name = "HDMI-A-1", workspace = 101 } })
end)
t.test("memory pointing into the wrong mode is ignored", function()
  local mons = { { name = "eDP-1", desc = "B", block = 0, active = 3, focused = true } }
  t.eq(L.plan_switch(mons, { work = {}, personal = { B = 4 } }, "personal"), { { name = "eDP-1", workspace = 103 } })
end)
t.test("remember records each monitor under its mode", function()
  local mem = L.remember(E(), { { name = "eDP-1", desc = "B", active = 113, focused = true }, { name = "DP-1", desc = "A", active = 0, focused = false } })
  t.eq(mem.personal.B, 113); t.eq(mem.work, {})
end)
t.test("renumbering from the 1-10/11-20 desk puts each workspace on its monitor's block", function()
  -- Before: Work 1-10 and Personal 11-20 shared by every monitor. The laptop (block 0) has
  -- Work 1 and Personal 12, HDMI (block 1) Work 4, 5 and Personal 11, DP (block 2) Work 2, 3
  -- and Personal 13. Personal moves first, so no Work id lands on one still in use.
  local ws = {
    { id = 1, block = 0 }, { id = 12, block = 0 },
    { id = 4, block = 1 }, { id = 5, block = 1 }, { id = 11, block = 1 },
    { id = 2, block = 2 }, { id = 3, block = 2 }, { id = 13, block = 2 },
  }
  t.eq(L.plan_renumber(ws), {
    { from = 12, to = 102 }, { from = 11, to = 111 }, { from = 13, to = 123 },
    { from = 4, to = 14 }, { from = 5, to = 15 }, { from = 2, to = 22 }, { from = 3, to = 23 },
  })
end)
t.test("renumbering keeps 11-20 in Work when its windows are Work's", function()
  -- Omarchy 4.5 had already moved HDMI's Work 4 and 5 to its own 14 and 15.
  t.eq(L.plan_renumber({ { id = 14, block = 1, mode = "work" }, { id = 15, block = 1 }, { id = 16, block = 2, mode = "work" } }),
    { { from = 15, to = 115 }, { from = 16, to = 26 } })
end)
t.test("renumbering frees an old Personal id before Work needs it", function()
  -- Work 3 on block 1 wants 13, which is old Personal 13 until that moves to 113.
  t.eq(L.plan_renumber({ { id = 3, block = 1 }, { id = 13, block = 1 } }),
    { { from = 13, to = 113 }, { from = 3, to = 13 } })
end)
t.test("renumbering keeps ids already right and takes the next free slot when one is taken", function()
  t.eq(L.plan_renumber({ { id = 1, block = 0 }, { id = 102, block = 0 }, { id = 25, block = 2 } }), {})
  -- Work 4 and Work 24 both on block 2: 24 stays, 4 takes block 2's first free slot.
  t.eq(L.plan_renumber({ { id = 24, block = 2 }, { id = 4, block = 2 } }), { { from = 4, to = 21 } })
  -- An old Work id on block 0 and ids past 200 are left alone.
  t.eq(L.plan_renumber({ { id = 7, block = 0 }, { id = 250, block = 1 } }), {})
end)

t.test("identity by executable first", function()
  t.eq(L.identity("chrome-abcdefghijklmnopabcdefghijklmnop-Default", "/usr/lib/chromium/chromium"), "personal")
  t.eq(L.identity("google-chrome", "/opt/google/chrome/chrome"), "work")
end)
t.test("identity by class", function()
  t.eq(L.identity("Slack", nil), "work"); t.eq(L.identity("filezilla", nil), "work"); t.eq(L.identity("FileZilla", nil), "work")
  t.eq(L.identity("steam", nil), "personal"); t.eq(L.identity("steam_app_480", nil), "personal")
  t.eq(L.identity("ClickUp", nil), "work"); t.eq(L.identity("chromium", nil), "personal")
  t.eq(L.identity("google-chrome", nil), "work")
  t.eq(L.identity("obsidian", "/usr/bin/obsidian"), nil)
end)
t.test("rgba normalises Hyprland colours", function()
  t.eq(L.rgba("0xEE33CCFF"), "rgba(33ccffee)"); t.eq(L.rgba("rgba(00FF99EE)"), "rgba(00ff99ee)")
end)
t.test("rule colour: active gradient, angle, inactive", function()
  t.eq(L.rule_colour({ colors = { "0xEE33CCFF", "0xEE00FF99" }, angle = 45.00000125 }, { colors = { "0xAA595959" }, angle = 0 }),
    "rgba(33ccffee) rgba(00ff99ee) 45deg rgba(595959aa)")
  t.eq(L.rule_colour("rgba(ffb000ff)", { colors = { "0xAA595959" }, angle = 0 }), "rgba(ffb000ff) 0deg rgba(595959aa)")
  t.eq(L.rule_colour(L.PERSONAL_ACTIVE, { colors = { "0x11223344", "0x55667788" }, angle = 90 }),
    "rgba(ffb000ee) rgba(ff6a00ee) 45deg rgba(22334411) rgba(66778855) 90deg")
end)
t.test("parse the workspace animation from looknfeel.lua", function()
  local text = 'hl.animation({ leaf = "workspaces", enabled = true, speed = 3, spring = "smooth", style = "slide" })\n'
    .. 'hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2.5, spring = "snappy", style = "slidevert" })\n'
    .. '-- hl.animation({ leaf = "workspaces", enabled = true, speed = 9, bezier = "x", style = "fade" })\n'
  t.eq(L.parse_workspace_animation(text), { enabled = true, speed = 3, curve_key = "spring", curve = "smooth", style = "slide" })
  t.eq(L.parse_workspace_animation('hl.animation({ leaf = "workspaces", enabled = false })'), { enabled = false })
  t.eq(L.parse_workspace_animation("-- nothing here"), nil)
end)

t.test("landing decisions", function()
  local d = function(c, m, f, p) return L.decide_landing({ current = c, ws_mode = m, on_focused_monitor = f, peeking = p }) end
  t.eq(d("work", "personal", true, false), "complete")
  t.eq(d("work", "personal", false, false), "fix_monitor")
  t.eq(d("work", "work", true, false), "ignore")
  t.eq(d("work", nil, true, false), "ignore")
  t.eq(d("work", "personal", true, true), "ignore")
end)
t.test("exe from /proc/<pid>/cmdline", function()
  t.eq(L.exe_of("/usr/lib/chromium/chromium\0--type=browser\0"), "/usr/lib/chromium/chromium")
  t.eq(L.exe_of(""), nil); t.eq(L.exe_of(nil), nil)
end)
t.test("home-mode apps", function()
  t.eq(L.is_home_app("Slack"), true); t.eq(L.is_home_app("filezilla"), true); t.eq(L.is_home_app("ClickUp"), true)
  t.eq(L.is_home_app("steam"), true); t.eq(L.is_home_app("steam_app_480"), true)
  t.eq(L.is_home_app("google-chrome"), false); t.eq(L.is_home_app("chromium"), false); t.eq(L.is_home_app("obsidian"), false)
end)
t.test("plan_fix moves only the monitors outside the mode or their block, focused one last", function()
  local mons = {
    { name = "A", desc = "a", block = 1, active = 112, focused = false },
    { name = "B", desc = "b", block = 0, active = 3, focused = true },
    { name = "C", desc = "c", block = 2, active = 21, focused = false },
  }
  t.eq(L.plan_fix(mons, { work = {}, personal = { b = 104 } }, "personal"), { { name = "C", workspace = 121 }, { name = "B", workspace = 104 } })
  t.eq(L.plan_fix({ { name = "A", desc = "a", block = 1, active = 112, focused = true } }, E(), "personal"), {})
  -- Personal, but another monitor's: back to its own block.
  t.eq(L.plan_fix({ { name = "A", desc = "a", block = 1, active = 102, focused = true } }, E(), "personal"),
    { { name = "A", workspace = 112 } })
end)
t.test("each scratchpad belongs to its mode; other special workspaces to none", function()
  t.eq(L.special_mode("special:" .. L.SCRATCHPAD.work), "work")
  t.eq(L.special_mode("special:" .. L.SCRATCHPAD.personal), "personal")
  t.eq(L.special_mode("special:minimized"), nil); t.eq(L.special_mode(nil), nil)
end)
t.test("per-mode terminals and agents carry their mode", function()
  t.eq(L.identity("org.omarchy.term-work", nil), "work"); t.eq(L.identity("org.omarchy.agent-work", nil), "work")
  t.eq(L.identity("org.omarchy.term-personal", nil), "personal"); t.eq(L.identity("org.omarchy.agent-personal", nil), "personal")
  t.eq(L.identity("org.omarchy.agent", nil), "work"); t.eq(L.identity("org.omarchy.terminal", nil), nil)
end)
t.test("VS Code's mode comes from its data dir", function()
  t.eq(L.identity("com.microsoft.VSCode", "/usr/share/code/code", "/usr/share/code/code\0--user-data-dir\0/home/u/.config/Code-Personal\0"), "personal")
  t.eq(L.identity("com.microsoft.VSCode", "/usr/share/code/code", "/usr/share/code/code\0--no-sandbox\0"), "work")
  t.eq(L.identity("com.microsoft.VSCode", nil, nil), "work")
end)
t.test("status line carries the share state", function()
  t.eq(L.status_line("work", false, 0, true), "mode=work peek=0 alerts=0 share=1")
  t.eq(L.status_line("personal", true, 2), "mode=personal peek=1 alerts=2 share=0")
end)
t.test("clock-in places read and write as class and Work workspace", function()
  local places = L.parse_places("slack\t5\ngoogle-chrome\t2\nchromium\t113\n\t4\ncom.microsoft.vscode\t4\nbroken\n")
  t.eq(places, { slack = 5, ["google-chrome"] = 2, ["com.microsoft.vscode"] = 4 })
  t.eq(L.format_places(places), "com.microsoft.vscode\t4\ngoogle-chrome\t2\nslack\t5\n")
  t.eq(L.format_places({}), "")
  t.eq(L.parse_places(nil), {})
end)
t.test("the Personal colour comes from the look file", function()
  t.eq(L.parse_look("personal_color=#3366ff\n"), "#3366FF")
  t.eq(L.parse_look("personal_color=orange\n"), nil)
  t.eq(L.parse_look(nil), nil)
  t.eq(L.personal_active(nil), L.PERSONAL_ACTIVE)
  t.eq(L.personal_active("orange"), L.PERSONAL_ACTIVE)
  t.eq(L.personal_active("#3366FF"), { colors = { "rgba(3366ffee)", "rgba(264cbfee)" }, angle = 45 })
end)
t.test("parse_apps reads every rule kind", function()
  local a = L.parse_apps(FIXTURE)
  t.eq(a.exes, { { "/opt/google/chrome/", "work" }, { "/usr/lib/chromium/", "personal" } })
  t.eq(a.classes.slack, "work"); t.eq(a.classes.clickup, "work"); t.eq(a.classes.chromium, "personal")
  t.eq(a.prefixes, { { "steam_app_", "personal" } })
  t.eq(a.browsers["google-chrome"], true); t.eq(a.home.filezilla, true); t.eq(a.home_prefixes, { "steam_app_" })
  t.eq(a.place["com.microsoft.vscode"], true); t.eq(a.place.steam, nil)
  -- Comments, blank lines and malformed rules are skipped.
  local b = L.parse_apps("# c\n\nclass work\nclass banana slack\nexe work\nhome Slack\n")
  t.eq(b.classes, {}); t.eq(b.exes, {}); t.eq(b.home, { slack = true })
end)

t.test("identity follows the configured browsers", function()
  L.configure(L.parse_apps("exe work /usr/lib/chromium/\nexe personal /opt/google/chrome/\nclass work chromium\nclass personal google-chrome\n"))
  t.eq(L.identity("chrome-abc-Default", "/usr/lib/chromium/chromium"), "work")
  t.eq(L.identity("google-chrome", nil), "personal")
  t.eq(L.identity("slack", nil), nil)
  L.configure(L.parse_apps(FIXTURE))
end)

t.test("no apps file: only the switcher's own classes", function()
  L.configure(nil)
  t.eq(L.identity("slack", nil), nil); t.eq(L.identity("google-chrome", "/opt/google/chrome/chrome"), nil)
  t.eq(L.identity("org.omarchy.term-personal", nil), "personal"); t.eq(L.identity("org.omarchy.agent", nil), "work")
  t.eq(L.is_home_app("steam_app_1"), false); t.eq(L.is_browser("chromium"), false); t.eq(L.PLACE_CLASSES, {})
  L.configure(L.parse_apps(FIXTURE))
end)
t.test("parse_apps skips the lines of a browser not chosen yet", function()
  local a = L.parse_apps("exe work \nclass work \nbrowser \nhome slack\n")
  t.eq(a.exes, {}); t.eq(a.classes, {}); t.eq(a.browsers, {}); t.eq(a.home, { slack = true })
end)
t.done()
