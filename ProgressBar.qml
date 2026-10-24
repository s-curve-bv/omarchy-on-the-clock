import QtQuick
import qs.Commons as Commons

// Thin horizontal bar. `marker` (0..1) draws a tick, e.g. where the pace
// says you should be today.
Item {
  id: root

  property real fraction: 0
  property real marker: -1
  property bool danger: false
  property color foreground: Commons.Color.popups.text
  property color fill: danger ? Commons.Color.urgent : Commons.Color.accent

  implicitHeight: 6

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
  }

  Rectangle {
    width: parent.width * Math.max(0, Math.min(1, root.fraction))
    height: parent.height
    radius: height / 2
    color: root.fill

    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
  }

  Rectangle {
    visible: root.marker >= 0 && root.marker <= 1
    x: parent.width * root.marker - width / 2
    y: -2
    width: 2
    height: parent.height + 4
    color: root.foreground
    opacity: 0.6
  }
}
