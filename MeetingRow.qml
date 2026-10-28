pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One calendar meeting: when, the title and the project it books on, and
// what you can do with it. A linked series' project is fixed; a one-off
// gets a picker, preset to the guessed project.
//   mode "now":    going on, ▶ starts the timer
//   mode "ask":    ended, book or skip it
//   mode "browse": the Calendar tab, also showing what was decided
Item {
  id: row

  required property var meeting
  property var service: null
  property var panel: null
  property string mode: "ask"

  readonly property string projectId: (service && service.meetingPicks[meeting.uid]) || meeting.projectId
  readonly property string decided: meeting.decided || ""

  readonly property var options: (service ? service.activeProjects : []).map(function(p) {
    return { value: p.id, label: row.service.projectLabel(p) }
  })

  width: parent ? parent.width : 0
  height: Math.max(info.implicitHeight, Style.spacing.controlHeight) + Style.spacing.sm

  FontMetrics {
    id: metrics
    font.family: row.panel ? row.panel.font : Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    id: when
    anchors.top: info.top
    width: Style.space(170)
    text: row.mode === "now"
        ? "Now  " + Qt.formatTime(new Date(row.meeting.start), "HH:mm") + "–" + Qt.formatTime(new Date(row.meeting.end), "HH:mm")
        : Qt.formatDateTime(new Date(row.meeting.start), "ddd d MMM  HH:mm")
    color: row.mode === "now" ? row.panel.accent : row.panel.fg
    font.family: row.panel.font
    font.pixelSize: Style.font.body
    font.bold: true
  }

  Column {
    id: info
    anchors.left: when.right
    anchors.right: actions.left
    anchors.rightMargin: Style.spacing.lg
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: row.meeting.title
      color: row.decided === "" ? row.panel.fg : row.panel.dim
      font.family: row.panel.font
      font.pixelSize: Style.font.body
    }
    Text {
      visible: row.meeting.linked || row.decided !== ""
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: "→ " + (row.service ? row.service.projectLabel(Model.byId(row.service.db.projects, row.projectId)) : "")
      color: row.panel.dim
      font.family: row.panel.font
      font.pixelSize: Style.font.bodySmall
    }
    Dropdown {
      id: picker
      visible: !row.meeting.linked && row.decided === ""
      width: {
        var w = 0
        for (var i = 0; i < row.options.length; i++) w = Math.max(w, metrics.advanceWidth(row.options[i].label))
        return Math.min(parent.width, Math.max(Style.space(220), Math.ceil(w) + Style.space(56)))
      }
      showLabel: false
      fontFamily: row.panel.font
      options: row.options
      value: row.projectId
      onChanged: function(v) { row.service.pickMeetingProject(row.meeting.uid, v) }
      Connections { target: row.panel; function onScrolled() { picker.close() } }
    }
  }

  Row {
    id: actions
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.sm

    Button {
      visible: row.mode === "now"
      text: "▶ Start timer"
      fontFamily: row.panel.font
      bordered: true
      onClicked: row.service.startMeeting(row.meeting, row.projectId)
    }
    Button {
      visible: row.mode !== "now" && row.decided === ""
      text: "Book " + Model.fmtHours(row.meeting.minutes)
      fontFamily: row.panel.font
      bordered: true
      onClicked: row.service.confirmSuggestion(row.meeting, row.projectId)
    }
    Button {
      visible: row.mode !== "now" && row.decided === ""
      text: "Skip"
      fontFamily: row.panel.font
      onClicked: row.service.dismissSuggestion(row.meeting)
    }
    Text {
      visible: row.decided !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: row.decided === "confirmed" ? "Booked" : row.decided === "timer" ? "Timer ran" : "Skipped"
      color: row.panel.dim
      font.family: row.panel.font
      font.pixelSize: Style.font.body
    }
    Button {
      visible: row.decided === "dismissed"
      text: "Undo"
      fontFamily: row.panel.font
      onClicked: row.service.undoDismiss(row.meeting)
    }
  }
}
