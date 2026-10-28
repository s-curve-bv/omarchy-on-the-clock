const test = require("node:test");
const assert = require("node:assert/strict");
const Model = require("../Model.js");

function sample() {
  const d = Model.defaults();
  d.rates = [{ id: "r1", name: "Standard", amount: 100 }, { id: "r2", name: "Senior", amount: 120 }];
  d.customers = [{ id: "c1", name: "Acme" }];
  d.projects = [
    { id: "p1", customerId: "c1", name: "Build", rateId: "r1", billable: true, budgetType: "hours", budget: 10 },
    { id: "p2", customerId: "c1", name: "Advice", rateId: "r2", billable: true, budgetType: "money", budget: 1200 },
    { id: "p3", customerId: "c1", name: "Sales", rateId: "r1", billable: false, budgetType: "none", budget: 0 }
  ];
  return d;
}

test("dates", () => {
  assert.equal(Model.weekStart("2026-10-23"), "2026-10-19");
  assert.equal(Model.weekStart("2026-10-19"), "2026-10-19");
  assert.equal(Model.weekStart("2026-10-25"), "2026-10-19");
  assert.equal(Model.addDays("2026-10-31", 1), "2026-11-01");
  assert.deepEqual(Model.monthRange("2026-02"), ["2026-02-01", "2026-02-28"]);
  assert.equal(Model.addMonths("2026-12", 1), "2027-01");
  assert.equal(Model.addMonths("2026-01", -1), "2025-12");
  assert.equal(Model.isoWeek("2026-10-23"), 43);
  assert.equal(Model.isoWeek("2027-01-01"), 53);
  assert.equal(Model.isoWeek("2025-12-29"), 1);
});

test("rounding and formatting", () => {
  assert.equal(Model.roundQuarter(7), 0);
  assert.equal(Model.roundQuarter(8), 15);
  assert.equal(Model.roundQuarter(67), 60);
  assert.equal(Model.roundQuarter(68), 75);
  assert.equal(Model.fmtHours(90), "1:30");
  assert.equal(Model.fmtMoney(12345.4, "EUR"), "€12.345");
  assert.equal(Model.fmtMoneyShort(6240, "EUR"), "€6.2k");
  assert.equal(Model.fmtMoneyShort(12400, "EUR"), "€12k");
  assert.equal(Model.fmtMoneyShort(950, "EUR"), "€950");
});

test("cells, totals, billable and budgets", () => {
  const d = sample();
  Model.addMinutes(d, "2026-10-20", "p1", 15);
  Model.addMinutes(d, "2026-10-20", "p1", 105);
  Model.addMinutes(d, "2026-10-21", "p2", 60);
  Model.addMinutes(d, "2026-10-21", "p3", 60);
  Model.addMinutes(d, "2026-09-30", "p1", 60);
  assert.equal(Model.minutesOn(d, "2026-10-20", "p1"), 120);

  const oct = Model.totals(d, "2026-10-01", "2026-10-31");
  assert.equal(oct.minutes, 240);
  assert.equal(oct.billableMinutes, 180);
  assert.equal(oct.income, 200 + 120);

  const all = Model.totals(d, null, null);
  assert.deepEqual(Model.budgetUsage(d, d.projects[0], all), { type: "hours", used: 3, budget: 10, fraction: 0.3 });
  assert.equal(Model.budgetUsage(d, d.projects[1], all).used, 120);
  assert.equal(Model.budgetUsage(d, d.projects[2], all), null);

  Model.addMinutes(d, "2026-10-20", "p1", -500);
  assert.equal(Model.minutesOn(d, "2026-10-20", "p1"), 0);
  assert.equal(d.entries["2026-10-20"], undefined);
});

test("pace", () => {
  // October 2026: 22 work days; on the 23rd, 17 have passed.
  const p = Model.pace(8500, 11000, "2026-10-01", "2026-10-31", "2026-10-23", [1, 2, 3, 4, 5]);
  assert.equal(p.total, 22);
  assert.equal(p.elapsed, 17);
  assert.equal(Math.round(p.projected), 11000);
  assert.equal(p.neededPerDay, 500);
  assert.equal(Model.pace(5, 10, "2026-09-01", "2026-09-30", "2026-10-23").done, true);
});

test("timer books rounded minutes on the start day", () => {
  const d = sample();
  const start = new Date(2026, 9, 22, 23, 30).getTime();
  d.timer = { projectId: "p1", startedAt: start };
  const booked = Model.stopTimer(d, start + 52 * 60000);
  assert.equal(booked, 45);
  assert.equal(Model.minutesOn(d, "2026-10-22", "p1"), 45);
  assert.equal(d.timer, null);
});

