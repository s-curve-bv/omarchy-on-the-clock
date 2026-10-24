import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Shown after a timer stops with time booked: what did you do? Meetings
// from that stretch can be added with one click, and typed lines are added
// on Enter. Esc, or Enter on an empty line, closes it.
Rectangle {
  id: prompt

  property var service: null
  property var panel: null

  readonly property var ask: service ? service.notePrompt : null
  readonly property var project: ask ? Model.byId(service.db.projects, ask.projectId) : null
  readonly property var lines: ask ? Model.notesOn(service.db, ask.day, ask.projectId) : []

  function focusInput() { input.forceActiveFocus() }

  function close() {
    input.text = ""
    service.closeNotePrompt()
    panel.focusGrid()
  }

  visible: !!ask
  height: content.implicitHeight + Style.spacing.lg * 2
  radius: Style.cornerRadius
  color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.15)

  onAskChanged: if (ask) Qt.callLater(focusInput)

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
      text: !prompt.ask ? "" : "Booked " + Model.fmtHours(prompt.ask.minutes) + " on " + prompt.service.projectLabel(prompt.project)
            + " · " + Qt.formatDate(Model.parseKey(prompt.ask.day), "ddd d MMM") + ". What did you do?"
      color: prompt.panel.fg
      font.family: prompt.panel.font
      font.pixelSize: Style.font.body
      font.bold: true
    }

    // Meetings while the timer ran.
    Repeater {
      model: prompt.service ? prompt.service.notePromptMeetings : []

      delegate: Item {
        id: meeting
        required property var modelData
        readonly property string line: modelData.title + " (" + Qt.formatTime(new Date(modelData.start), "HH:mm") + "–" + Qt.formatTime(new Date(modelData.end), "HH:mm") + ")"
        readonly property bool added: prompt.lines.indexOf(line) !== -1
        width: content.width
        height: Style.spacing.controlHeight

        Text {
          anchors.left: parent.left
          anchors.right: useButton.left
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: "Meeting: " + meeting.line
          color: prompt.panel.fg
          font.family: prompt.panel.font
          font.pixelSize: Style.font.body
        }
        Button {
          id: useButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: meeting.added ? "Added" : "That's what I did"
          iconText: meeting.added ? "󰄬" : ""
          bordered: !meeting.added
          fontFamily: prompt.panel.font
          onClicked: if (!meeting.added) prompt.service.confirmMeeting(meeting.modelData)
        }
      }
    }

    // Lines so far.
    Repeater {
      model: prompt.lines
      delegate: Text {
        required property string modelData
        width: content.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "• " + modelData
        color: prompt.panel.dim
        font.family: prompt.panel.font
        font.pixelSize: Style.font.body
      }
    }

    Item {
      width: content.width
      height: Style.spacing.controlHeight

      TextField {
        id: input
        anchors.left: parent.left
        anchors.right: doneButton.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        font.family: prompt.panel.font
        selectByMouse: true
        placeholderText: "Type a line and press Enter; Esc when done"
        function submit() {
          if (!text.trim()) { prompt.close(); return }
          prompt.service.addNote(prompt.ask.day, prompt.ask.projectId, text)
          text = ""
        }
        Keys.onReturnPressed: submit()
        Keys.onEnterPressed: submit()
        Keys.onEscapePressed: {
          if (text.trim()) prompt.service.addNote(prompt.ask.day, prompt.ask.projectId, text)
          prompt.close()
        }
      }
      Button {
        id: doneButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Done"
        fontFamily: prompt.panel.font
        onClicked: {
          if (input.text.trim()) prompt.service.addNote(prompt.ask.day, prompt.ask.projectId, input.text)
          prompt.close()
        }
      }
    }
  }
}
