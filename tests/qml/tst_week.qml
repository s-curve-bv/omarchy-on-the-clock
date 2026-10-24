pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import TestSupport
import "../.." as Plugin
import "../../Model.js" as Model

// The real WeekView with the real Service and Omarchy's own UI parts:
// the keyboard cursor, the timer rule and notes.
TestCase {
  id: test
  name: "Week"
  when: windowShown
  width: 900
  height: 700

  readonly property string dataPath: "/home/test/.local/share/on-the-clock/hours.json"

  // Stands in for Panel.qml: colours, font and focusGrid().
  QtObject {
    id: fakePanel
    property color fg: "#dddddd"
    property color dim: "#999999"
    property color faint: "#666666"
    property color accent: "#7fbbb3"
    property color urgent: "#e67e80"
    property string font: "monospace"
    property int focusGridCalls: 0
    function focusGrid() { focusGridCalls++ }
  }

  Component { id: serviceComponent; Plugin.Service {} }
  Component { id: weekComponent; Plugin.WeekView { width: 860 } }

  property var service: null
  property var week: null

  function today() { return Model.dateKey(new Date()) }
  function saved() { return JSON.parse(Fs.read(dataPath)) }
  function type(text) { for (const c of text) keyClick(c) }

  function init() {
    Fs.reset()
    fakePanel.focusGridCalls = 0
    Fs.write(dataPath, JSON.stringify({
      rates: [{ id: "r1", name: "Dev", amount: 100 }],
      customers: [{ id: "c1", name: "Acme", archived: false }],
      projects: [
        { id: "p1", customerId: "c1", name: "Alpha", rateId: "r1", billable: true, archived: false },
        { id: "p2", customerId: "c1", name: "Beta", rateId: "r1", billable: true, archived: false }
      ],
      entries: {}, settings: { lastProjectId: "p2" }
    }))
    service = createTemporaryObject(serviceComponent, test)
    tryVerify(() => service.loaded)
    week = createTemporaryObject(weekComponent, test, { service: service, panel: fakePanel })
    verify(week)
    week.resetCursor()
  }

  function test_cursorStartsOnTodayAndTheLastProject() {
    compare(week.cursorDay, today())
    compare(week.cursorId, "p2")
    verify(week.isCurrentWeek)
  }

  function test_upAndDownMoveBetweenProjects() {
    week.moveCursor(-1)
    compare(week.cursorId, "p1")
    week.moveCursor(-1)
    compare(week.cursorId, "p1", "should stop at the first project")
    week.moveCursor(1)
    compare(week.cursorId, "p2")
  }

  function test_plusAndMinusChangeTheSelectedCell() {
    week.addToCursor(15)
    week.addToCursor(15)
    week.addToCursor(-15)
    compare(saved().entries[today()].p2, 15)
  }

  function test_movingPastMondayOpensThePreviousWeek() {
    const monday = Model.weekStart(today())
    for (let d = today(); d > monday; d = Model.addDays(d, -1)) week.moveDay(-1)
    compare(week.cursorDay, monday)
    verify(week.isCurrentWeek)
    week.moveDay(-1)
    compare(week.cursorDay, Model.addDays(monday, -1))
    verify(!week.isCurrentWeek)
  }

  // The timer books on the day it starts, so another week never starts it.
  function test_spaceInAnotherWeekGoesBackInsteadOfStarting() {
    week.weekStart = Model.addDays(week.weekStart, -7)
    week.toggleCursor()
    verify(week.isCurrentWeek)
    compare(service.timer, null)
    week.toggleCursor()
    compare(service.timer.projectId, "p2")
  }

  function test_typingANoteAddsLines() {
    week.focusNote()
    type("Standup")
    keyClick(Qt.Key_Return)
    type("PR review")
    keyClick(Qt.Key_Return)
    compare(saved().notes[today()].p2, ["Standup", "PR review"])
    keyClick(Qt.Key_Return)  // empty line: back to the grid
    compare(fakePanel.focusGridCalls, 1)
  }

  function test_escapeKeepsWhatWasTyped() {
    week.focusNote()
    type("Half a thought")
    keyClick(Qt.Key_Escape)
    compare(saved().notes[today()].p2, ["Half a thought"])
    compare(fakePanel.focusGridCalls, 1)
  }
}
