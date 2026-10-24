import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Targets, rates, customers, projects and settings. Fields save when you
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

  // ---- Targets ----
  Column {
    width: parent.width
    spacing: Style.spacing.md

    PanelSectionHeader { text: "INCOME TARGETS (EXCL. VAT)"; foreground: view.panel.fg; fontFamily: view.panel.font }

    Row {
      spacing: Style.spacing.lg
      Label { text: "Per month"; width: view.labelW }
      Field {
        width: Style.space(140)
        value: String(view.db.targets.month || "")
        placeholderText: "e.g. 10000"
        validator: DoubleValidator { bottom: 0 }
        onCommit: view.service.setTarget("month", view.num(text))
      }
      Label { text: "Per year"; leftPadding: Style.spacing.xxl }
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

    Button {
      text: "+ Add rate"
      fontFamily: view.panel.font
      bordered: true
      onClicked: view.service.addItem("rates", { id: Model.uid("r"), name: "Rate " + (view.db.rates.length + 1), amount: 0 })
    }
  }

  PanelSeparator { width: view.width; foreground: view.panel.fg }

  // ---- Customers ----
  Column {
    width: parent.width
    spacing: Style.spacing.md

    PanelSectionHeader { text: "CUSTOMERS"; foreground: view.panel.fg; fontFamily: view.panel.font }

    Repeater {
      model: view.db.customers.length
      delegate: Row {
        id: crow
        required property int index
        readonly property var customer: view.db.customers[index] || {}
        spacing: Style.spacing.md

        Field {
          width: Style.space(320)
          value: crow.customer.name || ""
          placeholderText: "Name"
          opacity: crow.customer.archived ? 0.5 : 1
          onCommit: view.service.updateItem("customers", crow.customer.id, { name: text })
        }
        Button {
          text: crow.customer.archived ? "Restore" : "Archive"
          fontFamily: view.panel.font
          onClicked: view.service.updateItem("customers", crow.customer.id, { archived: !crow.customer.archived })
        }
        Button {
          visible: !view.customerInUse(crow.customer.id)
          text: "Delete"
          fontFamily: view.panel.font
          onClicked: view.service.removeItem("customers", crow.customer.id)
        }
      }
    }

    Button {
      text: "+ Add customer"
      fontFamily: view.panel.font
      bordered: true
      onClicked: view.service.addItem("customers", { id: Model.uid("c"), name: "Customer " + (view.db.customers.length + 1), archived: false })
    }
  }

  PanelSeparator { width: view.width; foreground: view.panel.fg }

  // ---- Projects ----
  Column {
    width: parent.width
    spacing: Style.spacing.lg

    PanelSectionHeader { text: "PROJECTS"; foreground: view.panel.fg; fontFamily: view.panel.font }

    Repeater {
      model: view.db.projects.length
      delegate: Column {
        id: prow
        required property int index
        readonly property var project: view.db.projects[index] || {}
        spacing: Style.spacing.sm
        opacity: project.archived ? 0.55 : 1

        Row {
          spacing: Style.spacing.md

          Picker {
            width: view.pickerW
            options: view.customerOptions
            value: prow.project.customerId || ""
            onChanged: function(v) { view.service.updateItem("projects", prow.project.id, { customerId: v }) }
          }
          Field {
            width: view.width - 2 * view.pickerW - 2 * Style.spacing.md
            value: prow.project.name || ""
            placeholderText: "Project name"
            onCommit: view.service.updateItem("projects", prow.project.id, { name: text })
          }
          Picker {
            width: view.pickerW
            options: view.rateOptions
            value: prow.project.rateId || ""
            onChanged: function(v) { view.service.updateItem("projects", prow.project.id, { rateId: v }) }
          }
        }

        Row {
          spacing: Style.spacing.md

          ToggleSwitch {
            anchors.verticalCenter: parent.verticalCenter
            checked: prow.project.billable !== false
            onToggled: view.service.updateItem("projects", prow.project.id, { billable: prow.project.billable === false })
          }
          Label { text: prow.project.billable !== false ? "Billable" : "Internal"; width: Style.space(60) }

          ButtonGroup {
            anchors.verticalCenter: parent.verticalCenter
            fontFamily: view.panel.font
            options: view.budgetOptions
            value: prow.project.budgetType || "none"
            onChanged: function(v) { view.service.updateItem("projects", prow.project.id, { budgetType: v }) }
          }
          Field {
            visible: (prow.project.budgetType || "none") !== "none"
            width: Style.space(100)
            value: String(prow.project.budget || "")
            placeholderText: prow.project.budgetType === "hours" ? "hours" : "amount"
            validator: DoubleValidator { bottom: 0 }
            onCommit: view.service.updateItem("projects", prow.project.id, { budget: view.num(text) })
          }
          Button {
            text: prow.project.archived ? "Restore" : "Archive"
            fontFamily: view.panel.font
            onClicked: view.service.updateItem("projects", prow.project.id, { archived: !prow.project.archived })
          }
          Button {
            visible: !view.service.projectHasHours(prow.project.id)
            text: "Delete"
            fontFamily: view.panel.font
            onClicked: view.service.removeItem("projects", prow.project.id)
          }
        }
      }
    }

    Text {
      visible: view.db.customers.length === 0 || view.db.rates.length === 0
      text: "Add a rate and a customer first."
      color: view.panel.dim
      font.family: view.panel.font
      font.pixelSize: Style.font.body
    }

    Button {
      visible: view.db.customers.length > 0 && view.db.rates.length > 0
      text: "+ Add project"
      fontFamily: view.panel.font
      bordered: true
      onClicked: view.service.addItem("projects", {
        id: Model.uid("p"), customerId: view.db.customers[0].id, name: "New project",
        rateId: view.db.rates[0].id, billable: true, budgetType: "none", budget: 0, archived: false
      })
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

    Row {
      spacing: Style.spacing.lg
      Label { text: "Calendar look-back"; width: view.labelW }
      Field {
        width: Style.space(70)
        value: String(view.db.settings.lookbackDays)
        validator: IntValidator { bottom: 1; top: 365 }
        onCommit: view.service.setSetting("lookbackDays", Math.max(1, Math.round(view.num(text))))
      }
      Label { text: "days" }
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

    Text {
      text: "Data: " + (view.service ? view.service.dataPath.replace(Quickshell.env("HOME"), "~") : "")
      color: view.panel.faint
      font.family: view.panel.font
      font.pixelSize: Style.font.caption
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
        id: backupButton
        text: view.service && view.service.backupRunning ? "Backing up…" : "Back up now"
        fontFamily: view.panel.font
        onClicked: view.service.backupNow()
      }
      Label {
        text: !view.service || !view.service.backupAt ? "Not backed up since the shell started"
            : "Last run " + Qt.formatDateTime(new Date(view.service.backupAt), "HH:mm") + ": " + view.service.backupResult
        color: view.service && view.service.backupFailed ? view.panel.urgent : view.panel.dim
        elide: Text.ElideMiddle
        width: view.wideW - backupButton.width - Style.spacing.lg
      }
    }
  }
}