test("calendar series and suggestions", () => {
  const d = sample();
  const ev = (uid, start, extra) => Object.assign({
    uid, title: "Weekly", seriesId: "s1", recurring: true, allDay: false, status: "confirmed", response: "accepted",
    start, end: new Date(Date.parse(start) + 50 * 60000).toISOString()
  }, extra || {});
  const events = [
    ev("s1_20261012T130000Z", "2026-10-12T13:00:00Z"),
    ev("s1_20261019T130000Z", "2026-10-19T13:00:00Z"),
    ev("s1_20261026T130000Z", "2026-10-26T13:00:00Z"),
    ev("s1_20261005T130000Z", "2026-10-05T13:00:00Z", { response: "declined" }),
    ev("x_1", "2026-10-20T09:00:00Z", { seriesId: "s2", title: "Other" })
  ];
  const now = Date.parse("2026-10-23T12:00:00Z");
  const series = Model.recurringSeries(events, now);
  assert.equal(series.length, 2);
  assert.equal(series.find(s => s.seriesId === "s1").count, 4);

  d.settings.askWorkDays = 10;   // back to Monday the 12th
  assert.equal(Model.suggestions(d, events, now).length, 0);
  d.calendar.links.s1 = "p1";
  let s = Model.suggestions(d, events, now);
  assert.deepEqual(s.map(x => x.uid), ["s1_20261012T130000Z", "s1_20261019T130000Z"]);
  assert.equal(s[0].minutes, 45);

  d.calendar.decided["s1_20261012T130000Z"] = "dismissed";
  s = Model.suggestions(d, events, now);
  assert.equal(s.length, 1);

  d.calendar.decided["s1_20250101T130000Z"] = "confirmed";
  Model.pruneDecided(d, now);
  assert.deepEqual(Object.keys(d.calendar.decided), ["s1_20261012T130000Z"]);
});

// Times are local, like the week grid: built with new Date(y, m, d, h).
const at = (day, h, min) => { const [y, m, d] = day.split("-").map(Number); return new Date(y, m - 1, d, h, min || 0).getTime(); };
const meeting = (uid, day, h, len, extra) => Object.assign({
  uid, title: "Meeting", seriesId: null, recurring: false, allDay: false, status: "confirmed", response: "accepted",
  start: new Date(at(day, h)).toISOString(), end: new Date(at(day, h) + len * 60000).toISOString()
}, extra || {});

test("Week asks about the last work days, today included", () => {
  // Wednesday 28 Oct: Tuesday and Wednesday.
  assert.equal(Model.askSince(at("2026-10-28", 13), 2), at("2026-10-27", 0));
  // Monday: back to Friday.
  assert.equal(Model.askSince(at("2026-10-26", 9), 2), at("2026-10-23", 0));
  // Saturday counts the last two work days, Thursday and Friday.
  assert.equal(Model.askSince(at("2026-10-24", 9), 2), at("2026-10-22", 0));
  assert.equal(Model.askSince(at("2026-10-28", 13), 1), at("2026-10-28", 0));
});

test("one-off meetings are asked about, recurring ones only when linked", () => {
  const d = sample();
  const now = at("2026-10-28", 13);
  const events = [
    meeting("old", "2026-10-26", 10, 60),                                       // Monday: too long ago
    meeting("one", "2026-10-27", 10, 60, { title: "[Acme] Build planning" }),
    meeting("rec_20261028", "2026-10-28", 9, 30, { recurring: true, seriesId: "s1" }),
    meeting("now", "2026-10-28", 12, 120)                                       // still going
  ];
  assert.deepEqual(Model.suggestions(d, events, now, "p2").map(m => m.uid), ["one"]);
  d.calendar.links.s1 = "p3";
  const s = Model.suggestions(d, events, now, "p2");
  assert.deepEqual(s.map(m => [m.uid, m.projectId]), [["one", "p1"], ["rec_20261028", "p3"]]);

  d.settings.askOneOff = false;
  assert.deepEqual(Model.suggestions(d, events, now, "p2").map(m => m.uid), ["rec_20261028"]);
  d.settings.askOneOff = true;
  d.settings.askWorkDays = 3;
  assert.equal(Model.suggestions(d, events, now, "p2").length, 3);
});

