// Fictional data for demo mode and the screenshots: three customers, a year
// of hours up to `today`, and a fake calendar of recurring meetings around
// it. One finished project and one former customer are archived, with hours
// in the first months of the year so they show up when you browse back.
// Given `nowMs`, a timer has been running for 52 minutes during a meeting,
// so stopping it shows the "what did you do?" prompt with that meeting. Deterministic for a given day. Takes Model as an argument so it runs
// both in QML (demo mode) and under node (demo/make-demo.js).

function build(Model, today, calendarPath, nowMs) {
  var d = Model.defaults()
  d.rates = [{ id: "r1", name: "Development", amount: 95 }, { id: "r2", name: "Solution architecture", amount: 120 }]
  d.customers = [
    { id: "c1", name: "Northwind Logistics", archived: false },
    { id: "c2", name: "Blue Harbor Health", archived: false },
    { id: "c3", name: "Own company", archived: false },
    { id: "c4", name: "Harbor Café", archived: true }
  ]
  function project(id, customerId, name, rateId, extra) {
    var p = { id: id, customerId: customerId, name: name, rateId: rateId, billable: true,
              budgetType: "none", budget: 0, archived: false }
    for (var k in extra || {}) p[k] = extra[k]
    return p
  }
  d.projects = [
    project("p1", "c1", "Route planner API", "r1", { budgetType: "hours", budget: 320 }),
    project("p2", "c1", "Architecture review", "r2", { budgetType: "money", budget: 15000 }),
    project("p3", "c2", "Patient portal", "r1"),
    project("p4", "c2", "Weekly standup", "r1"),
    project("p5", "c3", "Admin & invoicing", "r1", { billable: false }),
    project("p6", "c1", "Legacy data migration", "r1", { budgetType: "hours", budget: 120, archived: true }),
    project("p7", "c4", "Website relaunch", "r1", { budgetType: "money", budget: 8000, archived: true })
  ]
  d.targets = { month: 10000, year: 120000 }
  d.settings.calendarCache = calendarPath
  // Marker checked by the service and backup.sh: demo data is never saved
  // over the real file or committed to the backup.
  d.settings.demo = true

  // Hours on most work days since the start of the year.
  var seed = 7
  function rnd() { return (seed = (seed * 16807) % 2147483647) / 2147483647 }
  function quarters(lo, hi) { return Math.round((lo + rnd() * (hi - lo)) * 4) * 15 }
  for (var k = today.slice(0, 4) + "-01-01"; k < today; k = Model.addDays(k, 1)) {
    var dow = Model.parseKey(k).getDay()
    if (dow === 0 || dow === 6 || rnd() < 0.08) continue
    var day = {}
    if (rnd() < 0.7) day.p1 = quarters(1.5, 4.5)
    if (rnd() < 0.3) day.p2 = quarters(1, 3)
    if (rnd() < 0.55) day.p3 = quarters(1, 3.5)
    if (dow === 2) day.p4 = 60
    if (rnd() < 0.4) day.p5 = quarters(0.25, 1)
    var month = Number(k.slice(5, 7))
    if (month <= 3 && rnd() < 0.5) day.p6 = quarters(1, 3)
    if (month >= 2 && month <= 4 && rnd() < 0.35) day.p7 = quarters(1, 2.5)
    d.entries[k] = day
  }

  // Recurring meetings from eight weeks back to five weeks ahead.
  var series = [
    { id: "demo-standup", title: "Blue Harbor · weekly standup", dow: 2, h: 9, m: 30, len: 30, every: 1 },
    { id: "demo-review", title: "Northwind sprint review", dow: 4, h: 14, m: 0, len: 60, every: 2 },
    { id: "demo-arch", title: "Architecture board", dow: 1, h: 11, m: 0, len: 90, every: 2 },
    { id: "demo-lunch", title: "Team lunch", dow: 5, h: 12, m: 0, len: 60, every: 1 }
  ]
  var first = Model.addDays(Model.weekStart(today), -56)
  var events = []
  for (var i = 0; i < series.length; i++) {
    var s = series[i]
    for (var w = 0; w < 13; w += s.every) {
      var key = Model.addDays(first, w * 7 + (s.dow + 6) % 7)
      var start = Model.parseKey(key)
      start.setHours(s.h, s.m, 0, 0)
      events.push({
        uid: s.id + "_" + key, title: s.title, allDay: false, recurring: true, seriesId: s.id,
        start: start.toISOString(), end: new Date(start.getTime() + s.len * 60000).toISOString(),
        status: "confirmed", response: "accepted"
      })
    }
  }
  d.calendar.links = { "demo-standup": "p4", "demo-review": "p2" }

  // Notes on this week's cells, one line per thing done.
  var lines = {
    p1: [["Pagination for /routes", "Fix flaky integration tests"], ["Route optimiser: time windows"], ["Code review with Sam", "Deploy to staging"]],
    p3: [["Consent screen", "Accessibility pass"], ["Review with the care team"]],
    p2: [["Draft target architecture"], ["Workshop with Northwind IT (whiteboard photos in Drive)"]]
  }
  for (var nk = Model.weekStart(today), n = 0; nk < today; nk = Model.addDays(nk, 1), n++)
    for (var pid in lines)
      if (Model.minutesOn(d, nk, pid)) Model.setNotes(d, nk, pid, lines[pid][n % lines[pid].length])

  if (nowMs) {
    d.timer = { projectId: "p1", startedAt: nowMs - 52 * 60000 }
    d.settings.lastProjectId = "p1"
    events.push({
      uid: "demo-oneoff", title: "Route planner design review", allDay: false, recurring: false, seriesId: null,
      start: new Date(nowMs - 40 * 60000).toISOString(), end: new Date(nowMs - 10 * 60000).toISOString(),
      status: "confirmed", response: "accepted"
    })
  }

  // A one-off on the last work day before today, which Week asks about
  // and books on the project named in its title.
  var prev = Model.addDays(today, -1)
  while (!Model.isWorkDay(prev, d.settings.workDays)) prev = Model.addDays(prev, -1)
  var review = Model.parseKey(prev)
  review.setHours(15, 0, 0, 0)
  events.push({
    uid: "demo-portal-review", title: "Patient portal: accessibility review", allDay: false, recurring: false, seriesId: null,
    start: review.toISOString(), end: new Date(review.getTime() + 45 * 60000).toISOString(),
    status: "confirmed", response: "accepted"
  })

  // Meetings before the days Week asks about were booked; those since wait.
  var now = Model.parseKey(today).getTime() + 14 * 3600000
  var since = Model.askSince(now, d.settings.askWorkDays, d.settings.workDays)
  var asked = d.settings.askWorkDays
  d.settings.askWorkDays = 31
  var open = Model.suggestions(d, events, now)
  d.settings.askWorkDays = asked
  for (var j = 0; j < open.length; j++) if (open[j].start < since) d.calendar.decided[open[j].uid] = "confirmed"

  return { hours: d, events: events }
}

if (typeof module !== "undefined") {
  module.exports = { build: build }
}
