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

  readonly property string barShows: setting("barShows", "income")

  readonly property string label: {
    var s = service
    if (!s || !s.loaded) return "󱎫"
    var warn = s.pendingIdle ? "  " : ""
    if (s.timer) {
      var p = s.timerProject
      return warn + "󱎫 " + (p ? p.name : "?") + " " + Model.fmtHours(s.timerMinutes)
    }
    if (s.suggestions.length > 0 && barShows !== "icon") return "󰃰 " + s.suggestions.length
    if (barShows === "hours") return "󱎫 " + Model.fmtHours(s.monthTotals.minutes)
    if (barShows === "income") {
      var cur = s.db.settings.currency
      var target = s.db.targets.month
      return "󱎫 " + Model.fmtMoneyShort(s.monthTotals.income, cur) + (target > 0 ? "/" + Model.fmtMoneyShort(target, cur).replace(/^\D+/, "") : "")
    }
    return "󱎫"
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

  implicitWidth: button.implicitWidth
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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "󱎫" : root.label
    active: !!(root.service && root.service.timer)
    tooltipText: root.service && root.service.timer ? "Left: panel · Right: stop timer" : "Left: panel · Right: restart last timer"

    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.service) root.service.toggleTimer("") }
      else if (panelLoader.item) panelLoader.item.toggle()
    }
  }
}
