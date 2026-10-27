-- Tiny test harness for plain lua 5.5 (no busted on this machine).
local T = {}
local failed = 0

local function show(v)
  if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. show(v[k]) end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function T.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("ok   " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end

function T.eq(actual, expected)
  if not same(actual, expected) then
    error("expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

function T.ok(cond, msg)
  if not cond then error(msg or "expected a true value", 2) end
end

function T.done()
  if failed > 0 then
    print("\n" .. failed .. " failed")
    os.exit(1)
  end
  print("\nall passed")
  os.exit(0)
end

return T
