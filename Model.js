// Pure data and date math for the hours plugin. Qt-free so it runs under node
// (tests/test_model.js); the QML owns loading, saving and rendering.
//
// Data shape (hours.json):
//   rates:     [{ id, name, amount }]
//   customers: [{ id, name, archived }]               in the order you put them
//   projects:  [{ id, customerId, name, rateId, billable, archived,
//                 budgetType: "none" | "hours" | "money", budget }]   same
//   entries:   { "YYYY-MM-DD": { projectId: minutes } }
//   notes:     { "YYYY-MM-DD": { projectId: ["what was done", ...] } }
//   targets:   { month, year }                      income, excl. VAT; with a year
//                                                   target, months are derived from it
//   timer:     null | { projectId, startedAt, idleFrom, pendingIdle: {from, to},
//                       call, seriesId }             call: started by a call, which stops it;
//                                                   seriesId: the recurring meeting it times
//   calendar:  { links: { seriesId: projectId }, ignored: { seriesId: true },   not work
//                decided: { uid: "confirmed" | "dismissed" | "timer" } }   timer: the timer covered it
//   settings:  { currency, idleMinutes, workDays: [1..5], calendarCache,
//                workStart, workEnd: "HH:MM",         work hours: calls, today's share
//                holidayWeeks: [Jan..Dec],            weeks off per month, for the forecast
//                lookbackDays,                        Calendar tab: meetings to browse
//                askWorkDays, askOneOff,              Week: which meetings it asks about
//                guessProject, skipTimerCovered, meetingTimerFrom: "start" | "now",
//                onAir, autoBookCalls,                calls reported by On Air; timed by themselves
//                                                     during a linked meeting
//                backup, backupRemote }                git history of hours.json

var QUARTER = 15

function pad(n) { return n < 10 ? "0" + n : String(n) }

function dateKey(d) {
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function parseKey(key) {
  var p = String(key).split("-")
  return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2] || 1))
}

function addDays(key, n) {
  var d = parseKey(key)
  d.setDate(d.getDate() + n)
  return dateKey(d)
}

// Monday of the week holding `key`.
function weekStart(key) {
  var d = parseKey(key)
  var dow = (d.getDay() + 6) % 7
  d.setDate(d.getDate() - dow)
  return dateKey(d)
}

function isoWeek(key) {
  var d = parseKey(key)
  d.setDate(d.getDate() + 3 - (d.getDay() + 6) % 7)   // Thursday of this week
  var jan4 = new Date(d.getFullYear(), 0, 4)
  return 1 + Math.round(((d - jan4) / 86400000 - 3 + (jan4.getDay() + 6) % 7) / 7)
}

function monthKey(key) { return String(key).slice(0, 7) }

function addMonths(mkey, n) {
  var d = parseKey(mkey + "-01")
  d.setMonth(d.getMonth() + n)
  return dateKey(d).slice(0, 7)
}

function monthRange(mkey) {
  var first = parseKey(mkey + "-01")
  var last = new Date(first.getFullYear(), first.getMonth() + 1, 0)
  return [dateKey(first), dateKey(last)]
}

function yearRange(year) {
  return [year + "-01-01", year + "-12-31"]
}

function roundQuarter(minutes) {
  return Math.max(0, Math.round(minutes / QUARTER) * QUARTER)
}

function fmtHours(minutes) {
  var m = Math.round(minutes || 0)
  var sign = m < 0 ? "-" : ""
  m = Math.abs(m)
  return sign + Math.floor(m / 60) + ":" + pad(m % 60)
}

function currencySymbol(currency) {
  var symbols = { EUR: "€", USD: "$", GBP: "£" }
  return symbols[currency] || (currency ? currency + " " : "€")
}

