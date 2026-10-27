-- The per-mode look inside the compositor: border colours, the window rules for
-- identity colours and hidden-mode windows, and the vertical slide used only for mode switches.
local M = {}

local logic
local work = {}
local personal
local anim

function M.setup(l, store)
  logic = l
  personal = logic.personal_active(store and logic.parse_look(store.read("look")))
  -- The theme is already applied when this module loads, so these are the theme's.
  work.active = hl.get_config("general.col.active_border")
  work.inactive = hl.get_config("general.col.inactive_border")
  local f = io.open(os.getenv("HOME") .. "/.config/hypr/looknfeel.lua", "r")
  if f then
    anim = logic.parse_workspace_animation(f:read("a"))
    f:close()
  end
end

local function colours(mode)
  if mode == "personal" then return personal, work.inactive end
  return work.active, work.inactive
end

function M.apply(mode)
  local active, inactive = colours(mode)
  if not (active and inactive) then return end
  hl.config({
    general = { col = { active_border = active, inactive_border = inactive } },
    group = { col = { border_active = active, border_inactive = inactive } },
  })
end

local function personal_rule()
  hl.window_rule({ name = "account-switcher-id-personal", match = { tag = "dwm-id-personal" },
    border_color = logic.rule_colour(personal, work.inactive) })
end

function M.rules()
  if work.active and work.inactive then
    hl.window_rule({ name = "account-switcher-id-work", match = { tag = "dwm-id-work" },
      border_color = logic.rule_colour(work.active, work.inactive) })
    personal_rule()
  end
  -- The other mode's windows: no focus on activation, and blacked out of any screen share.
  hl.window_rule({ name = "account-switcher-hidden", match = { tag = "dwm-hidden" }, focus_on_activate = false,
    no_screen_share = true })
  -- Omarchy slows touchpad scrolling in Ghostty by its class; the per-mode terminals too.
  hl.window_rule({ name = "account-switcher-terminal-scroll", match = { class = "org\\.omarchy\\.(term|agent)-(work|personal)" },
    scroll_touchpad = 0.2 })
end

-- A new Personal colour ("#RRGGBB", or "" for the default): Personal's windows and, in
-- Personal, the borders. Returns false for anything that isn't a colour.
function M.set_personal(colour, mode)
  local cleared = colour == nil or colour == ""
  if not (cleared or (type(colour) == "string" and colour:match("^#%x%x%x%x%x%x$"))) then return false end
  personal = logic.personal_active(not cleared and colour or nil)
  if work.active and work.inactive then personal_rule() end
  if mode == "personal" then M.apply(mode) end
  return true
end

-- Run fn with the workspaces animation switched to the mode-switch style, then put the
-- user's style back. Hyprland reads the style when each switch starts.
function M.animated(fn)
  if not (anim and anim.enabled and anim.curve_key and anim.curve) then return fn() end
  local function style(s)
    hl.animation({ leaf = "workspaces", enabled = true, speed = anim.speed or 1, [anim.curve_key] = anim.curve, style = s })
  end
  style(logic.MODE_SWITCH_STYLE)
  local ok, err = pcall(fn)
  style(anim.style or "slide")
  if not ok then error(err, 0) end
end

return M
