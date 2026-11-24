import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Guide line for a mouse resize: snap-drag.lua summons it with
// {"guide": {monitor, x, top, bottom, label}} while the dragged edge is within
// reach of a snap point, and hides it after.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var guide: null

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    root.guide = payload.guide || null
    root.opened = root.guide !== null
  }

  function close() {
    root.opened = false
    root.guide = null
  }

  // Click-through line where the dragged edge will snap to.
  PanelWindow {
    visible: root.guide !== null && screen !== null
    screen: {
      var name = root.guide ? String(root.guide.monitor) : ""
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++)
        if (screens[i].name === name) return screens[i]
      return null
    }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "exe-snap-guide"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    Rectangle {
      id: line
      readonly property int thickness: Style.space(3)
      x: (root.guide ? Number(root.guide.x) : 0) - thickness / 2
      y: root.guide ? Number(root.guide.top) : 0
      width: thickness
      height: root.guide ? Number(root.guide.bottom) - Number(root.guide.top) : 0
      color: Commons.Color.accent
    }

    Rectangle {
      anchors.horizontalCenter: line.horizontalCenter
      y: line.y + Style.spacing.md
      width: guideLabel.implicitWidth + Style.spacing.md * 2
      height: guideLabel.implicitHeight + Style.spacing.md
      radius: Style.cornerRadius
      color: Commons.Color.accent

      Text {
        id: guideLabel
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.guide ? String(root.guide.label) : ""
        color: Commons.Color.menu.background
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.title
      }
    }
  }
}