// Whole units with thousands separators: €12.345 (Dutch style grouping).
function fmtMoney(amount, currency) {
  var n = Math.round(amount || 0)
  var sign = n < 0 ? "-" : ""
  var s = String(Math.abs(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ".")
  return sign + currencySymbol(currency) + s
}

// Short form for the bar: €950, €6.2k, €12k.
function fmtMoneyShort(amount, currency) {
  var n = amount || 0
  var sym = currencySymbol(currency)
  if (Math.abs(n) < 1000) return sym + Math.round(n)
  var k = n / 1000
  return sym + (Math.abs(k) < 10 ? k.toFixed(1).replace(/\.0$/, "") : Math.round(k)) + "k"
}

function uid(prefix) {
  return prefix + "-" + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36)
}

function defaults() {
  return {
    version: 2,
    rates: [],
    customers: [],
    projects: [],
    entries: {},
    notes: {},
    targets: { month: 0, year: 0 },
    timer: null,
    calendar: { links: {}, ignored: {}, decided: {} },
    settings: {
      currency: "EUR",
      idleMinutes: 10,
      workDays: [1, 2, 3, 4, 5],
      workStart: "09:00",
      workEnd: "18:00",
      holidayWeeks: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      calendarCache: "~/.cache/blacksheep.calendar/events.json",
      lookbackDays: 31,
      askWorkDays: 2,
      askOneOff: true,
      guessProject: true,
      skipTimerCovered: true,
      meetingTimerFrom: "start",
      onAir: true,
      autoBookCalls: true,
      backup: false,
      backupRemote: ""
    }
  }
}

function normalize(raw) {
  var d = defaults()
  if (!raw || typeof raw !== "object") return d
  var out = {}
  // Unknown fields are kept, so data from a newer version survives a save.
  for (var u in raw) if (!(u in d)) out[u] = raw[u]
  for (var k in d) out[k] = raw[k] !== undefined && raw[k] !== null ? raw[k] : d[k]
  if (raw.timer === null || raw.timer === undefined) out.timer = null
  out.targets = Object.assign({}, d.targets, raw.targets || {})
  out.settings = Object.assign({}, d.settings, raw.settings || {})
  out.calendar = Object.assign({}, d.calendar, raw.calendar || {})
  out.calendar.links = out.calendar.links || {}
  out.calendar.ignored = out.calendar.ignored || {}
  out.calendar.decided = out.calendar.decided || {}
  // Before version 2 lists were sorted by name on screen; that becomes
  // their order, which you change in Admin from then on.
  if (!(Number(raw.version) >= 2)) {
    var byName = function(a, b) { return String(a.name).localeCompare(String(b.name)) }
    out.customers = out.customers.slice().sort(byName)
    out.projects = out.projects.slice().sort(byName)
    out.version = 2
  }
  // Notes used to be one string per cell.
  for (var nk in out.notes)
    for (var np in out.notes[nk])
      if (!Array.isArray(out.notes[nk][np])) out.notes[nk][np] = [String(out.notes[nk][np])]
  return out
}

function parse(text) {
  try { return normalize(JSON.parse(text)) } catch (e) { return null }
}

function byId(list, id) {
  for (var i = 0; i < (list || []).length; i++) if (list[i].id === id) return list[i]
  return null
}

// Projects grouped by customer, both in their own order.
function orderedProjects(data) {
  var out = []
  for (var i = 0; i < data.customers.length; i++)
    for (var j = 0; j < data.projects.length; j++)
      if (data.projects[j].customerId === data.customers[i].id) out.push(data.projects[j])
  // Projects of a customer that no longer exists go last.
  for (var k = 0; k < data.projects.length; k++)
    if (!byId(data.customers, data.projects[k].customerId)) out.push(data.projects[k])
  return out
}

// Mutates `data`: moves item `id` of `list` ("customers" or "projects") to
// just before `targetId`, or just after it with `after`.
function moveItem(data, list, id, targetId, after) {
  var arr = data[list]
  var item = byId(arr, id)
  if (!item || id === targetId || !byId(arr, targetId)) return
  arr.splice(arr.indexOf(item), 1)
  var t = arr.indexOf(byId(arr, targetId))
  arr.splice(after ? t + 1 : t, 0, item)
}

function rateFor(data, project) {
  var r = project ? byId(data.rates, project.rateId) : null
  return r ? Number(r.amount) || 0 : 0
}

