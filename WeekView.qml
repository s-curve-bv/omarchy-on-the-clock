pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Projects x days of one week. Click a cell for +0:15, right-click for
// -0:15, shift-click for +1:00, scroll to step. Calendar meetings waiting
// for a decision sit on top.
Column {
  id: view

  property var service: null
  property var panel: null

  readonly property var db: service ? service.db : Model.defaults()
  readonly property string today: service ? service.today : Model.dateKey(new Date())
  property string weekStart: Model.weekStart(today)
  readonly property var days: [0, 1, 2, 3, 4, 5, 6].map(function(i) { return Model.addDays(view.weekStart, i) })
  readonly property string currency: db.settings.currency
  // The timer always books on the day it started, so it is only offered
  // in the current week.
  readonly property bool isCurrentWeek: weekStart === Model.weekStart(today)

  readonly property int cellW: Style.space(52)
  readonly property int totalW: Style.space(60)
  readonly property int actionW: Style.space(30)
  readonly property int rowH: Style.space(26)
  readonly property int nameW: width - 7 * cellW - totalW - actionW

  // Customer headers and project rows. Archived projects only show when
  // they have hours this week.
  readonly property var rows: {
    var out = []
    var customers = db.customers.slice().sort(function(a, b) { return a.name.localeCompare(b.name) })
    var week = Model.totals(db, days[0], days[6])
    for (var i = 0; i < customers.length; i++) {
      var c = customers[i]
      var ps = db.projects.filter(function(p) {
        return p.customerId === c.id && ((!p.archived && !c.archived) || week.byProject[p.id])
      }).sort(function(a, b) { return a.name.localeCompare(b.name) })
      if (!ps.length) continue
      out.push({ customer: c })
      for (var j = 0; j < ps.length; j++) out.push({ project: ps[j] })
    }
    return out
  }

  readonly property var weekTotals: Model.totals(db, days[0], days[6])

  // Keyboard cursor: a project row and a day. Space starts or stops the
  // project's timer, + and - change the hours in that cell.
  property string cursorId: ""
  property string cursorDay: today
  readonly property var cursorProject: Model.byId(db.projects, cursorId)
  readonly property var selectable: rows
    .filter(function(r) { return r.project && view.service && view.service.activeProjects.indexOf(r.project) !== -1 })
    .map(function(r) { return r.project.id })

  function resetCursor() {
    weekStart = Model.weekStart(today)
    cursorDay = today
    var s = service
    var id = s && s.timer ? s.timer.projectId : (s && s.selectedProject ? s.selectedProject.id : "")
    cursorId = selectable.indexOf(id) !== -1 ? id : (selectable[0] || "")
  }

  function moveCursor(step) {
    var i = selectable.indexOf(cursorId)
    if (i === -1) { resetCursor(); return }
    cursorId = selectable[Math.max(0, Math.min(selectable.length - 1, i + step))]
  }

  // In another week, space first brings you back to this one.
  function toggleCursor() {
    if (!isCurrentWeek) { weekStart = Model.weekStart(today); return }
    if (cursorId && service) service.toggleTimer(cursorId)
  }

  // Moving past Monday or Sunday continues in the next or previous week.
  function moveDay(step) {
    cursorDay = Model.addDays(days.indexOf(cursorDay) === -1 ? days[0] : cursorDay, step)
    weekStart = Model.weekStart(cursorDay)
  }

  function focusNote() {
    if (cursorId && days.indexOf(cursorDay) !== -1) noteField.forceActiveFocus()
  }

  function addToCursor(minutes) {
    if (!cursorId || !service || days.indexOf(cursorDay) === -1) return
    service.addMinutes(cursorDay, cursorId, minutes)
  }

  function dayTotal(key) {
    var day = db.entries[key]
    var m = 0
    if (day) for (var pid in day) m += day[pid]
    return m
  }

  function rowTotal(pid) {
    var t = weekTotals.byProject[pid]
    return t ? t.minutes : 0
  }

  function shortDate(key) {
    return Qt.formatDate(Model.parseKey(key), "d MMM")
  }

  spacing: Style.spacing.lg

  // ---- Week navigation ----
  Item {
    width: parent.width
    height: Style.spacing.controlHeight

    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.md

      Button { text: "‹"; fontFamily: view.panel.font; onClicked: view.weekStart = Model.addDays(view.weekStart, -7) }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(220)
        horizontalAlignment: Text.AlignHCenter
        text: "Week " + Model.isoWeek(view.weekStart) + " · " + view.shortDate(view.days[0]) + " – " + view.shortDate(view.days[6])
        color: view.panel.fg
        font.family: view.panel.font
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Button { text: "›"; fontFamily: view.panel.font; onClicked: view.weekStart = Model.addDays(view.weekStart, 7) }
      Button {
        visible: view.weekStart !== Model.weekStart(view.today)
        text: "Back to this week"
        fontFamily: view.panel.font
        onClicked: view.weekStart = Model.weekStart(view.today)
      }
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: Model.fmtHours(view.weekTotals.minutes) + "  ·  " + Model.fmtMoney(view.weekTotals.income, view.currency)
      color: view.panel.fg
      font.family: view.panel.font
      font.pixelSize: Style.font.title
    }
  }

  // ---- Calendar suggestions ----
  Column {
    width: parent.width
    spacing: Style.spacing.sm
    visible: view.service && view.service.suggestions.length > 0

    PanelSectionHeader {
      text: "FROM YOUR CALENDAR · DID THESE TAKE PLACE?"
      foreground: view.panel.fg
      fontFamily: view.panel.font
    }

    Repeater {
      model: view.service ? view.service.suggestions : []

      // Date and time in a fixed column, then the meeting, with the project
      // it books on underneath.
      delegate: Item {
        id: srow
        required property var modelData
        width: view.width
        height: Math.max(meeting.implicitHeight, Style.spacing.controlHeight) + Style.spacing.sm

        Text {
          id: when
          anchors.top: meeting.top
          width: Style.space(170)
          text: Qt.formatDateTime(new Date(srow.modelData.start), "ddd d MMM  HH:mm")
          color: view.panel.fg
          font.family: view.panel.font
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Column {
          id: meeting
          anchors.left: when.right
          anchors.right: actions.left
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter

          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: srow.modelData.title
            color: view.panel.fg
            font.family: view.panel.font
            font.pixelSize: Style.font.body
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: "→ " + view.service.projectLabel(Model.byId(view.db.projects, srow.modelData.projectId))
            color: view.panel.dim
            font.family: view.panel.font
            font.pixelSize: Style.font.bodySmall
          }
        }

        Row {
          id: actions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          Button {
            text: "Book " + Model.fmtHours(srow.modelData.minutes)
            fontFamily: view.panel.font
            bordered: true
            onClicked: view.service.confirmSuggestion(srow.modelData)
          }
          Button {
            text: "Didn't happen"
            fontFamily: view.panel.font
            onClicked: view.service.dismissSuggestion(srow.modelData)
          }
        }
      }
    }

    PanelSeparator { width: view.width; foreground: view.panel.fg }
  }

  // ---- Grid header ----
  Row {
    height: view.rowH

    Item { width: view.nameW; height: parent.height }

    Repeater {
      model: view.days
      delegate: Text {
        required property string modelData
        width: view.cellW
        height: view.rowH
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: Qt.formatDate(Model.parseKey(modelData), "ddd d")
        color: modelData === view.today ? view.panel.accent : view.panel.dim
        font.family: view.panel.font
        font.pixelSize: Style.font.bodySmall
        font.bold: modelData === view.today
      }
    }

    Text {
      width: view.totalW
      height: view.rowH
      horizontalAlignment: Text.AlignRight
      verticalAlignment: Text.AlignVCenter
      text: "Total"
      color: view.panel.dim
      font.family: view.panel.font
      font.pixelSize: Style.font.bodySmall
    }
  }

  // ---- Rows ----
  Text {
    visible: view.rows.length === 0
    width: parent.width
    wrapMode: Text.WordWrap
    text: "No projects yet. Add rates, customers and projects in the Admin tab."
    color: view.panel.dim
    font.family: view.panel.font
    font.pixelSize: Style.font.body
  }

  Column {
    width: parent.width

    Repeater {
      model: view.rows.length

      delegate: Item {
        id: row
        required property int index
        readonly property var entry: view.rows[index] || {}
        readonly property var project: entry.project || null
        readonly property bool running: !!(project && view.service && view.service.timer && view.service.timer.projectId === project.id)

        width: view.width
        height: project ? view.rowH : view.rowH + (index > 0 ? Style.spacing.md : 0)

        Rectangle {
          visible: !!row.project && row.project.id === view.cursorId
          anchors.fill: parent
          radius: Style.cornerRadius
          color: Style.hoverFill
        }

        // Customer header
        Text {
          visible: !row.project
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.spacing.xs
          text: row.entry.customer ? row.entry.customer.name.toUpperCase() : ""
          textFormat: Text.PlainText
          color: view.panel.dim
          font.family: view.panel.font
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Row {
          visible: !!row.project
          height: parent.height

          Text {
            width: view.nameW
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            leftPadding: Style.spacing.lg
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: row.project ? row.project.name + (row.project.billable === false ? "  (internal)" : "") : ""
            color: row.running ? view.panel.accent : view.panel.fg
            opacity: row.project && row.project.archived ? 0.5 : 1
            font.family: view.panel.font
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: view.days

            delegate: Rectangle {
              id: cell
              required property string modelData
              readonly property int minutes: row.project ? Model.minutesOn(view.db, modelData, row.project.id) : 0

              readonly property bool selected: !!row.project && row.project.id === view.cursorId && modelData === view.cursorDay
              width: view.cellW
              height: view.rowH
              radius: Style.cornerRadius
              border.width: selected ? 1 : 0
              border.color: view.panel.accent
              color: cellMouse.containsMouse ? Style.hoverFill
                   : (modelData === view.today ? Qt.rgba(view.panel.accent.r, view.panel.accent.g, view.panel.accent.b, 0.08) : "transparent")

              Text {
                anchors.centerIn: parent
                text: cell.minutes > 0 ? Model.fmtHours(cell.minutes) : "·"
                color: cell.minutes > 0 ? view.panel.fg : view.panel.faint
                font.family: view.panel.font
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: cellMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                  view.cursorId = row.project.id
                  view.cursorDay = cell.modelData
                  var step = (mouse.modifiers & Qt.ShiftModifier) ? 60 : 15
                  view.service.addMinutes(cell.modelData, row.project.id, mouse.button === Qt.RightButton ? -step : step)
                }
                onWheel: function(wheel) {
                  if (wheel.angleDelta.y !== 0)
                    view.service.addMinutes(cell.modelData, row.project.id, wheel.angleDelta.y > 0 ? 15 : -15)
                }
              }
            }
          }

          Text {
            width: view.totalW
            height: parent.height
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: row.project ? Model.fmtHours(view.rowTotal(row.project.id)) : ""
            color: view.panel.fg
            font.family: view.panel.font
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Item {
            width: view.actionW
            height: parent.height

            Button {
              anchors.centerIn: parent
              visible: !!row.project && !row.project.archived && view.isCurrentWeek
              iconText: row.running ? "󰓛" : "󰐊"
              tooltipText: row.running ? "Stop and book" : "Start timer"
              active: row.running
              horizontalPadding: Style.spacing.sm
              verticalPadding: Style.spacing.xxs
              fontFamily: view.panel.font
              onClicked: view.service.toggleTimer(row.project.id)
            }
          }
        }
      }
    }
  }

  // ---- Day totals ----
  PanelSeparator { width: view.width; foreground: view.panel.fg }

  Row {
    height: view.rowH

    Text {
      width: view.nameW
      height: parent.height
      verticalAlignment: Text.AlignVCenter
      leftPadding: Style.spacing.lg
      text: "Total"
      color: view.panel.dim
      font.family: view.panel.font
      font.pixelSize: Style.font.body
    }

    Repeater {
      model: view.days
      delegate: Text {
        required property string modelData
        width: view.cellW
        height: view.rowH
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        readonly property int m: view.dayTotal(modelData)
        text: m > 0 ? Model.fmtHours(m) : "·"
        color: m > 0 ? view.panel.fg : view.panel.faint
        font.family: view.panel.font
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    Text {
      width: view.totalW
      height: parent.height
      horizontalAlignment: Text.AlignRight
      verticalAlignment: Text.AlignVCenter
      text: Model.fmtHours(view.weekTotals.minutes)
      color: view.panel.accent
      font.family: view.panel.font
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }

  // ---- Notes for the selected cell ----
  // One line per thing done. Lines can be edited in place (empty removes
  // one); the field below adds a line on Enter and keeps focus for the next.
  Column {
    id: notes
    readonly property bool active: !!view.cursorProject && view.days.indexOf(view.cursorDay) !== -1
    readonly property var lines: active ? Model.notesOn(view.db, view.cursorDay, view.cursorId) : []
    visible: active
    width: parent.width
    spacing: Style.spacing.xs

    function replaceLine(i, text) {
      var next = lines.slice()
      next[i] = text
      view.service.setNotes(view.cursorDay, view.cursorId, next)
    }

    Text {
      leftPadding: Style.spacing.lg
      textFormat: Text.PlainText
      text: view.cursorProject ? "Notes · " + view.cursorProject.name + " · " + Qt.formatDate(Model.parseKey(view.cursorDay), "ddd d MMM") : ""
      color: view.panel.dim
      font.family: view.panel.font
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Repeater {
      model: notes.lines.length

      delegate: TextField {
        id: line
        required property int index
        readonly property string value: notes.lines[index] || ""
        property Timer pending: Timer { interval: 800; onTriggered: line.save() }

        function save() {
          pending.stop()
          if (text !== value) notes.replaceLine(index, text)
        }

        width: notes.width
        font.family: view.panel.font
        selectByMouse: true
        Component.onCompleted: text = value
        onValueChanged: if (!activeFocus) text = value
        onActiveFocusChanged: if (!activeFocus) { save(); text = value }
        onTextEdited: pending.restart()
        Keys.onReturnPressed: view.panel.focusGrid()
        Keys.onEnterPressed: view.panel.focusGrid()
        Keys.onEscapePressed: view.panel.focusGrid()
      }
    }

    TextField {
      id: noteField
      width: notes.width
      font.family: view.panel.font
      selectByMouse: true
      placeholderText: notes.lines.length ? "Add another line (n)" : "What did you do? (n)"

      function submit() {
        if (!text.trim()) { view.panel.focusGrid(); return }
        view.service.addNote(view.cursorDay, view.cursorId, text)
        text = ""
      }
      Keys.onReturnPressed: submit()
      Keys.onEnterPressed: submit()
      Keys.onEscapePressed: { if (text.trim()) submit(); view.panel.focusGrid() }
      onActiveFocusChanged: if (!activeFocus && text.trim()) submit()
    }
  }

  Text {
    text: "↑↓ project · ←→ day · + − 0:15 (shift 1:00) · n note · space " + (view.isCurrentWeek ? "timer" : "back to this week")
        + " · or click +0:15, right-click −0:15, scroll"
    color: view.panel.faint
    font.family: view.panel.font
    font.pixelSize: Style.font.caption
  }
}
