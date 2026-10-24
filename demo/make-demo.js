// Writes fictional data for screenshots: demo/out/hours.json and a fake
// Datebook cache at demo/out/events.json, dated around today so the week,
// month and pace all look current. Deterministic for a given day.
//   node demo/make-demo.js [YYYY-MM-DD]
const fs = require("fs");
const path = require("path");
const Model = require("../Model.js");

const today = process.argv[2] || Model.dateKey(new Date());
const out = path.join(__dirname, "out");
fs.mkdirSync(out, { recursive: true });

const d = Model.defaults();
d.rates = [{ id: "r1", name: "Development", amount: 95 }, { id: "r2", name: "Architecture", amount: 120 }];
d.customers = [
  { id: "c1", name: "Northwind Logistics", archived: false },
  { id: "c2", name: "Blue Harbor Health", archived: false },
  { id: "c3", name: "Own company", archived: false },
];
const P = (id, c, name, rate, extra) => Object.assign(
  { id, customerId: c, name, rateId: rate, billable: true, budgetType: "none", budget: 0, archived: false }, extra || {});
d.projects = [
  P("p1", "c1", "Route planner API", "r1", { budgetType: "hours", budget: 320 }),
  P("p2", "c1", "Architecture review", "r2", { budgetType: "money", budget: 15000 }),
  P("p3", "c2", "Patient portal", "r1"),
  P("p4", "c2", "Weekly standup", "r1"),
  P("p5", "c3", "Admin & invoicing", "r1", { billable: false }),
];
d.targets = { month: 10000, year: 120000 };
d.settings.calendarCache = "~/.cache/on-the-clock-demo/events.json";

// Hours on most work days since the start of the year.
let seed = 7;
const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const q = (lo, hi) => Math.round((lo + rnd() * (hi - lo)) * 4) * 15;
for (let k = today.slice(0, 4) + "-01-01"; k < today; k = Model.addDays(k, 1)) {
  const dow = Model.parseKey(k).getDay();
  if (dow === 0 || dow === 6 || rnd() < 0.08) continue;
  const day = {};
  if (rnd() < 0.7) day.p1 = q(1.5, 4.5);
  if (rnd() < 0.3) day.p2 = q(1, 3);
  if (rnd() < 0.55) day.p3 = q(1, 3.5);
  if (dow === 2) day.p4 = 60;
  if (rnd() < 0.4) day.p5 = q(0.25, 1);
  d.entries[k] = day;
}

// Recurring meetings from eight weeks back to five weeks ahead.
const series = [
  { id: "demo-standup", title: "Blue Harbor · weekly standup", dow: 2, h: 9, m: 30, len: 30, every: 1 },
  { id: "demo-review", title: "Northwind sprint review", dow: 4, h: 14, m: 0, len: 60, every: 2 },
  { id: "demo-arch", title: "Architecture board", dow: 1, h: 11, m: 0, len: 90, every: 2 },
  { id: "demo-lunch", title: "Team lunch", dow: 5, h: 12, m: 0, len: 60, every: 1 },
];
const first = Model.addDays(Model.weekStart(today), -56);
const events = [];
for (const s of series) {
  for (let w = 0; w < 13; w += s.every) {
    const k = Model.addDays(first, w * 7 + (s.dow + 6) % 7);
    const start = Model.parseKey(k);
    start.setHours(s.h, s.m, 0, 0);
    events.push({
      uid: s.id + "_" + k, title: s.title, allDay: false, recurring: true, seriesId: s.id,
      start: start.toISOString(), end: new Date(start.getTime() + s.len * 60000).toISOString(),
      status: "confirmed", response: "accepted",
    });
  }
}
d.calendar.links = { "demo-standup": "p4", "demo-review": "p2" };

// Leave the two most recent meetings waiting for a decision.
const now = Model.parseKey(today).getTime() + 14 * 3600000;
const open = Model.suggestions(d, events, now);
for (const s of open.slice(0, -2)) d.calendar.decided[s.uid] = "confirmed";

fs.writeFileSync(path.join(out, "hours.json"), JSON.stringify(d, null, 2) + "\n");
fs.writeFileSync(path.join(out, "events.json"), JSON.stringify({ events }, null, 1) + "\n");
console.log("demo data for " + today + " in " + out);
