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
