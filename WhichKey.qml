// Which-Key HUD -- a visual-only overlay that shows the keybindings for the
// modifier chord currently held. Modifier state is fed in over IPC by the
// companion daemon (whichkey-keyd); this surface never takes keyboard focus,
// so it can never swallow the keystroke you are about to press.
//
//   omarchy-shell -q whichkey mods "SUPER+SHIFT"   -> show that bucket
//   omarchy-shell -q whichkey hide                 -> hide
//
// Modelled on plugins/osd/Osd.qml (same layer-shell + theme-token pattern).
// All measurements live on `root`: Quickshell reparents PanelWindow content
// into its own scope, so `panel.*` ids are not reachable from delegates.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  // Wired up by the shell's panel loader if the properties exist.
  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/mike.whichkey"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/omarchy-whichkey"

  property var index: ({})
  property string mask: ""
  property double lastBuild: 0

  readonly property var rows: index[mask] || []
  readonly property bool opened: mask !== "" && rows.length > 0

  // --- layout tokens (read by the delegates) --------------------------------
  readonly property int pad: Style.space(22)
  readonly property int rowH: Style.font.bodySmall + Style.space(13)
  readonly property int capMin: Style.space(58)
  readonly property int colW: Style.space(300)
  property int screenH: 1080
  // Keep columns to ~18 rows so a big bucket wraps into 2-3 short columns
  // instead of one screen-height stripe.
  readonly property int availH: Math.max(rowH * 6, Math.min(screenH - Style.space(240), rowH * 18))
  readonly property int maxRows: Math.max(4, Math.floor(availH / rowH))
  readonly property int nCols: Math.max(1, Math.ceil(rows.length / maxRows))
  readonly property int nRows: Math.max(1, Math.ceil(rows.length / nCols))

  // Column-major split of `rows` into an nCols array of row-arrays. Declared
  // as a property (not a function) so it re-evaluates when rows/nCols change.
  readonly property var columns: {
    var out = []
    for (var c = 0; c < nCols; c++)
      out.push(rows.slice(c * nRows, (c + 1) * nRows))
    return out
  }
  // -------------------------------------------------------------------------

  function setMask(m) {
    root.mask = m || ""
    if (root.mask !== "" && (Date.now() - root.lastBuild) > 10000)
      root.rebuild()
  }

  function rebuild() {
    root.lastBuild = Date.now()
    builder.running = true
  }

  function loadIndex(txt) {
    try {
      root.index = JSON.parse(txt || "{}")
    } catch (e) {
      console.warn("whichkey: could not parse index.json:", e)
    }
  }

  // Keep the summon/hide API too, in case the plugin is ever driven that way.
  function open(payloadJson) {
    try { root.setMask(JSON.parse(payloadJson || "{}").mask || "") } catch (e) {}
  }
  function close() { root.setMask("") }

  Component.onCompleted: rebuild()

  IpcHandler {
    target: "whichkey"
    function mods(m: string): string { root.setMask(m); return "ok" }
    function hide(): string { root.setMask(""); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    // Force a fresh read of the keybinding index (normally rebuilt lazily,
    // at most once per 10s while the HUD is being shown).
    function rebuild(): string { root.rebuild(); return "ok" }
    function debug(): string {
      return JSON.stringify({
        mask: root.mask,
        rowsForMask: root.rows.length,
        cols: root.columns.map(function(c) { return c.length }),
        buckets: Object.keys(root.index)
      })
    }
    function ping(): string { return "ok" }
  }

  Process {
    id: builder
    command: [root.pluginDir + "/build-index.sh"]
    onExited: idxFile.reload()
  }

  FileView {
    id: idxFile
    path: root.cacheDir + "/index.json"
    onLoaded: root.loadIndex(text())
    onLoadFailed: root.loadIndex("{}")
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-whichkey"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual only: empty input region so the HUD never blocks the desktop.
    mask: Region {}

    onHeightChanged: if (height > 0) root.screenH = height

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: grid.implicitWidth + root.pad * 2
      height: header.implicitHeight + grid.implicitHeight + root.pad * 3
      color: Util.alpha(Color.background, 0.97)
      radius: Style.cornerRadius
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

      Column {
        x: root.pad
        y: root.pad
        spacing: root.pad

        Text {
          id: header
          text: root.mask.replace(/\+/g, "  +  ")
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          color: Color.accent
        }

        Row {
          id: grid
          spacing: Style.space(26)

          Repeater {
            model: root.columns

            delegate: Column {
              id: colDelegate
              required property var modelData
              spacing: Style.space(3)

              Repeater {
                model: colDelegate.modelData

                delegate: Row {
                  required property var modelData
                  width: root.colW
                  height: root.rowH
                  spacing: Style.space(10)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Style.space(5)
                    color: Util.alpha(Color.popups.text, 0.11)
                    border.width: 1
                    border.color: Util.alpha(Color.popups.text, 0.18)
                    implicitWidth: Math.max(root.capMin, cap.implicitWidth + Style.space(14))
                    implicitHeight: cap.implicitHeight + Style.space(6)

                    Text {
                      id: cap
                      anchors.centerIn: parent
                      text: modelData.k
                      textFormat: Text.PlainText
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      color: Color.popups.text
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.colW - root.capMin - Style.space(20)
                    text: modelData.d
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    color: Util.alpha(Color.popups.text, 0.92)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
