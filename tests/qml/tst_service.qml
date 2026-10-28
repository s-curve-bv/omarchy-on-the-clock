pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import TestSupport
import "../.." as Plugin

// The real Service.qml on an in-memory file system (TestSupport.Fs): what
// gets written where, and what never may be.
TestCase {
  id: test
  name: "Service"

  readonly property string dataPath: "/home/test/.local/share/on-the-clock/hours.json"
  readonly property string demoPath: "/home/test/.cache/on-the-clock-demo/hours.json"
  readonly property string calendarPath: "/home/test/.cache/blacksheep.calendar/events.json"

  Component { id: serviceComponent; Plugin.Service {} }

  function sample(extra) {
    const d = {
      rates: [{ id: "r1", name: "Dev", amount: 100 }],
      customers: [{ id: "c1", name: "Acme", archived: false }],
      projects: [
        { id: "p1", customerId: "c1", name: "Build", rateId: "r1", billable: true, archived: false },
        { id: "p2", customerId: "c1", name: "Old", rateId: "r1", billable: true, archived: true }
      ],
      entries: {}, settings: {}
    }
    return Object.assign(d, extra || {})
  }

  function start(data) {
    if (data !== undefined) Fs.write(dataPath, typeof data === "string" ? data : JSON.stringify(data))
    const s = createTemporaryObject(serviceComponent, test)
    tryVerify(() => s.loaded || s.corrupt, 2000, "service did not load")
    wait(20)  // let the first save after loading settle
    return s
  }

  function saved(path) { return JSON.parse(Fs.read(path || dataPath)) }
  function today() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }

  function init() { Fs.reset() }

  function test_savesChanges() {
    const s = start(sample())
    s.setTarget("month", 5000)
    compare(saved().targets.month, 5000)
  }

  // A save is reloaded by the file watcher. That reload must not replace
  // db, or every field bound to it would be reset while you type.
  function test_ownSaveKeepsDb() {
    const s = start(sample())
    s.setTarget("month", 5000)
    const after = s.db
    wait(50)
    verify(s.db === after, "db was replaced by the reload of our own save")
  }

  function test_externalChangeIsPickedUp() {
    const s = start(sample())
    Fs.write(dataPath, JSON.stringify(sample({ targets: { month: 1234, year: 0 } })))
    tryVerify(() => s.db.targets.month === 1234)
  }

  function test_corruptFileIsNeverOverwritten() {
    const s = start("{ not json")
    verify(s.corrupt)
    s.setTarget("month", 5000)
    compare(Fs.read(dataPath), "{ not json")
  }

  function test_unknownFieldsSurviveASave() {
    const s = start(sample({ fromTheFuture: { keep: true } }))
    s.setTarget("month", 1)
    compare(saved().fromTheFuture.keep, true)
  }

  function test_demoModeNeverTouchesTheRealFile() {
    const s = start(sample())
    const real = Fs.read(dataPath)
    s.setDemo(true)
    tryVerify(() => s.loaded && s.db.settings.demo === true)
    s.addMinutes(today(), "p1", 60)
    s.setTarget("month", 99)
    compare(Fs.read(dataPath), real, "demo changes reached the real file")
    compare(saved(demoPath).targets.month, 99)

    s.setDemo(false)
    tryVerify(() => s.loaded && !s.db.settings.demo)
    compare(s.db.projects[0].name, "Build")
  }

  function test_saveRefusesDemoDataOnTheRealPath() {
    const s = start(sample())
    const real = Fs.read(dataPath)
    const d = JSON.parse(JSON.stringify(s.db))
    d.settings.demo = true
    d.targets.month = 777
    s.db = d
    s.save()
    compare(Fs.read(dataPath), real)
  }

  function test_backupRunsForRealData() {
    const s = start(sample({ settings: { backup: true } }))
    Fs.commands = []
    s.backupNow()
    verify(Fs.ran("backup.sh"), "backup.sh did not run")
    tryVerify(() => !s.backupRunning)
    compare(s.backupResult, "committed locally")
  }

  function test_backupNeverRunsInDemoMode() {
    const s = start(sample({ settings: { backup: true } }))
    s.setDemo(true)
    tryVerify(() => s.loaded && s.demo)
    // Demo data has backup off; switch it on so only the demo guard is left.
    s.setSetting("backup", true)
    Fs.commands = []
    s.backupNow()
    s.setTarget("month", 1)
    wait(50)
    verify(!Fs.ran("backup.sh"), "backup ran in demo mode")
  }

  function test_stoppingBooksRoundedAndAsksWhatYouDid() {
    const s = start(sample({ timer: { projectId: "p1", startedAt: Date.now() - 50 * 60000 } }))
    Fs.commands = []
    compare(s.stopTimer(), 45)
    compare(saved().entries[today()].p1, 45)
    compare(saved().timer, null)
    verify(s.notePrompt, "no prompt after stopping")
    compare(s.notePrompt.minutes, 45)
    verify(Fs.ran("summon s-curve.on-the-clock"), "panel was not opened")
  }

  function test_shortTimerBooksNothingAndDoesNotAsk() {
    const s = start(sample({ timer: { projectId: "p1", startedAt: Date.now() - 5 * 60000 } }))
    compare(s.stopTimer(), 0)
    compare(s.notePrompt, null)
  }

  function test_meetingDuringTheTimerBecomesANote() {
    const now = Date.now()
    Fs.write(calendarPath, JSON.stringify({ events: [
      { uid: "m1", title: "Design review", start: new Date(now - 40 * 60000).toISOString(), end: new Date(now - 10 * 60000).toISOString() },
      { uid: "m2", title: "Yesterday", start: new Date(now - 30 * 3600000).toISOString(), end: new Date(now - 29 * 3600000).toISOString() }
    ] }))
    const s = start(sample({ timer: { projectId: "p1", startedAt: now - 50 * 60000 } }))
    tryVerify(() => s.calendarAvailable)
    s.stopTimer()
    compare(s.notePromptMeetings.length, 1)
    s.confirmMeeting(s.notePromptMeetings[0])
    const notes = saved().notes[today()].p1
    compare(notes.length, 1)
    verify(notes[0].indexOf("Design review (") === 0, notes[0])
    compare(saved().calendar.decided.m1, "confirmed")
    s.addNote(today(), "p1", "  Fixed the build  ")
    compare(saved().notes[today()].p1[1], "Fixed the build")
  }

  function test_startingAnotherProjectBooksTheRunningOne() {
    const s = start(sample({ timer: { projectId: "p1", startedAt: Date.now() - 30 * 60000 } }))
    s.addItem("projects", { id: "p3", customerId: "c1", name: "Next", rateId: "r1", billable: true, archived: false })
    s.startTimer("p3")
    compare(saved().entries[today()].p1, 30)
    compare(saved().timer.projectId, "p3")
    compare(s.notePrompt.projectId, "p1")
  }

  function meeting(uid, title, fromMin, toMin) {
    const now = Date.now()
    return { uid: uid, title: title, recurring: false, seriesId: null,
             start: new Date(now + fromMin * 60000).toISOString(), end: new Date(now + toMin * 60000).toISOString() }
  }

  function withNext(extra) {
    const d = sample(extra)
    d.projects.push({ id: "p3", customerId: "c1", name: "Next", rateId: "r1", billable: true, archived: false })
    return d
  }

  // ▶ on a meeting going on: the timer counts from the meeting's start, the
  // running one stops there, and the meeting isn't asked about afterwards.
  function test_startingAMeetingCountsFromItsStart() {
    Fs.write(calendarPath, JSON.stringify({ events: [meeting("m1", "Build sync", -20, 40)] }))
    const s = start(withNext({ timer: { projectId: "p3", startedAt: Date.now() - 60 * 60000 } }))
    tryVerify(() => s.currentMeetings.length === 1)
    const m = s.currentMeetings[0]
    compare(m.projectId, "p1", "guessed from the title")
    s.startMeeting(m, m.projectId)
    compare(saved().timer.projectId, "p1")
    compare(saved().timer.startedAt, m.start)
    compare(saved().entries[Qt.formatDate(new Date(m.start - 40 * 60000), "yyyy-MM-dd")].p3, 45)
    compare(saved().calendar.decided.m1, "timer")
    compare(s.currentMeetings.length, 0)
  }

  function test_meetingTimerCanStartWhenClicked() {
    Fs.write(calendarPath, JSON.stringify({ events: [meeting("m1", "Sync", -20, 40)] }))
    const s = start(withNext({ settings: { meetingTimerFrom: "now" } }))
    tryVerify(() => s.currentMeetings.length === 1)
    const before = Date.now()
    s.startMeeting(s.currentMeetings[0], "p3")
    verify(saved().timer.startedAt >= before)
    compare(saved().timer.projectId, "p3", "the picked project")
  }

  function test_oneOffBooksOnThePickedProject() {
    Fs.write(calendarPath, JSON.stringify({ events: [meeting("m1", "Talk", -90, -30)] }))
    const s = start(withNext())
    tryVerify(() => s.suggestions.length === 1)
    const m = s.suggestions[0]
    compare(m.projectId, "p1", "nothing in the title: the bar's project")
    s.pickMeetingProject(m.uid, "p3")
    s.confirmSuggestion(m, s.meetingPicks[m.uid])
    compare(saved().entries[m.dateKey].p3, 60)
    compare(saved().calendar.decided.m1, "confirmed")
    compare(s.suggestions.length, 0)
  }

  function test_didntHappenCanBeUndone() {
    Fs.write(calendarPath, JSON.stringify({ events: [meeting("m1", "Talk", -90, -30)] }))
    const s = start(sample({ settings: { askOneOff: false } }))
    tryVerify(() => s.pastMeetings.length === 1)
    compare(s.suggestions.length, 0, "one-offs are off")
    s.dismissSuggestion(s.pastMeetings[0])
    compare(s.pastMeetings[0].decided, "dismissed")
    s.undoDismiss(s.pastMeetings[0])
    compare(saved().calendar.decided, {})
  }

  // A call during a linked meeting books itself, with the meeting as note.
  function test_callDuringALinkedMeetingBooksItself() {
    const ev = meeting("m1", "CCT meeting", -60, 0)
    ev.recurring = true; ev.seriesId = "s1"
    Fs.write(calendarPath, JSON.stringify({ events: [ev] }))
    const s = start(withNext({ calendar: { links: { s1: "p3" }, decided: {} } }))
    tryVerify(() => s.calendarAvailable)
    const from = Date.now() - 58 * 60000
    s.finishCall(from, Date.now() - 2 * 60000)
    const day = Qt.formatDate(new Date(from), "yyyy-MM-dd")
    compare(saved().entries[day].p3, 60)
    verify(saved().notes[day].p3[0].indexOf("Meeting: CCT meeting (") === 0)
    compare(saved().calendar.decided.m1, "confirmed")
    compare(s.callPrompt, null)
  }

  // An ad-hoc call asks for the project, preset to the bar's.
  function test_adHocCallAsksForTheProject() {
    const s = start(withNext({ settings: { lastProjectId: "p1" } }))
    const from = Date.now() - 25 * 60000
    s.finishCall(from, Date.now())
    compare(s.callPrompt.projectId, "p1")
    compare(s.callPrompt.minutes, 30)
    compare(s.callPrompt.meeting, null)
    s.bookCall(s.callPrompt, "p3", "Call with Sam")
    const day = Qt.formatDate(new Date(from), "yyyy-MM-dd")
    compare(saved().entries[day].p3, 30)
    compare(saved().notes[day].p3, ["Call with Sam"])
    compare(s.callPrompt, null)
  }

  function sec(ms) { return String(Math.floor(ms / 1000)) }

  // Camera and microphone of one call, events doubled and out of order.
  function test_onAirSessionsMakeOneCall() {
    const s = start(withNext({ settings: { lastProjectId: "p1" } }))
    const t0 = Date.now() - 40 * 60000, t1 = t0 + 60000, end = Date.now() - 5 * 60000
    compare(s.onAirEvent("start", "mic", "zoom", sec(t0), ""), "in a call")
    compare(s.onAirEvent("start", "camera", "zoom", sec(t1), ""), "in a call")
    compare(s.onAirEvent("start", "mic", "zoom", sec(t0), ""), "known")
    compare(s.onAirEvent("start", "screen", "zoom", sec(t1), ""), "ignored")
    compare(s.onAirEvent("stop", "camera", "zoom", sec(t1), sec(end - 60000)), "in a call")
    compare(s.callPrompt, null)
    compare(s.onAirEvent("stop", "mic", "zoom", sec(t0), sec(end)), "call ended")
    compare(s.onAirEvent("stop", "mic", "zoom", sec(t0), sec(end)), "known")
    compare(s.callPrompt.from, Number(sec(t0)) * 1000)
    compare(s.callPrompt.to, Number(sec(end)) * 1000)
    compare(s.callPrompt.minutes, 30)
    compare(s.callPrompt.projectId, "p1")
  }

  // During a linked meeting the call times itself, from its real start.
  function test_callDuringALinkedMeetingStartsAndStopsTheTimer() {
    const ev = meeting("m1", "CCT meeting", -30, 30)
    ev.recurring = true; ev.seriesId = "s1"
    Fs.write(calendarPath, JSON.stringify({ events: [ev] }))
    const s = start(withNext({ calendar: { links: { s1: "p3" }, decided: {} } }))
    tryVerify(() => s.calendarAvailable)
    const t0 = Date.now() - 28 * 60000
    s.onAirEvent("start", "mic", "LibreWolf", sec(t0), "")
    compare(saved().timer.projectId, "p3")
    compare(saved().timer.startedAt, Number(sec(t0)) * 1000)
    compare(saved().calendar.decided.m1, "confirmed")
    s.onAirEvent("stop", "mic", "LibreWolf", sec(t0), sec(Date.now()))
    compare(saved().timer, null)
    const day = Qt.formatDate(new Date(t0), "yyyy-MM-dd")
    compare(saved().entries[day].p3, 30)
    verify(saved().notes[day].p3[0].indexOf("Meeting: CCT meeting (") === 0)
    compare(s.callPrompt, null)
    compare(s.notePrompt, null, "no 'what did you do?' for a call")
  }

  function test_aRunningTimerIsLeftAlone() {
    const s = start(withNext({ timer: { projectId: "p1", startedAt: Date.now() - 60 * 60000 } }))
    const t0 = Date.now() - 30 * 60000
    s.onAirEvent("start", "mic", "Slack", sec(t0), "")
    s.onAirEvent("stop", "mic", "Slack", sec(t0), sec(Date.now()))
    compare(saved().timer.projectId, "p1")
    compare(s.callPrompt, null, "the timer books that time")
  }

  // After a shell restart only the stop arrives; it is still a call.
  function test_aStopWithoutItsStartIsACall() {
    const s = start(sample())
    s.onAirEvent("stop", "camera", "zoom", sec(Date.now() - 20 * 60000), sec(Date.now()))
    compare(s.callPrompt.minutes, 15)
  }

  function test_onAirCanBeTurnedOff() {
    const s = start(sample({ settings: { onAir: false } }))
    compare(s.onAirEvent("start", "mic", "zoom", sec(Date.now()), ""), "off")
    compare(s.onAirEvent("stop", "mic", "zoom", sec(Date.now() - 20 * 60000), sec(Date.now())), "off")
    compare(s.callPrompt, null)
  }

  function test_selectedProjectSkipsArchived() {
    const s = start(sample({ settings: { lastProjectId: "p2" } }))
    compare(s.selectedProject.id, "p1")
    s.toggleTimer("")
    compare(saved().timer.projectId, "p1")
  }
}
