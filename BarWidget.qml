import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "s-curve.on-the-clock"

  // The service is mounted by the shell, possibly after this widget, so
  // poll until the lookup answers.
  property var service: null

  function resolveService() {
    if (service) return
    var s = bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor("s-curve.on-the-clock") : null
    if (s) service = s
  }

  Timer {
    interval: 250
    running: !root.service
    repeat: true
    triggeredOnStart: true
    onTriggered: root.resolveService()
  }

  readonly property string barShows: setting("barShows", "project")

  // Text next to the play/stop button: the running project and its time,
  // or the project the button would start, or a month figure (setting).
  readonly property string label: {
    var s = service
    if (!s || !s.loaded) return "On the Clock"
    var prefix = (s.demo ? "DEMO " : "") + (s.pendingIdle ? "  " : "")
    if (s.timer) {
      var p = s.timerProject
      return prefix + (p ? p.name : "?") + " " + Model.fmtHours(s.timerMinutes)
    }
    if (barShows === "hours") return prefix + Model.fmtHours(s.monthTotals.minutes)
    if (barShows === "income") {
      var cur = s.db.settings.currency
      var target = s.db.targets.month
      return prefix + Model.fmtMoneyShort(s.monthTotals.income, cur) + (target > 0 ? "/" + Model.fmtMoneyShort(target, cur).replace(/^\D+/, "") : "")
    }
    if (barShows === "icon") return prefix
    var sel = s.selectedProject
    return prefix + (sel ? sel.name : "On the Clock")
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.service = root.service
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onServiceChanged: injectPanel()

  // Shape contract for shell summon/hide/toggle routing.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.openFromHotkey() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: root.vertical ? button.implicitWidth : row.implicitWidth
  implicitHeight: button.implicitHeight

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Play/stop for the project shown, then the label, which opens the panel.
  // Right-click on either also starts or stops. Vertical bars get a single
  // icon that opens the panel.
  Row {
    id: row
    visible: !root.vertical
    height: parent.height

    WidgetButton {
      id: playButton
      height: parent.height
      bar: root.bar
      horizontalMargin: 4
      text: root.service && root.service.timer ? "󰓛" : "󰐊"
      // The bar's active colour is the urgent red, which reads as an error.
      useActiveColor: false
      tooltipText: !root.service ? ""
        : root.service.timer ? "Stop and book " + root.service.projectLabel(root.service.timerProject)
        : root.service.selectedProject ? "Start " + root.service.projectLabel(root.service.selectedProject)
        : "Add a project in the panel first"
      onPressed: function(b) { if (root.service) root.service.toggleTimer("") }
    }

    WidgetButton {
      id: button
      height: parent.height
      bar: root.bar
      horizontalMargin: 4
      text: root.label
      useActiveColor: false
      tooltipText: "Open On the Clock"
      onPressed: function(b) {
        if (b === Qt.RightButton) { if (root.service) root.service.toggleTimer("") }
        else if (panelLoader.item) panelLoader.item.toggle()
      }
    }
  }

  WidgetButton {
    visible: root.vertical
    anchors.fill: parent
    bar: root.bar
    text: root.service && root.service.timer ? "󰓛" : "󱎫"
    useActiveColor: false
    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.service) root.service.toggleTimer("") }
      else if (panelLoader.item) panelLoader.item.toggle()
    }
  }
}
