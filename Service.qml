pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model
import "Demo.js" as Demo

// Owns hours.json, the running timer, idle detection and the calendar
// suggestions. Mounted once by the shell; every bar instance (one per
// monitor) reads from it through shell.serviceFor().
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/on-the-clock"
  readonly property string realPath: dataDir + "/hours.json"

  // Demo mode swaps in fictional data from Demo.js, kept in its own folder
  // outside the data repository, with backups off. It is never remembered:
  // every shell start begins on the real file.
  property bool demo: false
  // Hides the demo banner, for screenshots.
  property bool demoQuiet: false
  readonly property string demoDir: Quickshell.env("HOME") + "/.cache/on-the-clock-demo"
  readonly property string dataPath: demo ? demoDir + "/hours.json" : realPath

  property var db: Model.defaults()
  property bool loaded: false
  // A file we cannot parse is never overwritten; the panel says so instead.
  property bool corrupt: false

  // Ticks every second while the timer runs, every 30s otherwise, so
  // elapsed labels and "today" stay current.
  property real now: Date.now()
  readonly property string today: Model.dateKey(new Date(now))

  readonly property var timer: db.timer
  readonly property var timerProject: timer ? Model.byId(db.projects, timer.projectId) : null
  readonly property real timerMinutes: timer ? Model.timerElapsedMinutes(timer, now) : 0
  readonly property var pendingIdle: timer && timer.pendingIdle ? timer.pendingIdle : null

  // The project the bar offers to start: the last one used, or the first.
  readonly property var activeProjects: db.projects
    .filter(function(p) {
      var c = Model.byId(db.customers, p.customerId)
      return !p.archived && !(c && c.archived)
    })
    .sort(function(a, b) { return root.projectLabel(a).localeCompare(root.projectLabel(b)) })
  readonly property var selectedProject: {
    var p = Model.byId(db.projects, db.settings.lastProjectId)
    return p && activeProjects.indexOf(p) !== -1 ? p : (activeProjects[0] || null)
  }

  readonly property var monthTotals: {
    var r = Model.monthRange(Model.monthKey(today))
    return Model.totals(db, r[0], r[1])
  }

  // ---- Calendar (Datebook's local cache) ----
  property var events: []
  property bool calendarAvailable: false
  readonly property string calendarPath: String(db.settings.calendarCache || "").replace(/^~/, Quickshell.env("HOME"))
  // Coarser clock for the calendar lists, so their rows are not rebuilt
  // every second while a timer runs.
  property real calendarNow: Date.now()
  readonly property var series: Model.recurringSeries(events, calendarNow)
  readonly property var suggestions: Model.suggestions(db, events, calendarNow)

  // What we last wrote, so the watcher's reload of our own save is skipped
  // instead of replacing db with an identical copy (which resets every
  // bound field in the panel).
  property string lastWritten: ""

  function save() {
    if (!loaded || corrupt) return
    // Demo data only ever goes to the demo file.
    if (!!db.settings.demo !== demo) {
      console.warn("on-the-clock: refusing to save " + (demo ? "real" : "demo") + " data to " + dataPath)
      return
    }
    lastWritten = JSON.stringify(db, null, 2) + "\n"
    store.setText(lastWritten)
    if (db.settings.backup && !demo) backupDelay.restart()
  }

  // All writes go through here: copy, change, publish, persist.
  function mutate(fn) {
    if (!loaded || corrupt) return
    var d = JSON.parse(JSON.stringify(db))
    fn(d)
    db = d
    save()
  }

  function notify(headline, description) {
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "On the Clock", "-g", "󱎫", headline, description || ""])
  }

  function projectLabel(p) {
    if (!p) return ""
    var c = Model.byId(db.customers, p.customerId)
    return (c ? c.name + " · " : "") + p.name
  }

  // ---- Grid ----
  function addMinutes(key, projectId, delta) {
    mutate(function(d) { Model.addMinutes(d, key, projectId, delta) })
  }

  // ---- Notes ----
  function addNote(key, projectId, text) {
    if (!String(text || "").trim()) return
    mutate(function(d) { Model.addNote(d, key, projectId, text) })
  }

  function setNotes(key, projectId, lines) {
    mutate(function(d) { Model.setNotes(d, key, projectId, lines) })
  }

  // After a timer stops with time booked, the panel asks what was done and
  // offers the meetings from that stretch. Not saved: a restart drops it.
  property var notePrompt: null   // { day, projectId, minutes, from, to }
  readonly property var notePromptMeetings: notePrompt ? Model.meetingsDuring(events, notePrompt.from, notePrompt.to) : []

  function askNote(project, startedAt, minutes) {
    if (!project || minutes <= 0) return
    notePrompt = { day: Model.dateKey(new Date(startedAt)), projectId: project.id, minutes: minutes, from: startedAt, to: Date.now() }
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "s-curve.on-the-clock", "{}"])
  }

  // "Yes, that meeting is what I did": add it as a line, and mark that
  // occurrence handled so Week doesn't offer to book it a second time.
  function confirmMeeting(m) {
    if (!notePrompt) return
    var p = notePrompt
    var line = m.title + " (" + Qt.formatTime(new Date(m.start), "HH:mm") + "–" + Qt.formatTime(new Date(m.end), "HH:mm") + ")"
    mutate(function(d) {
      Model.addNote(d, p.day, p.projectId, line)
      d.calendar.decided[m.uid] = "confirmed"
    })
  }

  function closeNotePrompt() { notePrompt = null }

  // ---- Timer ----
  function startTimer(projectId) {
    var booked = 0
    var previous = null
    var previousStart = 0
    mutate(function(d) {
      if (d.timer) {
        previous = Model.byId(d.projects, d.timer.projectId)
        previousStart = d.timer.startedAt
        booked = Model.stopTimer(d, Date.now())
      }
      d.timer = { projectId: projectId, startedAt: Date.now() }
      d.settings.lastProjectId = projectId
    })
    if (previous && booked > 0) {
      notify("Booked " + Model.fmtHours(booked), projectLabel(previous))
      askNote(previous, previousStart, booked)
    }
  }

  function stopTimer() {
    if (!timer) return 0
    var p = timerProject
    var startedAt = timer.startedAt
    var booked = 0
    mutate(function(d) { booked = Model.stopTimer(d, Date.now()) })
    askNote(p, startedAt, booked)
    notify(booked > 0 ? "Booked " + Model.fmtHours(booked) : "Timer stopped, under 8 minutes so nothing booked", projectLabel(p))
    return booked
  }

  // Makes a project the one the bar offers to start, without starting it.
  function selectProject(projectId) {
    var p = Model.byId(db.projects, projectId)
    if (!p || activeProjects.indexOf(p) === -1 || db.settings.lastProjectId === projectId) return
    mutate(function(d) { d.settings.lastProjectId = projectId })
  }

  function toggleTimer(projectId) {
    if (timer && (!projectId || timer.projectId === projectId)) stopTimer()
    else if (projectId || selectedProject) startTimer(projectId || selectedProject.id)
  }

  function keepIdle() {
    mutate(function(d) { if (d.timer) delete d.timer.pendingIdle })
  }

  // Shift the start forward by the idle stretch, as if the clock had paused.
  function discardIdle() {
    mutate(function(d) {
      var t = d.timer
      if (!t || !t.pendingIdle) return
      t.startedAt += Math.max(0, t.pendingIdle.to - t.pendingIdle.from)
      delete t.pendingIdle
    })
  }

  IdleMonitor {
    id: idle
    enabled: root.loaded && !!root.timer && !root.pendingIdle && root.db.settings.idleMinutes > 0
    timeout: Math.max(1, root.db.settings.idleMinutes) * 60
    respectInhibitors: true
    onIsIdleChanged: {
      if (isIdle) {
        var from = Date.now() - timeout * 1000
        root.mutate(function(d) { if (d.timer) d.timer.idleFrom = Math.max(from, d.timer.startedAt) })
      } else {
        root.resolveIdle()
      }
    }
  }

  // Turns a recorded idle start into a question. Also runs after a shell
  // restart, when the return from idle was never observed.
  function resolveIdle() {
    if (!timer || !timer.idleFrom) return
    var from = timer.idleFrom
    var to = Date.now()
    mutate(function(d) {
      if (!d.timer) return
      delete d.timer.idleFrom
      if (to - from >= 60000) d.timer.pendingIdle = { from: from, to: to }
    })
    if (to - from >= 60000)
      notify("Away for " + Model.fmtHours((to - from) / 60000) + " while the timer ran", "Open Hours to keep or discard that time")
  }

  // ---- Calendar ----
  function confirmSuggestion(s, minutes) {
    mutate(function(d) {
      Model.addMinutes(d, s.dateKey, s.projectId, minutes === undefined ? s.minutes : minutes)
      d.calendar.decided[s.uid] = "confirmed"
    })
  }

  function dismissSuggestion(s) {
    mutate(function(d) { d.calendar.decided[s.uid] = "dismissed" })
  }

  function linkSeries(seriesId, projectId) {
    mutate(function(d) {
      if (projectId) d.calendar.links[seriesId] = projectId
      else delete d.calendar.links[seriesId]
    })
  }

  // ---- Admin ----
  function addItem(list, item) {
    mutate(function(d) { d[list].push(item) })
  }

  function updateItem(list, id, fields) {
    mutate(function(d) {
      var it = Model.byId(d[list], id)
      if (it) for (var k in fields) it[k] = fields[k]
    })
  }

  function removeItem(list, id) {
    mutate(function(d) {
      d[list] = d[list].filter(function(x) { return x.id !== id })
    })
  }

  function setTarget(which, amount) {
    mutate(function(d) { d.targets[which] = Math.max(0, Number(amount) || 0) })
  }

  function setSetting(key, value) {
    mutate(function(d) { d.settings[key] = value })
  }

  function projectHasHours(id) {
    for (var k in db.entries) if (db.entries[k][id]) return true
    return false
  }

  // ---- Backup ----
  // backup.sh commits hours.json in the data folder (a git repository) and
  // pushes it when there is a remote. It runs a few minutes after the last
  // change, so a burst of edits becomes one commit, and once at startup to
  // push anything a previous run could not.
  property bool backupRunning: false
  property real backupAt: 0
  property string backupResult: ""
  property bool backupFailed: false

  function backupNow() {
    if (!db.settings.backup || demo) return
    if (backupRunning) { backupDelay.restart(); return }
    backupDelay.stop()
    backupRunning = true
    backupProc.command = ["bash", Qt.resolvedUrl("backup.sh").toString().replace(/^file:\/\//, ""),
                          dataDir, String(db.settings.backupRemote || "")]
    backupProc.running = true
  }

  Timer {
    id: backupDelay
    interval: 180000
    onTriggered: root.backupNow()
  }

  Process {
    id: backupProc
    stdout: StdioCollector { id: backupOut; waitForEnd: true }
    stderr: StdioCollector { id: backupErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.backupRunning = false
      root.backupAt = Date.now()
      root.backupFailed = exitCode !== 0
      var out = (exitCode === 0 ? backupOut.text : backupErr.text || backupOut.text).trim().split("\n")
      root.backupResult = out[out.length - 1] || (exitCode === 0 ? "done" : "failed with code " + exitCode)
      if (root.backupFailed) console.warn("on-the-clock: backup failed: " + root.backupResult)
      // Show the remote the folder already pushes to, so the setting matches.
      var m = /^pushed to (.+)$/.exec(root.backupResult)
      if (m && !root.db.settings.backupRemote) root.setSetting("backupRemote", m[1])
    }
  }

  // ---- Demo mode ----
  // Writes fresh demo files, then points the store at them; the store's
  // reload does the rest, exactly as on startup.
  function setDemo(on) {
    if (on === demo) return
    backupDelay.stop()
    if (on) {
      var built = Demo.build(Model, today, "~/.cache/on-the-clock-demo/events.json", Date.now())
      demoEvents.setText(JSON.stringify({ events: built.events }) + "\n")
      demoHours.setText(JSON.stringify(built.hours, null, 2) + "\n")
    }
    loaded = false
    lastWritten = ""
    demo = on
  }

  FileView { id: demoHours; path: root.demoDir + "/hours.json"; blockWrites: true; printErrors: false }
  FileView { id: demoEvents; path: root.demoDir + "/events.json"; blockWrites: true; printErrors: false }

  // ---- Files ----
  FileView {
    id: store
    path: root.dataPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var raw = text()
      if (root.loaded && raw === root.lastWritten) return
      var parsed = Model.parse(raw)
      if (!parsed) {
        root.corrupt = true
        console.warn("on-the-clock: " + root.dataPath + " is not valid JSON; not saving until it is fixed")
        return
      }
      root.corrupt = false
      var first = !root.loaded
      root.db = parsed
      root.loaded = true
      if (first) {
        if (parsed.timer && parsed.timer.idleFrom) root.resolveIdle()
        root.mutate(function(d) { Model.pruneDecided(d, Date.now()) })
        Qt.callLater(root.backupNow)
      }
    }
    onLoadFailed: function(error) {
      // No file yet: start empty and create it on the first change.
      if (!root.loaded) {
        root.db = Model.defaults()
        root.loaded = true
      }
    }
  }

  FileView {
    id: calendarFile
    path: root.calendarPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.calendarNow = Date.now()
        root.events = parsed && Array.isArray(parsed.events) ? parsed.events : []
        root.calendarAvailable = true
      } catch (e) {
        root.calendarAvailable = false
      }
    }
    onLoadFailed: {
      root.events = []
      root.calendarAvailable = false
    }
  }

  Timer {
    interval: root.timer ? 1000 : 30000
    running: true
    repeat: true
    onTriggered: root.now = Date.now()
  }

  Timer {
    interval: 300000
    running: true
    repeat: true
    onTriggered: root.calendarNow = Date.now()
  }

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.dataDir, root.demoDir])

  // omarchy-shell ontheclock toggle | start <project> | stop | status | backup | demo [on|off] | state
  IpcHandler {
    target: "ontheclock"

    function toggle(): string {
      root.toggleTimer("")
      return root.timer ? "running " + root.projectLabel(root.timerProject) : "stopped"
    }

    function stop(): string {
      return root.timer ? "booked " + Model.fmtHours(root.stopTimer()) : "not running"
    }

    // Matches a project by id or by a case-insensitive part of "Customer · Project".
    function start(query: string): string {
      var q = String(query || "").toLowerCase()
      var hit = null
      for (var i = 0; i < root.db.projects.length && !hit; i++) {
        var p = root.db.projects[i]
        if (p.archived) continue
        if (p.id === query || root.projectLabel(p).toLowerCase().indexOf(q) !== -1) hit = p
      }
      if (!hit) return "no project matches " + query
      root.startTimer(hit.id)
      return "running " + root.projectLabel(hit)
    }

    function backup(): string {
      if (!root.db.settings.backup) return "backup is off; turn it on in Admin"
      root.backupNow()
      return "backup started"
    }

    // on | off | toggle | quiet (on, without the banner; for screenshots)
    function demo(state: string): string {
      root.demoQuiet = state === "quiet"
      root.setDemo(state === "on" || state === "quiet" ? true : state === "off" ? false : !root.demo)
      return root.demo ? "demo data" : "real data"
    }

    // Read-only snapshot for tests/e2e.sh.
    function state(): string {
      return JSON.stringify({
        demo: root.demo, loaded: root.loaded, today: root.today,
        timer: root.timer, notePrompt: root.notePrompt,
        selectedProjectId: root.selectedProject ? root.selectedProject.id : null,
        entriesToday: root.db.entries[root.today] || {}, notesToday: root.db.notes[root.today] || {},
        links: root.db.calendar.links
      })
    }

    function status(): string {
      if (root.timer) return root.projectLabel(root.timerProject) + " " + Model.fmtHours(root.timerMinutes)
      return "idle, month " + Model.fmtHours(root.monthTotals.minutes) + " " + Model.fmtMoney(root.monthTotals.income, root.db.settings.currency)
    }
  }
}
