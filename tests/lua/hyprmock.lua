-- A small model of Hyprland 0.56.2 (commit efb5099) workspace placement, enough to run the
-- real account-switcher modules outside the compositor. Adapted from the final review's
-- simulation. Rules cite the source: W = src/state/WorkspacePlacementController.cpp,
-- M = src/output/Monitor.cpp, A = src/config/shared/actions/ConfigActions.cpp,
-- E = src/config/lua/LuaEventHandler.cpp, F = src/state/FocusState.cpp.
local H = {}

function H.reset()
  H.monitors, H.all, H.workspaces, H.windows = {}, {}, {}, {}
  H.focus, H.remembered, H.timers, H.handlers = nil, {}, {}, {}
  H.now, H.events, H.border, H.next_special, H.next_addr = 0, {}, nil, -98, 1
  H.rules = {}
end
H.reset()

local function contains(list, x)
  for _, v in ipairs(list) do if v == x then return true end end
  return false
end
local function remove(list, x)
  for i, v in ipairs(list) do if v == x then table.remove(list, i) return end end
end

function H.ws(id)
  for _, w in ipairs(H.workspaces) do if w.id == id then return w end end
end
function H.ws_named(name)
  for _, w in ipairs(H.workspaces) do if w.name == name then return w end end
end
function H.mon(name)
  for _, m in ipairs(H.all) do if m.name == name then return m end end
