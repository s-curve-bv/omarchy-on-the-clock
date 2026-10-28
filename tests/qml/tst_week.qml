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
    signal scrolled()
    function focusGrid() { focusGridCalls++ }
  }

  Component { id: serviceComponent; Plugin.Service {} }
  Component { id: weekComponent; Plugin.WeekView { width: 860 } }
  Component { id: callComponent; Plugin.CallPrompt { width: 860 } }

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

  // The keys as a US layout sends them: shift+= is Key_Plus with shift,
  // shift+- is Key_Underscore. A plain + (numpad, other layouts) is 0:15.
  function test_shiftStepsAnHour_data() {
    return [
      { tag: "=", key: Qt.Key_Equal, mods: Qt.NoModifier, minutes: 15 },
      { tag: "+", key: Qt.Key_Plus, mods: Qt.NoModifier, minutes: 15 },
      { tag: "shift+=", key: Qt.Key_Plus, mods: Qt.ShiftModifier, minutes: 60 },
      { tag: "shift+= as Equal", key: Qt.Key_Equal, mods: Qt.ShiftModifier, minutes: 60 },
      { tag: "shift+-", key: Qt.Key_Underscore, mods: Qt.ShiftModifier, minutes: -60 },
      { tag: "-", key: Qt.Key_Minus, mods: Qt.NoModifier, minutes: -15 }
    ]
  }

  function test_shiftStepsAnHour(row) {
    week.addToCursor(120)
    verify(week.handleKey(row.key, row.mods))
    compare(saved().entries[today()].p2, 120 + row.minutes)
  }

  // Enter picks the project the bar starts; moving alone doesn't.
  function test_enterMakesTheCursorTheBarProject() {
    compare(service.selectedProject.id, "p2")
    verify(week.handleKey(Qt.Key_Up, Qt.NoModifier))
    compare(service.selectedProject.id, "p2")
    verify(week.handleKey(Qt.Key_Return, Qt.NoModifier))
    compare(service.selectedProject.id, "p1")
    compare(saved().settings.lastProjectId, "p1")
    compare(service.timer, null, "selecting doesn't start the timer")
    service.toggleTimer()
    compare(service.timer.projectId, "p1")
  }

  // Every MeetingRow in the view, in order.
  function meetingRows(item, out) {
    out = out || []
    for (const c of item.children) {
      if (c.meeting !== undefined && c.mode !== undefined) out.push(c)
      meetingRows(c, out)
    }
    return out
  }

  function test_meetingsGoingOnAndEndedShowOnTop() {
    const now = Date.now()
    const at = (min) => new Date(now + min * 60000).toISOString()
    Fs.write("/home/test/.cache/blacksheep.calendar/events.json", JSON.stringify({ events: [
      { uid: "now", title: "Alpha sync", start: at(-10), end: at(20) },
      { uid: "done", title: "Talk", start: at(-90), end: at(-30) }
    ] }))
    service = createTemporaryObject(serviceComponent, test)
    tryVerify(() => service.loaded && service.calendarAvailable)
    week = createTemporaryObject(weekComponent, test, { service: service, panel: fakePanel })
    const rows = meetingRows(week)
    compare(rows.map(r => [r.mode, r.meeting.uid, r.projectId]), [["now", "now", "p1"], ["ask", "done", "p2"]])
    service.startMeeting(rows[0].meeting, rows[0].projectId)
    tryVerify(() => meetingRows(week).filter(r => r.mode === "now").length === 0)
    compare(service.timer.projectId, "p1")
  }

  // After a call the prompt shows with the note filled in; Enter books it.
  function test_callPromptBooksOnEnter() {
    const prompt = createTemporaryObject(callComponent, test, { service: service, panel: fakePanel })
    compare(prompt.call, null)
    const from = Date.now() - 20 * 60000
    service.finishCall(from, Date.now())
    tryVerify(() => prompt.call !== null && prompt.input.activeFocus)
    compare(prompt.projectId, "p2", "the bar's project")
    verify(prompt.input.text.indexOf("Meeting (") === 0, prompt.input.text)
    keyClick(Qt.Key_Return)
    const day = Qt.formatDate(new Date(from), "yyyy-MM-dd")
    compare(saved().entries[day].p2, 15)
    compare(prompt.call, null)
    compare(fakePanel.focusGridCalls, 1)
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
