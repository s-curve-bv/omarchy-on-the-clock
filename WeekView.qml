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
        text: "This week"
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

      delegate: Item {
        required property var modelData
        width: view.width
        height: Style.spacing.controlHeight + Style.spacing.xs

        Text {
          anchors.left: parent.left
          anchors.right: actions.left
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: Qt.formatDateTime(new Date(modelData.start), "ddd d MMM HH:mm") + "  " + modelData.title
                + "  →  " + view.service.projectLabel(Model.byId(view.db.projects, modelData.projectId))
          color: view.panel.fg
          font.family: view.panel.font
          font.pixelSize: Style.font.body
        }

        Row {
          id: actions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          Button {
            text: "Book " + Model.fmtHours(modelData.minutes)
            fontFamily: view.panel.font
            bordered: true
            onClicked: view.service.confirmSuggestion(modelData)
          }
          Button {
            text: "Didn't happen"
            fontFamily: view.panel.font
            onClicked: view.service.dismissSuggestion(modelData)
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

              width: view.cellW
              height: view.rowH
              radius: Style.cornerRadius
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
              visible: !!row.project && !row.project.archived
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

  Text {
    text: "click +0:15 · right-click −0:15 · shift-click ±1:00 · scroll to step · ▶ timer rounds to the nearest 0:15"
    color: view.panel.faint
    font.family: view.panel.font
    font.pixelSize: Style.font.caption
  }
}