function isBillable(project) { return !!project && project.billable !== false }

function minutesOn(data, key, projectId) {
  var day = data.entries[key]
  return day && day[projectId] ? day[projectId] : 0
}

// Mutates `data`: sets one day/project cell, dropping empty ones.
function setMinutes(data, key, projectId, minutes) {
  var m = Math.max(0, Math.round(minutes))
  var day = data.entries[key] || {}
  if (m > 0) day[projectId] = m
  else delete day[projectId]
  if (Object.keys(day).length) data.entries[key] = day
  else delete data.entries[key]
}

function addMinutes(data, key, projectId, minutes) {
  setMinutes(data, key, projectId, minutesOn(data, key, projectId) + minutes)
}

// Notes are lines per day and project.
function notesOn(data, key, projectId) {
  var day = data.notes[key]
  var v = day ? day[projectId] : null
  return Array.isArray(v) ? v : (v ? [String(v)] : [])
}

// Mutates `data`: replaces the lines of one day/project, dropping empty
// lines and empty cells.
function setNotes(data, key, projectId, lines) {
  var clean = (lines || []).map(function(l) { return String(l || "").trim() }).filter(function(l) { return l })
  var day = data.notes[key] || {}
  if (clean.length) day[projectId] = clean
  else delete day[projectId]
  if (Object.keys(day).length) data.notes[key] = day
  else delete data.notes[key]
}

function addNote(data, key, projectId, text) {
  setNotes(data, key, projectId, notesOn(data, key, projectId).concat([text]))
}

// Sums entries with from <= day <= to (inclusive keys; null = unbounded).
function totals(data, from, to) {
  var t = { minutes: 0, billableMinutes: 0, income: 0, byProject: {}, byCustomer: {} }
  for (var key in data.entries) {
    if (from && key < from) continue
    if (to && key > to) continue
    var day = data.entries[key]
    for (var pid in day) {
      var m = day[pid]
      var p = byId(data.projects, pid)
      var billable = isBillable(p)
      var income = billable ? m / 60 * rateFor(data, p) : 0
      t.minutes += m
      if (billable) t.billableMinutes += m
      t.income += income
      var bp = t.byProject[pid] || (t.byProject[pid] = { minutes: 0, income: 0 })
      bp.minutes += m
      bp.income += income
      var cid = p ? p.customerId : ""
      var bc = t.byCustomer[cid] || (t.byCustomer[cid] = { minutes: 0, income: 0 })
      bc.minutes += m
      bc.income += income
    }
  }
  return t
}

// Budget use over the project's whole life. Money budgets count hours x rate
// even for non-billable projects, since the budget is what the work is worth.
function budgetUsage(data, project, allTime) {
  var type = project.budgetType || "none"
  var budget = Number(project.budget) || 0
  if (type === "none" || budget <= 0) return null
  var pt = allTime.byProject[project.id] || { minutes: 0 }
  var used = type === "hours" ? pt.minutes / 60 : pt.minutes / 60 * rateFor(data, project)
  return { type: type, used: used, budget: budget, fraction: used / budget }
}

function isWorkDay(key, workDays) {
  var dow = parseKey(key).getDay() || 7   // 1 = Monday .. 7 = Sunday
  return (workDays || [1, 2, 3, 4, 5]).indexOf(dow) !== -1
}

// "HH:MM" as minutes since midnight; null when it isn't a time.
function clockMinutes(hhmm) {
  var m = /^(\d{1,2}):(\d{2})$/.exec(String(hhmm || "").trim())
  if (!m || Number(m[1]) > 24 || Number(m[2]) > 59) return null
  return Math.min(24 * 60, Number(m[1]) * 60 + Number(m[2]))
}

// Work hours from the settings as [start, end] in minutes since midnight;
// the whole day when they are missing or the wrong way round.
function workHours(settings) {
  var from = clockMinutes(settings && settings.workStart)
  var to = clockMinutes(settings && settings.workEnd)
  if (from === null || to === null || to <= from) return [0, 24 * 60]
  return [from, to]
}

