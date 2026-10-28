pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Shown after a call (the microphone was in use) whose project isn't clear
// from the calendar: pick the project, adjust the note and book it. Enter
// books, Esc skips.
Rectangle {
  id: prompt

  property var service: null
  property var panel: null

  readonly property var call: service ? service.callPrompt : null
  property string projectId: ""

  readonly property var options: (service ? service.activeProjects : []).map(function(p) {
    return { value: p.id, label: prompt.service.projectLabel(p) }
  })

  // The panel focuses this when it opens with a call waiting.
  readonly property Item input: noteField

  function book() {
    service.bookCall(call, projectId, noteField.text)
    panel.focusGrid()
  }

  function skip() {
    service.closeCallPrompt()
    panel.focusGrid()
  }

  visible: !!call
  height: content.implicitHeight + Style.spacing.lg * 2
  radius: Style.cornerRadius
  color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15)

  onCallChanged: {
    if (!call) return
    projectId = call.projectId
    noteField.text = call.line
    Qt.callLater(function() { noteField.forceActiveFocus() })
  }

  Column {
    id: content
    x: Style.spacing.lg
    y: Style.spacing.lg
    width: parent.width - 2 * Style.spacing.lg
    spacing: Style.spacing.sm

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: !prompt.call ? "" : "You were in " + (prompt.call.meeting ? prompt.call.meeting.title : "a meeting") + " for "
            + Model.fmtHours(Math.round((prompt.call.to - prompt.call.from) / 60000)) + " · "
            + Qt.formatDate(Model.parseKey(prompt.call.day), "ddd d MMM") + ". Which project?"
      color: prompt.panel.fg
      font.family: prompt.panel.font
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Dropdown {
      id: picker
      width: Math.min(content.width, Style.space(420))
      showLabel: false
      fontFamily: prompt.panel.font
      options: prompt.options
      value: prompt.projectId
      onChanged: function(v) { prompt.projectId = v }
      Connections { target: prompt.panel; function onScrolled() { picker.close() } }
    }

    Item {
      width: content.width
      height: Style.spacing.controlHeight

      TextField {
        id: noteField
        anchors.left: parent.left
        anchors.right: actions.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        font.family: prompt.panel.font
        selectByMouse: true
        placeholderText: "Note for this meeting"
        Keys.onReturnPressed: prompt.book()
        Keys.onEnterPressed: prompt.book()
        Keys.onEscapePressed: prompt.skip()
      }
      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.sm

        Button {
          text: prompt.call ? "Book " + Model.fmtHours(prompt.call.minutes) : ""
          bordered: true
          fontFamily: prompt.panel.font
          onClicked: prompt.book()
        }
        Button {
          text: "Skip"
          fontFamily: prompt.panel.font
          onClicked: prompt.skip()
        }
      }
    }
  }
}
