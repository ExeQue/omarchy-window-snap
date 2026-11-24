import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Guide lines for a mouse resize: snap-drag.lua summons it with
// {"monitor": name, "guides": [{axis, pos, from, to, label}, ...]} while a
// dragged edge is within reach of a snap point, and hides it after. axis "x"
// draws a vertical line at x = pos from y = from to y = to; axis "y" a
// horizontal one. A corner drag can show one of each.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string monitor: ""
  property var guides: []
  readonly property var targetScreen: {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === root.monitor) return screens[i]
    return null
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    root.monitor = String(payload.monitor || "")
    root.guides = Array.isArray(payload.guides) ? payload.guides : []
    root.opened = root.guides.length > 0
  }

  function close() {
    root.opened = false
    root.guides = []
  }

  // Click-through lines where the dragged edges will snap to.
  PanelWindow {
    visible: root.guides.length > 0 && root.targetScreen !== null
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "exe-snap-guide"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    Repeater {
      model: root.guides

      delegate: Item {
        id: guide
        required property var modelData
        readonly property bool vertical: modelData.axis === "x"
        anchors.fill: parent

        Rectangle {
          id: line
          readonly property int thickness: Style.space(3)
          readonly property real pos: Number(guide.modelData.pos) - thickness / 2
          readonly property real from: Number(guide.modelData.from)
          readonly property real length: Number(guide.modelData.to) - from
          x: guide.vertical ? pos : from
          y: guide.vertical ? from : pos
          width: guide.vertical ? thickness : length
          height: guide.vertical ? length : thickness
          color: Commons.Color.accent
        }

        Rectangle {
          x: guide.vertical ? line.x + (line.width - width) / 2 : line.x + Style.spacing.md
          y: guide.vertical ? line.y + Style.spacing.md : line.y + (line.height - height) / 2
          width: label.implicitWidth + Style.spacing.md * 2
          height: label.implicitHeight + Style.spacing.md
          radius: Style.cornerRadius
          color: Commons.Color.accent

          Text {
            id: label
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: String(guide.modelData.label)
            color: Commons.Color.menu.background
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
          }
        }
      }
    }
  }
}
