// Prints the crop geometry (WxH+X+Y) of the open panel in a screenshot,
// given as a binary PPM on stdin. The panel is the rectangle whose left and
// right borders are long vertical runs of the same colour, with matching
// tops and bottoms and a bottom border between them, starting just under
// the bar.
//   magick shot.png ppm:- | node demo/find-panel.js
const buf = require("fs").readFileSync(0);

let pos = 0;
function token() {
  while (/\s/.test(String.fromCharCode(buf[pos]))) pos++;
  const start = pos;
  while (!/\s/.test(String.fromCharCode(buf[pos]))) pos++;
  return buf.toString("ascii", start, pos);
}
if (token() !== "P6") throw new Error("expected a binary PPM");
const W = Number(token()), H = Number(token()), max = Number(token());
if (max !== 255) throw new Error("expected 8-bit PPM");
const data = buf.subarray(pos + 1);
const px = (x, y) => { const i = (y * W + x) * 3; return (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]; };

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
  const area = width * (left.bottom - left.top);
  if (!best || area > best.area) best = { left, right, area };
}
if (!best) { console.error("no panel found"); process.exit(1); }

// Rounded corners put the outermost border columns in other runs.
const pad = 6;
const x = Math.max(0, best.left.x - pad), y = Math.max(0, best.left.top - pad);
const w = Math.min(W, best.right.x + pad + 1) - x, h = Math.min(H, best.left.bottom + pad + 1) - y;
console.log(w + "x" + h + "+" + x + "+" + y);
