import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "s-curve.on-the-clock"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root

  property string tab: "week"

  // Room around the content so focus/hover borders on the edge rows are not
  // clipped by the scroll area.
  readonly property int edge: Style.spacing.sm

  // Open dropdowns close on this: their list follows the trigger and would
  // otherwise slide out past the panel edge while scrolling.
  signal scrolled()

  // Shared look for the views.
  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property color faint: Qt.darker(fg, 2.2)
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property string font: bar && bar.fontFamily ? bar.fontFamily : Style.font.family

  function open() { root.controller.show() }
  function openFromHotkey() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  function focusGrid() { keys.forceActiveFocus() }

  // A control in the tab you leave (a dropdown you just used) would keep
  // keyboard focus while hidden and catch Enter and the arrows; switching
  // tabs hands the keys back to the panel.
  onTabChanged: keys.forceActiveFocus()

  // Opening selects the running or last-used project in Week.
  onOpenedChanged: {
    if (!opened) return
    weekView.resetCursor()
    if (root.service && root.service.notePrompt) notePrompt.focusInput()
    else keys.forceActiveFocus()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(780))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + 2 * root.edge, Style.space(860))

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()

      // Week: up/down (k/j) pick the project, left/right (h/l) the day,
      // + and - add or remove 0:15 in that cell (with shift 1:00), space
      // starts or stops the project's timer.
      Keys.onPressed: function(event) {
        var k = event.key
        // w, o, c and a switch tabs anywhere outside a text field.
        var tabs = {}
        tabs[Qt.Key_W] = "week"; tabs[Qt.Key_O] = "overview"; tabs[Qt.Key_C] = "calendar"; tabs[Qt.Key_A] = "admin"
        if (tabs[k] && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
          root.tab = tabs[k]
          event.accepted = true
          return
        }
        if (root.tab !== "week") return
        var hour = (event.modifiers & Qt.ShiftModifier) && k !== Qt.Key_Plus
        if (k === Qt.Key_Up || k === Qt.Key_K) weekView.moveCursor(-1)
        else if (k === Qt.Key_Down || k === Qt.Key_J) weekView.moveCursor(1)
        else if (k === Qt.Key_Left || k === Qt.Key_H) weekView.moveDay(-1)
        else if (k === Qt.Key_Right || k === Qt.Key_L) weekView.moveDay(1)
        else if (k === Qt.Key_Plus || k === Qt.Key_Equal) weekView.addToCursor(hour ? 60 : 15)
        else if (k === Qt.Key_Minus || k === Qt.Key_Underscore) weekView.addToCursor(hour || k === Qt.Key_Underscore ? -60 : -15)
        else if (k === Qt.Key_Space) weekView.toggleCursor()
        else return
        event.accepted = true
      }

      // Click on empty space takes focus out of a text field, which saves it.
      MouseArea {
        anchors.fill: parent
        onPressed: function(mouse) { keys.forceActiveFocus(); mouse.accepted = false }
        // Scrolling for the Flickable below (a WheelHandler would ignore
        // touchpads by default).
        onWheel: function(wheel) {
          if (wheel.pixelDelta.y !== 0) {
            wheelGlide.stop()
            scroller.cancelFlick()
            var now = Date.now()
            var dt = Math.max(1, now - scroller.lastWheelAt)
            scroller.lastWheelAt = now
            scroller.contentY = scroller.clampY(scroller.contentY - wheel.pixelDelta.y)
            var v = -wheel.pixelDelta.y * 1000 / dt
            scroller.wheelVelocity = dt > 100 ? v : 0.6 * v + 0.4 * scroller.wheelVelocity
            touchpadRelease.restart()
          } else if (wheel.angleDelta.y === 0 && wheel.pixelDelta.y === 0) {
            // Touchpads send an empty event when the fingers lift: fling now
            // rather than waiting for the release timer.
            if (touchpadRelease.running) {
              touchpadRelease.stop()
              scroller.fling()
            }
          } else if (wheel.angleDelta.y !== 0) {
            scroller.cancelFlick()
            var from = wheelGlide.running ? scroller.wheelTarget : scroller.contentY
            scroller.wheelTarget = scroller.clampY(from - wheel.angleDelta.y / 120 * Style.space(110))
            wheelGlide.stop()
            wheelGlide.to = scroller.wheelTarget
            wheelGlide.start()
          }
        }
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + 2 * root.edge
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // The MouseArea above does the scrolling; an interactive Flickable
        // would grab wheel events first and skip it.
        interactive: false
        onContentYChanged: root.scrolled()

        // Flickable's own wheel handling jumps in steps and stops dead.
        // Mouse wheels glide to their target instead; touchpads follow the
        // fingers and keep their speed as a fling once they let go.
        property real wheelTarget: 0
        property real wheelVelocity: 0
        property real lastWheelAt: 0

        function clampY(y) { return Math.max(0, Math.min(contentHeight - height, y)) }

        function fling() {
          if (Math.abs(wheelVelocity) > 200) flick(0, -wheelVelocity)
          wheelVelocity = 0
        }

        NumberAnimation {
          id: wheelGlide
          target: scroller
          property: "contentY"
          duration: 280
          easing.type: Easing.OutCubic
        }

        Timer {
          id: touchpadRelease
          // Fallback for touchpads that send no lift event.
          interval: 80
          onTriggered: scroller.fling()
        }

        Column {
          id: column
          y: root.edge
          width: parent.width
          spacing: Style.spacing.xl

          // ---- Running timer ----
          // Above the tabs so it shows on every tab: what runs, for how long,
          // and what stopping now would book on which day.
          Rectangle {
            visible: !!(root.service && root.service.timer)
            width: parent.width
            height: Style.spacing.controlHeight + Style.spacing.md * 2
            radius: Style.cornerRadius
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.right: stopButton.left
              anchors.rightMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.lg

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.service && root.service.timer ? "󱎫 " + Model.fmtHours(root.service.timerMinutes) : ""
                color: root.fg
                font.family: root.font
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - parent.children[0].width - parent.spacing

                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: root.service ? root.service.projectLabel(root.service.timerProject) : ""
                  color: root.fg
                  font.family: root.font
                  font.pixelSize: Style.font.body
                }
                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  text: !(root.service && root.service.timer) ? ""
                    : "since " + Qt.formatTime(new Date(root.service.timer.startedAt), "HH:mm") + " · stopping now books "
                      + Model.fmtHours(Model.roundQuarter(root.service.timerMinutes)) + " on "
                      + Qt.formatDate(new Date(root.service.timer.startedAt), "ddd d MMM")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Button {
              id: stopButton
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰓛"
              text: "Stop and book"
              bordered: true
              fontFamily: root.font
              onClicked: root.service.stopTimer()
            }
          }

          // ---- Tabs ----
          ButtonGroup {
            fontFamily: root.font
            value: root.tab
            // The first letter is the shortcut; U+0332 underlines it in plain text.
            options: [
              { value: "week", label: "W\u0332eek" + (root.service && root.service.suggestions.length ? " (" + root.service.suggestions.length + ")" : ""), tooltip: "Shortcut: w" },
              { value: "overview", label: "O\u0332verview", tooltip: "Shortcut: o" },
              { value: "calendar", label: "C\u0332alendar", tooltip: "Shortcut: c" },
              { value: "admin", label: "A\u0332dmin", tooltip: "Shortcut: a" }
            ]
            onChanged: function(v) { root.tab = v }
          }

          // ---- Banners ----
          Rectangle {
            visible: !!(root.service && root.service.demo && !root.service.demoQuiet)
            width: parent.width
            height: Style.spacing.controlHeight + Style.spacing.md * 2
            radius: Style.cornerRadius
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: "Demo data: fictional customers and hours. Your own file is untouched."
              color: root.fg
              font.family: root.font
              font.pixelSize: Style.font.body
            }
            Button {
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              text: "Back to my data"
              fontFamily: root.font
              bordered: true
              onClicked: root.service.setDemo(false)
            }
          }

          Text {
            visible: !!(root.service && root.service.corrupt)
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.service ? root.service.dataPath + " could not be read as JSON. Nothing is saved until it is fixed." : ""
            color: root.urgent
            font.family: root.font
            font.pixelSize: Style.font.body
          }

          Rectangle {
            visible: !!(root.service && root.service.pendingIdle)
            width: parent.width
            height: idleRow.implicitHeight + Style.spacing.lg * 2
            radius: Style.cornerRadius
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.15)

            Row {
              id: idleRow
              anchors.verticalCenter: parent.verticalCenter
              x: Style.spacing.lg
              spacing: Style.spacing.lg

              Text {
                anchors.verticalCenter: parent.verticalCenter
                readonly property var idle: root.service ? root.service.pendingIdle : null
                text: idle
                      ? "You were away " + Qt.formatTime(new Date(idle.from), "HH:mm") + " – " + Qt.formatTime(new Date(idle.to), "HH:mm")
                        + " (" + Model.fmtHours((idle.to - idle.from) / 60000) + ") while the timer ran."
                      : ""
                color: root.fg
                font.family: root.font
                font.pixelSize: Style.font.body
              }
              Button { text: "Discard that time"; bordered: true; fontFamily: root.font; onClicked: root.service.discardIdle() }
              Button { text: "Keep it"; fontFamily: root.font; onClicked: root.service.keepIdle() }
            }
          }

          // ---- Views ----
          WeekView {
            id: weekView
            visible: root.tab === "week"
            width: parent.width
            service: root.service
            panel: root
          }
          OverviewView {
            visible: root.tab === "overview"
            width: parent.width
            service: root.service
            panel: root
          }
          CalendarView {
            visible: root.tab === "calendar"
            width: parent.width
            service: root.service
            panel: root
          }
          AdminView {
            visible: root.tab === "admin"
            width: parent.width
            service: root.service
            panel: root
          }
        }
      }
    }
  }
}