test("the project of a meeting: link, then title, then the fallback", () => {
  const d = sample();
  d.projects.push({ id: "p4", customerId: "c1", name: "Build tools", rateId: "r1" });
  d.projects.push({ id: "p5", customerId: "c1", name: "Old build", rateId: "r1", archived: true });
  assert.equal(Model.guessProject(d, "Build-tools sync"), "p4", "longest name wins, punctuation ignored");
  assert.equal(Model.guessProject(d, "BUILD review"), "p1");
  assert.equal(Model.guessProject(d, "Old build retro"), "p1", "archived projects are never guessed");
  assert.equal(Model.guessProject(d, "Lunch"), "");

  const e = meeting("m", "2026-10-28", 9, 30, { title: "Advice call" });
  assert.equal(Model.meetingProject(d, e, "p3"), "p2");
  d.settings.guessProject = false;
  assert.equal(Model.meetingProject(d, e, "p3"), "p3");
  d.calendar.links.s1 = "p1";
  assert.equal(Model.meetingProject(d, Object.assign({}, e, { seriesId: "s1", recurring: true }), "p3"), "p1");
});

test("meetings the timer covered aren't asked about", () => {
  const d = sample();
  const events = [
    meeting("half", "2026-10-28", 9, 60),    // 9:00-10:00, timer 9:30-11:00 covers half
    meeting("bit", "2026-10-28", 11, 60),    // 11:00-12:00, timer stops 11:15
    meeting("declined", "2026-10-28", 10, 60, { response: "declined" })
  ];
  d.timer = { projectId: "p1", startedAt: at("2026-10-28", 9, 30) };
  // While it runs, as well as after it stopped.
  assert.deepEqual(Model.suggestions(d, events, at("2026-10-28", 11, 15)).map(m => m.uid), []);
  Model.stopTimer(d, at("2026-10-28", 11, 15), events);
  assert.deepEqual(d.calendar.decided, { half: "timer" });
  assert.deepEqual(Model.suggestions(d, events, at("2026-10-28", 13)).map(m => m.uid), ["bit"]);

  const off = sample();
  off.settings.skipTimerCovered = false;
  off.timer = { projectId: "p1", startedAt: at("2026-10-28", 9) };
  assert.equal(Model.suggestions(off, events, at("2026-10-28", 13)).length, 2);
  Model.stopTimer(off, at("2026-10-28", 13), events);
  assert.deepEqual(off.calendar.decided, {});
});

test("current and past meetings", () => {
  const d = sample();
  const now = at("2026-10-28", 13);
  const events = [
    meeting("now", "2026-10-28", 12, 120),
    meeting("later", "2026-10-28", 16, 60),
    meeting("done", "2026-10-28", 9, 60),
    meeting("month", "2026-10-05", 9, 60),
    meeting("unlinked_20261027", "2026-10-27", 9, 60, { recurring: true, seriesId: "s9" })
  ];
  assert.deepEqual(Model.currentMeetings(d, events, now, "p1").map(m => m.uid), ["now"]);
  d.calendar.decided.now = "timer";
  assert.deepEqual(Model.currentMeetings(d, events, now, "p1"), []);
  // The Calendar tab shows every started meeting, decided or not, newest first.
  const past = Model.pastMeetings(d, events, now, "p1");
  assert.deepEqual(past.map(m => [m.uid, m.decided]),
    [["now", "timer"], ["done", ""], ["unlinked_20261027", ""], ["month", ""]]);
  d.settings.lookbackDays = 7;
  assert.equal(Model.pastMeetings(d, events, now, "p1").length, 3);
});

test("a call books on the meeting it overlapped most", () => {
  const d = sample();
  const events = [
    meeting("cct_20261028", "2026-10-28", 13, 60, { title: "CCT meeting", recurring: true, seriesId: "s1" }),
    meeting("quick", "2026-10-28", 13, 10, { title: "Advice check-in" })
  ];
  const from = at("2026-10-28", 13, 2), to = at("2026-10-28", 13, 49);

  // Not linked: the project isn't clear, so it is asked.
  let c = Model.callOutcome(d, events, from, to, "p3");
  assert.equal(c.minutes, 45);
  assert.equal(c.meeting.uid, "cct_20261028");
  assert.equal(c.projectId, "p3");
  assert.equal(c.clear, false);
  assert.equal(c.line, "Meeting: CCT meeting (13:02–13:49)");

  d.calendar.links.s1 = "p1";
  c = Model.callOutcome(d, events, from, to, "p3");
  assert.deepEqual([c.projectId, c.clear], ["p1", true]);
  d.calendar.decided.cct_20261028 = "confirmed";
  assert.equal(Model.callOutcome(d, events, from, to, "p3").clear, false, "already booked: ask");

  // Ad hoc: no meeting at all.
  c = Model.callOutcome(d, events, at("2026-10-28", 16), at("2026-10-28", 16, 20), "p3");
  assert.deepEqual([c.meeting, c.projectId, c.minutes, c.line], [null, "p3", 15, "Meeting (16:00–16:20)"]);

  assert.equal(Model.callOutcome(d, events, from, from + 7 * 60000, "p3"), null, "too short to book");
  d.timer = { projectId: "p2", startedAt: at("2026-10-28", 12) };
  assert.equal(Model.callOutcome(d, events, from, to, "p3"), null, "the timer already books it");
});

