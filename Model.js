// Pure data and date math for the hours plugin. Qt-free so it runs under node
// (tests/test_model.js); the QML owns loading, saving and rendering.
//
// Data shape (hours.json):
//   rates:     [{ id, name, amount }]
//   customers: [{ id, name, archived }]
//   projects:  [{ id, customerId, name, rateId, billable, archived,
//                 budgetType: "none" | "hours" | "money", budget }]
//   entries:   { "YYYY-MM-DD": { projectId: minutes } }
//   targets:   { month, year }                      income, excl. VAT
//   timer:     null | { projectId, startedAt, idleFrom, pendingIdle: {from, to} }
//   calendar:  { links: { seriesId: projectId }, decided: { uid: "confirmed" | "dismissed" } }
//   settings:  { currency, idleMinutes, workDays: [1..5], calendarCache, lookbackDays,
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
    version: 1,
    rates: [],
    customers: [],
    projects: [],
    entries: {},
    targets: { month: 0, year: 0 },
    timer: null,
    calendar: { links: {}, decided: {} },
    settings: {
      currency: "EUR",
      idleMinutes: 10,
      workDays: [1, 2, 3, 4, 5],
      calendarCache: "~/.cache/blacksheep.calendar/events.json",
      lookbackDays: 31,
      backup: false,
      backupRemote: ""
    }
  }
}

function normalize(raw) {
  var d = defaults()
  if (!raw || typeof raw !== "object") return d
  var out = {}
  for (var k in d) out[k] = raw[k] !== undefined && raw[k] !== null ? raw[k] : d[k]
  if (raw.timer === null || raw.timer === undefined) out.timer = null
  out.targets = Object.assign({}, d.targets, raw.targets || {})
  out.settings = Object.assign({}, d.settings, raw.settings || {})
  out.calendar = Object.assign({}, d.calendar, raw.calendar || {})
  out.calendar.links = out.calendar.links || {}
  out.calendar.decided = out.calendar.decided || {}
  return out
}

function parse(text) {
  try { return normalize(JSON.parse(text)) } catch (e) { return null }
}

function byId(list, id) {
  for (var i = 0; i < (list || []).length; i++) if (list[i].id === id) return list[i]
  return null
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

function workDaysBetween(from, to, workDays) {
  var n = 0
  for (var k = from; k <= to; k = addDays(k, 1)) if (isWorkDay(k, workDays)) n++
  return n
}

// Where the period ends up at the current rate. `today` counts as elapsed.
function pace(actual, target, from, to, today, workDays) {
  var total = workDaysBetween(from, to, workDays)
  if (today < from) return { projected: 0, total: total, elapsed: 0, remaining: total, neededPerDay: total ? target / total : 0, done: false }
  if (today > to) return { projected: actual, total: total, elapsed: total, remaining: 0, neededPerDay: 0, done: true }
  var elapsed = workDaysBetween(from, today, workDays)
  var remaining = total - elapsed
  var projected = elapsed > 0 ? actual / elapsed * total : actual
  var neededPerDay = remaining > 0 ? Math.max(0, target - actual) / remaining : 0
  return { projected: projected, total: total, elapsed: elapsed, remaining: remaining, neededPerDay: neededPerDay, done: false }
}

function timerElapsedMinutes(timer, nowMs) {
  if (!timer) return 0
  return Math.max(0, (nowMs - timer.startedAt) / 60000)
}

// Mutates `data`: books the running timer on the day it started, rounded to
// the nearest quarter. Returns the booked minutes.
function stopTimer(data, nowMs) {
  var t = data.timer
  if (!t) return 0
  var minutes = roundQuarter(timerElapsedMinutes(t, nowMs))
  if (minutes > 0 && byId(data.projects, t.projectId))
    addMinutes(data, dateKey(new Date(t.startedAt)), t.projectId, minutes)
  data.timer = null
  return minutes
}

// ---------------------------------------------------------------- calendar
// Events come from Datebook's cache (blacksheep.calendar events.json):
// { uid, title, start, end, allDay, recurring, seriesId, status, response }.

function usableEvent(e) {
  return !!e && !e.allDay && e.status !== "cancelled" && e.response !== "declined"
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

// Past occurrences of linked series that are still waiting for a decision.
function suggestions(data, events, nowMs) {
  var links = data.calendar.links
  var decided = data.calendar.decided
  var since = nowMs - (data.settings.lookbackDays || 31) * 86400000
  var out = []
  for (var i = 0; i < (events || []).length; i++) {
    var e = events[i]
    if (!usableEvent(e) || !e.seriesId) continue
    var pid = links[e.seriesId]
    if (!pid || decided[e.uid]) continue
    var p = byId(data.projects, pid)
    if (!p || p.archived) continue
    var start = Date.parse(e.start)
    if (Date.parse(e.end) > nowMs || start < since) continue
    out.push({ uid: e.uid, title: e.title || "", start: start, dateKey: dateKey(new Date(start)), minutes: eventMinutes(e), projectId: pid })
  }
  out.sort(function(a, b) { return a.start - b.start })
  return out
}

// Decisions only matter while the occurrence is still inside the lookback
// window; older ones are dropped so the file does not grow forever.
function pruneDecided(data, nowMs) {
  var keep = {}
  var cutoff = dateKey(new Date(nowMs - ((data.settings.lookbackDays || 31) + 14) * 86400000))
  for (var uid in data.calendar.decided) {
    var m = /_(\d{4})(\d{2})(\d{2})(T|$)/.exec(uid)
    if (m && (m[1] + "-" + m[2] + "-" + m[3]) < cutoff) continue
    keep[uid] = data.calendar.decided[uid]
  }
  data.calendar.decided = keep
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey, parseKey: parseKey, addDays: addDays, weekStart: weekStart, isoWeek: isoWeek,
    monthKey: monthKey, addMonths: addMonths, monthRange: monthRange, yearRange: yearRange,
    roundQuarter: roundQuarter, fmtHours: fmtHours, fmtMoney: fmtMoney, fmtMoneyShort: fmtMoneyShort,
    uid: uid, defaults: defaults, normalize: normalize, parse: parse, byId: byId,
    rateFor: rateFor, isBillable: isBillable, minutesOn: minutesOn, setMinutes: setMinutes,
    addMinutes: addMinutes, totals: totals, budgetUsage: budgetUsage, isWorkDay: isWorkDay,
    workDaysBetween: workDaysBetween, pace: pace, timerElapsedMinutes: timerElapsedMinutes,
    stopTimer: stopTimer, recurringSeries: recurringSeries, suggestions: suggestions,
    pruneDecided: pruneDecided
  }
}