// Whether `ms` falls on a work day, within work hours.
function isWorkTime(ms, settings) {
  var d = new Date(ms)
  if (!isWorkDay(dateKey(d), settings && settings.workDays)) return false
  var h = workHours(settings), m = d.getHours() * 60 + d.getMinutes()
  return m >= h[0] && m < h[1]
}

// How much of today's work hours has passed at `ms`, from 0 to 1.
function workDayDone(ms, settings) {
  var d = new Date(ms)
  var h = workHours(settings), m = d.getHours() * 60 + d.getMinutes() + d.getSeconds() / 60
  return Math.min(1, Math.max(0, (m - h[0]) / (h[1] - h[0])))
}

function workDaysBetween(from, to, workDays) {
  var n = 0
  for (var k = from; k <= to; k = addDays(k, 1)) if (isWorkDay(k, workDays)) n++
  return n
}

// Share of a month's work days that are actually worked, after
// `holidayWeeks[month - 1]` weeks off. Only the number of weeks is known, not
// which days, so every work day of the month counts for that share.
function workShare(mkey, workDays, holidayWeeks) {
  var weeks = Number((holidayWeeks || [])[Number(mkey.slice(5, 7)) - 1]) || 0
  if (weeks <= 0) return 1
  var r = monthRange(mkey)
  var total = workDaysBetween(r[0], r[1], workDays)
  var off = weeks * (workDays || [1, 2, 3, 4, 5]).length
  return total > 0 ? Math.max(0, total - off) / total : 0
}

// Work days between `from` and `to`, holidays taken off: a December with
// two weeks off counts each work day as about half a day.
function workingDaysBetween(from, to, workDays, holidayWeeks) {
  var n = 0, mkey = "", share = 1
  for (var k = from; k <= to; k = addDays(k, 1)) {
    if (!isWorkDay(k, workDays)) continue
    if (monthKey(k) !== mkey) { mkey = monthKey(k); share = workShare(mkey, workDays, holidayWeeks) }
    n += share
  }
  return n
}

// The income target for month `mkey`. A year target is spread over the
// months by their work days after holidays, so a month with two weeks off
// asks less. Without one, the fixed monthly target applies.
function monthTarget(data, mkey) {
  var year = Number(data.targets.year) || 0
  if (year <= 0) return Number(data.targets.month) || 0
  var s = data.settings, y = yearRange(mkey.slice(0, 4)), m = monthRange(mkey)
  var total = workingDaysBetween(y[0], y[1], s.workDays, s.holidayWeeks)
  return total > 0 ? year * workingDaysBetween(m[0], m[1], s.workDays, s.holidayWeeks) / total : 0
}

// Where the period ends up at the current rate. Of `today`, the share
// `todayDone` (0..1, default all of it) counts as elapsed. Day counts are
// fractional when `holidayWeeks` takes days off or today is under way.
function pace(actual, target, from, to, today, workDays, holidayWeeks, todayDone) {
  var total = workingDaysBetween(from, to, workDays, holidayWeeks)
  if (today < from) return { projected: 0, total: total, elapsed: 0, remaining: total, neededPerDay: total ? target / total : 0, started: false, done: false }
  if (today > to) return { projected: actual, total: total, elapsed: total, remaining: 0, neededPerDay: 0, started: true, done: true }
  var done = todayDone === undefined ? 1 : todayDone
  var elapsed = workingDaysBetween(from, addDays(today, -1), workDays, holidayWeeks)
              + workingDaysBetween(today, today, workDays, holidayWeeks) * done
  var remaining = total - elapsed
  var projected = elapsed > 0 ? actual / elapsed * total : actual
  var neededPerDay = remaining > 0 ? Math.max(0, target - actual) / remaining : 0
  return { projected: projected, total: total, elapsed: elapsed, remaining: remaining, neededPerDay: neededPerDay, started: true, done: false }
}

function timerElapsedMinutes(timer, nowMs) {
  if (!timer) return 0
  return Math.max(0, (nowMs - timer.startedAt) / 60000)
}

