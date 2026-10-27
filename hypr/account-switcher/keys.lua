-- Omarchy's workspace keys, rebound so they stay inside the current mode's range.
-- Descriptions match Omarchy's, so the SUPER+K menu still lists each key once.
local K = {}

-- Omarchy's exact display strings (/usr/share/omarchy/default/hypr/bindings/tiling.lua);
-- hl.unbind silently ignores a string that doesn't match.
K.STOCK = {}
for n = 10, 19 do
  K.STOCK[#K.STOCK + 1] = "SUPER + code:" .. n
  K.STOCK[#K.STOCK + 1] = "SUPER + SHIFT + code:" .. n
  K.STOCK[#K.STOCK + 1] = "SUPER + SHIFT + ALT + code:" .. n
end
for _, keys in ipairs({
  "SUPER + TAB", "SUPER + SHIFT + TAB", "SUPER + CTRL + TAB", "SUPER + mouse_down", "SUPER + mouse_up",
  "SUPER + S", "SUPER + ALT + S", "CTRL + ALT + DELETE",
}) do
  K.STOCK[#K.STOCK + 1] = keys
end

-- Each key: its description and the desk function it calls, with the arguments.
K.ENTRIES = {}
local function entry(keys, description, method, ...)
  K.ENTRIES[#K.ENTRIES + 1] = { keys = keys, description = description, method = method, args = { ... } }
end
for n = 1, 10 do
  local key = "code:" .. (n + 9)
  entry("SUPER + " .. key, "Switch to workspace " .. n, "focus_slot", n)
  entry("SUPER + SHIFT + " .. key, "Move window to workspace " .. n, "move_to_slot", n, true)
  entry("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. n, "move_to_slot", n, false)
end
entry("SUPER + TAB", "Next workspace", "cycle", 1)
entry("SUPER + SHIFT + TAB", "Previous workspace", "cycle", -1)
entry("SUPER + CTRL + TAB", "Former workspace", "former")
entry("SUPER + mouse_down", "Scroll active workspace forward", "cycle", 1)
entry("SUPER + mouse_up", "Scroll active workspace backward", "cycle", -1)
entry("SUPER + S", "Toggle scratchpad", "scratchpad_toggle")
entry("SUPER + ALT + S", "Move window to scratchpad", "scratchpad_move")
entry("CTRL + ALT + DELETE", "Close all windows", "close_all")
-- SUPER+` (keycode 49): tap switches, hold peeks.
entry("SUPER + code:49", "Switch mode (hold to peek)", "grave_down")
entry("SUPER + SHIFT + code:49", "Send window to other mode", "send_across")

-- Omarchy's app keys whose apps carry a mode (bindings/applications.lua, utilities.lua):
-- the exact display strings, Omarchy's descriptions, and the account-switcher command each runs.
K.APPS = {
  { "SUPER + RETURN", "Terminal", "terminal" },
  { "SUPER + SHIFT + F", "File manager", "files" },
  { "SUPER + ALT + SHIFT + F", "File manager (cwd)", "files --cwd" },
  { "SUPER + SHIFT + CTRL + A", "Agent", "agent" },
  { "SUPER + SHIFT + RETURN", "Browser", "browser" },
  { "SUPER + SHIFT + B", "Browser", "browser" },
  { "SUPER + SHIFT + ALT + B", "Browser (private)", "browser --private" },
  { "PRINT", "Screenshot", "capture screenshot" },
  { "ALT + PRINT", "Screenrecording", "capture toggle" },
}
-- Omarchy binds these only while its preinstalled bindings are on. Each web app names itself:
-- the config's web-app lists decide its mode, else it follows the desk; the URLs are Omarchy's.
K.PREINSTALLED = {
  { "SUPER + ALT + RETURN", "Tmux", "tmux" },
  { "SUPER + CTRL + RETURN", "Herdr", "herdr" },
  { "SUPER + SHIFT + A", "ChatGPT", "webapp --name=ChatGPT https://chatgpt.com" },
  { "SUPER + SHIFT + ALT + A", "Grok", "webapp --name=Grok https://grok.com" },
  { "SUPER + SHIFT + C", "Calendar", "webapp --name=HEY https://app.hey.com/calendar/weeks/" },
  { "SUPER + SHIFT + E", "Email", "webapp --name=HEY https://app.hey.com" },
  { "SUPER + SHIFT + ALT + E", "New email", "webapp --name=HEY 'https://app.hey.com/messages/new?display=standalone&new_window=true'" },
  { "SUPER + SHIFT + Y", "YouTube", "webapp --name=YouTube https://youtube.com/" },
  { "SUPER + SHIFT + ALT + G", "WhatsApp", "webapp --name=WhatsApp --focus=WhatsApp https://web.whatsapp.com/" },
  { "SUPER + SHIFT + CTRL + G", "Google Messages", "webapp '--name=Google Messages' '--focus=Google Messages' https://messages.google.com/web/conversations" },
  { "SUPER + SHIFT + P", "Google Photos", "webapp '--name=Google Photos' '--focus=Google Photos' https://photos.google.com/" },
  { "SUPER + SHIFT + S", "Google Maps", "webapp '--name=Google Maps' '--focus=Google Maps' https://maps.google.com/" },
  { "SUPER + SHIFT + X", "X", "webapp --name=X https://x.com/" },
  { "SUPER + SHIFT + ALT + X", "X Post", "webapp --name=X https://x.com/compose/post" },
}

local function preinstalled_on()
  if _G.omarchy_preinstalled_bindings ~= nil then return _G.omarchy_preinstalled_bindings end
  local f = io.open((os.getenv("HOME") or "") .. "/.local/state/omarchy/preinstalls-removed", "r")
  if f then
    f:close()
    return false
  end
  return true
end

-- exec dispatchers, so the SUPER+K menu replays them as commands.
local function rebind_apps(list)
  local dm = (os.getenv("HOME") or "") .. "/.local/bin/account-switcher"
  for _, app in ipairs(list) do
    hl.unbind(app[1])
    hl.bind(app[1], hl.dsp.exec_cmd(dm .. " " .. app[3]), { description = app[2] })
  end
end

-- What the SUPER+K menu runs when the entry is picked (it hands this to hyprctl dispatch).
-- Picking the mode key there can't be a hold, so it switches.
function K.replay(e)
  local args = {}
  for i, a in ipairs(e.args) do args[i] = tostring(a) end
  local method = e.method == "grave_down" and "switch" or e.method
  return "function() account_switcher.desk." .. method .. "(" .. table.concat(args, ", ") .. ") end"
end

function K.register(desk, live)
  for _, keys in ipairs(K.STOCK) do hl.unbind(keys) end
  for _, e in ipairs(K.ENTRIES) do
    local action
    if live then
      action = function() desk[e.method](table.unpack(e.args)) end
    else
      -- The keybindings menu's stub keeps dispatchers in this form and replays them.
      action = { __omarchy_dispatcher = true, kind = "lua", arg = K.replay(e) }
    end
    hl.bind(e.keys, action, { description = e.description })
  end
  -- The release half of SUPER+`. No description, so the menu lists the key once.
  hl.bind("SUPER + code:49", function() desk.grave_up() end, { release = true })

  if _G.omarchy_default_bindings ~= false then
    rebind_apps(K.APPS)
    if preinstalled_on() then rebind_apps(K.PREINSTALLED) end
  end
end

return K
