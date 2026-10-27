import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "AppsModel.js" as AppsModel
import "Model.js" as Model

// The setup window: each mode's browser, the apps and web apps that live in Work or in
// Personal (Either: wherever you are; a web app there follows the mode), and Personal's
// wallpaper. The lists come from `account-switcher apps-list`; Save sends the choice to
// `account-switcher apps-set`, which checks it, writes config.json and re-runs setup.
Item {
  id: root

  property var service: null
  signal saved()
  readonly property string bin: (Quickshell.env("HOME") || "") + "/.local/bin/account-switcher"
  property var apps: AppsModel.initState(null)
  property string query: ""
  property string message: ""
  property bool loading: false
  readonly property var cols: AppsModel.columns(root.apps, root.query)
  readonly property var problems: AppsModel.problems(root.apps)
  readonly property var browserOptions: [{ label: "None yet", value: "" }].concat(
    AppsModel.columns(root.apps, "").browsers.filter(function (e) { return e.usable })
      .map(function (e) { return { label: e.name, value: e.key } }))
  readonly property string wallpaper: root.service ? String(root.service.barSettings.personalWallpaper || "") : ""

  readonly property color foreground: Commons.Color.foreground
  readonly property color faint: Commons.Color.muted
  readonly property color workColor: Commons.Color.accent
  readonly property color personalColor: root.service && root.service.personalColor !== "" ? root.service.personalColor : "#FFB000"

  function open() {
    window.visible = true
    root.reload()
  }
  function close() { window.visible = false }
  function reload() {
    root.loading = true
    lister.running = true
  }
  function browseWallpaper() {
    window.visible = true
    fileDialog.open()
  }
  function setWallpaper(path) {
    Quickshell.execDetached(["omarchy", "bar", "set", "account-switcher", "personalWallpaper", path])
  }
  function save() {
    var p = AppsModel.payload(root.apps)
    if (!p) return
    root.message = "Saving…"
    saver.command = [root.bin, "apps-set", JSON.stringify(p)]
    saver.running = true
  }
  function moveTo(key, column) { root.apps = AppsModel.move(root.apps, key, column) }

  Process {
    id: lister
    command: [root.bin, "apps-list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loading = false
        try {
          root.apps = AppsModel.initState(JSON.parse(text))
        } catch (e) {
          root.message = "Couldn't read the installed apps (account-switcher apps-list)."
        }
      }
    }
  }

  Process {
    id: saver
    stdout: StdioCollector { id: saveOut; waitForEnd: true }
    stderr: StdioCollector { id: saveErr; waitForEnd: true }
    onExited: function (exitCode, exitStatus) {
      if (exitCode === 0) {
        root.message = "Saved."
        root.saved()
        root.reload()
      } else {
        root.message = (saveErr.text || saveOut.text || "Not saved.").trim()
      }
    }
  }

  FileDialog {
    id: fileDialog
    title: "Personal wallpaper"
    nameFilters: ["Images (*.jpg *.jpeg *.png *.webp)"]
    onAccepted: root.setWallpaper(decodeURIComponent(String(selectedFile).replace(/^file:\/\//, "")))
  }

  FloatingWindow {
    id: window
    visible: false
    title: "Account Switcher – apps"
    color: Commons.Color.background
    implicitWidth: 900
    implicitHeight: 640
    minimumSize: Qt.size(760, 520)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(16)
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: Style.space(12)
        TextField {
          width: parent.width - workBrowser.width - personalBrowser.width - Style.space(24)
          placeholderText: "Search apps…"
          foreground: root.foreground
          onTextChanged: root.query = text
        }
        Dropdown {
          id: workBrowser
          width: 220
          label: "Work browser"
          options: root.browserOptions
          value: root.apps.assigned.work.browser || ""
          onChanged: function (v) { root.apps = AppsModel.setBrowser(root.apps, "work", v || null) }
        }
        Dropdown {
          id: personalBrowser
          width: 220
          label: "Personal browser"
          options: root.browserOptions
          value: root.apps.assigned.personal.browser || ""
          onChanged: function (v) { root.apps = AppsModel.setBrowser(root.apps, "personal", v || null) }
        }
      }

      Row {
        id: columnsRow
        width: parent.width
        height: parent.height - y - footer.height - wallpaperRow.height - Style.space(20)
        spacing: Style.space(10)

        Repeater {
          model: [
            { id: "work", title: "Work", color: root.workColor },
            { id: "either", title: "Either mode", color: root.faint },
            { id: "personal", title: "Personal", color: root.personalColor },
          ]
          delegate: Rectangle {
            required property var modelData
            width: (columnsRow.width - 2 * columnsRow.spacing) / 3
            height: columnsRow.height
            color: "transparent"
            radius: 6
            border.width: modelData.id === "either" ? 1 : 2
            border.color: modelData.color

            Text {
              id: heading
              x: Style.space(10); y: Style.space(8)
              text: modelData.title + "  (" + root.cols[modelData.id].length + ")"
              color: modelData.color
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            ListView {
              anchors.fill: parent
              anchors.topMargin: heading.height + Style.space(14)
              anchors.margins: Style.space(6)
              clip: true
              spacing: 2
              model: root.cols[parent.modelData.id]
              delegate: Item {
                id: row
                required property var modelData
                readonly property string column: AppsModel.columnOf(root.apps, modelData)
                width: ListView.view.width
                height: 30
                opacity: modelData.usable ? 1 : 0.45

                Image {
                  id: icon
                  anchors.verticalCenter: parent.verticalCenter
                  width: 20; height: 20
                  sourceSize: Qt.size(20, 20)
                  source: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                }
                Text {
                  anchors.left: icon.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: arrows.left
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: row.modelData.name + (row.modelData.kind === "webapp" ? "  · web app" : "")
                  color: root.foreground
                  font.pixelSize: Style.font.body
                }
                Row {
                  id: arrows
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  visible: row.modelData.usable
                  Button {
                    visible: row.column !== "work"
                    text: "←"
                    tooltipText: row.column === "personal" ? "Either mode" : "Work"
                    onClicked: root.moveTo(row.modelData.key, row.column === "personal" ? "either" : "work")
                  }
                  Button {
                    visible: row.column !== "personal"
                    text: "→"
                    tooltipText: row.column === "work" ? "Either mode" : "Personal"
                    onClicked: root.moveTo(row.modelData.key, row.column === "work" ? "either" : "personal")
                  }
                }
                ToolTip.visible: !row.modelData.usable && hover.hovered
                ToolTip.text: "Can't be put in a mode yet: " + row.modelData.reason
                HoverHandler { id: hover }
              }
            }
          }
        }
      }

      Row {
        id: wallpaperRow
        width: parent.width
        spacing: Style.space(10)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Personal wallpaper"
          color: root.faint
          font.pixelSize: Style.font.bodySmall
        }
        Image {
          width: 96; height: 54
          fillMode: Image.PreserveAspectCrop
          sourceSize: Qt.size(192, 108)
          source: root.wallpaper ? "file://" + Model.wallpaperFor({ personalWallpaper: root.wallpaper }, Quickshell.env("HOME") || "") : ""
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, 320)
          elide: Text.ElideMiddle
          textFormat: Text.PlainText
          text: root.wallpaper || "Default (one of Omarchy's backgrounds)"
          color: root.foreground
          font.pixelSize: Style.font.body
        }
        Button { text: "Browse…"; bordered: true; onClicked: fileDialog.open() }
        Button { text: "Default"; bordered: true; onClicked: root.setWallpaper("") }
      }

      Row {
        id: footer
        width: parent.width
        spacing: Style.space(12)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - saveButton.width - Style.space(12)
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.loading ? "Looking for installed apps…"
            : root.problems.length ? root.problems.join("\n")
            : root.message !== "" ? root.message
            : AppsModel.missingBrowsers(root.apps).length ? "Choose a browser for each mode, then Save."
            : "Move apps with the arrows, then Save. Greyed apps can't be put in a mode yet."
          color: root.problems.length ? "#E06C75" : root.faint
          font.pixelSize: Style.font.bodySmall
        }
        Button {
          id: saveButton
          text: "Save"
          bordered: true
          enabled: !root.loading && AppsModel.payload(root.apps) !== null
          onClicked: root.save()
        }
      }
    }
  }
}