// Mutates `data`: books the running timer on the day it started, rounded to
// the nearest quarter. Returns the booked minutes. With `events` and
// skipTimerCovered on, meetings the timer covered are marked as handled.
function stopTimer(data, nowMs, events) {
  var t = data.timer
  if (!t) return 0
  var minutes = roundQuarter(timerElapsedMinutes(t, nowMs))
  if (minutes > 0 && byId(data.projects, t.projectId))
    addMinutes(data, dateKey(new Date(t.startedAt)), t.projectId, minutes)
  if (minutes > 0 && events && data.settings.skipTimerCovered) {
    for (var i = 0; i < events.length; i++) {
      var e = events[i]
      if (usableEvent(e) && !data.calendar.decided[e.uid] && covers(t.startedAt, nowMs, e))
        data.calendar.decided[e.uid] = "timer"
    }
  }
  data.timer = null
  return minutes
}

// ---------------------------------------------------------------- calendar
// Events come from Datebook's cache (blacksheep.calendar events.json):
// { uid, title, start, end, allDay, recurring, seriesId, status, response }.

function usableEvent(e) {
  return !!e && !e.allDay && e.status !== "cancelled" && e.response !== "declined"
}

// Not work, so never a meeting to book: a series marked as ignored (lunch,
// a block to keep the calendar free), or an event shown as free that isn't
// linked to a project.
function ignoredEvent(data, e) {
  var series = e && e.seriesId
  if (series && data.calendar.ignored && data.calendar.ignored[series]) return true
  return !!e && e.busy === false && !(series && data.calendar.links[series])
}

// A calendar event that counts as a meeting.
function meetingEvent(data, e) {
  return usableEvent(e) && !ignoredEvent(data, e)
}

// Meetings overlapping a stretch of time, e.g. while a timer ran; earliest
// first. With `data`, ignored meetings are left out.
function meetingsDuring(events, fromMs, toMs, data) {
  return (events || [])
    .filter(function(e) { return (data ? meetingEvent(data, e) : usableEvent(e)) && Date.parse(e.start) < toMs && Date.parse(e.end) > fromMs })
    .map(function(e) { return { uid: e.uid, title: e.title || "(no title)", start: Date.parse(e.start), end: Date.parse(e.end) } })
    .sort(function(a, b) { return a.start - b.start })
}

function eventMinutes(e) {
  return Math.max(QUARTER, roundQuarter((Date.parse(e.end) - Date.parse(e.start)) / 60000))
}

// One row per recurring series seen in the cache, most recent first.
function recurringSeries(events, nowMs) {
  var map = {}
  for (var i = 0; i < (events || []).length; i++) {
    var e = events[i]
    if (!e || !e.recurring || !e.seriesId || e.allDay) continue
    var s = map[e.seriesId]
    if (!s) s = map[e.seriesId] = { seriesId: e.seriesId, title: e.title || "(no title)", count: 0, last: 0, next: 0, minutes: eventMinutes(e) }
    s.count++
    var t = Date.parse(e.start)
    if (t <= nowMs) { if (t > s.last) { s.last = t; s.title = e.title || s.title } }
    else if (!s.next || t < s.next) s.next = t
  }
  var out = []
  for (var k in map) out.push(map[k])
  out.sort(function(a, b) { return (b.last || b.next) - (a.last || a.next) })
  return out
}

// Whether a timer that ran from `fromMs` to `toMs` covered at least half
// of the meeting.
function covers(fromMs, toMs, e) {
  var start = Date.parse(e.start), end = Date.parse(e.end)
  return Math.min(end, toMs) - Math.max(start, fromMs) >= (end - start) / 2
}

// Start of the `n`th most recent work day, today included: with n = 2 on a
// Monday, that is the Friday before.
function askSince(nowMs, n, workDays) {
  var k = dateKey(new Date(nowMs))
  for (var seen = 0, i = 0; i < 31; i++, k = addDays(k, -1)) {
    if (isWorkDay(k, workDays) && ++seen >= n) break
  }
  return parseKey(k).getTime()
}

function squash(text) { return String(text || "").toLowerCase().replace(/[^a-z0-9]/g, "") }

