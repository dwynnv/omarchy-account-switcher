-- Pure rules for the Work/Personal mode switcher (account-switcher).
-- No hl and no io here, so plain lua 5.5 can test every function.
local L = {}

L.OFFSET = { work = 0, personal = 10 }
L.PERSONAL_ACTIVE = { colors = { "rgba(ffb000ee)", "rgba(ff6a00ee)" }, angle = 45 }
L.MODE_SWITCH_STYLE = "slidevert"
L.HOLD_MS = 300
L.POLL_MS = 40
-- After a landing, how long until the rest of the desk follows; after monitors change,
-- how long Hyprland gets to finish before every monitor is put back in the desk's mode.
L.LAND_MS = 20
L.SETTLE_MS = 400
-- Each mode's scratchpad (a special workspace).
L.SCRATCHPAD = { work = "scratchpad", personal = "scratchpad-personal" }

function L.mode_of(id)
  if type(id) ~= "number" then return nil end
  if id >= 1 and id <= 10 then return "work" end
  if id >= 11 and id <= 20 then return "personal" end
  return nil
end

function L.other(mode)
  return mode == "work" and "personal" or "work"
end

function L.slot_of(id)
  return (id - 1) % 10 + 1
end

function L.id_for(mode, slot)
  return L.OFFSET[mode] + slot
end

function L.send_target(id)
  local mode = L.mode_of(id)
  if not mode then return nil end
  return L.id_for(L.other(mode), L.slot_of(id))
end

