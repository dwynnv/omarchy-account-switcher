-- What the mode switcher does inside the compositor.
local D = {}

local logic, store, look
local live = false
-- The desk's mode: what the badge shows and what the keys act in. A monitor showing the
-- other mode (a peek, a landing, Hyprland rearranging monitors) is brought back to match it.
local last = "work"
local peeking = false
local busy = false
-- A screen share is live (the shell watches the portal's stream): switching asks first.
local sharing = false
-- Monitors are coming, going or swapping workspaces: wait for Hyprland, then fix_all.
local settling = false
local settle_timer, land_timer
-- Clock in: classes whose next window it placed (lowercased class -> generation), and the
-- Work workspace each class last closed on.
local expecting, expect_gen = {}, 0
local places = {}
local EXPECT_MS = 120000
-- Toast clicks: classes whose toast was just clicked (class -> generation).
local clicks, click_gen = {}, 0
local CLICK_MS = 3000

function D.setup(l, s, is_live)
  logic, store, live = l, s, is_live
  if live then
    last = store.load_mode() or "work"
    places = store.load_places()
  end
end

function D.use_look(l) look = l end

-- hl.dsp.focus and hl.dsp.window.move as they were before route.lua wrapped them, so the
-- switcher's own dispatches are never routed (or looped) through the wrappers.
local dsp = {}
function D.use_dispatchers(originals) dsp = originals end
local function dsp_focus(args) return (dsp.focus or hl.dsp.focus)(args) end
local function dsp_move(args) return (dsp.move or hl.dsp.window.move)(args) end

function D.current() return last end

function D.monitors()
  local list = {}
  for _, m in ipairs(hl.get_monitors()) do
    local ws = m.active_workspace
    list[#list + 1] = { name = m.name, desc = m.description, active = ws and ws.id or 0, focused = m.focused == true }
  end
  return list
end

local function focus_workspace(id)
  hl.dispatch(dsp_focus({ workspace = tostring(id) }))
end

function D.focus_slot(n)
  focus_workspace(logic.id_for(last, n))
end

function D.move_to_slot(n, follow)
  hl.dispatch(dsp_move({ workspace = tostring(logic.id_for(last, n)), follow = follow }))
end

function D.cycle(dir)
  local ids = {}
  for _, ws in ipairs(hl.get_workspaces()) do
    if ws.id and ws.id > 0 then ids[#ids + 1] = ws.id end
  end
  local active = hl.get_active_workspace()
  local id = logic.next_in_mode(ids, active and active.id, last, dir)
  if id then focus_workspace(id) end
end

function D.former()
  local ws = hl.get_last_workspace()
  if ws and ws.id and logic.mode_of(ws.id) == last then focus_workspace(ws.id) end
end

function D.scratchpad_toggle()
  hl.dispatch(hl.dsp.workspace.toggle_special(logic.SCRATCHPAD[last]))
end

function D.scratchpad_move()
  hl.dispatch(dsp_move({ workspace = "special:" .. logic.SCRATCHPAD[last], follow = false }))
end

-- Omarchy's close-all ends on workspace 1; this ends on the current mode's first workspace.
function D.close_all()
  for _, w in ipairs(hl.get_windows()) do hl.dispatch(hl.dsp.window.close({ window = w })) end
  focus_workspace(logic.id_for(last, 1))
end

-- One Lua call for every monitor, focused monitor last, so they all animate together.
local function apply_steps(steps)
  for _, step in ipairs(steps) do
    hl.dispatch(dsp_focus({ monitor = step.name }))
    hl.dispatch(dsp_focus({ workspace = tostring(step.workspace), on_current_monitor = true }))
  end
end

local function cmdline_of(pid)
  if not pid then return nil end
  local f = io.open("/proc/" .. pid .. "/cmdline", "rb")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

local function identity_of(w)
  local cmdline = cmdline_of(w.pid)
  return logic.identity(w.class, logic.exe_of(cmdline), cmdline)
end
D.identity_of = identity_of

local function has_tag(w, tag)
  for _, t in ipairs(w.tags or {}) do
    if t == tag then return true end
  end
  return false
end

local function set_tag(w, tag, wanted)
  if has_tag(w, tag) ~= wanted then
    hl.dispatch(hl.dsp.window.tag({ tag = (wanted and "+" or "-") .. tag, window = w }))
  end
end

-- The mode a window is in: its workspace's; on a special workspace, the scratchpad's mode,
-- else the mode it was last seen in (its dwm-from-* tag), else its accounts'.
local function window_mode(w)
  local ws = w.workspace
  if not ws then return nil end
  local mode = logic.mode_of(ws.id)
  if mode or not ws.special then return mode end
  mode = logic.special_mode(ws.name)
  if mode then return mode end
  if has_tag(w, "dwm-from-work") then return "work" end
  if has_tag(w, "dwm-from-personal") then return "personal" end
  return identity_of(w)
end

D.window_mode = window_mode

-- Another window of the same class in MODE (not on a special workspace), if there is one.
function D.window_in_mode(class, mode, except)
  for _, w in ipairs(hl.get_windows({ class = class })) do
    local ws = w.workspace
    if w.address ~= except and ws and logic.mode_of(ws.id) == mode then return w end
  end
  return nil
end

-- Alerts are dwm-alert tags on windows of the hidden mode that asked for attention, so
-- they outlive the Lua state that every reload throws away.
local function alert_count(except)
  local n, hidden = 0, logic.other(last)
  for _, w in ipairs(hl.get_windows()) do
    if w.address ~= except and has_tag(w, "dwm-alert") and window_mode(w) == hidden then n = n + 1 end
  end
  return n
end

-- While sharing, nothing switches by itself: the shell asks (a toast whose click confirms).
local function ask(target)
  hl.dispatch(hl.dsp.event("account-switcher-ask switch " .. target))
end
D.ask = ask

function D.set_sharing(on)
  on = on == true
  if on == sharing then return end
  sharing = on
  if sharing and peeking then D.peek_end() end
  D.emit()
end

function D.is_sharing() return sharing end

function D.switch(target, opts)
  if peeking then return end
  target = target or logic.other(last)
  if sharing and target ~= last and not (opts and opts.confirmed) then
    ask(target)
    return
  end
  local mons = D.monitors()
  local memory = logic.remember(store.load_memory(), mons)
  local steps = logic.plan_switch(mons, memory, target)
  last, busy = target, true
  local ok, err = pcall(look.animated, function() apply_steps(steps) end)
  busy = false
  look.apply(target)
  store.save_memory(logic.remember(memory, D.monitors()))
  for _, w in ipairs(hl.get_windows()) do
    if has_tag(w, "dwm-alert") and window_mode(w) == target then set_tag(w, "dwm-alert", false) end
  end
  store.save_mode(target)
  D.retag_all()
  D.emit()
  if not ok then error(err, 0) end
end

function D.is_busy() return busy end

-- dwm-id-<mode> gives a window its accounts' border colour wherever it is; dwm-from-<mode>
-- remembers its mode while it sits on a special workspace; dwm-hidden (windows in the
-- mode you're not in) stops them taking focus on activation.
function D.tag_window(w)
  if not (w and w.address) then return end
  local id = identity_of(w)
  set_tag(w, "dwm-id-work", id == "work")
  set_tag(w, "dwm-id-personal", id == "personal")
  local ws = w.workspace
  local here = ws and logic.mode_of(ws.id)
  if here then
    set_tag(w, "dwm-from-work", here == "work")
    set_tag(w, "dwm-from-personal", here == "personal")
  end
  set_tag(w, "dwm-hidden", window_mode(w) == logic.other(last))
end

function D.retag_all()
  for _, w in ipairs(hl.get_windows()) do D.tag_window(w) end
end

-- A home-mode app's or browser's window that opens in the other mode (a Slack call while
-- in Personal) goes to its own mode, next to its other windows, and waits there with an
-- alert. An agent from the bar's agents panel goes to Work and the desk follows it.
function D.place_new(w)
  if not (w and w.address) then return end
  local follows = logic.follows_desk(w.class)
  if not (follows or logic.is_home_app(w.class) or logic.is_browser(w.class)) then return end
  local ws = w.workspace
  local here = ws and logic.mode_of(ws.id)
  local own = identity_of(w)
  if not here or not own or own == here then return end
  local target
  for _, other in ipairs(hl.get_windows({ class = w.class })) do
    local ows = other.workspace
    if other.address ~= w.address and ows and logic.mode_of(ows.id) == own then
      target = ows.id
      break
    end
  end
  target = target or logic.send_target(ws.id)
  hl.dispatch(dsp_move({ workspace = tostring(target), follow = false, window = w }))
  if follows then
    -- Not inside Hyprland's window-open handling: a moment later.
    local address = w.address
    hl.timer(function()
      D.switch(own)
      hl.dispatch(dsp_focus({ window = "address:" .. address }))
    end, { timeout = logic.LAND_MS, type = "oneshot" })
  elseif own ~= last then
    set_tag(w, "dwm-alert", true)
    D.emit()
  end
end

function D.add_alert(w)
  if not (w and w.address) or has_tag(w, "dwm-alert") or window_mode(w) ~= logic.other(last) then return end
  set_tag(w, "dwm-alert", true)
  D.emit()
end

-- A closing window may still be listed while its close event runs.
function D.drop_alert(w)
  if w and w.address and has_tag(w, "dwm-alert") then D.emit(w.address) end
end

-- Toast clicks (clicking a notification is your own action). A terminal's or
-- agent's toast is Ghostty's, and a click on it asks Ghostty to bring its window forward,
-- which the hidden mode blocks (an alert). The notification copy says first that a toast of
-- CLASS was clicked; the blocked request that follows within CLICK_MS is that click.
function D.toast_clicked(class)
  if type(class) ~= "string" or class == "" then return end
  click_gen = click_gen + 1
  local gen = click_gen
  clicks[class] = gen
  hl.timer(function()
    if clicks[class] == gen then clicks[class] = nil end
  end, { timeout = CLICK_MS, type = "oneshot" })
end

-- From window.urgent: true when the request is a toast click. A moment later, outside
-- Hyprland's event, the desk goes to the window's mode (asking first during a share) and
-- focuses that very window.
function D.take_click(w)
  if not (w and w.address and w.class and clicks[w.class]) then return false end
  clicks[w.class] = nil
  local address = w.address
  hl.timer(function()
    local target
    for _, x in ipairs(hl.get_windows()) do
      if x.address == address then target = x end
    end
    if not target then return end
    local mode = window_mode(target)
    if mode and mode ~= last then D.switch(mode) end
    if not mode or mode == last then hl.dispatch(dsp_focus({ window = "address:" .. address })) end
  end, { timeout = logic.LAND_MS, type = "oneshot" })
  return true
end

-- A toast with no live sender (shown again from history, or restored after a shell restart):
-- its class's most recently used window, by the rules of any click across modes (route.lua).
function D.focus_class(class)
  if type(class) ~= "string" or class == "" then return end
  local best, best_rank
  for _, w in ipairs(hl.get_windows()) do
    if w.class == class then
      local rank = tonumber(w.focus_history_id) or -1
      if rank < 0 then rank = math.huge end
      if not best or rank < best_rank then best, best_rank = w, rank end
    end
  end
  if best then hl.dispatch(hl.dsp.focus({ window = "address:" .. best.address })) end
end

-- Clock in is about to start an app: its next window (within EXPECT_MS) is placed.
function D.expect(class)
  if type(class) ~= "string" or class == "" then return end
  local key = class:lower()
  expect_gen = expect_gen + 1
  local gen = expect_gen
  expecting[key] = gen
  hl.timer(function()
    if expecting[key] == gen then expecting[key] = nil end
  end, { timeout = EXPECT_MS, type = "oneshot" })
end

-- An expected window goes to the Work workspace its class last closed on, else to the Work
-- workspace of the focused slot; never a window that belongs to Personal. Returns true when
-- it took the window. If the desk stayed in Personal (a share asked first), it waits there
-- as an alert.
function D.place_expected(w)
  if not (w and w.address and w.class) then return false end
  local key = w.class:lower()
  if not expecting[key] or identity_of(w) == "personal" then return false end
  expecting[key] = nil
  local target = places[key]
  if not target then
    local active = hl.get_active_workspace()
    local id = active and active.id
    target = logic.id_for("work", logic.mode_of(id) and logic.slot_of(id) or 1)
  end
  local ws = w.workspace
  if not (ws and ws.id == target) then
    hl.dispatch(dsp_move({ workspace = tostring(target), follow = false, window = w }))
  end
  if last ~= "work" then
    set_tag(w, "dwm-alert", true)
    D.emit()
  end
  return true
end

-- A clock-in app's window closing on a Work workspace: that's where its class goes next time.
function D.remember_place(w)
  if not (w and w.class) then return end
  local key = w.class:lower()
  local ws = w.workspace
  local id = ws and ws.id
  if not logic.PLACE_CLASSES[key] or logic.mode_of(id) ~= "work" or identity_of(w) == "personal" then return end
  if places[key] == id then return end
  places[key] = id
  store.save_places(places)
end

-- Put every monitor that isn't showing the desk's mode back into it, keep focus where it
-- is, and tell the shell. Runs once monitors settle, after reloads and at start-up.
function D.fix_all()
  if peeking then return end
  local memory = store.load_memory()
  local steps = logic.plan_fix(D.monitors(), memory, last)
  if #steps > 0 then
    local focused = hl.get_active_monitor()
    busy = true
    local ok, err = pcall(function()
      apply_steps(steps)
      if focused and focused.name and focused.name ~= steps[#steps].name then
        hl.dispatch(dsp_focus({ monitor = focused.name }))
      end
    end)
    busy = false
    if not ok then error(err, 0) end
    store.save_memory(logic.remember(memory, D.monitors()))
  end
  D.emit()
end

-- Hyprland is rearranging monitors and filling the gaps with whatever workspace it finds:
-- wait until it has been quiet for logic.SETTLE_MS, then fix_all. Never act inside its events.
function D.settle()
  settling = true
  if settle_timer then settle_timer:set_enabled(false) end
  settle_timer = hl.timer(function()
    settle_timer = nil
    if peeking then return D.settle() end
    settling = false
    D.fix_all()
  end, { timeout = logic.SETTLE_MS, type = "oneshot" })
end

-- The user landed on the other mode on the focused monitor (a bar click, a dispatch): the
-- rest of the desk follows, unless the landing was Hyprland's own gap-filling.
function D.land()
  if settling or land_timer then return end
  land_timer = hl.timer(function()
    land_timer = nil
    if settling or peeking then return end
    local ws = hl.get_active_workspace()
    local mode = ws and logic.mode_of(ws.id)
    if mode and mode ~= last then
      if sharing then
        D.settle()
        ask(mode)
      else
        D.switch(mode)
      end
    end
  end, { timeout = logic.LAND_MS, type = "oneshot" })
end

-- At start-up the monitors come up on workspace 1; once they settle, fix_all puts them in
-- the saved mode and replaces last session's status.
function D.restore()
  D.settle()
end

-- Once: windows whose accounts are Personal (the config's Personal apps and browser) move from
-- Work to the same number in Personal; everything else stays in Work.
function D.first_run()
  if store.first_run_done() then return end
  for _, w in ipairs(hl.get_windows()) do
    local ws = w.workspace
    if ws and logic.mode_of(ws.id) == "work" and identity_of(w) == "personal" then
      hl.dispatch(dsp_move({ workspace = tostring(logic.send_target(ws.id)), follow = false, window = w }))
    end
  end
  store.mark_first_run()
end

function D.is_peeking() return peeking end

-- Peek: show the other mode on every monitor while SUPER+` is held. No memory, colours,
-- alerts or saved mode change; release puts back exactly the workspaces that were showing.
local hold_timer, poll_timer
local peek_from

local function show(steps)
  busy = true
  local ok, err = pcall(look.animated, function() apply_steps(steps) end)
  busy = false
  if not ok then error(err, 0) end
end

function D.peek_start()
  if peeking then return end
  peek_from = D.monitors()
  peeking = true
  show(logic.plan_switch(peek_from, store.load_memory(), logic.other(last)))
  D.emit()
end

function D.peek_end()
  if poll_timer then
    poll_timer:set_enabled(false)
    poll_timer = nil
  end
  if not peeking then return end
  local steps, focused = {}, nil
  for _, m in ipairs(peek_from) do
    if m.active > 0 then
      local step = { name = m.name, workspace = m.active }
      if m.focused then focused = step else steps[#steps + 1] = step end
    end
  end
  steps[#steps + 1] = focused
  show(steps)
  peeking = false
  D.emit()
end

-- Tap or hold, told apart by whether keycode 49 is still down after logic.HOLD_MS.
-- If SUPER is let go first, the release bind never fires: the hold timer then finds the
-- key up and treats it as a tap, and while peeking the poll timer ends the peek.
function D.grave_down()
  if sharing then return ask(logic.other(last)) end
  if peeking or hold_timer then return end
  hold_timer = hl.timer(function()
    hold_timer = nil
    if hl.is_key_down(49) then
      D.peek_start()
      poll_timer = hl.timer(function()
        if not hl.is_key_down(49) then D.peek_end() end
      end, { timeout = logic.POLL_MS, type = "repeat" })
    else
      D.switch()
    end
  end, { timeout = logic.HOLD_MS, type = "oneshot" })
end

function D.grave_up()
  if peeking then return D.peek_end() end
  if hold_timer then
    hold_timer:set_enabled(false)
    hold_timer = nil
    D.switch()
  end
end

function D.send_across()
  local w = hl.get_active_window()
  local ws = w and w.workspace
  local target = ws and logic.send_target(ws.id)
  if target then hl.dispatch(dsp_move({ workspace = tostring(target), follow = false })) end
end

function D.status_line()
  return logic.status_line(last, peeking, alert_count(), sharing)
end

-- Tell the shell: the status file for its first read, a custom event for every change.
function D.emit(except)
  local line = logic.status_line(last, peeking, alert_count(except), sharing)
  store.save_status(line)
  hl.dispatch(hl.dsp.event("account-switcher " .. line))
end

return D