// The active project whose name appears in the title, the longest name if
// several do; "" when none does.
function guessProject(data, title) {
  var t = squash(title)
  var best = null
  for (var i = 0; i < data.projects.length; i++) {
    var p = data.projects[i]
    var c = byId(data.customers, p.customerId)
    var name = squash(p.name)
    if (p.archived || (c && c.archived) || name.length < 3 || t.indexOf(name) === -1) continue
    if (!best || name.length > squash(best.name).length) best = p
  }
  return best ? best.id : ""
}

// The project a meeting books on: its series' link, else (guessProject on)
// a project named in the title, else `fallbackId`.
function meetingProject(data, e, fallbackId) {
  var linked = e.seriesId ? data.calendar.links[e.seriesId] : ""
  var p = linked ? byId(data.projects, linked) : null
  if (p && !p.archived) return p.id
  return (data.settings.guessProject && guessProject(data, e.title)) || fallbackId || ""
}

// Week asks about meetings of a linked series and, with askOneOff on, about
// meetings that don't repeat. Recurring meetings that aren't linked are
// never asked about: leaving them unlinked says they aren't work.
function askable(data, e) {
  if (!meetingEvent(data, e)) return false
  if (e.recurring && e.seriesId) {
    var p = byId(data.projects, data.calendar.links[e.seriesId])
    return !!p && !p.archived
  }
  return !!data.settings.askOneOff
}

function meetingRow(data, e, fallbackId) {
  var start = Date.parse(e.start)
  return {
    uid: e.uid, title: e.title || "(no title)", start: start, end: Date.parse(e.end),
    dateKey: dateKey(new Date(start)), minutes: eventMinutes(e),
    projectId: meetingProject(data, e, fallbackId),
    seriesId: e.seriesId || "",
    linked: !!(e.seriesId && data.calendar.links[e.seriesId]),
    decided: data.calendar.decided[e.uid] || ""
  }
}

// Ended meetings from the last askWorkDays work days that are still waiting
// for a decision, earliest first. With skipTimerCovered, a meeting the
// running timer covers isn't asked about either.
function suggestions(data, events, nowMs, fallbackId) {
  var s = data.settings
  var since = askSince(nowMs, s.askWorkDays || 1, s.workDays)
  var t = data.timer
  var out = []
  for (var i = 0; i < (events || []).length; i++) {
    var e = events[i]
    if (!askable(data, e) || data.calendar.decided[e.uid]) continue
    if (Date.parse(e.end) > nowMs || Date.parse(e.start) < since) continue
    if (t && s.skipTimerCovered && covers(t.startedAt, nowMs, e)) continue
    out.push(meetingRow(data, e, fallbackId))
  }
  out.sort(function(a, b) { return a.start - b.start })
  return out
}

// Meetings going on right now that Week can start the timer for.
function currentMeetings(data, events, nowMs, fallbackId) {
  var out = []
  for (var i = 0; i < (events || []).length; i++) {
    var e = events[i]
    if (!askable(data, e) || data.calendar.decided[e.uid]) continue
    if (Date.parse(e.start) > nowMs || Date.parse(e.end) <= nowMs) continue
    out.push(meetingRow(data, e, fallbackId))
  }
  out.sort(function(a, b) { return a.start - b.start })
  return out
}

// Every meeting of the last lookbackDays that has started, for browsing in
// the Calendar tab, newest first, with what was decided about it.
function pastMeetings(data, events, nowMs, fallbackId) {
  var since = nowMs - (data.settings.lookbackDays || 31) * 86400000
  var out = []
  for (var i = 0; i < (events || []).length; i++) {
    var e = events[i]
    var start = Date.parse(e && e.start)
    if (!meetingEvent(data, e) || start > nowMs || start < since) continue
    out.push(meetingRow(data, e, fallbackId))
  }
  out.sort(function(a, b) { return b.start - a.start })
  return out
}

// ---------------------------------------------------------------- calls
// A call is a stretch with the camera or microphone in use, reported by
// the On Air plugin. Afterwards it is booked as a meeting: on the calendar
// meeting it overlapped most, if any.