end
function H.create_ws(id, mon)
  local w = { id = id, name = tostring(id), monitor = mon, lastMonitor = "" }
  H.workspaces[#H.workspaces + 1] = w
  return w
end
local function special(name)
  local w = H.ws_named("special:" .. name)
  if not w then
    w = { id = H.next_special, name = "special:" .. name, special = true, lastMonitor = "" }
    H.next_special = H.next_special - 1
    H.workspaces[#H.workspaces + 1] = w
  end
  return w
end

-- Lua-side proxies, read lazily like CLuaMonitor/CLuaWorkspace/CLuaWindow __index.
local monproxy, wsproxy, winproxy
function monproxy(m)
  return setmetatable({}, { __index = function(_, k)
    if k == "name" then return m.name end
    if k == "description" then return m.desc end
    if k == "focused" then return m == H.focus end
    if k == "active_workspace" then return m.active and wsproxy(m.active) or nil end
  end })
end
function wsproxy(w)
  return setmetatable({}, { __index = function(_, k)
    if k == "id" then return w.id end
    if k == "name" then return w.name end
    if k == "special" then return w.special == true end
    if k == "monitor" then return w.monitor and monproxy(w.monitor) or nil end
  end })
end
function winproxy(c)
  return setmetatable({}, { __index = function(_, k)
    if k == "address" then return c.address end
    if k == "class" then return c.class end
    if k == "pid" then return nil end
    -- 0 is the focused window, 1 the one before it; -1 was never focused.
    if k == "focus_history_id" then return c.history or -1 end
    if k == "workspace" then return c.ws and wsproxy(c.ws) or nil end
    if k == "tags" then
      local copy = {}
      for i, t in ipairs(c.tags) do copy[i] = t end
      return copy
    end
  end })
end
H.wsproxy, H.winproxy = wsproxy, winproxy

-- E:24-80: handlers run synchronously; one that is already running is skipped.
function H.emit(name, ...)
  for _, h in ipairs(H.handlers[name] or {}) do
    if not h.active then
      h.active = true
      local ok, err = pcall(h.fn, ...)
      h.active = false
      if not ok then error("hl.on(" .. name .. "): " .. tostring(err), 0) end
    end
  end
end

function H.rawMonitorFocus(m) H.focus = m end

-- M:1439-1531 changeWorkspace: workspace.active is emitted only when not internal.
function H.changeWorkspace(mon, w, internal)
  if not w or w == mon.active then return end
  mon.active = w
  if not internal then H.emit("workspace.active", wsproxy(w)) end
end

-- W:239-380 moveWorkspaceToMonitor: the old monitor's gap is filled (and announced) first.
function H.moveWorkspaceToMonitor(w, mon)
  if not w or not mon or w.monitor == mon then return end
  local old = w.monitor
  local was_active = old ~= nil and old.active == w
  if was_active then
    local nextId
    for _, o in ipairs(H.workspaces) do
      if not o.special and o.monitor == old and o.id ~= w.id then nextId = o.id break end
    end
    if not nextId then
      nextId = 1
      while H.ws(nextId) do nextId = nextId + 1 end
      H.create_ws(nextId, old)
    end
    H.changeWorkspace(old, H.ws(nextId), false) -- W:290 internal = false
  end
  w.monitor = mon
  if was_active and old == H.focus then -- W:328: focus follows, no workspace.active
    H.rawMonitorFocus(mon)
    mon.active = w
  end
  H.emit("workspace.move_to_monitor", wsproxy(w), monproxy(mon)) -- W:379
end

-- W:151-237 swapActiveWorkspaces
function H.swapActiveWorkspaces(a, b)
  local wa, wb = a.active, b.active
  wa.monitor, wb.monitor = b, a
  a.active, b.active = wb, wa
  if H.focus == a or H.focus == b then H.emit("workspace.active", wsproxy(H.focus == a and wb or wa)) end
  H.emit("workspace.move_to_monitor", wsproxy(wa), monproxy(b))
  H.emit("workspace.move_to_monitor", wsproxy(wb), monproxy(a))
end

-- A:934-990 changeWorkspace
function H.actionChangeWorkspace(w)
  local owner = w.monitor
  if not owner then return end
  H.rawMonitorFocus(owner)
  H.changeWorkspace(owner, w, false)
end

-- A:1086-1108 changeWorkspaceOnCurrentMonitor
function H.changeWorkspaceOnCurrentMonitor(w)
  local cur = H.focus
  if w.monitor ~= cur then
    if w.monitor and w.monitor.active == w then return H.swapActiveWorkspaces(w.monitor, cur) end
    H.moveWorkspaceToMonitor(w, cur)
  end
  return H.actionChangeWorkspace(w)
end

-- Missing ids are created on the focused monitor (LuaBindingsInternal.cpp resolveWorkspaceStr).
local function resolve(id)
  return H.ws(id) or (H.focus and H.create_ws(id, H.focus))
end

-- M:392-520 onDisconnect: focus moves to the backup monitor before workspaces move.
function H.disconnect(name, disable_only)
  local mon = H.mon(name)
  if mon.active then H.remembered[mon.name] = mon.active.id end
  local backup
  for _, m in ipairs(H.monitors) do if m ~= mon then backup = m break end end
  local move = {}
  for _, w in ipairs(H.workspaces) do
    if not w.special and (w.monitor == mon or not w.monitor) then move[#move + 1] = w end
  end
  for _, w in ipairs(move) do if w.lastMonitor == "" then w.lastMonitor = mon.name end end
  if backup then
    H.rawMonitorFocus(backup)
    for _, w in ipairs(move) do H.moveWorkspaceToMonitor(w, backup) end
  else
    H.focus = nil
  end
  mon.active = nil
  remove(H.monitors, mon)
  H.emit("monitor.removed", monproxy(mon))
  if disable_only then return end
  remove(H.all, mon)
  for _, w in ipairs(H.workspaces) do if w.monitor == mon then w.monitor = nil end end
end

-- M:108-390 onConnect: a default workspace (lowest free id), then returning workspaces.
function H.connect(name, desc, x)
  local mon = H.mon(name)
  if not mon then
    mon = { name = name, desc = desc, x = x or 0 }
    H.all[#H.all + 1] = mon
  end
  local id = 1
  while H.ws(id) do id = id + 1 end
  mon.active = H.create_ws(id, mon)
  for _, w in ipairs({ table.unpack(H.workspaces) }) do
    if not w.special and w.lastMonitor == name and w ~= mon.active then
      H.moveWorkspaceToMonitor(w, mon)
      w.lastMonitor = ""
    end
  end
  local rid = H.remembered[name]
  if rid and H.ws(rid) then
    H.moveWorkspaceToMonitor(H.ws(rid), mon)
    H.changeWorkspace(mon, H.ws(rid), true)
  end
  if not contains(H.monitors, H.focus) then H.rawMonitorFocus(mon) end
  H.monitors[#H.monitors + 1] = mon
  H.emit("monitor.added", monproxy(mon))
end

-- Monitors and workspaces for a scenario, without any events.
function H.monitor(name, desc, x)
  local m = { name = name, desc = desc, x = x or 0 }
  H.all[#H.all + 1] = m
  H.monitors[#H.monitors + 1] = m
  return m
end
function H.show(mon, w) mon.active = w end

function H.window(class, ws)
  local c = { address = string.format("0x%x", H.next_addr), class = class, ws = ws, tags = {} }
  H.next_addr = H.next_addr + 1
  H.windows[#H.windows + 1] = c
  return c
end
function H.open_window(class, ws)
  local c = H.window(class, ws)
  H.emit("window.open", winproxy(c))
  return c
end
function H.has_tag(c, tag) return contains(c.tags, tag) end

-- Timers run in due order against a virtual clock.
function H.advance(ms)
  local stop = H.now + ms
  while true do
    local next
    for _, t in ipairs(H.timers) do
      if t.enabled and t.due <= stop and (not next or t.due < next.due) then next = t end
    end
    if not next then break end
    H.now = next.due
    if next.rep then next.due = H.now + next.timeout else next.enabled = false end
    next.fn()
  end
  H.now = stop
end

-- The view the tests check: every monitor's workspace, the focused one, and the border.
function H.screens()
  local parts = {}
  for _, m in ipairs(H.monitors) do
    parts[#parts + 1] = m.name .. "=" .. (m.active and m.active.id or 0) .. (m == H.focus and "*" or "")
  end
  return table.concat(parts, " ")
end

local function find_window(sel)
  if sel == nil then
    for _, c in ipairs(H.windows) do if c.focused then return c end end
    return nil
  end
  local addr = type(sel) == "table" and sel.address or tostring(sel):gsub("^address:", "")
  for _, c in ipairs(H.windows) do if c.address == addr then return c end end
end

local function target_ws(name)
  local sname = tostring(name):match("^special:(.+)$")
  if sname then return special(sname) end
  return resolve(tonumber(name))
end

hl = {
  on = function(name, fn)
    H.handlers[name] = H.handlers[name] or {}
    table.insert(H.handlers[name], { fn = fn })
  end,
  timer = function(fn, opts)
    assert(opts.timeout > 0, "hl.timer: opts.timeout must be > 0")
    local t = { fn = fn, timeout = opts.timeout, due = H.now + opts.timeout, rep = opts.type == "repeat", enabled = true }
    H.timers[#H.timers + 1] = t
    return { set_enabled = function(_, v) t.enabled = v end }
  end,
  get_monitors = function()
    local out = {}
    for i, m in ipairs(H.monitors) do out[i] = monproxy(m) end
    return out
  end,
  get_active_monitor = function() return H.focus and monproxy(H.focus) or nil end,
  get_active_workspace = function() return H.focus and H.focus.active and wsproxy(H.focus.active) or nil end,
  get_workspaces = function()
    local out = {}
    for _, w in ipairs(H.workspaces) do out[#out + 1] = wsproxy(w) end
    return out
  end,
  get_windows = function(filter)
    local out = {}
    for _, c in ipairs(H.windows) do
      if not (filter and filter.class) or c.class == filter.class then out[#out + 1] = winproxy(c) end
    end
    return out
  end,
  get_active_window = function()
    local c = find_window(nil)
    return c and winproxy(c) or nil
  end,
  get_last_workspace = function() return nil end,
  is_key_down = function() return H.keydown == true end,
  get_config = function(k)
    if k == "general.col.active_border" then return "0xee33ccff" end
    if k == "general.col.inactive_border" then return "0xaa595959" end
  end,
  config = function(t)
    local a = t.general and t.general.col and t.general.col.active_border
    if a ~= nil then
      H.border = type(a) == "table" and "personal" or "work"
      H.border_value = a
    end
  end,
  animation = function() end,
  window_rule = function(r) H.rules[#H.rules + 1] = r end,
  bind = function() end,
  unbind = function() end,
  dispatch = function(d) return d() end,
  dsp = {
    focus = function(t)
      if t.monitor then return function() local m = H.mon(t.monitor); if m then H.rawMonitorFocus(m) end end end
      -- Focusing a window shows its workspace on its monitor first (ConfigActions focus).
      if t.window then
        return function()
          local c = find_window(t.window)
          if not c then return end
          if c.ws and not c.ws.special then H.actionChangeWorkspace(c.ws) end
          for _, x in ipairs(H.windows) do x.focused = (x == c) end
        end
      end
      if t.workspace then
        local id = tonumber(t.workspace)
        if t.on_current_monitor then return function() H.changeWorkspaceOnCurrentMonitor(resolve(id)) end end
        return function() H.actionChangeWorkspace(resolve(id)) end
      end
      return function() end
    end,
    window = {
      move = function(t)
        return function()
          local c = find_window(t.window)
          if not c then return end
          c.ws = target_ws(t.workspace)
          H.emit("window.move_to_workspace", winproxy(c), wsproxy(c.ws))
        end
      end,
      tag = function(t)
        return function()
          local c = find_window(t.window)
          if not c then return end
          local sign, tag = t.tag:sub(1, 1), t.tag:sub(2)
          if sign == "+" then
            if not contains(c.tags, tag) then c.tags[#c.tags + 1] = tag end
          else
            remove(c.tags, tag)
          end
        end
      end,
      close = function(t)
        return function()
          local c = find_window(t.window)
          if c then
            remove(H.windows, c)
            H.emit("window.close", winproxy(c))
          end
        end
      end,
    },
    workspace = {
      toggle_special = function() return function() end end,
      -- moveCurrentWorkspaceToMonitor (A:1075 -> W:239)
      move = function(t)
        return function()
          local cur, target = H.focus, nil
          for _, m in ipairs(H.monitors) do
            if m ~= cur and ((t.monitor == "l" and m.x < cur.x) or (t.monitor == "r" and m.x > cur.x)) then target = m end
          end
          if target then H.moveWorkspaceToMonitor(cur.active, target) end
        end
      end,
    },
    event = function(s) return function() H.events[#H.events + 1] = s end end,
    exec_cmd = function(c) return function() H.events[#H.events + 1] = "exec " .. c end end,
  },
}

-- Hyprland builds a fresh `hl` on every config load: tests put the pristine dispatchers back.
H.pristine = { focus = hl.dsp.focus, move = hl.dsp.window.move }
function H.fresh_hl()
  hl.dsp.focus = H.pristine.focus
  hl.dsp.window.move = H.pristine.move
end

return H
