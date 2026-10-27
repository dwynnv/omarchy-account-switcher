-- State files for the mode switcher under ~/.local/state/account-switcher/.
-- They are read with io.open and never require()d, so writing them doesn't reload Hyprland.
local logic = require("hypr.account-switcher.logic")
local S = {}

local override

-- Tests point the store at a scratch folder.
function S.use_dir(path) override = path end

function S.dir()
  if override then return override end
  local base = os.getenv("XDG_STATE_HOME")
  if not base or base == "" then base = os.getenv("HOME") .. "/.local/state" end
  return base .. "/account-switcher"
end

function S.read(name)
  local f = io.open(S.dir() .. "/" .. name, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

-- Write to <name>.tmp, then rename over <name>. The folder is created on first use.
function S.write(name, text)
  local dir = S.dir()
  local tmp = dir .. "/" .. name .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then
    os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'")
    f = io.open(tmp, "w")
    if not f then return false end
  end
  f:write(text)
  f:close()
  return os.rename(tmp, dir .. "/" .. name) == true
end

function S.load_memory() return logic.parse_memory(S.read("memory")) end
function S.save_memory(memory) return S.write("memory", logic.format_memory(memory)) end

function S.load_mode()
  local mode = (S.read("mode") or ""):match("^%s*(%a+)%s*$")
  if mode == "work" or mode == "personal" then return mode end
  return nil
end
function S.save_mode(mode) return S.write("mode", mode .. "\n") end

function S.first_run_done() return S.read("first-run-done") ~= nil end
function S.mark_first_run() return S.write("first-run-done", os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n") end

function S.save_status(line) return S.write("status", line .. "\n") end

function S.load_places() return logic.parse_places(S.read("places")) end

-- The app rules `account-switcher setup` derives from config.json (logic.parse_apps).
function S.load_apps() return logic.parse_apps(S.read("apps")) end
function S.save_places(places) return S.write("places", logic.format_places(places)) end

return S
