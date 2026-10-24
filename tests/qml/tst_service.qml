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

  function test_selectedProjectSkipsArchived() {
    const s = start(sample({ settings: { lastProjectId: "p2" } }))
    compare(s.selectedProject.id, "p1")
    s.toggleTimer("")
    compare(saved().timer.projectId, "p1")
  }
}
