-- The real switcher modules driven by hyprmock: monitors coming and going, special
-- workspaces, alerts across reloads, and start-up. State goes to a scratch folder.
local tmp = os.getenv("TEST_TMPDIR") or error("run through tests/run.sh")
local statedir = tmp .. "/desk-state"
-- Every store, including the ones a simulated reload loads, writes under the scratch folder.
local real_getenv = os.getenv
os.getenv = function(k)
  if k == "XDG_STATE_HOME" then return statedir end
  return real_getenv(k)
end
-- The plugin's own modules (hypr/...) and test helpers, wherever the tests run from.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
package.path = here .. "/../../?.lua;" .. here .. "/?.lua;" .. package.path
local t = require("t")
local H = require("hyprmock")
local logic = require("hypr.account-switcher.logic")
local store = require("hypr.account-switcher.store")
assert(store.dir():sub(1, #tmp) == tmp, "state must stay in the scratch folder")

local AU, LGA, LGB = "Laptop Panel 0x0001", "Desk Monitor A", "Desk Monitor B"
local DOCKED = { work = { [AU] = 1, [LGA] = 3, [LGB] = 2 }, personal = { [AU] = 12, [LGA] = 13, [LGB] = 14 } }

local desk
-- A config load: Hyprland rebuilds the Lua state, so handlers and timers are gone and the
-- module runs again. Monitor rules apply after the load, then config.reloaded fires.
local function load_config(rules)
  H.handlers, H.timers = {}, {}
  H.fresh_hl()
  for k in pairs(package.loaded) do
    if k:match("^hypr%.account%-switcher") and k ~= "hypr.account-switcher.store" and k ~= "hypr.account-switcher.logic" then
      package.loaded[k] = nil
    end
  end
  _G.account_switcher = nil
  require("hypr.account-switcher")
  desk = require("hypr.account-switcher.desk")
  if rules then rules() end
  H.emit("config.reloaded")
end

-- The app rules setup writes for tests/fixtures/config.full.json.
local apps_fixture
do
  local f = assert(io.open(here .. "/../fixtures/apps", "r"))
  apps_fixture = f:read("a")
  f:close()
end

local function fresh(mode, memory)
  H.reset()
  os.execute("rm -rf '" .. statedir .. "'")
  store.write("apps", apps_fixture)
  if mode then store.save_mode(mode) end
  if memory then store.save_memory(memory) end
end

-- Laptop plus two monitors in Personal, focus on the middle one.
local function docked_personal(extra)
  fresh("personal", DOCKED)
  local e, a, b = H.monitor("eDP-1", AU, 0), H.monitor("HDMI-A-1", LGA, 1920), H.monitor("DP-1", LGB, 3840)
  H.create_ws(1, e); H.create_ws(3, a); H.create_ws(2, b)
  H.show(e, H.create_ws(12, e)); H.show(a, H.create_ws(13, a)); H.show(b, H.create_ws(14, b))
  if extra then extra(e, a, b) end
  H.focus = a
  load_config()
  H.advance(2000)
  return e, a, b
end

local function laptop(mode, active)
  fresh(mode, { work = { [AU] = 1 }, personal = { [AU] = 12 } })
  local e = H.monitor("eDP-1", AU, 0)
  H.create_ws(1, e); H.create_ws(3, e); H.create_ws(12, e)
  H.show(e, H.ws(active)); H.focus = e
  load_config()
  H.advance(2000)
  return e
end

local function assert_desk(mode)
  for _, m in ipairs(H.monitors) do
    t.ok(logic.mode_of(m.active and m.active.id) == mode, "screens " .. H.screens() .. " should all be " .. mode)
  end
  t.eq(desk.current(), mode)
  t.eq(store.load_mode(), mode)
  t.eq(H.border, mode)
end

local function status() return store.read("status") end

t.test("moving a workspace to another monitor keeps the desk in Personal", function()
  fresh("personal", { work = { [AU] = 1, [LGA] = 3 }, personal = { [AU] = 12, [LGA] = 13 } })
  local e, d = H.monitor("eDP-1", AU, 0), H.monitor("DP-1", LGA, 1920)
  H.create_ws(1, e); H.create_ws(3, d)
  H.show(e, H.create_ws(12, e)); H.show(d, H.create_ws(13, d)); H.focus = d
  load_config(); H.advance(2000)
  hl.dispatch(hl.dsp.workspace.move({ monitor = "l" })) -- stock SUPER+SHIFT+ALT+LEFT
  H.advance(2000)
  assert_desk("personal")
  t.eq(H.focus.active.id, 13)
end)

t.test("undocking and re-docking in Personal keeps every monitor in Personal", function()
  docked_personal()
  H.disconnect("HDMI-A-1"); H.disconnect("DP-1"); H.advance(2000)
  load_config(); H.advance(2000) -- the monitor tool: laptop only
  desk.focus_slot(3); H.advance(2000)
  H.connect("HDMI-A-1", LGA, 1920); H.advance(100)
  H.connect("DP-1", LGB, 3840); H.advance(2000)
  load_config(); H.advance(2000) -- the monitor tool: docked
  assert_desk("personal")
end)

t.test("closing and opening the lid while docked in Personal keeps the desk in Personal", function()
  docked_personal()
  load_config(function() H.disconnect("eDP-1", true) end); H.advance(2000)
  desk.focus_slot(2); H.advance(2000)
  load_config(function() H.connect("eDP-1", AU, 0) end); H.advance(2000)
  assert_desk("personal")
end)

t.test("a new monitor that gets focus before the fix still joins Personal", function()
  laptop("personal", 12)
  H.connect("DP-1", LGA, 1920)
  H.rawMonitorFocus(H.mon("DP-1")) -- the pointer moves onto it right away
  H.advance(2000)
  assert_desk("personal")
end)

t.test("unplugging a monitor in Personal loses no workspace", function()
  docked_personal(function(_, a) H.show(a, H.create_ws(15, a)) end)
  H.disconnect("HDMI-A-1"); H.advance(2000)
  desk.focus_slot(3); H.advance(2000)
  assert_desk("personal")
  t.eq(H.focus.active.id, 13)
end)

t.test("landing on a Work workspace on the focused monitor still switches the desk", function()
  docked_personal()
  hl.dispatch(hl.dsp.focus({ workspace = "3" })) -- a click on a Work workspace
  H.advance(2000)
  assert_desk("work")
end)

t.test("start-up in Personal brings the first monitor to Personal", function()
  fresh("personal", { work = {}, personal = { [AU] = 14 } })
  load_config() -- the first load runs before any monitor exists
  H.connect("eDP-1", AU, 0)
  H.emit("hyprland.start")
  H.advance(2000)
  assert_desk("personal")
  t.eq(H.screens(), "eDP-1=14*")
end)

t.test("start-up writes a fresh status, dropping last session's alerts", function()
  fresh("work")
  store.save_status("mode=work peek=0 alerts=2")
  load_config()
  H.connect("eDP-1", AU, 0)
  H.emit("hyprland.start")
  H.advance(2000)
  t.eq(status(), "mode=work peek=0 alerts=0 share=0\n")
end)

t.test("a window in the Work scratchpad can't pull focus in Personal", function()
  laptop("work", 1)
  local c = H.open_window("com.mitchellh.ghostty", H.ws(1))
  c.focused = true
  desk.scratchpad_move() -- SUPER+ALT+S in Work
  desk.switch("personal"); H.advance(2000)
  t.ok(H.has_tag(c, "dwm-hidden"), "tags: " .. table.concat(c.tags, ","))
end)

t.test("a window in the Personal scratchpad can't pull focus in Work", function()
  laptop("personal", 12)
  local c = H.open_window("com.mitchellh.ghostty", H.ws(12))
  c.focused = true
  desk.scratchpad_move() -- SUPER+ALT+S in Personal
  desk.switch("work"); H.advance(2000)
  t.ok(H.has_tag(c, "dwm-hidden"), "tags: " .. table.concat(c.tags, ","))
end)

t.test("a window minimized from Work stays Work's, and its attention becomes an alert", function()
  laptop("work", 3)
  local c = H.open_window("com.mitchellh.ghostty", H.ws(3))
  hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", window = H.winproxy(c) })) -- SUPER+M
  desk.switch("personal"); H.advance(2000)
  H.emit("window.urgent", H.winproxy(c))
  t.ok(H.has_tag(c, "dwm-hidden"), "tags: " .. table.concat(c.tags, ","))
  t.eq(status(), "mode=personal peek=0 alerts=1 share=0\n")
end)

t.test("alerts survive a config reload", function()
  laptop("personal", 12)
  local c = H.open_window("com.mitchellh.ghostty", H.ws(3))
  H.emit("window.urgent", H.winproxy(c))
  t.eq(status(), "mode=personal peek=0 alerts=1 share=0\n")
  load_config(); H.advance(2000)
  t.eq(status(), "mode=personal peek=0 alerts=1 share=0\n")
end)

t.test("switching to the alerting window's mode clears its alert", function()
  laptop("personal", 12)
  local c = H.open_window("com.mitchellh.ghostty", H.ws(3))
  H.emit("window.urgent", H.winproxy(c))
  desk.switch("work"); H.advance(2000)
  t.eq(status(), "mode=work peek=0 alerts=0 share=0\n")
  desk.switch("personal"); H.advance(2000)
  t.eq(status(), "mode=personal peek=0 alerts=0 share=0\n")
end)

t.test("closing an alerting window drops its alert", function()
  laptop("personal", 12)
  local c = H.open_window("com.mitchellh.ghostty", H.ws(3))
  H.emit("window.urgent", H.winproxy(c))
  hl.dispatch(hl.dsp.window.close({ window = H.winproxy(c) }))
  t.eq(status(), "mode=personal peek=0 alerts=0 share=0\n")
end)

t.test("a Chrome window opening in Personal waits in Work with an alert", function()
  laptop("personal", 12)
  local c = H.open_window("google-chrome", H.ws(12))
  H.advance(2000)
  t.eq(c.ws.id, 2)
  t.eq(status(), "mode=personal peek=0 alerts=1 share=0\n")
  assert_desk("personal")
end)

t.test("the app rules are read at every load: a Chromium configured as Work's waits in Work", function()
  laptop("personal", 12)
  store.write("apps", "exe work /usr/lib/chromium/\nclass work chromium\nbrowser chromium\n")
  load_config(); H.advance(2000)
  local c = H.open_window("chromium", H.ws(12))
  H.advance(2000)
  t.eq(logic.mode_of(c.ws.id), "work")
  t.eq(status(), "mode=personal peek=0 alerts=1 share=0\n")
end)

t.test("a Chromium window opening in Work waits in Personal with an alert", function()
  laptop("work", 3)
  local c = H.open_window("chromium", H.ws(3))
  H.advance(2000)
  t.eq(c.ws.id, 13)
  t.eq(status(), "mode=work peek=0 alerts=1 share=0\n")
end)

t.test("an agent from the bar's agents panel takes the desk to Work", function()
  laptop("personal", 12)
  local c = H.open_window("org.omarchy.agent", H.ws(12))
  H.advance(2000)
  t.eq(logic.mode_of(c.ws.id), "work")
  assert_desk("work")
end)

t.test("per-mode terminals keep Ghostty's touchpad scroll speed", function()
  laptop("work", 1)
  local found
  for _, r in ipairs(H.rules) do
    if r.scroll_touchpad == 0.2 and r.match and r.match.class == "org\\.omarchy\\.(term|agent)-(work|personal)" then found = r end
  end
  t.ok(found, "no scroll_touchpad rule for the per-mode classes")
end)

t.test("while sharing, a switch asks instead of moving", function()
  laptop("work", 1)
  desk.set_sharing(true)
  H.events = {}
  desk.switch("personal")
  H.advance(2000)
  assert_desk("work")
  t.ok(table.concat(H.events, "|"):find("account-switcher-ask switch personal", 1, true), table.concat(H.events, "|"))
  t.eq(status(), "mode=work peek=0 alerts=0 share=1\n")
  desk.switch("personal", { confirmed = true })
  H.advance(2000)
  assert_desk("personal")
end)

t.test("a landing on the other mode while sharing is put back", function()
  docked_personal()
  desk.set_sharing(true)
  H.events = {}
  hl.dispatch(hl.dsp.focus({ workspace = "3" }))
  H.advance(2000)
  assert_desk("personal")
  t.ok(table.concat(H.events, "|"):find("account-switcher-ask switch work", 1, true), table.concat(H.events, "|"))
end)

t.test("no peek while sharing", function()
  laptop("work", 1)
  desk.set_sharing(true)
  H.events = {}
  H.keydown = true
  desk.grave_down()
  H.advance(2000)
  H.keydown = false
  t.eq(desk.is_peeking(), false)
  assert_desk("work")
  t.ok(table.concat(H.events, "|"):find("account-switcher-ask switch personal", 1, true), table.concat(H.events, "|"))
end)

t.test("hidden-mode windows are kept out of screen shares", function()
  laptop("work", 1)
  local found
  for _, r in ipairs(H.rules) do
    if r.match and r.match.tag == "dwm-hidden" then found = r end
  end
  t.ok(found and found.no_screen_share == true and found.focus_on_activate == false, "dwm-hidden rule")
end)

local function click(c) hl.dispatch(hl.dsp.focus({ window = "address:" .. c.address })) end

t.test("a dock click on a hidden shared app brings it to you", function()
  laptop("personal", 12)
  local c = H.open_window("spotify", H.ws(3))
  click(c)
  H.advance(2000)
  t.eq(c.ws.id, 12)
  assert_desk("personal")
end)

t.test("a dock click on a hidden home-mode app takes the desk to its mode", function()
  laptop("personal", 12)
  local c = H.open_window("Slack", H.ws(3))
  click(c)
  H.advance(2000)
  assert_desk("work")
  t.eq(H.focus.active.id, 3)
  t.eq(c.focused, true)
end)

t.test("a click on a hidden window focuses the same app's window in this mode instead", function()
  laptop("personal", 12)
  local work = H.open_window("google-chrome", H.ws(3))
  local here = H.open_window("google-chrome", H.ws(3))
  here.focused = true
  desk.send_across() -- this Chrome window is now in Personal (13)
  here.focused = false
  click(work)
  H.advance(2000)
  assert_desk("personal")
  t.eq(here.focused, true)
end)

t.test("while sharing, a click on a hidden window moves nothing and asks", function()
  laptop("personal", 12)
  local c = H.open_window("Slack", H.ws(3))
  desk.set_sharing(true)
  H.events = {}
  click(c)
  H.advance(2000)
  assert_desk("personal")
  t.eq(c.ws.id, 3)
  t.ok(table.concat(H.events, "|"):find("account-switcher-ask switch work", 1, true), table.concat(H.events, "|"))
end)

t.test("a window restored from the minimized pile into the other mode goes to its own", function()
  laptop("personal", 12)
  local c = H.open_window("Slack", H.ws(3))
  hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", window = H.winproxy(c) }))
  -- The dock after a shell restart: back onto the current workspace, then focus.
  hl.dispatch(hl.dsp.window.move({ workspace = "12", window = "address:" .. c.address, follow = false }))
  t.eq(c.ws.id, 2)
  click(c)
  H.advance(2000)
  assert_desk("work")
end)

t.test("focus by workspace is left to the landing rules", function()
  laptop("personal", 12)
  hl.dispatch(hl.dsp.focus({ workspace = "3" }))
  H.advance(2000)
  assert_desk("work")
end)

t.test("after a reload the wrappers are back and the switcher's own moves don't loop", function()
  laptop("personal", 12)
  load_config()
  load_config()
  H.advance(2000)
  desk.focus_slot(3)
  t.eq(H.focus.active.id, 13)
  local c = H.open_window("spotify", H.ws(3))
  click(c)
  t.eq(c.ws.id, 13)
end)

-- Toast clicks: a terminal's or agent's toast is Ghostty's, and a click on it comes back as
-- Ghostty's own request to bring its window forward, which the hidden mode blocks.
local TERM_P = "org.omarchy.term-personal"

t.test("a toast click on a hidden terminal takes the desk to it instead of an alert", function()
  laptop("work", 3)
  local c = H.open_window(TERM_P, H.ws(12))
  desk.toast_clicked(TERM_P)
  H.emit("window.urgent", H.winproxy(c))
  H.advance(2000)
  assert_desk("personal")
  t.eq(c.focused, true)
  t.eq(status(), "mode=personal peek=0 alerts=0 share=0\n")
end)

t.test("a hidden terminal asking for attention by itself still waits as an alert", function()
  laptop("work", 3)
  local c = H.open_window(TERM_P, H.ws(12))
  H.emit("window.urgent", H.winproxy(c))
  H.advance(2000)
  assert_desk("work")
  t.eq(status(), "mode=work peek=0 alerts=1 share=0\n")
end)

t.test("a toast click counts only for a moment", function()
  laptop("work", 3)
  local c = H.open_window(TERM_P, H.ws(12))
  desk.toast_clicked(TERM_P)
  H.advance(5000)
  H.emit("window.urgent", H.winproxy(c))
  H.advance(2000)
  assert_desk("work")
  t.eq(status(), "mode=work peek=0 alerts=1 share=0\n")
end)

t.test("a toast click counts once", function()
  laptop("work", 3)
  local c = H.open_window(TERM_P, H.ws(12))
  desk.toast_clicked(TERM_P)
  H.emit("window.urgent", H.winproxy(c))
  H.advance(500)
  desk.switch("work"); H.advance(1000)
  H.emit("window.urgent", H.winproxy(c))
  H.advance(1000)
  assert_desk("work")
  t.eq(status(), "mode=work peek=0 alerts=1 share=0\n")
end)

t.test("a toast click focuses the window that asked, not another of its class", function()
  laptop("personal", 12)
  local here = H.open_window("org.omarchy.term-work", H.ws(12)) -- a Work terminal sent to Personal
  local there = H.open_window("org.omarchy.term-work", H.ws(3))
  desk.toast_clicked("org.omarchy.term-work")
  H.emit("window.urgent", H.winproxy(there))
  H.advance(2000)
  assert_desk("work")
  t.eq(there.focused, true)
  t.eq(here.focused, false)
end)

t.test("while sharing, a toast click on a hidden terminal asks first", function()
  laptop("work", 3)
  local c = H.open_window(TERM_P, H.ws(12))
  desk.set_sharing(true)
  H.events = {}
  desk.toast_clicked(TERM_P)
  H.emit("window.urgent", H.winproxy(c))
  H.advance(2000)
  assert_desk("work")
  t.ok(table.concat(H.events, "|"):find("account-switcher-ask switch personal", 1, true), table.concat(H.events, "|"))
end)

t.test("a toast with no live sender focuses its class's most recent window", function()
  laptop("work", 3)
  local never = H.open_window(TERM_P, H.ws(12))
  local older = H.open_window(TERM_P, H.ws(12))
  local newer = H.open_window(TERM_P, H.ws(12))
  never.history, older.history, newer.history = -1, 2, 1
  H.open_window("org.omarchy.term-work", H.ws(3)).history = 0
  desk.focus_class(TERM_P)
  H.advance(2000)
  assert_desk("personal")
  t.eq(newer.focused, true)
end)

t.test("a toast with no live sender and no window left changes nothing", function()
  laptop("work", 3)
  desk.focus_class(TERM_P)
  H.advance(2000)
  assert_desk("work")
end)

-- Clock in: the apps it launches go back to where they last were in Work.
t.test("clock-in: an expected window goes to the Work workspace its class last closed on", function()
  local e = laptop("work", 1)
  H.create_ws(5, e)
  local old = H.open_window("Slack", H.ws(5))
  hl.dispatch(hl.dsp.window.close({ window = H.winproxy(old) }))
  t.eq(store.read("places"), "slack\t5\n")
  account_switcher.desk.expect("Slack")
  local c = H.open_window("Slack", H.ws(1))
  H.advance(2000)
  t.eq(c.ws.id, 5)
  t.eq(e.active.id, 1)
  assert_desk("work")
  -- Only the next window of the class.
  local d = H.open_window("Slack", H.ws(1))
  H.advance(2000)
  t.eq(d.ws.id, 1)
end)

t.test("clock-in: places last across a reload, and only Work workspaces are remembered", function()
  local e = laptop("work", 1)
  H.create_ws(4, e)
  local code = H.open_window("com.microsoft.VSCode", H.ws(4))
  hl.dispatch(hl.dsp.window.close({ window = H.winproxy(code) }))
  local sent = H.open_window("com.microsoft.VSCode", H.ws(12))
  hl.dispatch(hl.dsp.window.close({ window = H.winproxy(sent) }))
  local term = H.open_window("com.mitchellh.ghostty", H.ws(1))
  hl.dispatch(hl.dsp.window.close({ window = H.winproxy(term) }))
  t.eq(store.read("places"), "com.microsoft.vscode\t4\n")
  load_config()
  H.advance(2000)
  account_switcher.desk.expect("com.microsoft.VSCode")
  local c = H.open_window("com.microsoft.VSCode", H.ws(1))
  H.advance(2000)
  t.eq(c.ws.id, 4)
end)

t.test("clock-in: with no remembered place the window stays on the current Work workspace", function()
  laptop("work", 3)
  account_switcher.desk.expect("google-chrome")
  local c = H.open_window("google-chrome", H.ws(3))
  H.advance(2000)
  t.eq(c.ws.id, 3)
  t.eq(status(), "mode=work peek=0 alerts=0 share=0\n")
end)

t.test("clock-in: an expectation lapses after two minutes", function()
  local e = laptop("work", 1)
  H.create_ws(5, e)
  local old = H.open_window("Slack", H.ws(5))
  hl.dispatch(hl.dsp.window.close({ window = H.winproxy(old) }))
  account_switcher.desk.expect("Slack")
  H.advance(121000)
  local c = H.open_window("Slack", H.ws(1))
  H.advance(2000)
  t.eq(c.ws.id, 1)
end)

t.test("clock-in: a window expected while the desk stays in Personal waits in Work", function()
  laptop("personal", 12)
  account_switcher.desk.expect("Slack")
  local c = H.open_window("Slack", H.ws(12))
  H.advance(2000)
  t.eq(c.ws.id, 2)
  t.eq(status(), "mode=personal peek=0 alerts=1 share=0\n")
  assert_desk("personal")
end)

-- Settings: the Personal colour.
t.test("the Personal colour is read at load and can change live", function()
  fresh("personal", { work = { [AU] = 1 }, personal = { [AU] = 12 } })
  store.write("look", "personal_color=#3366FF\n")
  local e = H.monitor("eDP-1", AU, 0)
  H.create_ws(1, e); H.create_ws(12, e)
  H.show(e, H.ws(12)); H.focus = e
  load_config()
  H.advance(2000)
  t.eq(H.border_value, { colors = { "rgba(3366ffee)", "rgba(264cbfee)" }, angle = 45 })
  account_switcher.set_personal_colour("#FF0000")
  t.eq(H.border_value, { colors = { "rgba(ff0000ee)", "rgba(bf0000ee)" }, angle = 45 })
  local rule
  for _, r in ipairs(H.rules) do
    if r.name == "account-switcher-id-personal" then rule = r end
  end
  t.ok(rule and tostring(rule.border_color):find("ff0000ee", 1, true), "Personal windows' rule kept the old colour")
  -- Not a colour: nothing changes.
  account_switcher.set_personal_colour("orange")
  t.eq(H.border_value, { colors = { "rgba(ff0000ee)", "rgba(bf0000ee)" }, angle = 45 })
  -- Cleared: back to the default amber.
  account_switcher.set_personal_colour("")
  t.eq(H.border_value, logic.PERSONAL_ACTIVE)
  -- In Work, Work's border stays.
  desk.switch("work")
  H.advance(2000)
  account_switcher.set_personal_colour("#00FF00")
  t.eq(H.border, "work")
end)

t.done()