test("decisions on one-offs are kept while the calendar has them", () => {
  const d = sample();
  d.calendar.decided = { gone: "dismissed", here: "confirmed" };
  Model.pruneDecided(d, Date.now(), []);
  assert.deepEqual(Object.keys(d.calendar.decided), ["gone", "here"], "an empty calendar prunes nothing");
  Model.pruneDecided(d, Date.now(), [{ uid: "here" }]);
  assert.deepEqual(Object.keys(d.calendar.decided), ["here"]);
});

test("normalize fills defaults", () => {
  const d = Model.parse('{"rates":[{"id":"r"}],"settings":{"idleMinutes":5}}');
  assert.equal(d.settings.idleMinutes, 5);
  assert.equal(d.settings.currency, "EUR");
  assert.deepEqual(d.calendar.links, {});
  assert.equal(d.timer, null);
  assert.equal(Model.parse("{oops"), null);
});

test("demo data is marked and survives a save round trip", () => {
  const Demo = require("../Demo.js");
  const demo = Demo.build(Model, "2026-10-24", "~/.cache/on-the-clock-demo/events.json");
  assert.equal(demo.hours.settings.demo, true);
  assert.equal(demo.hours.settings.backup, false);
  // The marker must survive load/normalize, or the guards would not see it.
  assert.equal(Model.parse(JSON.stringify(demo.hours)).settings.demo, true);
  assert.equal(Model.defaults().settings.demo, undefined);
  assert.equal(Model.suggestions(demo.hours, demo.events, Date.parse("2026-10-24T14:00:00")).length, 2);
});

test("demo data with a running timer during a meeting", () => {
  const Demo = require("../Demo.js");
  const now = Date.parse("2026-10-24T15:00:00");
  const demo = Demo.build(Model, "2026-10-24", "x", now);
  assert.equal(demo.hours.timer.projectId, "p1");
  const met = Model.meetingsDuring(demo.events, demo.hours.timer.startedAt, now);
  assert.deepEqual(met.map(m => m.title), ["Route planner design review"]);
  assert.ok(Object.keys(demo.hours.notes).length > 0);
});

test("notes are lines per day and project", () => {
  const d = Model.defaults();
  Model.addNote(d, "2026-10-20", "p1", "  Standup met Rein  ");
  Model.addNote(d, "2026-10-20", "p1", "PR reviews");
  assert.deepEqual(Model.notesOn(d, "2026-10-20", "p1"), ["Standup met Rein", "PR reviews"]);
  assert.deepEqual(Model.notesOn(d, "2026-10-20", "p2"), []);
  assert.deepEqual(Model.parse(JSON.stringify(d)).notes["2026-10-20"].p1, ["Standup met Rein", "PR reviews"]);
  // Old single-string notes load as one line.
  assert.deepEqual(Model.parse('{"notes":{"2026-10-20":{"p1":"a; b"}}}').notes["2026-10-20"].p1, ["a; b"]);
  Model.setNotes(d, "2026-10-20", "p1", ["", "  "]);
  assert.deepEqual(d.notes, {});
});

test("meetings during a stretch of time", () => {
  const ev = [
    { uid: "a", title: "Standup", start: "2026-10-20T09:00:00Z", end: "2026-10-20T09:30:00Z" },
    { uid: "b", title: "Lunch", start: "2026-10-20T12:00:00Z", end: "2026-10-20T13:00:00Z" },
    { uid: "c", title: "Declined", start: "2026-10-20T09:00:00Z", end: "2026-10-20T10:00:00Z", response: "declined" },
    { uid: "d", title: "All day", start: "2026-10-20T00:00:00Z", end: "2026-10-21T00:00:00Z", allDay: true },
  ];
  const got = Model.meetingsDuring(ev, Date.parse("2026-10-20T09:15:00Z"), Date.parse("2026-10-20T12:30:00Z"));
  assert.deepEqual(got.map(m => m.uid), ["a", "b"]);
});

test("unknown fields survive a load", () => {
  assert.deepEqual(Model.parse('{"future": {"x": 1}}').future, { x: 1 });
});
