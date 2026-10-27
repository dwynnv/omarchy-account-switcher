-- The plugin's own modules (hypr/...) and test helpers, wherever the tests run from.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
package.path = here .. "/../../?.lua;" .. here .. "/?.lua;" .. package.path
local t = require("t")
local S = require("hypr.account-switcher.store")
local dir = (os.getenv("TEST_TMPDIR") or "/tmp") .. "/store-" .. os.time() .. "/account-switcher"
S.use_dir(dir)

t.test("missing files read as defaults", function()
  t.eq(S.load_mode(), nil); t.eq(S.load_memory(), { work = {}, personal = {} }); t.eq(S.first_run_done(), false)
end)
t.test("writes create the folder and read back", function()
  S.save_mode("personal"); t.eq(S.load_mode(), "personal")
  S.save_memory({ work = { A = 2 }, personal = { A = 12 } }); t.eq(S.load_memory().personal.A, 12)
  S.mark_first_run(); t.eq(S.first_run_done(), true)
  S.save_status("mode=work peek=0 alerts=0"); t.eq(S.read("status"), "mode=work peek=0 alerts=0\n")
end)
t.test("a bad mode file reads as nil", function()
  S.write("mode", "banana\n"); t.eq(S.load_mode(), nil)
end)
t.done()
