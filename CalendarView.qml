pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Meetings from Datebook's calendar cache. "Meetings" browses the last
// lookbackDays to book or skip what Week no longer asks about; "Recurring"
// links a series to a project, so Week asks about each occurrence.
Column {
  id: view

  property var service: null
  property var panel: null

  readonly property var db: service ? service.db : Model.defaults()
  property string section: "meetings"   // meetings | series
  property string filter: "all"         // all | linked | unlinked
  property string meetingFilter: "waiting"   // waiting | all

  readonly property var meetings: {
    var all = service ? service.pastMeetings : []
    return meetingFilter === "all" ? all : all.filter(function(m) { return !m.decided })
  }

  readonly property var projectOptions: {
    var opts = [{ value: "", label: "Not linked" }]
    var ps = db.projects.filter(function(p) { return !p.archived })
    for (var i = 0; i < ps.length; i++) opts.push({ value: ps[i].id, label: service.projectLabel(ps[i]) })
    opts.sort(function(a, b) { return a.value === "" ? -1 : b.value === "" ? 1 : a.label.localeCompare(b.label) })
    return opts
  }

  readonly property var shown: {
    var all = service ? service.series : []
    if (filter === "all") return all
    return all.filter(function(s) { return !!view.db.calendar.links[s.seriesId] === (view.filter === "linked") })
  }

  // The project dropdown fits the longest "Customer · Project", up to half
  // the row so the meeting title keeps room.
  readonly property int pickerW: {
    var w = 0
    for (var i = 0; i < projectOptions.length; i++) w = Math.max(w, metrics.advanceWidth(projectOptions[i].label))
    return Math.min(width / 2, Math.max(Style.space(280), Math.ceil(w) + Style.space(56)))
  }

  FontMetrics {
    id: metrics
    font.family: view.panel ? view.panel.font : Style.font.family
    font.pixelSize: Style.font.body
  }

  function when(ms) { return ms ? Qt.formatDate(new Date(ms), "ddd d MMM") : "–" }

  spacing: Style.spacing.lg

  ButtonGroup {
    fontFamily: view.panel.font
    options: [
      { value: "meetings", label: "Meetings" },
      { value: "series", label: "Recurring" }
    ]
    value: view.section
    onChanged: function(v) { view.section = v }
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    text: view.section === "meetings"
        ? "Meetings of the last " + view.db.settings.lookbackDays + " days. Week asks about the last "
          + view.db.settings.askWorkDays + " work days; book or skip older ones here. Declined and cancelled meetings are skipped."
        : "Link a recurring meeting to a project. Once an occurrence has ended it appears at the top of the Week tab, "
          + "where you book or skip it. Unlinked recurring meetings are never asked about."
    color: view.panel.dim
    font.family: view.panel.font
    font.pixelSize: Style.font.body
  }

  Text {
    visible: view.service && !view.service.calendarAvailable
    width: parent.width
    wrapMode: Text.WordWrap
    text: "No calendar cache found at " + view.db.settings.calendarCache + ". This reads the events the Datebook plugin "
        + "(blacksheep.calendar) syncs; change the path in Admin if yours lives elsewhere."
    color: view.panel.urgent
    font.family: view.panel.font
    font.pixelSize: Style.font.body
  }

  // ---- Meetings ----
  ButtonGroup {
    visible: view.section === "meetings" && view.service && view.service.calendarAvailable
    fontFamily: view.panel.font
    options: [
      { value: "waiting", label: "Not decided" },
      { value: "all", label: "All" }
    ]
    value: view.meetingFilter
    onChanged: function(v) { view.meetingFilter = v }
  }

  Text {
    visible: view.section === "meetings" && view.service && view.service.calendarAvailable && view.meetings.length === 0
    text: view.meetingFilter === "waiting" ? "Every meeting has been decided on." : "No meetings found."
    color: view.panel.dim
    font.family: view.panel.font
    font.pixelSize: Style.font.body
  }

  Column {
    visible: view.section === "meetings"
    width: parent.width
    spacing: Style.spacing.xs

    Repeater {
      model: view.section === "meetings" ? view.meetings : []
      delegate: MeetingRow {
        required property var modelData
        meeting: modelData
        mode: "browse"
        service: view.service
        panel: view.panel
      }
    }
  }

  // ---- Recurring ----
  ButtonGroup {
    visible: view.section === "series" && view.service && view.service.calendarAvailable
    fontFamily: view.panel.font
    options: [
      { value: "all", label: "All" },
      { value: "linked", label: "Linked" },
      { value: "unlinked", label: "Not linked" }
    ]
    value: view.filter
    onChanged: function(v) { view.filter = v }
  }

  Text {
    visible: view.section === "series" && view.service && view.service.calendarAvailable && view.shown.length === 0
    text: view.filter === "linked" ? "No meetings linked yet." : view.filter === "unlinked" ? "Every recurring meeting is linked." : "No recurring meetings found."
    color: view.panel.dim
    font.family: view.panel.font
    font.pixelSize: Style.font.body
  }

  Column {
    visible: view.section === "series"
    width: parent.width
    spacing: Style.spacing.sm

    Repeater {
      model: view.section === "series" ? view.shown : []

      delegate: Item {
        id: srow
        required property var modelData
        readonly property string linked: view.db.calendar.links[modelData.seriesId] || ""
        width: view.width
        height: Math.max(info.implicitHeight, Style.spacing.controlHeight) + Style.spacing.xs

        Column {
          id: info
          anchors.left: parent.left
          anchors.right: picker.left
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter

          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: srow.modelData.title
            color: srow.linked ? view.panel.accent : view.panel.fg
            font.family: view.panel.font
            font.pixelSize: Style.font.body
          }
          Text {
            text: Model.fmtHours(srow.modelData.minutes) + " · last " + view.when(srow.modelData.last) + " · next " + view.when(srow.modelData.next)
            color: view.panel.dim
            font.family: view.panel.font
            font.pixelSize: Style.font.bodySmall
          }
        }

        Dropdown {
          id: picker
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: view.pickerW
          showLabel: false
          fontFamily: view.panel.font
          options: view.projectOptions
          value: srow.linked
          onChanged: function(v) { view.service.linkSeries(srow.modelData.seriesId, v) }
          Connections { target: view.panel; function onScrolled() { picker.close() } }
        }
      }
    }
  }
}