function hhmm(ms) { var d = new Date(ms); return pad(d.getHours()) + ":" + pad(d.getMinutes()) }

// What a call from `fromMs` to `toMs` books, or null when there is nothing
// to book: under 8 minutes, or a timer already ran for most of it.
//   { day, from, to, minutes, meeting: meetingRow | null, projectId, clear, line }
// `clear`: the meeting belongs to a linked series, so the project is known.
function callOutcome(data, events, fromMs, toMs, fallbackId) {
  var minutes = roundQuarter((toMs - fromMs) / 60000)
  if (minutes <= 0) return null
  var t = data.timer
  if (t && toMs - Math.max(fromMs, t.startedAt) >= (toMs - fromMs) / 2) return null
  var best = null, bestOverlap = 0
  for (var i = 0; i < (events || []).length; i++) {
    var e = events[i]
    if (!meetingEvent(data, e)) continue
    var overlap = Math.min(toMs, Date.parse(e.end)) - Math.max(fromMs, Date.parse(e.start))
    if (overlap > bestOverlap) { best = e; bestOverlap = overlap }
  }
  var m = best ? meetingRow(data, best, fallbackId) : null
  return {
    day: dateKey(new Date(fromMs)), from: fromMs, to: toMs, minutes: minutes,
    meeting: m, projectId: m ? m.projectId : (fallbackId || ""),
    clear: !!(m && m.linked && !m.decided),
    line: (m ? "Meeting: " + m.title : "Meeting") + " (" + hhmm(fromMs) + "–" + hhmm(toMs) + ")"
  }
}

// Decisions only matter while the occurrence is still inside the lookback
// window; older ones are dropped so the file does not grow forever. A
// one-off's uid carries no date: it is kept while the calendar still has it.
function pruneDecided(data, nowMs, events) {
  var keep = {}
  var cutoff = dateKey(new Date(nowMs - ((data.settings.lookbackDays || 31) + 14) * 86400000))
  var known = {}
  for (var i = 0; i < (events || []).length; i++) if (events[i]) known[events[i].uid] = true
  for (var uid in data.calendar.decided) {
    var m = /_(\d{4})(\d{2})(\d{2})(T|$)/.exec(uid)
    if (m && (m[1] + "-" + m[2] + "-" + m[3]) < cutoff) continue
    if (!m && events && events.length && !known[uid]) continue
    keep[uid] = data.calendar.decided[uid]
  }
  data.calendar.decided = keep
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey, parseKey: parseKey, addDays: addDays, weekStart: weekStart, isoWeek: isoWeek,
    monthKey: monthKey, addMonths: addMonths, monthRange: monthRange, yearRange: yearRange,
    roundQuarter: roundQuarter, fmtHours: fmtHours, fmtMoney: fmtMoney, fmtMoneyShort: fmtMoneyShort,
    uid: uid, defaults: defaults, normalize: normalize, parse: parse, byId: byId, orderedProjects: orderedProjects, moveItem: moveItem,
    rateFor: rateFor, isBillable: isBillable, minutesOn: minutesOn, setMinutes: setMinutes,
    notesOn: notesOn, setNotes: setNotes, addNote: addNote, meetingsDuring: meetingsDuring, ignoredEvent: ignoredEvent,
    addMinutes: addMinutes, totals: totals, budgetUsage: budgetUsage, isWorkDay: isWorkDay,
    workDaysBetween: workDaysBetween, workShare: workShare, clockMinutes: clockMinutes,
    workHours: workHours, isWorkTime: isWorkTime, workDayDone: workDayDone,
    workingDaysBetween: workingDaysBetween, monthTarget: monthTarget, pace: pace, timerElapsedMinutes: timerElapsedMinutes,
    stopTimer: stopTimer, recurringSeries: recurringSeries, suggestions: suggestions,
    pruneDecided: pruneDecided, askSince: askSince, guessProject: guessProject,
    meetingProject: meetingProject, currentMeetings: currentMeetings, pastMeetings: pastMeetings,
    callOutcome: callOutcome
  }
}
