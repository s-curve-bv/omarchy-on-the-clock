// Writes the demo data (Demo.js) to demo/out/hours.json and a fake Datebook
// cache to demo/out/events.json. In the panel, demo mode builds the same
// data itself; this is for CI and for looking at the files.
//   node demo/make-demo.js [YYYY-MM-DD]
const fs = require("fs");
const path = require("path");
const Model = require("../Model.js");
const Demo = require("../Demo.js");

const today = process.argv[2] || Model.dateKey(new Date());
const out = path.join(__dirname, "out");
fs.mkdirSync(out, { recursive: true });

const demo = Demo.build(Model, today, "~/.cache/on-the-clock-demo/events.json");
fs.writeFileSync(path.join(out, "hours.json"), JSON.stringify(demo.hours, null, 2) + "\n");
fs.writeFileSync(path.join(out, "events.json"), JSON.stringify({ events: demo.events }, null, 1) + "\n");
console.log("demo data for " + today + " in " + out);
