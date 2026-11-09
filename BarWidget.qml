import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The mode badge, then this monitor's workspaces of the current mode labelled 1-0. Replaces
// omarchy.workspaces and keeps its sizes; one instance per monitor, each showing its own block.
BarWidget {
  id: root
  moduleName: "account-switcher"

  // Looked up again rather than bound once: a reload of the plugin (any file saved in its
  // folder) keeps this widget but destroys the service and makes a new one, and serviceFor()
  // doesn't tell a binding about it, so the badge and every panel button went dead until
  // the shell restarted.
  property var service: null
  function findService() {
    var s = bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor("account-switcher") : null
    if (s !== root.service) root.service = s || null
  }
  Component.onCompleted: findService()
  Timer { interval: 1000; repeat: true; running: true; onTriggered: root.findService() }
  readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0
  readonly property string mode: service ? service.mode : (Model.modeOf(focusedId) || "work")
  readonly property bool peeking: service ? service.peeking : false
  readonly property int alerts: service ? service.alerts : 0
  readonly property bool sharing: service ? service.sharing : false
  readonly property int held: service ? service.held : 0
  // The mode on screen: the other one while peeking.
  readonly property string shownMode: peeking ? Model.otherMode(mode) : mode
  // This monitor's own workspace (the stock widget marks the globally focused one).
  readonly property var screenMonitor: root.QsWindow.window && root.QsWindow.window.screen
    ? Hyprland.monitorFor(root.QsWindow.window.screen) : null
  readonly property int activeId: screenMonitor && screenMonitor.activeWorkspace ? screenMonitor.activeWorkspace.id : focusedId
  readonly property string monitorName: screenMonitor ? screenMonitor.name : ""

  // Connector -> block, from the file Omarchy keeps them in (default/hypr/monitor-workspaces.lua).
  property var blocks: ({})
  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.blocks = Model.parseBlocks(text())
    onLoadFailed: root.blocks = ({})
  }
  // Until Omarchy has written the file (or on an Omarchy without it), the block of the
  // workspace this monitor shows.
  readonly property int block: root.blocks[root.monitorName] !== undefined
    ? root.blocks[root.monitorName] : (Model.modeOf(root.activeId) ? Model.blockOf(root.activeId) : 0)
  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function existingIds() {
    var ids = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) ids.push(values[i].id)
    return ids
  }

  // The workspaces on this monitor, other monitors' included (an unplug leaves them here).
  function idsOnMonitor() {
    var ids = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].monitor && values[i].monitor.name === root.monitorName) ids.push(values[i].id)
    }
    return ids
  }

  function focusWorkspace(id) {
    Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
  }

  // The badge's panel (right-click).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.anchorItem = badge
    target.hostWidget = root
    target.service = root.service
    target.bar = root.bar
  }
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (root.opened) root.close(); else root.open() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  onServiceChanged: root.injectPanel()
  onBarChanged: {
    root.findService()
    root.injectPanel()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    readonly property var ids: Model.buttonIds(root.shownMode, root.existingIds(), root.block, root.idsOnMonitor())

    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : ids.length + 1
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    WidgetButton {
      id: badge
      bar: root.bar
      text: Model.badgeText(root.mode, root.peeking, root.alerts, root.sharing, root.held)
      foreground: Model.badgeColor(root.shownMode, Commons.Color.accent, root.service ? root.service.personalColor : "")
      verticalPadding: 6
      fixedHeight: root.barSize
      // Left: switch; right: the panel.
      onPressed: function(mouseButton) {
        if (mouseButton === Qt.RightButton) root.toggle()
        else if (root.service) root.service.switchMode()
      }
    }

    Repeater {
      model: grid.ids

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool isActive: root.activeId === modelData

        bar: root.bar
        text: isActive ? String.fromCodePoint(0xF14FB) : Model.labelFor(modelData)
        opacity: occupied || isActive ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
