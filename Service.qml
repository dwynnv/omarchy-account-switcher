import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "Model.js" as Model
import "notifications/HoldLogic.js" as HoldLogic

// One instance for all monitors. The mode lives in Hyprland (~/.config/hypr/account-switcher.lua):
// this reads its status file once at start, then follows its "account-switcher" custom events.
Item {
  id: root

  property var shell: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/account-switcher"
  // Omarchy's current wallpaper (Work's); it is re-pointed on every theme or background change.
  readonly property string backgroundDir: home + "/.local/state/omarchy/current"
  property string mode: "work"
  property bool peeking: false
  property int alerts: 0
  // What the desk knows (its status line): while true, every switch asks first.
  property bool sharing: false
  // Notifications waiting in the account-switcher.notifications clone (its held.json).
  property int held: 0

  function applyStatus(s) {
    if (!s) return
    root.mode = s.mode
    root.peeking = s.peek
    root.alerts = s.alerts
    root.sharing = s.share
  }

  // A portal screen share is live while xdph's PipeWire stream exists. Hyprland's own
  // screenshare state also flips for screenshots and the picker's previews, so it isn't used.
  readonly property bool shareDetected: Model.sharingFrom(Pipewire.nodes ? Pipewire.nodes.values : [])

  // Hyprland rebuilds the desk on every config reload, so this is sent again after each one.
  function sendSharing() {
    Hyprland.dispatch("function() if account_switcher and account_switcher.desk then account_switcher.desk.set_sharing("
      + (root.shareDetected ? "true" : "false") + ") end end")
  }

  onShareDetectedChanged: {
    root.sendSharing()
    if (!root.shareDetected) root.closeAskToast()
  }
  Timer { interval: 2000; running: true; onTriggered: root.sendSharing() }

  // The desk refused a switch while sharing: one toast (replaced, not stacked, on later asks)
  // whose click switches anyway. It goes away when the share ends.
  property string askToastId: ""
  property string pendingAsk: ""

  function askSwitch(target) {
    if (askSender.running) {
      root.pendingAsk = target
      return
    }
    askSender.command = Model.askCommand(target, root.home + "/.local/bin/account-switcher", root.askToastId)
    askSender.running = true
  }

  // By title, so a toast restored after a shell restart (its id unknown here) goes too.
  function closeAskToast() {
    Quickshell.execDetached(Model.askDismissCommand())
    root.askToastId = ""
  }

  Process {
    id: askSender
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var id = text.trim()
        if (/^[0-9]+$/.test(id)) root.askToastId = id
      }
    }
    onRunningChanged: {
      if (running || root.pendingAsk === "") return
      var next = root.pendingAsk
      root.pendingAsk = ""
      root.askSwitch(next)
    }
  }

  function switchMode() {
    Hyprland.dispatch("function() if account_switcher then account_switcher.switch() end end")
  }

  // The personalColor setting ("" = the default amber): written to the look file Hyprland's
  // side reads at every load, and sent to it live; also once after start, so a setting changed
  // while the shell was down reaches it.
  readonly property var barSettings: Model.entrySettings(root.shell ? root.shell.barConfig : null, "account-switcher")
  readonly property string personalColor: Model.validColor(root.barSettings.personalColor)
  onPersonalColorChanged: root.sendLook()
  Timer { interval: 3000; running: true; onTriggered: root.sendLook() }

  function sendLook() {
    lookFile.setText(Model.lookText(root.personalColor))
    Hyprland.dispatch("function() if account_switcher and account_switcher.set_personal_colour then account_switcher.set_personal_colour('"
      + root.personalColor + "') end end")
  }

  FileView {
    id: lookFile
    path: root.stateDir + "/look"
    atomicWrites: true
    printErrors: false
  }

  // The panel's buttons. The clock file is read again once the command has written it.
  function clock(kind) {
    Quickshell.execDetached([root.home + "/.local/bin/account-switcher", "clock", kind])
    clockReread.restart()
  }
  Timer { id: clockReread; interval: 2000; onTriggered: clockFile.reload() }

  function showHeldNow() {
    Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "releaseHeld"])
  }

  // Sent through one process, one call at a time (see Model.wallpaperRequest).
  property var wallpaperQueue: ({})

  function setInstant(path) {
    if (!path) return
    var next = Model.wallpaperRequest(root.wallpaperQueue, path)
    if (next) root.sendWallpaper(next)
  }

  function sendWallpaper(path) {
    wallpaperSender.command = ["omarchy-shell", "-q", "background", "setInstant", path]
    wallpaperSender.running = true
  }

  Process {
    id: wallpaperSender
    onRunningChanged: {
      if (running) return
      var next = Model.wallpaperFinished(root.wallpaperQueue)
      if (next) root.sendWallpaper(next)
    }
  }

  // Personal shows its own image; Work goes back to whatever Omarchy's symlink points at.
  // A peek changes neither.
  function applyWallpaper() {
    if (root.peeking) return
    if (root.mode === "personal") {
      var bar = root.shell ? root.shell.barConfig : null
      root.setInstant(Model.wallpaperFor(Model.entrySettings(bar, "account-switcher"), root.home))
    } else if (!workBackground.running) {
      workBackground.running = true
    }
  }

  onModeChanged: applyWallpaper()

  Process {
    id: workBackground
    command: ["readlink", "-f", root.backgroundDir + "/background"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.mode === "work") root.setInstant(text.trim())
    }
  }

  // Omarchy's background service shows the symlink again on its own start, so in Personal
  // send the image twice while the shell settles.
  Timer { interval: 1500; running: true; onTriggered: if (root.mode === "personal") root.applyWallpaper() }
  Timer { interval: 4000; running: true; onTriggered: if (root.mode === "personal") root.applyWallpaper() }

  // A theme or background change re-points the symlink and shows the new Work image; in
  // Personal, put the Personal image back.
  Process {
    id: backgroundWatch
    running: true
    command: ["inotifywait", "-m", "-q", "-e", "create,moved_to", "--format", "%f", root.backgroundDir]
    stdout: SplitParser {
      onRead: function(line) { if (line === "background" && root.mode === "personal") reassert.restart() }
    }
    onRunningChanged: if (!running) watchRetry.start()
  }
  Timer { id: reassert; interval: 300; onTriggered: root.applyWallpaper() }
  Timer { id: watchRetry; interval: 5000; onTriggered: backgroundWatch.running = true }

  // Omarchy's refresh and package updates can put their own launcher entries back over the
  // switcher's, or change the system entries they are made from; account-switcher desktop-check
  // --fix re-applies them (and notifies) when needed.
  readonly property string appsDir: (Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")) + "/applications"
  readonly property string omarchyAppsDir: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/applications"

  Process {
    id: entriesWatch
    running: true
    command: ["inotifywait", "-m", "-q", "-e", "close_write,moved_to,delete", "--format", "%f",
              root.appsDir, "/usr/share/applications", root.omarchyAppsDir]
    stdout: SplitParser {
      onRead: function(line) { if (line.endsWith(".desktop")) entriesCheck.restart() }
    }
    onRunningChanged: if (!running) entriesWatchRetry.start()
  }
  Timer { id: entriesWatchRetry; interval: 5000; onTriggered: entriesWatch.running = true }
  // Also once, shortly after the shell starts.
  Timer {
    id: entriesCheck
    interval: 2000
    running: true
    onTriggered: Quickshell.execDetached([root.home + "/.local/bin/account-switcher", "desktop-check", "--fix"])
  }

  // Time in each mode: every 30 s the desk's mode (a peek doesn't change it) gets the time since
  // the last tick while the session is unlocked and in use: input in the last 5 minutes, since
  // Stay Awake can keep the screen from locking. A gap over 90 s (a suspend) counts nothing.
  property var timeStore: ({ days: {} })
  property int timeRevision: 0
  property bool timeLoaded: false
  property real lastTickMs: 0
  property bool locked: false

  IdleMonitor {
    id: useMonitor
    timeout: 300
    respectInhibitors: false
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: if (!lockCheck.running) lockCheck.running = true
  }

  Process {
    id: lockCheck
    // A stuck hyprctl (Hyprland mid-reload) counts as unknown rather than holding up later ticks.
    command: ["timeout", "5", "hyprctl", "locked", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.countTime(Model.parseLocked(text))
    }
  }

  function countTime(locked) {
    var now = Date.now()
    var seconds = Model.tickSeconds(root.lastTickMs, now, 90000)
    root.lastTickMs = now
    root.locked = locked === true
    if (!root.timeLoaded || locked !== false || useMonitor.isIdle || seconds <= 0) return
    Model.prune(Model.addTime(root.timeStore, Model.dayKey(now), root.mode, seconds), 60)
    root.timeRevision++
    timeFile.setText(JSON.stringify(root.timeStore) + "\n")
  }

  FileView {
    id: timeFile
    path: root.stateDir + "/time.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.timeStore = Model.parseTime(text())
      root.timeLoaded = true
      root.timeRevision++
    }
    // A missing file starts a new record; any other failure leaves the file alone.
    onLoadFailed: function(error) { if (error === FileViewError.FileNotFound) root.timeLoaded = true }
  }

  // Clock reminders: once a minute, against the bar settings clockInAt / clockOutAt ("HH:MM";
  // none until set) and clockDays (default mon-fri). Each fires at most once a day; the day is
  // kept in reminders.json so a shell restart doesn't repeat it.
  property string clockText: ""
  property var remindersFired: ({})
  property bool remindersLoaded: false

  // account-switcher clock writes the clock file; it is read again before every check.
  Timer { interval: 60000; running: true; repeat: true; onTriggered: clockFile.reload() }

  FileView {
    id: clockFile
    path: root.stateDir + "/clock"
    printErrors: false
    onLoaded: {
      root.clockText = text()
      root.checkReminder()
    }
    onLoadFailed: {
      root.clockText = ""
      root.checkReminder()
    }
  }

  function checkReminder() {
    if (!root.remindersLoaded) return
    var settings = Model.entrySettings(root.shell ? root.shell.barConfig : null, "account-switcher")
    var now = Date.now()
    var due = Model.dueReminder(settings, now, root.remindersFired, root.clockText)
    if (due === "") return
    root.remindersFired[due] = Model.dayKey(now)
    remindersFile.setText(JSON.stringify(root.remindersFired) + "\n")
    Quickshell.execDetached(Model.reminderCommand(due, root.home + "/.local/bin/account-switcher"))
  }

  FileView {
    id: remindersFile
    path: root.stateDir + "/reminders.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.remindersFired = Model.parseFired(text())
      root.remindersLoaded = true
    }
    onLoadFailed: function(error) { if (error === FileViewError.FileNotFound) root.remindersLoaded = true }
  }

  FileView {
    id: heldFile
    path: root.stateDir + "/held.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.held = HoldLogic.heldCount(text())
    onLoadFailed: root.held = 0
  }

  // Keeps the account-switcher.notifications clone in step with Omarchy's notification plugin: checked
  // once the shell has settled (handing back to Omarchy's own if the clone doesn't answer),
  // and again whenever the packaged plugin changes.
  readonly property string notifySrcDir: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/shell/plugins/notifications"

  Timer {
    interval: 10000
    running: true
    onTriggered: Quickshell.execDetached([root.home + "/.local/bin/account-switcher", "notifications-check", "--ping"])
  }

  Process {
    id: notifySrcWatch
    running: true
    command: ["inotifywait", "-m", "-q", "-r", "-e", "close_write,moved_to,create,delete", "--format", "%f", root.notifySrcDir]
    stdout: SplitParser {
      onRead: function(line) { notifyCheck.restart() }
    }
    onRunningChanged: if (!running) notifySrcRetry.start()
  }
  Timer { id: notifySrcRetry; interval: 30000; onTriggered: notifySrcWatch.running = true }

  // Turning Omarchy's own notifications back on (by hand, or by the check's fallback) changes
  // shell.json; the check then hands what the copy was holding over to Omarchy's own.
  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || (root.home + "/.config")) + "/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: notifyCheck.restart()
  }
  Timer {
    id: notifyCheck
    interval: 5000
    onTriggered: Quickshell.execDetached([root.home + "/.local/bin/account-switcher", "notifications-check"])
  }

  FileView {
    path: root.stateDir + "/status"
    printErrors: false
    onLoaded: root.applyStatus(Model.parseStatus(text()))
    onLoadFailed: function() {
      var ws = Hyprland.focusedWorkspace
      root.mode = (ws && Model.modeOf(ws.id)) || "work"
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") {
        root.sendSharing()
        if (root.mode === "personal") root.applyWallpaper()
      }
      if (event.name !== "custom") return
      var data = String(event.data)
      var ask = Model.parseAsk(data)
      if (ask) root.askSwitch(ask)
      else root.applyStatus(Model.parseEvent(data))
    }
  }

  IpcHandler {
    target: "account-switcher"
    function status(): string {
      return JSON.stringify({ mode: root.mode, peek: root.peeking, alerts: root.alerts, share: root.sharing,
        shareDetected: root.shareDetected, held: root.held })
    }
    function time(): string {
      var t = Model.totals(root.timeStore, Date.now())
      return JSON.stringify({ today: t.today, week: t.week, idle: useMonitor.isIdle, locked: root.locked,
        loaded: root.timeLoaded })
    }
    function switchMode(): void { root.switchMode() }
    function reapply(): void { root.applyWallpaper() }
  }

  // The setup window (AppsWindow.qml): browsers, apps and web apps per mode, and the Personal
  // wallpaper. Which modes still have no browser is asked again after every save.
  property var missingBrowsers: []
  function openApps() { appsWindow.open() }
  function browseWallpaper() { appsWindow.browseWallpaper() }
  function refreshMissing() { missingCheck.running = true }

  AppsWindow {
    id: appsWindow
    service: root
    onSaved: root.refreshMissing()
  }

  Process {
    id: missingCheck
    running: true
    command: [root.home + "/.local/bin/account-switcher", "apps-missing"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.missingBrowsers = text.split("\n").filter(function (m) { return m === "work" || m === "personal" })
    }
  }

  IpcHandler {
    target: "account-switcher.apps"
    function open(): void { appsWindow.open() }
    function close(): void { appsWindow.close() }
  }
}
