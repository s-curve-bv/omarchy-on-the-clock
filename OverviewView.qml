import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One month against its target, the year so far, and per-project hours,
// income and budget use.
Column {
  id: view

  property var service: null
  property var panel: null

  readonly property var db: service ? service.db : Model.defaults()
  readonly property string today: service ? service.today : Model.dateKey(new Date())
  readonly property string currency: db.settings.currency
  readonly property var workDays: db.settings.workDays

  property string month: Model.monthKey(today)
  readonly property string year: month.slice(0, 4)
  readonly property var mRange: Model.monthRange(month)
  readonly property var yRange: Model.yearRange(year)
  readonly property var mTotals: Model.totals(db, mRange[0], mRange[1])
  readonly property var yTotals: Model.totals(db, yRange[0], yRange[1])
  readonly property var allTotals: Model.totals(db, null, null)
  readonly property real mTarget: Number(db.targets.month) || 0
  readonly property real yTarget: Number(db.targets.year) || 0
  readonly property var mPace: Model.pace(mTotals.income, mTarget, mRange[0], mRange[1], today, workDays)
  readonly property var yPace: Model.pace(yTotals.income, yTarget, yRange[0], yRange[1], today, workDays)

  readonly property var monthIncomes: {
    var out = []
    for (var i = 1; i <= 12; i++) {
      var mk = year + "-" + (i < 10 ? "0" + i : i)
      var r = Model.monthRange(mk)
      out.push({ month: mk, income: Model.totals(db, r[0], r[1]).income })
    }
    return out
  }
  readonly property real chartMax: Math.max(mTarget, monthIncomes.reduce(function(m, x) { return Math.max(m, x.income) }, 0), 1)

  readonly property int hoursW: Style.space(64)
  readonly property int incomeW: Style.space(90)
  readonly property int budgetW: Style.space(200)

  function money(v) { return Model.fmtMoney(v, currency) }
  function pct(a, b) { return b > 0 ? Math.round(a / b * 100) + "%" : "" }

  function paceLine(p, actual, target, unit) {
    if (target <= 0) return "Set a target in Admin to see your pace."
    if (p.done) return "Finished at " + pct(actual, target) + " of target (" + (actual >= target ? "+" : "") + money(actual - target) + ")."
    if (p.elapsed === 0) return "Starts " + (unit === "month" ? "this month" : "this year") + ": " + money(target / Math.max(1, p.total)) + " per work day reaches the target."
    var diff = p.projected - target
    return "At this pace: " + money(p.projected) + " (" + (diff >= 0 ? "+" : "") + money(diff) + ")"
         + (p.remaining > 0 && actual < target ? " · need " + money(p.neededPerDay) + " per work day for the " + p.remaining + " left" : "")
  }

  spacing: Style.spacing.lg

  // ---- Month navigation ----
  Row {
    spacing: Style.spacing.md

    Button { text: "‹"; fontFamily: view.panel.font; onClicked: view.month = Model.addMonths(view.month, -1) }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(180)
      horizontalAlignment: Text.AlignHCenter
      text: Qt.formatDate(Model.parseKey(view.month + "-01"), "MMMM yyyy")
      color: view.panel.fg
      font.family: view.panel.font
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Button { text: "›"; fontFamily: view.panel.font; onClicked: view.month = Model.addMonths(view.month, 1) }
    Button {
      visible: view.month !== Model.monthKey(view.today)
      text: "This month"
      fontFamily: view.panel.font
      onClicked: view.month = Model.monthKey(view.today)
    }
  }

  // ---- Month ----
  Column {
    width: parent.width
    spacing: Style.spacing.md

    Row {
      spacing: Style.spacing.lg
      Text {
        text: view.money(view.mTotals.income)
        color: view.panel.fg
        font.family: view.panel.font
        font.pixelSize: Style.font.display
        font.bold: true
      }
      Text {
        anchors.baseline: parent.children[0].baseline
        text: view.mTarget > 0 ? "of " + view.money(view.mTarget) + " · " + view.pct(view.mTotals.income, view.mTarget) : "no monthly target"
        color: view.panel.dim
        font.family: view.panel.font
        font.pixelSize: Style.font.subtitle
      }
    }

    ProgressBar {
      width: parent.width
      fraction: view.mTarget > 0 ? view.mTotals.income / view.mTarget : 0
      marker: view.mTarget > 0 && !view.mPace.done && view.mPace.total > 0 ? view.mPace.elapsed / view.mPace.total : -1
      foreground: view.panel.fg
    }

    Text {
      text: "Hours " + Model.fmtHours(view.mTotals.minutes) + " · billable " + Model.fmtHours(view.mTotals.billableMinutes)
            + (view.mTotals.billableMinutes > 0 ? " · avg " + view.money(view.mTotals.income / (view.mTotals.billableMinutes / 60)) + "/h" : "")
      color: view.panel.fg
      font.family: view.panel.font
      font.pixelSize: Style.font.body
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: view.paceLine(view.mPace, view.mTotals.income, view.mTarget, "month")
      color: view.mTarget > 0 && !view.mPace.done && view.mPace.projected < view.mTarget ? view.panel.urgent : view.panel.dim
      font.family: view.panel.font
      font.pixelSize: Style.font.body
    }
  }

  PanelSeparator { width: view.width; foreground: view.panel.fg }

  // ---- Year ----
  Column {
    width: parent.width
    spacing: Style.spacing.md

    PanelSectionHeader { text: "YEAR " + view.year; foreground: view.panel.fg; fontFamily: view.panel.font }

    Row {
      spacing: Style.spacing.lg
      Text {
        text: view.money(view.yTotals.income)
        color: view.panel.fg
        font.family: view.panel.font
        font.pixelSize: Style.font.heading
        font.bold: true
      }
      Text {
        anchors.baseline: parent.children[0].baseline
        text: (view.yTarget > 0 ? "of " + view.money(view.yTarget) + " · " + view.pct(view.yTotals.income, view.yTarget) + " · " : "")
              + Model.fmtHours(view.yTotals.minutes) + " h"
        color: view.panel.dim
        font.family: view.panel.font
        font.pixelSize: Style.font.body
      }
    }

    ProgressBar {
      width: parent.width
      fraction: view.yTarget > 0 ? view.yTotals.income / view.yTarget : 0
      marker: view.yTarget > 0 && !view.yPace.done && view.yPace.total > 0 ? view.yPace.elapsed / view.yPace.total : -1
      foreground: view.panel.fg
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: view.paceLine(view.yPace, view.yTotals.income, view.yTarget, "year")
      color: view.yTarget > 0 && !view.yPace.done && view.yPace.projected < view.yTarget ? view.panel.urgent : view.panel.dim
      font.family: view.panel.font
      font.pixelSize: Style.font.body
    }

    // Income per month; the line is the monthly target. Click to open a month.
    Item {
      id: chart
      width: parent.width
      height: Style.space(90)
      readonly property real colW: width / 12
      readonly property real plotH: height - Style.space(16)

      Repeater {
        model: view.monthIncomes
        delegate: Item {
          required property var modelData
          required property int index
          x: index * chart.colW
          width: chart.colW
          height: chart.height

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: label.top
            anchors.bottomMargin: Style.spacing.xs
            width: chart.colW * 0.55
            height: Math.max(modelData.income > 0 ? 2 : 0, chart.plotH * modelData.income / view.chartMax)
            radius: Style.cornerRadius
            color: modelData.month === view.month ? view.panel.accent : Qt.rgba(view.panel.fg.r, view.panel.fg.g, view.panel.fg.b, monthMouse.containsMouse ? 0.5 : 0.3)
          }
          Text {
            id: label
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(Model.parseKey(modelData.month + "-01"), "MMM")
            color: modelData.month === view.month ? view.panel.accent : view.panel.dim
            font.family: view.panel.font
            font.pixelSize: Style.font.caption
          }
          MouseArea {
            id: monthMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: view.month = modelData.month
          }
        }
      }

      Rectangle {
        visible: view.mTarget > 0
        width: parent.width
        height: 1
        y: chart.plotH - chart.plotH * view.mTarget / view.chartMax
        color: view.panel.fg
        opacity: 0.35
      }
    }
  }

  PanelSeparator { width: view.width; foreground: view.panel.fg }

  // ---- Projects this month ----
  PanelSectionHeader { text: "PROJECTS · " + Qt.formatDate(Model.parseKey(view.month + "-01"), "MMMM").toUpperCase(); foreground: view.panel.fg; fontFamily: view.panel.font }

  Column {
    width: parent.width
    spacing: Style.spacing.xs

    Repeater {
      model: view.db.customers.slice().sort(function(a, b) { return a.name.localeCompare(b.name) })

      delegate: Column {
        id: cust
        required property var modelData
        readonly property var projects: view.db.projects.filter(function(p) {
          return p.customerId === cust.modelData.id && (!p.archived || view.mTotals.byProject[p.id])
        }).sort(function(a, b) { return a.name.localeCompare(b.name) })
        readonly property var ct: view.mTotals.byCustomer[modelData.id] || { minutes: 0, income: 0 }
        visible: projects.length > 0 && (!modelData.archived || ct.minutes > 0)
        width: view.width
        spacing: Style.spacing.xxs
        topPadding: Style.spacing.sm

        Row {
          Text {
            width: view.width - view.hoursW - view.incomeW - view.budgetW
            text: cust.modelData.name
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: view.panel.fg
            font.family: view.panel.font
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: view.hoursW
            horizontalAlignment: Text.AlignRight
            text: Model.fmtHours(cust.ct.minutes)
            color: view.panel.fg
            font.family: view.panel.font
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: view.incomeW
            horizontalAlignment: Text.AlignRight
            text: view.money(cust.ct.income)
            color: view.panel.fg
            font.family: view.panel.font
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        Repeater {
          model: cust.projects
          delegate: Row {
            id: prow
            required property var modelData
            readonly property var pt: view.mTotals.byProject[modelData.id] || { minutes: 0, income: 0 }
            readonly property var budget: Model.budgetUsage(view.db, modelData, view.allTotals)

            Text {
              width: view.width - view.hoursW - view.incomeW - view.budgetW
              leftPadding: Style.spacing.lg
              text: prow.modelData.name + (prow.modelData.billable === false ? "  (internal)" : "") + "  · " + view.money(Model.rateFor(view.db, prow.modelData)) + "/h"
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: view.panel.dim
              font.family: view.panel.font
              font.pixelSize: Style.font.body
            }
            Text {
              width: view.hoursW
              horizontalAlignment: Text.AlignRight
              text: Model.fmtHours(prow.pt.minutes)
              color: view.panel.fg
              font.family: view.panel.font
              font.pixelSize: Style.font.body
            }
            Text {
              width: view.incomeW
              horizontalAlignment: Text.AlignRight
              text: view.money(prow.pt.income)
              color: view.panel.fg
              font.family: view.panel.font
              font.pixelSize: Style.font.body
            }
            Item {
              width: view.budgetW
              height: Style.font.body * 1.4

              ProgressBar {
                visible: !!prow.budget
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.xxl
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(70)
                fraction: prow.budget ? prow.budget.fraction : 0
                danger: !!prow.budget && prow.budget.fraction > 0.9
                foreground: view.panel.fg
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: !prow.budget ? "" : (prow.budget.type === "hours"
                        ? Math.round(prow.budget.used) + " / " + prow.budget.budget + " h"
                        : Model.fmtMoneyShort(prow.budget.used, view.currency) + " / " + Model.fmtMoneyShort(prow.budget.budget, view.currency))
                color: prow.budget && prow.budget.fraction > 0.9 ? view.panel.urgent : view.panel.dim
                font.family: view.panel.font
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }

  Text {
    text: "Amounts excl. VAT. Budgets count all hours ever booked on the project."
    color: view.panel.faint
    font.family: view.panel.font
    font.pixelSize: Style.font.caption
  }
}
