-- Clicks across modes, before Hyprland moves anything (the dock itself stays as it is). The
-- dock, Omarchy's launch-or-focus and notification clicks all build their focus and
-- move through hl.dsp.focus / hl.dsp.window.move, so this wraps those two factories. Every
-- config load builds a fresh `hl`, so this runs on every load; the switcher's own dispatches
-- use the saved originals. Anything unexpected, including an error here, passes through.
local R = {}

local desk, logic, orig

local function window_at(selector)
  local address = type(selector) == "string" and selector:match("^address:(0x%x+)$")
  if not address then return nil end
  for _, w in ipairs(hl.get_windows()) do
    if w.address == address then return w end
  end
  return nil
end

-- Focusing a window of the mode you're not in.
local function route_focus(args)
  local w = type(args) == "table" and window_at(args.window)
  if not w then return nil end
  local mode, current = desk.window_mode(w), desk.current()
  if not mode or mode == current then return nil end
  if desk.is_sharing() then
    return function() desk.ask(mode) end
  end
  if not desk.identity_of(w) then
    -- A shared app (no accounts) comes to you instead of taking you there.
    return function()
      local ws = hl.get_active_workspace()
      if ws and ws.id and ws.id > 0 then
        hl.dispatch(orig.move({ workspace = tostring(ws.id), window = args.window, follow = false }))
      end
      return hl.dispatch(orig.focus(args))
    end
  end
  local sibling = desk.window_in_mode(w.class, current, w.address)
  if sibling then return orig.focus({ window = "address:" .. sibling.address }) end
  return function()
    desk.switch(mode)
    return hl.dispatch(orig.focus(args))
  end
end

-- The dock restoring a window from the minimized pile onto the other mode's workspace (it
-- forgets where windows came from when the shell restarts): an app with accounts goes back
-- to its own mode's same number instead; the dock's following focus then takes you there.
local function route_move(args)
  local w = type(args) == "table" and window_at(args.window)
  if not (w and w.workspace and w.workspace.name == "special:minimized") then return nil end
  local target = tonumber(args.workspace)
  local target_mode = target and logic.mode_of(target)
  local own = desk.identity_of(w)
  if not target_mode or not own or own == target_mode then return nil end
  return orig.move({ workspace = tostring(logic.send_target(target)), window = args.window, follow = args.follow })
end

local function wrap(router, original)
  return function(args)
    local ok, result = pcall(router, args)
    if ok and result ~= nil then return result end
    return original(args)
  end
end

function R.install(d, l)
  desk, logic = d, l
  local dsp = hl.dsp
  if type(dsp) ~= "table" or type(dsp.focus) ~= "function" or type(dsp.window) ~= "table"
    or type(dsp.window.move) ~= "function" then
    return
  end
  orig = { focus = dsp.focus, move = dsp.window.move }
  desk.use_dispatchers(orig)
  dsp.focus = wrap(route_focus, orig.focus)
  dsp.window.move = wrap(route_move, orig.move)
end

return R
