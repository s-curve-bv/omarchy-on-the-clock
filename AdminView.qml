pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Targets, rates, customers with their projects, settings and backup. Fields save when you
// press Enter or leave them. Anything with hours booked can be archived but
// not deleted, so past months keep adding up.
//
// Repeaters use a count as their model: an array model would rebuild every
// row on each save and steal focus from the field you just clicked into.
Column {
  id: view

  property var service: null
  property var panel: null

  readonly property var db: service ? service.db : Model.defaults()
  readonly property string currency: db.settings.currency
  readonly property int labelW: Style.space(150)
  // Wide fields take what is left of the row after the label.
  readonly property int wideW: width - labelW - Style.spacing.lg
  readonly property int pickerW: Style.space(210)

  // Project list columns and the one item open for editing.
  readonly property int lineH: Style.space(28)
  readonly property int nameColW: Style.space(270)
  // Rate column and rate dropdown fit the longest rate, which the 32-character
  // name limit keeps within reason.
  readonly property int rateNameMax: 32
  readonly property real widestRate: {
    var w = 0
    for (var i = 0; i < rateOptions.length; i++) w = Math.max(w, metrics.advanceWidth(rateOptions[i].label))
    return w
  }
  readonly property int rateColW: Math.max(Style.space(160), Math.ceil(widestRate) + Style.space(24))
  readonly property int ratePickerW: Math.max(pickerW, Math.ceil(widestRate) + Style.space(56))
  readonly property int budgetColW: width - indent - nameColW - rateColW - Style.space(40)
  readonly property int editLabelW: Style.space(80)
  readonly property int indent: Style.space(24)
  property string editingProject: ""
  property string editingCustomer: ""
  property bool showArchived: false

  function byName(a, b) { return String(a.name).localeCompare(String(b.name)) }

  readonly property var shownCustomers: db.customers
    .filter(function(c) { return view.showArchived || !c.archived })
    .sort(function(a, b) { return (a.archived ? 1 : 0) - (b.archived ? 1 : 0) || view.byName(a, b) })

  function projectsOf(customerId) {
    return db.projects
      .filter(function(p) { return p.customerId === customerId && (view.showArchived || !p.archived) })
      .sort(function(a, b) { return (a.archived ? 1 : 0) - (b.archived ? 1 : 0) || view.byName(a, b) })
  }

  readonly property int archivedCount: db.customers.filter(function(c) { return c.archived }).length
    + db.projects.filter(function(p) {
        var c = Model.byId(view.db.customers, p.customerId)
        return p.archived && c && !c.archived
      }).length

  function rateLabel(id) {
    var r = Model.byId(db.rates, id)
    return r ? r.name + " " + Model.fmtMoney(r.amount, currency) : "no rate"
  }

  function budgetLabel(p) {
    if (p.budgetType === "hours" && p.budget) return p.budget + " h budget"
    if (p.budgetType === "money" && p.budget) return Model.fmtMoney(p.budget, currency) + " budget"
    return ""
  }

  readonly property var customerOptions: db.customers.map(function(c) { return { value: c.id, label: c.name } })
  readonly property var rateOptions: db.rates.map(function(r) { return { value: r.id, label: r.name + " · " + Model.fmtMoney(r.amount, view.currency) } })
  readonly property var budgetOptions: [
    { value: "none", label: "No budget" },
    { value: "hours", label: "Hours" },
    { value: "money", label: Model.fmtMoney(0, currency).replace(/0$/, "") }
  ]

  function num(text) {
    var n = Number(String(text).replace(",", "."))
    return isNaN(n) ? 0 : n
  }

  function rateInUse(id) {
    return db.projects.some(function(p) { return p.rateId === id })
  }

  function customerInUse(id) {
    return db.projects.some(function(p) { return p.customerId === id })
  }

  spacing: Style.spacing.xl

  FontMetrics {
    id: metrics
    font.family: view.panel ? view.panel.font : Style.font.family
    font.pixelSize: Style.font.body
  }

  component Label: Text {
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    color: view.panel.dim
    font.family: view.panel.font
    font.pixelSize: Style.font.body
    verticalAlignment: Text.AlignVCenter
    height: Style.spacing.controlHeight
  }

  // Text field fed by `value` instead of a binding on `text`, so a save
  // elsewhere (a dropdown, another row) never overwrites what you are typing.
  // Commits on Enter, on leaving the field, and shortly after you stop typing.
  component Field: TextField {
    id: field
    property string value: ""
    signal commit(string text)

    function flush() {
      pending.stop()
      if (text !== value) commit(text)
    }

    property Timer pending: Timer { interval: 800; onTriggered: field.flush() }

    font.family: view.panel.font
    selectByMouse: true
    Component.onCompleted: text = value
    onValueChanged: if (!activeFocus) text = value
    onActiveFocusChanged: if (!activeFocus) { flush(); text = value }
    onTextEdited: pending.restart()
    onEditingFinished: flush()
  }

  component Picker: Dropdown {
    id: picker
    showLabel: false
    fontFamily: view.panel.font
    Connections { target: view.panel; function onScrolled() { picker.close() } }
  }

  // Every list ends in one of these.
  component AddButton: Button {
    fontFamily: view.panel.font
    bordered: true
  }

  // Pencil at the right end of a hovered row; the whole row is clickable.
  component EditHint: Text {
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    text: "󰏫"
    color: view.panel.dim
    font.family: view.panel.font
    font.pixelSize: Style.font.body
  }

  // Outline around an open editor; children stack in a padded column.
  component EditBox: Rectangle {
    id: box
    default property alias content: inner.data
    readonly property int innerWidth: width - 2 * Style.spacing.lg
    height: inner.height
    radius: Style.cornerRadius
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(view.panel.fg.r, view.panel.fg.g, view.panel.fg.b, 0.25)

    Column {
      id: inner
      x: Style.spacing.lg
      width: box.innerWidth
      topPadding: Style.spacing.lg
      bottomPadding: Style.spacing.lg
      spacing: Style.spacing.md
    }
  }

  // Archive / Delete / Done, right-aligned on an editor's last row.
  component EditActions: Row {
    id: actions
    property bool archived: false
    property bool canDelete: false
    signal archive()
    signal remove()
    signal done()

    anchors.right: parent ? parent.right : undefined
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    spacing: Style.spacing.sm

    Button {
      text: actions.archived ? "Restore" : "Archive"
      fontFamily: view.panel.font
      onClicked: actions.archive()
    }
    Button {
      visible: actions.canDelete
      text: "Delete"
      fontFamily: view.panel.font
      onClicked: actions.remove()
    }
    Button {
      text: "Done"
      fontFamily: view.panel.font
      bordered: true
      onClicked: actions.done()
    }
  }

  // ---- Targets ----
  Column {
    width: parent.width
    spacing: Style.spacing.md

    PanelSectionHeader { text: "INCOME TARGETS (EXCL. VAT)"; foreground: view.panel.fg; fontFamily: view.panel.font }

    // With a year target, each month's target follows from it and the work
    // days in that month; the fixed monthly target is only for without one.
    Row {
      spacing: Style.spacing.lg
      Label { text: "Per year"; width: view.labelW }
      Field {
        width: Style.space(140)
        value: String(view.db.targets.year || "")
        placeholderText: "e.g. 120000"
        validator: DoubleValidator { bottom: 0 }
        onCommit: view.service.setTarget("year", view.num(text))
      }
      Button {
        visible: view.db.targets.month > 0 && !view.db.targets.year
        text: "Year = 12 × month"
        fontFamily: view.panel.font
        onClicked: view.service.setTarget("year", view.db.targets.month * 12)
      }
    }

    Row {
      spacing: Style.spacing.lg
      Label { text: "Per month"; width: view.labelW }
      Field {
        visible: !(view.db.targets.year > 0)
        width: Style.space(140)
        value: String(view.db.targets.month || "")
        placeholderText: "e.g. 10000"
        validator: DoubleValidator { bottom: 0 }
        onCommit: view.service.setTarget("month", view.num(text))
      }
      Label {
        visible: view.db.targets.year > 0
        readonly property string month: Model.monthKey(view.service ? view.service.today : Model.dateKey(new Date()))
        text: "from the year, by work days after holidays: "
              + Model.fmtMoney(Model.monthTarget(view.db, month), view.currency) + " in "
              + Qt.formatDate(Model.parseKey(month + "-01"), "MMMM")
      }
    }

    // Weeks off per month. The forecast leaves them out, so a December with
    // two weeks off doesn't expect a full month of income.
    Row {
      spacing: Style.spacing.lg
      Label { text: "Holiday weeks"; width: view.labelW; anchors.verticalCenter: undefined }
      Column {
        spacing: Style.spacing.sm
        Grid {
          columns: 4
          columnSpacing: Style.spacing.lg
          rowSpacing: Style.spacing.sm
          Repeater {
            model: 12
            Row {
              id: monthCell
              required property int index
              spacing: Style.spacing.sm
              Label {
                text: Qt.locale().standaloneMonthName(monthCell.index, Locale.ShortFormat)
                width: Style.space(36)
              }
              Field {
                width: Style.space(50)
                value: String((view.db.settings.holidayWeeks || [])[monthCell.index] || 0)
                validator: DoubleValidator { bottom: 0; top: 5 }
                onCommit: {
                  var weeks = (view.db.settings.holidayWeeks || []).slice()
                  for (var i = 0; i < 12; i++) weeks[i] = Number(weeks[i]) || 0
                  weeks[monthCell.index] = Math.min(5, Math.max(0, view.num(text)))
                  view.service.setSetting("holidayWeeks", weeks)
                }
              }
            }
          }
        }
        Label {
          anchors.verticalCenter: undefined
          text: "weeks off per month, left out of the forecast (halves are fine: 0.5)"
        }
      }
    }
  }

  PanelSeparator { width: view.width; foreground: view.panel.fg }

  // ---- Rates ----
  Column {
    width: parent.width
    spacing: Style.spacing.md

    PanelSectionHeader { text: "HOURLY RATES"; foreground: view.panel.fg; fontFamily: view.panel.font }

    Repeater {
      model: view.db.rates.length
      delegate: Row {
        id: rrow
        required property int index
        readonly property var rate: view.db.rates[index] || {}
        spacing: Style.spacing.md

        Field {
          width: Style.space(320)
          value: rrow.rate.name || ""
          placeholderText: "Name"
          maximumLength: view.rateNameMax
          onCommit: view.service.updateItem("rates", rrow.rate.id, { name: text })
        }
        Field {
          width: Style.space(110)
          value: String(rrow.rate.amount || "")
          placeholderText: "per hour"
          validator: DoubleValidator { bottom: 0 }
          onCommit: view.service.updateItem("rates", rrow.rate.id, { amount: view.num(text) })
        }
        Label { text: "per hour" }
        Button {
          visible: !view.rateInUse(rrow.rate.id)
          text: "Delete"
          fontFamily: view.panel.font
          onClicked: view.service.removeItem("rates", rrow.rate.id)
        }
      }
    }

    AddButton {
      text: "+ Add rate"
      onClicked: view.service.addItem("rates", { id: Model.uid("r"), name: "Rate " + (view.db.rates.length + 1), amount: 0 })
    }
  }

  PanelSeparator { width: view.width; foreground: view.panel.fg }

  // ---- Customers & projects ----
  // One quiet line per project, grouped by customer; clicking a line opens
  // its editor. Archived customers and projects hide behind a toggle.
  Column {
    width: parent.width
    spacing: Style.spacing.md

    PanelSectionHeader { text: "CUSTOMERS & PROJECTS"; foreground: view.panel.fg; fontFamily: view.panel.font }

    Text {
      visible: view.db.rates.length === 0
      text: "Add an hourly rate first; every project needs one."
      color: view.panel.dim
      font.family: view.panel.font
      font.pixelSize: Style.font.body
    }

    Repeater {
      model: view.shownCustomers.length

      delegate: Column {
        id: cblock
        required property int index
        readonly property var customer: view.shownCustomers[index] || {}
        readonly property var projects: view.projectsOf(customer.id)
        readonly property bool editing: view.editingCustomer === customer.id
        width: view.width
        spacing: Style.spacing.xxs
        topPadding: index > 0 ? Style.spacing.md : 0

        // Customer name, or its editor.
        Rectangle {
          visible: !cblock.editing
          width: parent.width
          height: view.lineH
          radius: Style.cornerRadius
          color: customerMouse.containsMouse ? Style.hoverFill : "transparent"

          Text {
            x: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            text: (cblock.customer.name || "") + (cblock.customer.archived ? "  (archived)" : "")
            textFormat: Text.PlainText
            color: view.panel.fg
            opacity: cblock.customer.archived ? 0.55 : 1
            font.family: view.panel.font
            font.pixelSize: Style.font.body
            font.bold: true
          }
          EditHint { visible: customerMouse.containsMouse }

          MouseArea {
            id: customerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { view.editingProject = ""; view.editingCustomer = cblock.customer.id }
          }
        }

        EditBox {
          visible: cblock.editing
          width: parent.width

          Item {
            width: parent.width
            height: Style.spacing.controlHeight

            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.md
              Label { text: "Customer"; width: view.editLabelW }
              Field {
                width: Style.space(320)
                value: cblock.customer.name || ""
                placeholderText: "Customer name"
                onCommit: view.service.updateItem("customers", cblock.customer.id, { name: text })
                onVisibleChanged: if (visible && cblock.customer.name === "New customer") { forceActiveFocus(); selectAll() }
              }
            }

            EditActions {
              archived: !!cblock.customer.archived
              canDelete: !view.customerInUse(cblock.customer.id)
              onArchive: {
                view.service.updateItem("customers", cblock.customer.id, { archived: !cblock.customer.archived })
                view.editingCustomer = ""
              }
              onRemove: {
                view.service.removeItem("customers", cblock.customer.id)
                view.editingCustomer = ""
              }
              onDone: view.editingCustomer = ""
            }
          }
        }

        Repeater {
          model: cblock.projects.length

          delegate: Item {
            id: prow
            required property int index
            readonly property var project: cblock.projects[index] || {}
            readonly property bool editing: view.editingProject === project.id
            width: view.width
            height: editing ? editor.height + Style.spacing.xs * 2 : view.lineH

            // Summary line
            Rectangle {
              visible: !prow.editing
              anchors.fill: parent
              radius: Style.cornerRadius
              color: lineMouse.containsMouse ? Style.hoverFill : "transparent"
              opacity: prow.project.archived ? 0.55 : 1

              Row {
                anchors.verticalCenter: parent.verticalCenter
                x: view.indent

                Text {
                  width: view.nameColW
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: prow.project.name || ""
                  color: view.panel.fg
                  font.family: view.panel.font
                  font.pixelSize: Style.font.body
                }
                Text {
                  width: view.rateColW
                  elide: Text.ElideRight
                  text: view.rateLabel(prow.project.rateId)
                  color: view.panel.dim
                  font.family: view.panel.font
                  font.pixelSize: Style.font.body
                }
                Text {
                  width: view.budgetColW
                  elide: Text.ElideRight
                  text: [view.budgetLabel(prow.project), prow.project.billable === false ? "internal" : "",
                         prow.project.archived ? "archived" : ""].filter(function(s) { return s }).join(" · ")
                  color: view.panel.dim
                  font.family: view.panel.font
                  font.pixelSize: Style.font.body
                }
              }

              EditHint { visible: lineMouse.containsMouse }

              MouseArea {
                id: lineMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { view.editingCustomer = ""; view.editingProject = prow.project.id }
              }
            }

            // Editor
            EditBox {
              id: editor
              visible: prow.editing
              y: Style.spacing.xs
              width: parent.width

              Row {
                spacing: Style.spacing.md
                Label { text: "Name"; width: view.editLabelW }
                Field {
                  width: editor.innerWidth - view.editLabelW - view.ratePickerW - Style.space(50) - 3 * Style.spacing.md
                  value: prow.project.name || ""
                  placeholderText: "Project name"
                  onCommit: view.service.updateItem("projects", prow.project.id, { name: text })
                  onVisibleChanged: if (visible && prow.project.name === "New project") { forceActiveFocus(); selectAll() }
                }
                Label { text: "Rate"; width: Style.space(50) }
                Picker {
                  width: view.ratePickerW
                  options: view.rateOptions
                  value: prow.project.rateId || ""
                  onChanged: function(v) { view.service.updateItem("projects", prow.project.id, { rateId: v }) }
                }
              }

              Row {
                spacing: Style.spacing.md
                Label { text: "Budget"; width: view.editLabelW }
                ButtonGroup {
                  anchors.verticalCenter: parent.verticalCenter
                  fontFamily: view.panel.font
                  options: view.budgetOptions
                  value: prow.project.budgetType || "none"
                  onChanged: function(v) { view.service.updateItem("projects", prow.project.id, { budgetType: v }) }
                }
                Field {
                  visible: (prow.project.budgetType || "none") !== "none"
                  width: Style.space(110)
                  value: String(prow.project.budget || "")
                  placeholderText: prow.project.budgetType === "hours" ? "hours" : "amount"
                  validator: DoubleValidator { bottom: 0 }
                  onCommit: view.service.updateItem("projects", prow.project.id, { budget: view.num(text) })
                }
                Item { width: Style.spacing.xl; height: 1 }
                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  checked: prow.project.billable !== false
                  onToggled: view.service.updateItem("projects", prow.project.id, { billable: prow.project.billable === false })
                }
                Label { text: prow.project.billable !== false ? "Billable" : "Internal" }
              }

              Item {
                width: editor.innerWidth
                height: Style.spacing.controlHeight

                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.md
                  Label { text: "Customer"; width: view.editLabelW }
                  Picker {
                    width: view.pickerW
                    options: view.customerOptions
                    value: prow.project.customerId || ""
                    onChanged: function(v) { view.service.updateItem("projects", prow.project.id, { customerId: v }) }
                  }
                }

                EditActions {
                  archived: !!prow.project.archived
                  canDelete: !view.service.projectHasHours(prow.project.id)
                  onArchive: {
                    view.service.updateItem("projects", prow.project.id, { archived: !prow.project.archived })
                    view.editingProject = ""
                  }
                  onRemove: {
                    view.service.removeItem("projects", prow.project.id)
                    view.editingProject = ""
                  }
                  onDone: view.editingProject = ""
                }
              }
            }
          }
        }

        AddButton {
          visible: !cblock.customer.archived && view.db.rates.length > 0
          x: view.indent
          text: "+ Add project"
          onClicked: {
            var id = Model.uid("p")
            view.service.addItem("projects", {
              id: id, customerId: cblock.customer.id, name: "New project",
              rateId: view.db.rates[0].id, billable: true, budgetType: "none", budget: 0, archived: false
            })
            view.editingCustomer = ""
            view.editingProject = id
          }
        }
      }
    }

    Row {
      spacing: Style.spacing.md
      topPadding: Style.spacing.md

      AddButton {
        text: "+ Add customer"
        onClicked: {
          var id = Model.uid("c")
          view.service.addItem("customers", { id: id, name: "New customer", archived: false })
          view.editingProject = ""
          view.editingCustomer = id
        }
      }
      Button {
        visible: view.archivedCount > 0
        text: view.showArchived ? "Hide archived" : "Show " + view.archivedCount + " archived"
        fontFamily: view.panel.font
        onClicked: view.showArchived = !view.showArchived
      }
    }
  }

  PanelSeparator { width: view.width; foreground: view.panel.fg }

  // ---- Settings ----
  Column {
    width: parent.width
    spacing: Style.spacing.md

    PanelSectionHeader { text: "SETTINGS"; foreground: view.panel.fg; fontFamily: view.panel.font }

    Row {
      spacing: Style.spacing.lg
      Label { text: "Idle check after"; width: view.labelW }
      Field {
        width: Style.space(70)
        value: String(view.db.settings.idleMinutes)
        validator: IntValidator { bottom: 0; top: 240 }
        onCommit: view.service.setSetting("idleMinutes", Math.round(view.num(text)))
      }
      Label { text: "minutes without input while a timer runs (0 = off)" }
    }

    // Which calendar meetings Week asks about, and how.
    Row {
      spacing: Style.spacing.lg
      Label { text: "Week asks about"; width: view.labelW }
      Field {
        width: Style.space(70)
        value: String(view.db.settings.askWorkDays)
        validator: IntValidator { bottom: 1; top: 31 }
        onCommit: view.service.setSetting("askWorkDays", Math.max(1, Math.round(view.num(text))))
      }
      Label { text: "work days of meetings, today included" }
    }

    Row {
      spacing: Style.spacing.lg
      Label { text: "Calendar tab shows"; width: view.labelW }
      Field {
        width: Style.space(70)
        value: String(view.db.settings.lookbackDays)
        validator: IntValidator { bottom: 1; top: 365 }
        onCommit: view.service.setSetting("lookbackDays", Math.max(1, Math.round(view.num(text))))
      }
      Label { text: "days of meetings to browse and book" }
    }

    Row {
      spacing: Style.spacing.lg
      Label { text: "One-off meetings"; width: view.labelW }
      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: !!view.db.settings.askOneOff
        onToggled: view.service.setSetting("askOneOff", !view.db.settings.askOneOff)
      }
      Label { text: "ask about meetings that don't repeat too, not only linked series" }
    }

    Row {
      spacing: Style.spacing.lg
      Label { text: "Guess the project"; width: view.labelW }
      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: !!view.db.settings.guessProject
        onToggled: view.service.setSetting("guessProject", !view.db.settings.guessProject)
      }
      Label { text: "for a one-off, the project named in its title; otherwise the bar's project" }
    }

    Row {
      spacing: Style.spacing.lg
      Label { text: "Skip timed meetings"; width: view.labelW }
      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: !!view.db.settings.skipTimerCovered
        onToggled: view.service.setSetting("skipTimerCovered", !view.db.settings.skipTimerCovered)
      }
      Label { text: "don't ask about a meeting when the timer ran for at least half of it" }
    }

    Row {
      spacing: Style.spacing.lg
      Label { text: "Calls from On Air"; width: view.labelW }
      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: !!view.db.settings.onAir
        onToggled: view.service.setSetting("onAir", !view.db.settings.onAir)
      }
      Label { text: "book a camera or microphone call as a meeting (needs the On Air plugin and its hook)" }
    }

    Row {
      visible: !!view.db.settings.onAir
      spacing: Style.spacing.lg
      Label { text: "Time linked calls"; width: view.labelW }
      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: !!view.db.settings.autoBookCalls
        onToggled: view.service.setSetting("autoBookCalls", !view.db.settings.autoBookCalls)
      }
      Label { text: "during a linked meeting, start and stop the timer without asking" }
    }

    Row {
      spacing: Style.spacing.lg
      Label { text: "Meeting timer from"; width: view.labelW }
      ButtonGroup {
        fontFamily: view.panel.font
        options: [
          { value: "start", label: "Meeting start" },
          { value: "now", label: "When I click ▶" }
        ]
        value: view.db.settings.meetingTimerFrom === "now" ? "now" : "start"
        onChanged: function(v) { view.service.setSetting("meetingTimerFrom", v) }
      }
    }

    Row {
      spacing: Style.spacing.lg
      Label { text: "Calendar cache"; width: view.labelW }
      Field {
        width: view.wideW
        value: view.db.settings.calendarCache
        onCommit: view.service.setSetting("calendarCache", text)
      }
    }

    // Five quick clicks on this line switch between your data and demo data.
    Text {
      text: "Data: " + (view.service ? view.service.dataPath.replace(Quickshell.env("HOME"), "~") : "")
      color: view.panel.faint
      font.family: view.panel.font
      font.pixelSize: Style.font.caption

      property int clicks: 0
      property real firstClick: 0
      MouseArea {
        anchors.fill: parent
        onClicked: {
          var t = Date.now()
          if (t - parent.firstClick > 2000) { parent.firstClick = t; parent.clicks = 0 }
          if (++parent.clicks >= 5) {
            parent.clicks = 0
            view.service.setDemo(!view.service.demo)
          }
        }
      }
    }
  }

  PanelSeparator { width: view.width; foreground: view.panel.fg }

  // ---- Backup ----
  Column {
    width: parent.width
    spacing: Style.spacing.md

    PanelSectionHeader { text: "BACKUP"; foreground: view.panel.fg; fontFamily: view.panel.font }

    Row {
      spacing: Style.spacing.lg
      Label { text: "Git history"; width: view.labelW }
      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: !!view.db.settings.backup
        onToggled: {
          view.service.setSetting("backup", !view.db.settings.backup)
          if (view.db.settings.backup) view.service.backupNow()
        }
      }
      Label { text: "commit the data file a few minutes after each change" }
    }

    Row {
      visible: !!view.db.settings.backup
      spacing: Style.spacing.lg
      Label { text: "Remote"; width: view.labelW }
      Field {
        width: view.wideW
        value: view.db.settings.backupRemote || ""
        placeholderText: "Optional, e.g. git@github.com:you/hours-data.git (keep it private)"
        onCommit: view.service.setSetting("backupRemote", text.trim())
      }
    }

    Row {
      visible: !!view.db.settings.backup
      spacing: Style.spacing.lg
      Item { width: view.labelW; height: 1 }
      Button {
        iconText: "󰓦"
        iconSpinning: !!(view.service && view.service.backupRunning)
        text: view.service && view.service.backupRunning ? "Backing up…" : "Back up now"
        fontFamily: view.panel.font
        bordered: true
        onClicked: view.service.backupNow()
      }
    }

    Row {
      visible: !!view.db.settings.backup
      spacing: Style.spacing.lg
      Item { width: view.labelW; height: 1 }
      Text {
        width: view.wideW
        wrapMode: Text.WrapAnywhere
        textFormat: Text.PlainText
        text: !view.service || !view.service.backupAt ? "Not backed up since the shell started"
            : "Last run " + Qt.formatDateTime(new Date(view.service.backupAt), "ddd d MMM HH:mm") + "\n" + view.service.backupResult
        color: view.service && view.service.backupFailed ? view.panel.urgent : view.panel.dim
        font.family: view.panel.font
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
