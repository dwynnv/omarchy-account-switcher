import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The mode badge's panel (right-click): the mode and share state, clock in and out, time in
// each mode, what's waiting, and the settings with the commands that change them.
Panel {
  id: root
  moduleName: "account-switcher"
  ipcTarget: "account-switcher.panel"

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root

  readonly property string mode: service ? service.mode : "work"
  readonly property bool peeking: service ? service.peeking : false
  readonly property bool sharing: service ? service.sharing : false
  readonly property int held: service ? service.held : 0
  readonly property int alerts: service ? service.alerts : 0
  readonly property string clockText: service ? service.clockText : ""
  readonly property bool clockedIn: Model.parseClock(root.clockText).kind === "in"
  property real nowMs: Date.now()
  Timer { interval: 30000; repeat: true; running: root.opened; triggeredOnStart: true; onTriggered: root.nowMs = Date.now() }
  // Reading timeRevision makes the totals follow every tick.
  readonly property var totals: root.service && root.service.timeRevision >= 0
    ? Model.totals(root.service.timeStore, root.nowMs) : Model.totals(null, root.nowMs)
  readonly property var settingRows: Model.settingsRows(
    Model.entrySettings(root.bar && root.bar.shell ? root.bar.shell.barConfig : null, "account-switcher"))

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color faint: Qt.darker(foreground, 1.7)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.controller.show()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function clock(kind) {
    if (root.service) root.service.clock(kind)
    root.close()
  }
  function copyText(text) {
    var t = String(text || "")
    if (t !== "") Quickshell.execDetached(["wl-copy", "--", t])
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: scrollArea.width
          spacing: Style.spacing.panelGap

          PanelHero {
            width: parent.width
            title: Model.modeTitle(root.mode)
            meta: Model.modeLine(root.mode, root.peeking, root.sharing)
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: Model.GLYPH[root.mode]
                color: Model.badgeColor(root.mode, Commons.Color.accent, root.service ? root.service.personalColor : "")
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
            }
            trailingControl: Component {
              Button {
                text: "Switch"
                tooltipText: "Switch to " + Model.modeTitle(Model.otherMode(root.mode))
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: if (root.service) root.service.switchMode()
              }
            }
          }

          // ------------------------------------------------- clock
          Item {
            width: parent.width
            implicitHeight: Math.max(clockLabel.implicitHeight, clockButtons.implicitHeight)
            Text {
              id: clockLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - clockButtons.width - Style.space(8)
              textFormat: Text.PlainText
              text: Model.clockLine(root.clockText, root.nowMs)
              elide: Text.ElideRight
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Row {
              id: clockButtons
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              Button {
                text: "Clock in"
                tooltipText: "Switch to Work and open your work apps"
                bordered: true
                selected: !root.clockedIn
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.clock("in")
              }
              Button {
                text: "Clock out"
                tooltipText: "Switch to Personal"
                bordered: true
                selected: root.clockedIn
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.clock("out")
              }
            }
          }

          // ------------------------------------------------- time
          Grid {
            columns: 2
            columnSpacing: Style.space(12)
            rowSpacing: Style.space(4)
            Text { text: "Today"; color: root.faint; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            Text {
              textFormat: Text.PlainText
              text: Model.timeLine(root.totals.today)
              color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body
            }
            Text { text: "This week"; color: root.faint; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            Text {
              textFormat: Text.PlainText
              text: Model.timeLine(root.totals.week)
              color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Counted while the screen is unlocked and you've used the keyboard or mouse in the last 5 minutes."
            wrapMode: Text.Wrap
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // ------------------------------------------------- waiting
          PanelSeparator { width: parent.width }

          Item {
            width: parent.width
            implicitHeight: Math.max(waitingLabel.implicitHeight, showNow.implicitHeight)
            Text {
              id: waitingLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - (showNow.visible ? showNow.width + Style.space(8) : 0)
              textFormat: Text.PlainText
              text: Model.waitingLine(root.held, root.alerts)
              elide: Text.ElideRight
              color: root.held + root.alerts > 0 ? root.foreground : root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Button {
              id: showNow
              visible: root.held > 0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "Show now"
              tooltipText: "Show the held notifications here, now"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.showHeldNow()
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "In Personal, Work apps' notifications wait for Work (calls too); while you share your screen, anything not urgent waits. Do not disturb still applies first."
            wrapMode: Text.Wrap
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // ------------------------------------------------- settings
          PanelSeparator { width: parent.width }

          PanelSectionHeader {
            text: "Settings"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.settingRows
            delegate: Column {
              required property var modelData
              width: contentColumn.width
              spacing: Style.space(2)

              Item {
                width: parent.width
                implicitHeight: Math.max(settingLabel.implicitHeight, settingValue.implicitHeight)
                Text {
                  id: settingLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  id: settingValue
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, parent.width - settingLabel.width - Style.space(12))
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                  text: modelData.value
                  elide: Text.ElideMiddle
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              Item {
                width: parent.width
                implicitHeight: Math.max(commandText.implicitHeight, commandCopy.implicitHeight)
                Text {
                  id: commandText
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - commandCopy.width - Style.space(8)
                  textFormat: Text.PlainText
                  text: modelData.command
                  elide: Text.ElideMiddle
                  color: Commons.Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                PanelActionButton {
                  id: commandCopy
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: String.fromCodePoint(0xF018F)
                  tooltipText: "Copy command"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.copyText(modelData.command)
                }
              }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Change settings with these commands (an empty value, '', clears one). Reminders need a time; a new Personal wallpaper shows at the next switch."
            wrapMode: Text.Wrap
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
