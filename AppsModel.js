// Pure logic for the setup window (AppsWindow.qml): which column each installed app is in,
// search, moves, the browsers, and what `account-switcher apps-set` gets. Plain JS (no .pragma
// library) so the QML engine reloads it on save and node can load it for tests.
//
// A state is {list, assigned}: list is what `account-switcher apps-list` printed, assigned its
// {work: {browser, apps, webapps}, personal: {…}, follow} as the window changes it.

function copy(x) { return JSON.parse(JSON.stringify(x)) }

function initState(list) {
  var a = (list && list.assigned) || {}
  function mode(m) {
    var x = a[m] || {}
    return { browser: x.browser || null, apps: (x.apps || []).slice(), webapps: (x.webapps || []).slice() }
  }
  return { list: list || { entries: [] }, assigned: { work: mode("work"), personal: mode("personal"), follow: (a.follow || []).slice() } }
}

// The column an entry is in: work, personal or either (browsers aren't in a column).
function columnOf(state, e) {
  var a = state.assigned
  var field = e.kind === "webapp" ? "webapps" : "apps"
  if (a.work[field].indexOf(e.key) !== -1) return "work"
  if (a.personal[field].indexOf(e.key) !== -1) return "personal"
  return "either"
}

function byName(x, y) {
  var a = String(x.name).toLowerCase(), b = String(y.name).toLowerCase()
  return a < b ? -1 : a > b ? 1 : 0
}

// {work, either, personal, browsers}: the entries matching QUERY (name or key, any case), by name.
function columns(state, query) {
  var q = String(query || "").toLowerCase()
  var out = { work: [], either: [], personal: [], browsers: [] }
  var entries = state.list.entries || []
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (q && String(e.name).toLowerCase().indexOf(q) === -1 && String(e.key).toLowerCase().indexOf(q) === -1) continue
    if (e.kind === "browser") out.browsers.push(e)
    else out[columnOf(state, e)].push(e)
  }
  out.work.sort(byName); out.either.sort(byName); out.personal.sort(byName); out.browsers.sort(byName)
  return out
}

function without(xs, x) { return xs.filter(function (y) { return y !== x }) }

// The entry KEY moved to COLUMN (work, either, personal). A web app in Either follows the mode.
function move(state, key, column) {
  var entries = state.list.entries || [], e = null
  for (var i = 0; i < entries.length; i++) if (entries[i].key === key && entries[i].kind !== "browser") e = entries[i]
  if (!e || !e.usable) return state
  var s = { list: state.list, assigned: copy(state.assigned) }
  var field = e.kind === "webapp" ? "webapps" : "apps"
  s.assigned.work[field] = without(s.assigned.work[field], key)
  s.assigned.personal[field] = without(s.assigned.personal[field], key)
  s.assigned.follow = without(s.assigned.follow, key)
  if (column === "work" || column === "personal") s.assigned[column][field].push(key)
  else if (e.kind === "webapp") s.assigned.follow.push(key)
  return s
}

function setBrowser(state, mode, key) {
  var s = { list: state.list, assigned: copy(state.assigned) }
  s.assigned[mode].browser = key || null
  return s
}

function missingBrowsers(state) {
  return ["work", "personal"].filter(function (m) { return !state.assigned[m].browser })
}

function problems(state) {
  var a = state.assigned, out = []
  if (a.work.browser && a.work.browser === a.personal.browser) out.push("Work and Personal need different browsers")
  return out
}

// What `account-switcher apps-set` gets, or null while there's a problem.
function payload(state) {
  return problems(state).length ? null : copy(state.assigned)
}
