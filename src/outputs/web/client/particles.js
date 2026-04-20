// Canvas-driven overlay particles, per state.
//
// The underlying ASCII pose is static for its frame window; the
// overlay layer paints monospace glyphs at sub-character positions
// over the top to match the ESP firmware's fill effects (zzz, !!!,
// confetti, orbiting stars, rising hearts, binary stream, etc.).

// Palette keyed to the state. Must line up with pet color variables
// in app.css.
const COLORS = {
  dim:       "rgba(180,184,195,0.55)",
  white:     "#e8e8ee",
  yellow:    "#f7c65b",
  cyan:      "#7ed3ff",
  green:     "#5fd49a",
  red:       "#ff6b6b",
  purple:    "#c7a6ff",
  heart:     "#ff8fb4",
};

function clear(ctx) {
  ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
}

/** Draw a monospace char centered at (x, y). */
function glyph(ctx, char, x, y, color, size = 16) {
  ctx.fillStyle = color;
  ctx.font = `600 ${size}px ui-monospace, "SF Mono", Menlo, monospace`;
  ctx.textBaseline = "middle";
  ctx.textAlign = "center";
  ctx.shadowColor = color;
  ctx.shadowBlur = 6;
  ctx.fillText(char, x, y);
  ctx.shadowBlur = 0;
}

// Each draw function takes (ctx, tickMs, W, H) where W/H are
// css/client pixels of the overlay. We use DPI-aware sizing in the
// main app so w/h match the underlying <pre>.

function drawSleep(ctx, t, W, H) {
  clear(ctx);
  const cx = W / 2;
  // Three staggered zzz streams drifting up-right
  const period = 1200;
  const streams = [
    { off: 0,   glyph: "z", color: COLORS.dim,   baseX: 24, baseY: 0, size: 12 },
    { off: 400, glyph: "Z", color: COLORS.white, baseX: 40, baseY: 4, size: 15 },
    { off: 800, glyph: "z", color: COLORS.dim,   baseX: 14, baseY: 10, size: 11 },
  ];
  for (const s of streams) {
    const phase = ((t + s.off) % period) / period; // 0..1
    const x = cx + s.baseX + phase * 20;
    const y = H * 0.55 + s.baseY - phase * H * 0.4;
    glyph(ctx, s.glyph, x, y, s.color, s.size);
  }
}

function drawAttention(ctx, t, W, H) {
  clear(ctx);
  // Pulsing exclamations above the head
  const on1 = (Math.floor(t / 250) % 2) === 0;
  const on2 = (Math.floor(t / 380) % 2) === 0;
  if (on1) glyph(ctx, "!", W * 0.40, H * 0.12, COLORS.yellow, 22);
  if (on2) glyph(ctx, "!", W * 0.60, H * 0.18, COLORS.red, 22);
}

function drawBusy(ctx, t, W, H) {
  clear(ctx);
  // Dot ticker beside the body
  const dots = [". ", ".. ", "...", " ..", "  .", "   "];
  const step = Math.floor(t / 180) % dots.length;
  glyph(ctx, dots[step], W * 0.82, H * 0.62, COLORS.white, 14);
}

function drawCelebrate(ctx, t, W, H) {
  clear(ctx);
  // Confetti rain
  const cols = [COLORS.yellow, COLORS.heart, COLORS.cyan, COLORS.white, COLORS.green, COLORS.purple];
  for (let i = 0; i < 8; i++) {
    const period = 1100;
    const phase = ((t + i * 170) % period) / period;
    const x = W * 0.1 + (W * 0.8) * (i / 7);
    const y = -8 + phase * (H + 16);
    const color = cols[i % cols.length];
    const ch = ((i + Math.floor(t / 120)) & 1) ? "*" : "o";
    glyph(ctx, ch, x, y, color, 12);
  }
}

function drawDizzy(ctx, t, W, H) {
  clear(ctx);
  // Two orbiting stars at +/- phase offsets
  const cx = W / 2;
  const cy = H * 0.45;
  const rx = 58;
  const ry = 22;
  const period = 1400;
  const a1 = (t / period) * Math.PI * 2;
  const a2 = a1 + Math.PI;
  glyph(ctx, "*", cx + Math.cos(a1) * rx, cy + Math.sin(a1) * ry, COLORS.cyan, 16);
  glyph(ctx, "*", cx + Math.cos(a2) * rx, cy + Math.sin(a2) * ry, COLORS.yellow, 16);
}

function drawHeart(ctx, t, W, H) {
  clear(ctx);
  // Rising v hearts
  for (let i = 0; i < 5; i++) {
    const period = 1400;
    const phase = ((t + i * 280) % period) / period;
    const x = W * 0.25 + (W * 0.5) * (i / 4) + Math.sin(phase * Math.PI * 4 + i) * 4;
    const y = H * 0.9 - phase * H * 0.9;
    glyph(ctx, "v", x, y, COLORS.heart, 14);
  }
}

const OVERLAYS = {
  sleep: drawSleep,
  attention: drawAttention,
  busy: drawBusy,
  celebrate: drawCelebrate,
  dizzy: drawDizzy,
  heart: drawHeart,
};

/** Paint overlay layer for a given kind. No-op if kind is null. */
export function paintOverlay(canvas, kind, t) {
  const ctx = canvas.getContext("2d");
  if (!kind || !OVERLAYS[kind]) {
    clear(ctx);
    return;
  }
  const { width, height } = canvas;
  OVERLAYS[kind](ctx, t, width, height);
}

/** Size the overlay canvas to the <pre> art below it, DPR-aware. */
export function resizeOverlay(canvas, art) {
  const rect = art.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  canvas.style.width = `${rect.width}px`;
  canvas.style.height = `${rect.height}px`;
  canvas.width = Math.floor(rect.width * dpr);
  canvas.height = Math.floor(rect.height * dpr);
  const ctx = canvas.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}