-- Next or previous existing workspace of the mode, wrapping around.
function L.next_in_mode(ids, current, mode, dir)
  local list = {}
  for _, id in ipairs(ids) do
    if L.mode_of(id) == mode then list[#list + 1] = id end
  end
  if #list == 0 then return nil end
  table.sort(list)
  for i, id in ipairs(list) do
    if id == current then return list[(i - 1 + dir) % #list + 1] end
  end
  return dir < 0 and list[#list] or list[1]
end

function L.status_line(mode, peek, alerts, share)
  return string.format("mode=%s peek=%d alerts=%d share=%d", mode, peek and 1 or 0, alerts, share and 1 or 0)
end

-- Memory file: one "mode<TAB>monitor description<TAB>workspace id" line per entry.
function L.parse_memory(text)
  local memory = { work = {}, personal = {} }
  for line in (text or ""):gmatch("[^\n]+") do
    local mode, desc, id = line:match("^(%a+)\t(.-)\t(%d+)$")
    id = tonumber(id)
    if memory[mode] and desc ~= "" and L.mode_of(id) == mode then memory[mode][desc] = id end
  end
  return memory
end

function L.format_memory(memory)
  local lines = {}
  for _, mode in ipairs({ "work", "personal" }) do
    for desc, id in pairs(memory[mode] or {}) do lines[#lines + 1] = mode .. "\t" .. desc .. "\t" .. id end
  end
  table.sort(lines)
  return #lines > 0 and table.concat(lines, "\n") .. "\n" or ""
end

-- The Personal colour (setting personalColor, which the bar service writes to the store's
-- "look" file): "#RRGGBB", or nil.
function L.parse_look(text)
  local hex = (text or ""):match("personal_color=#?(%x%x%x%x%x%x)")
  return hex and ("#" .. hex:upper()) or nil
end

-- Personal's active border: the colour into a darker shade of itself, or the default amber
-- gradient without a valid colour.
function L.personal_active(colour)
  local hex = type(colour) == "string" and colour:match("^#(%x%x%x%x%x%x)$")
  if not hex then return L.PERSONAL_ACTIVE end
  local dark = ""
  for i = 1, 5, 2 do dark = dark .. string.format("%02x", tonumber(hex:sub(i, i + 1), 16) * 3 // 4) end
  return { colors = { "rgba(" .. hex:lower() .. "ee)", "rgba(" .. dark .. "ee)" }, angle = 45 }
end

-- Where clock in puts the apps it starts: the Work workspace each class last closed on,
-- one "class<TAB>id" line per class (classes lowercased). Only L.PLACE_CLASSES are kept
-- (the app rules' "place" lines, set by L.configure).

function L.parse_places(text)
  local places = {}
  for line in (text or ""):gmatch("[^\n]+") do
    local class, id = line:match("^(.-)\t(%d+)$")
    id = tonumber(id)
    if class and class ~= "" and L.mode_of(id) == "work" then places[class] = id end
  end
  return places
end

function L.format_places(places)
  local lines = {}
  for class, id in pairs(places or {}) do lines[#lines + 1] = class .. "\t" .. id end
  table.sort(lines)
  return #lines > 0 and table.concat(lines, "\n") .. "\n" or ""
end

-- The workspace each monitor shows after switching to `target`, focused monitor last.
-- Claims run in passes over every monitor: a workspace already in the target mode,
-- then memory, then the same number, then the lowest free id. No id is used twice.
function L.plan_switch(monitors, memory, target)
  local claimed, pick = {}, {}
  local function claim(i, id)
    if pick[i] or not id or claimed[id] or L.mode_of(id) ~= target then return end
    claimed[id] = true
    pick[i] = id
  end
  for i, m in ipairs(monitors) do claim(i, m.active) end
  for i, m in ipairs(monitors) do claim(i, (memory[target] or {})[m.desc]) end
  for i, m in ipairs(monitors) do
    if L.mode_of(m.active) then claim(i, L.id_for(target, L.slot_of(m.active))) end
  end
  for i in ipairs(monitors) do
    for slot = 1, 10 do claim(i, L.id_for(target, slot)) end
  end
  local steps, focused = {}, nil
  for i, m in ipairs(monitors) do
    local step = { name = m.name, workspace = pick[i] }
    if m.focused then focused = step else steps[#steps + 1] = step end
  end
  steps[#steps + 1] = focused
  return steps
end

-- The steps that put every monitor not showing `mode` back into it, focused monitor last.
-- They are plan_switch's picks, so no workspace is used twice.
function L.plan_fix(monitors, memory, mode)
  local outside = {}
  for _, m in ipairs(monitors) do
    if L.mode_of(m.active) ~= mode then outside[m.name] = true end
  end
  local steps = {}
  for _, step in ipairs(L.plan_switch(monitors, memory, mode)) do
    if outside[step.name] then steps[#steps + 1] = step end
  end
  return steps
end

-- A special workspace's mode, by name: each scratchpad belongs to its mode.
function L.special_mode(name)
  for mode, pad in pairs(L.SCRATCHPAD) do
    if name == "special:" .. pad then return mode end
  end
  return nil
end

function L.remember(memory, monitors)
  for _, m in ipairs(monitors) do
    local mode = L.mode_of(m.active)
    if mode then memory[mode][m.desc] = m.active end
  end
  return memory
end

-- The app rules `account-switcher setup` writes from config.json (~/.local/state/account-switcher/apps),
-- one per line: "exe MODE DIR" and "class MODE CLASS" (whose accounts a window uses),
-- "prefix MODE PREFIX", "browser CLASS", "home CLASS" and "home-prefix PREFIX" (apps that live
-- in one mode), "place CLASS" (windows clock-in puts back). Anything else is skipped.
function L.parse_apps(text)
  local apps = { exes = {}, classes = {}, prefixes = {}, browsers = {}, home = {}, home_prefixes = {}, place = {} }
  for line in (text or ""):gmatch("[^\n]+") do
    local kind, a, b = line:match("^(%S+)%s+(%S+)%s*(%S*)%s*$")
    local mode = (a == "work" or a == "personal") and b ~= ""
    if kind == "exe" and mode then table.insert(apps.exes, { b, a })
    elseif kind == "class" and mode then apps.classes[b:lower()] = a
    elseif kind == "prefix" and mode then table.insert(apps.prefixes, { b:lower(), a })
    elseif kind == "browser" and b == "" then apps.browsers[a:lower()] = true
    elseif kind == "home" and b == "" then apps.home[a:lower()] = true
    elseif kind == "home-prefix" and b == "" then table.insert(apps.home_prefixes, a:lower())
    elseif kind == "place" and b == "" then apps.place[a:lower()] = true
    end
  end
  return apps
end

-- Per-mode terminals and agents (account-switcher terminal/agent) are the switcher's own; the agents
-- panel's are Work.
local OWN_CLASSES = {
  ["org.omarchy.term-work"] = "work", ["org.omarchy.agent-work"] = "work", ["org.omarchy.agent"] = "work",
  ["org.omarchy.term-personal"] = "personal", ["org.omarchy.agent-personal"] = "personal",
}
local IDENTITY_EXES, IDENTITY_CLASSES, IDENTITY_PREFIXES, HOME_APPS, HOME_PREFIXES, BROWSERS

-- Use these rules (from parse_apps; nil: none beyond the switcher's own classes).
function L.configure(apps)
  apps = apps or L.parse_apps(nil)
  IDENTITY_EXES, IDENTITY_PREFIXES = apps.exes, apps.prefixes
  IDENTITY_CLASSES = {}
  for class, mode in pairs(apps.classes) do IDENTITY_CLASSES[class] = mode end
  for class, mode in pairs(OWN_CLASSES) do IDENTITY_CLASSES[class] = mode end
  HOME_APPS, HOME_PREFIXES, BROWSERS = apps.home, apps.home_prefixes, apps.browsers
  L.PLACE_CLASSES = apps.place
end

-- Whose accounts a window uses: by its executable first, then by its class. The two VS
-- Codes share a class; the Personal one runs with --user-data-dir ~/.config/Code-Personal.
function L.identity(class, exe, cmdline)
  if exe then
    for _, rule in ipairs(IDENTITY_EXES) do
      if exe:sub(1, #rule[1]) == rule[1] then return rule[2] end
    end
  end
  local c = (class or ""):lower()
  if c == "com.microsoft.vscode" then
    return (cmdline or ""):find("/.config/Code-Personal", 1, true) and "personal" or "work"
  end
  if IDENTITY_CLASSES[c] then return IDENTITY_CLASSES[c] end
  for _, rule in ipairs(IDENTITY_PREFIXES) do
    if c:sub(1, #rule[1]) == rule[1] then return rule[2] end
  end
  return nil
end

-- hl.get_config gives colours as 0xAARRGGBB; window rules take rgba(rrggbbaa).
function L.rgba(colour)
  local a, rgb = colour:match("^0[xX](%x%x)(%x%x%x%x%x%x)$")
  if a then return ("rgba(" .. rgb .. a .. ")"):lower() end
  if colour:match("^rgba%(") then return colour:lower() end
  return colour
end

local function gradient(g)
  if type(g) == "string" then return { L.rgba(g) }, 0 end
  local colours = {}
  for i, c in ipairs(g.colors) do colours[i] = L.rgba(c) end
  return colours, g.angle or 0
end

-- A window rule's border_color: active colours and angle, then the inactive colours
-- (Hyprland reads every colour after the first "Ndeg" as the inactive gradient).
function L.rule_colour(active, inactive)
  local a, a_angle = gradient(active)
  local i, i_angle = gradient(inactive)
  local parts = {}
  for _, c in ipairs(a) do parts[#parts + 1] = c end
  parts[#parts + 1] = math.floor(a_angle + 0.5) .. "deg"
  for _, c in ipairs(i) do parts[#parts + 1] = c end
  if #i > 1 then parts[#parts + 1] = math.floor(i_angle + 0.5) .. "deg" end
  return table.concat(parts, " ")
end

-- What to do when a monitor starts showing a workspace the switcher didn't ask for:
-- the user's own action on the focused monitor completes the switch; any other monitor
-- (a newly plugged one, say) is put back into the desk's mode.
function L.decide_landing(a)
  if a.peeking or not a.ws_mode or a.ws_mode == a.current then return "ignore" end
  return a.on_focused_monitor and "complete" or "fix_monitor"
end

-- The executable from the contents of /proc/<pid>/cmdline (NUL-separated arguments).
function L.exe_of(cmdline)
  if not cmdline then return nil end
  return cmdline:match("^([^\0]+)")
end

-- Apps that live in one mode: their windows never open in the other mode.
function L.is_home_app(class)
  local c = (class or ""):lower()
  if HOME_APPS[c] == true then return true end
  for _, prefix in ipairs(HOME_PREFIXES) do
    if c:sub(1, #prefix) == prefix then return true end
  end
  return false
end

-- Browsers belong to one mode. A browser's own windows (session restore, its own popups)
-- can't be told apart from launcher ones, so new ones wait in their mode.
function L.is_browser(class)
  return BROWSERS[(class or ""):lower()] == true
end

-- Windows only the user opens (an agent from the bar's agents panel): when one opens in the
-- other mode, the desk goes with it.
function L.follows_desk(class)
  return class == "org.omarchy.agent"
end

-- The user's workspaces animation from looknfeel.lua (the last uncommented call wins),
-- so a mode switch can borrow its curve and put its style back afterwards.
function L.parse_workspace_animation(text)
  local found
  for line in (text or ""):gmatch("[^\n]+") do
    if not line:match("^%s*%-%-") and line:find("hl.animation(", 1, true) and line:match('leaf%s*=%s*"workspaces"') then
      if line:match("enabled%s*=%s*false") then
        found = { enabled = false }
      else
        local key, curve = line:match('(spring)%s*=%s*"([^"]+)"')
        if not key then key, curve = line:match('(bezier)%s*=%s*"([^"]+)"') end
        found = {
          enabled = true,
          speed = tonumber(line:match("speed%s*=%s*([%d%.]+)")),
          curve_key = key,
          curve = curve,
          style = line:match('style%s*=%s*"([^"]+)"'),
        }
      end
    end
  end
  return found
end

-- No app rules until the entry file configures them from the apps file.
L.configure(nil)

return L
