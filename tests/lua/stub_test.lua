-- Loads the module the way the SUPER+K keybindings menu does (/usr/bin/omarchy-menu-keybindings
-- runs hyprland.lua under a stub hl where every unknown field is a self-returning proxy).
-- The plugin's own modules (hypr/...) and test helpers, wherever the tests run from.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
package.path = here .. "/../../?.lua;" .. here .. "/?.lua;" .. package.path
local t = require("t")
local proxy
proxy = setmetatable({}, { __index = function() return proxy end, __call = function() return proxy end })
local binds = {}
hl = setmetatable({
  -- Like the menu's stub: a table dispatcher is kept so the menu can replay the bind.
  bind = function(keys, d, opts)
    local replay = type(d) == "table" and d.__omarchy_dispatcher and d or {}
    binds[#binds + 1] = { keys = keys, desc = opts and opts.description, kind = replay.kind, arg = replay.arg }
  end,
  get_config = function() return nil end,
  dsp = setmetatable({
    exec_cmd = function(c) return { __omarchy_dispatcher = true, kind = "exec", arg = c } end,
  }, { __index = function() return proxy end }),
}, { __index = function() return proxy end })
debug.sethook(function() error("load did not finish") end, "", 5000000)
local ok, err = pcall(require, "hypr.account-switcher")
debug.sethook()

t.test("loads under the keybindings-menu stub", function() t.ok(ok, tostring(err)) end)
t.test("workspace keys keep Omarchy's descriptions", function()
  local seen = {}
  for _, b in ipairs(binds) do seen[b.keys .. "|" .. tostring(b.desc)] = true end
  t.ok(seen["SUPER + code:10|Switch to workspace 1"], "switch 1")
  t.ok(seen["SUPER + SHIFT + code:19|Move window to workspace 10"], "move 10")
  t.ok(seen["SUPER + SHIFT + ALT + code:19|Move window silently to workspace 10"], "silent 10")
  t.ok(seen["SUPER + TAB|Next workspace"], "next"); t.ok(seen["SUPER + CTRL + TAB|Former workspace"], "former")
  t.ok(seen["SUPER + mouse_down|Scroll active workspace forward"], "wheel")
  t.ok(seen["SUPER + S|Toggle scratchpad"], "scratchpad"); t.ok(seen["CTRL + ALT + DELETE|Close all windows"], "close all")
end)
t.test("mode keys are registered", function()
  local seen = {}
  for _, b in ipairs(binds) do seen[b.keys .. "|" .. tostring(b.desc)] = true end
  t.ok(seen["SUPER + code:49|Switch mode (hold to peek)"], "switch/peek")
  t.ok(seen["SUPER + SHIFT + code:49|Send window to other mode"], "send")
end)
t.test("rebound keys can be replayed from the SUPER+K menu", function()
  local by = {}
  for _, b in ipairs(binds) do if b.desc then by[b.keys] = b end end
  t.eq(by["SUPER + code:12"].kind, "lua")
  t.eq(by["SUPER + code:12"].arg, "function() account_switcher.desk.focus_slot(3) end")
  t.eq(by["SUPER + SHIFT + ALT + code:19"].arg, "function() account_switcher.desk.move_to_slot(10, false) end")
  t.eq(by["SUPER + SHIFT + TAB"].arg, "function() account_switcher.desk.cycle(-1) end")
  t.eq(by["SUPER + code:49"].arg, "function() account_switcher.desk.switch() end")
  for keys, b in pairs(by) do t.ok((b.kind == "lua" or b.kind == "exec") and b.arg, keys .. " has no replay") end
end)
t.test("Omarchy's app keys run account-switcher, once each, with Omarchy's descriptions", function()
  local count, by = {}, {}
  for _, b in ipairs(binds) do
    if b.desc then count[b.keys] = (count[b.keys] or 0) + 1; by[b.keys] = b end
  end
  local want = {
    ["SUPER + RETURN"] = { "Terminal", "account%-switcher terminal$" },
    ["SUPER + SHIFT + F"] = { "File manager", "account%-switcher files$" },
    ["SUPER + ALT + SHIFT + F"] = { "File manager (cwd)", "account%-switcher files %-%-cwd$" },
    ["SUPER + SHIFT + CTRL + A"] = { "Agent", "account%-switcher agent$" },
    ["SUPER + ALT + RETURN"] = { "Tmux", "account%-switcher tmux$" },
    ["SUPER + CTRL + RETURN"] = { "Herdr", "account%-switcher herdr$" },
    ["SUPER + SHIFT + RETURN"] = { "Browser", "account%-switcher browser$" },
    ["SUPER + SHIFT + B"] = { "Browser", "account%-switcher browser$" },
    ["SUPER + SHIFT + ALT + B"] = { "Browser (private)", "account%-switcher browser %-%-private$" },
    ["SUPER + SHIFT + A"] = { "ChatGPT", "account%-switcher webapp %-%-name=ChatGPT https://chatgpt%.com$" },
    ["SUPER + SHIFT + ALT + A"] = { "Grok", "account%-switcher webapp %-%-name=Grok https://grok%.com$" },
    ["SUPER + SHIFT + C"] = { "Calendar", "account%-switcher webapp %-%-name=HEY https://app%.hey%.com/calendar/weeks/$" },
    ["SUPER + SHIFT + E"] = { "Email", "account%-switcher webapp %-%-name=HEY https://app%.hey%.com$" },
    ["SUPER + SHIFT + ALT + E"] = { "New email", "account%-switcher webapp %-%-name=HEY 'https://app%.hey%.com/messages/new%?display=standalone&new_window=true'$" },
    ["SUPER + SHIFT + Y"] = { "YouTube", "account%-switcher webapp %-%-name=YouTube https://youtube%.com/$" },
    ["SUPER + SHIFT + ALT + G"] = { "WhatsApp", "account%-switcher webapp %-%-name=WhatsApp %-%-focus=WhatsApp https://web%.whatsapp%.com/$" },
    ["SUPER + SHIFT + CTRL + G"] = { "Google Messages", "account%-switcher webapp '%-%-name=Google Messages' '%-%-focus=Google Messages' https://messages%.google%.com/web/conversations$" },
    ["SUPER + SHIFT + P"] = { "Google Photos", "account%-switcher webapp '%-%-name=Google Photos' '%-%-focus=Google Photos' https://photos%.google%.com/$" },
    ["SUPER + SHIFT + S"] = { "Google Maps", "account%-switcher webapp '%-%-name=Google Maps' '%-%-focus=Google Maps' https://maps%.google%.com/$" },
    ["SUPER + SHIFT + X"] = { "X", "account%-switcher webapp %-%-name=X https://x%.com/$" },
    ["SUPER + SHIFT + ALT + X"] = { "X Post", "account%-switcher webapp %-%-name=X https://x%.com/compose/post$" },
    ["PRINT"] = { "Screenshot", "account%-switcher capture screenshot$" },
    ["ALT + PRINT"] = { "Screenrecording", "account%-switcher capture toggle$" },
  }
  for keys, w in pairs(want) do
    t.ok(by[keys], keys .. " missing")
    t.eq(count[keys], 1); t.eq(by[keys].desc, w[1]); t.eq(by[keys].kind, "exec")
    t.ok(by[keys].arg:match("^/.*" .. w[2]), keys .. " runs " .. tostring(by[keys].arg))
  end
end)
t.done()
