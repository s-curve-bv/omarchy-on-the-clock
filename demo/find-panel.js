// Prints the crop geometry (WxH+X+Y) of the open panel, given a screenshot
// with the panel open and one of the same screen with it closed, both as
// binary PPM files. Candidates are rectangles whose left and right borders
// are long vertical runs of one colour with matching tops and bottoms and a
// bottom border between them, starting just under the bar; the panel is the
// one whose inside changes most when it closes, which rules out look-alikes
// such as coloured blocks in a terminal.
//   node demo/find-panel.js open.ppm closed.ppm
const fs = require("fs");

function readPpm(file) {
  const buf = fs.readFileSync(file);
  let pos = 0;
  function token() {
    while (/\s/.test(String.fromCharCode(buf[pos]))) pos++;
    const start = pos;
    while (!/\s/.test(String.fromCharCode(buf[pos]))) pos++;
    return buf.toString("ascii", start, pos);
  }
  if (token() !== "P6") throw new Error(file + ": expected a binary PPM");
  const width = Number(token()), height = Number(token()), max = Number(token());
  if (max !== 255) throw new Error(file + ": expected 8-bit PPM");
  const data = buf.subarray(pos + 1);
  return { width, height, px: (x, y) => { const i = (y * width + x) * 3; return (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]; } };
}

const open = readPpm(process.argv[2]);
const closed = readPpm(process.argv[3]);
const W = open.width, H = open.height, px = open.px;

// Vertical runs of one colour at least MIN tall.
const MIN = 200;
const runs = [];
for (let x = 0; x < W; x++) {
  let start = 0;
  for (let y = 1; y <= H; y++) {
    if (y < H && px(x, y) === px(x, start)) continue;
    if (y - start >= MIN) runs.push({ x, top: start, bottom: y - 1, color: px(x, start) });
    start = y;
  }
}

// Pair runs into left/right borders: same colour, same top and bottom, and a
// bottom border of that colour between them.
let best = null;
const byKey = new Map();
for (const r of runs) {
  const k = r.color + ":" + r.top + ":" + r.bottom;
  if (!byKey.has(k)) byKey.set(k, []);
  byKey.get(k).push(r);
}
for (const list of byKey.values()) {
  if (list.length < 2) continue;
  const left = list[0], right = list[list.length - 1];
  const width = right.x - left.x;
  // Panels drop down from the bar, so they start near the top of the screen.
  if (width < 300 || left.top > H * 0.08) continue;
  // Borders are thin lines, not the edges of a filled block.
  const mid = (left.top + left.bottom) >> 1;
  if (px(left.x + 4, mid) === left.color || px(right.x - 4, mid) === left.color) continue;
  // The bottom border sits a little above the column ends because of the
  // rounded corners; look for it in the middle.
  const cx = (left.x + right.x) >> 1;
  let joined = false;
  for (let y = left.bottom - 10; y <= left.bottom + 10 && !joined; y++)
    joined = y >= 0 && y < H && px(cx, y) === left.color && px(cx - 100, y) === left.color;
  if (!joined) continue;
  // Share of the inside that differs once the panel is closed.
  let changed = 0, total = 0;
  for (let y = left.top + 8; y < left.bottom - 8; y += 16)
    for (let x = left.x + 8; x < right.x - 8; x += 16, total++)
      if (px(x, y) !== closed.px(x, y)) changed++;
  const score = total ? changed / total : 0;
  if (score > 0.3 && (!best || score > best.score)) best = { left, right, score };
}
if (!best) { console.error("no panel found"); process.exit(1); }

// Rounded corners put the outermost border columns in other runs.
const pad = 6;
const x = Math.max(0, best.left.x - pad), y = Math.max(0, best.left.top - pad);
const w = Math.min(W, best.right.x + pad + 1) - x, h = Math.min(H, best.left.bottom + pad + 1) - y;
console.log(w + "x" + h + "+" + x + "+" + y);
