-- Work/Personal mode switcher (account-switcher), required from ~/.config/hypr/hyprland.lua.
-- Hyprland rebuilds its whole Lua state on every reload, so this file runs again on each
-- load; everything that must last lives in ~/.local/state/account-switcher/.
local logic = require("hypr.account-switcher.logic")
local store = require("hypr.account-switcher.store")
local desk = require("hypr.account-switcher.desk")
local keys = require("hypr.account-switcher.keys")

-- The SUPER+K keybindings menu re-runs the config under a stub hl whose queries never
-- end: there, only register the binds.
local live = type(hl) == "table" and type(hl.on) == "function"

desk.setup(logic, store, live)
keys.register(desk, live)
if not live then return end

-- Which apps and browsers belong to which mode, from the config (re-read on every load).
logic.configure(store.load_apps())

-- The SUPER+K menu replays the rebound keys through account_switcher.desk.
_G.account_switcher = { mode = desk.current, desk = desk }

local look = require("hypr.account-switcher.look")
look.setup(logic, store)
desk.use_look(look)
look.rules()
look.apply(desk.current())
account_switcher.switch = desk.switch
account_switcher.status = desk.status_line
-- The bar service sends the Personal colour setting here when it changes.
account_switcher.set_personal_colour = function(colour) return look.set_personal(colour, desk.current()) end

-- New windows open in the mode they were launched from, even after a switch.
hl.config({ misc = { initial_workspace_tracking = 1 } })
require("hypr.account-switcher.watch").register(desk, logic)
-- Cross-mode clicks (the dock, launch-or-focus, notification clicks) follow the mode rules.
require("hypr.account-switcher.route").install(desk, logic)
account_switcher.restore = desk.restore
