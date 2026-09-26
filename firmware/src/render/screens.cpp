#include "render/screens.h"

#include <cstdio>
#include <cstring>

#include "render/font.h"
#include "render/palette.h"
#include "render/raster.h"

namespace render {

namespace {

constexpr int kMargin = 12;

// The face's centre and scale. The centre is the eyes', and the mouth hangs
// below them, so the eyes sit kFaceDrop (face.h) above the middle of their
// space. Alone, the face is centred in the space above the strip; with a
// bubble it moves up into the space above the bubble and shrinks.
constexpr int kFaceCy = kStripTop / 2 - kFaceDrop;
constexpr int kFaceBubbleScale = 750;
constexpr int kFaceBubbleCy = kBubbleTop / 2 - kFaceDrop * kFaceBubbleScale / 1000;

// The middle of the bubble and of the strip.
constexpr int kBubbleCy = (kBubbleTop + kStripTop) / 2;
constexpr int kStripCy = (kStripTop + kHeight) / 2;

// Where the face sits: `raise` eases it between the two places.
void placeFace(Canvas& c, const Pose& p) {
  int r = p.raise < 0 ? 0 : p.raise > 1000 ? 1000 : p.raise;
  int cy = kFaceCy + (kFaceBubbleCy - kFaceCy) * r / 1000;
  int scale = 1000 + (kFaceBubbleScale - 1000) * r / 1000;
  drawFace(c, p, kWidth / 2, cy, scale);
}

void plotInk(Canvas& c, int x, int y, int level, int ink) { c.pixels()[y * kWidth + x] = inkAt(ink, level); }

void fillCircle(Canvas& c, int cx, int cy, int r, int ink) {
  fillShape((cy - r) / kSub - 1, (cy + r) / kSub + 2, [&](int sy) { return ellipse(cx, cy, r, r, sy); },
            [&](int x, int y, int level) { plotInk(c, x, y, level, ink); });
}

void fillRing(Canvas& c, int cx, int cy, int r, int inner, int ink) {
  fillShape((cy - r) / kSub - 1, (cy + r) / kSub + 2,
            [&](int sy) {
              Spans s = ellipse(cx, cy, r, r, sy);
              int lo, hi;
              if (ellipseRow(cx, cy, inner, inner, sy, lo, hi)) s.cut(lo, hi);
              return s;
            },
            [&](int x, int y, int level) { plotInk(c, x, y, level, ink); });
}

// Angle of (x, y) from 12 o'clock, clockwise, in 1/1024 turns.
int clockAngle(int x, int y) {
  int ax = x < 0 ? -x : x, ay = y < 0 ? -y : y;
  if (!ax && !ay) return 0;
  int lo = ax < ay ? ax : ay, hi = ax < ay ? ay : ax;
  int r = int(int64_t(lo) * 1024 / hi);
  int a = (128 * r + 44 * r * (1024 - r) / 1024) / 1024;  // atan, 0..128
  if (ay > ax) a = 256 - a;
  if (x < 0) a = 512 - a;
  if (y < 0) a = 1024 - a;  // angle from +x towards +y (clockwise on screen)
  return (a + 256) & 1023;
}

// Text centred between x0 and x1.
void centred(Canvas& c, const Font& f, int x0, int x1, int y, const char* text, int ink) {
  int w = stringWidth(f, text);
  if (w > x1 - x0) w = x1 - x0;
  drawStringFit(c, f, (x0 + x1 - w) / 2, y, text, ink, x1 - x0);
}
void centred(Canvas& c, const Font& f, int y, const char* text, int ink) {
  centred(c, f, kMargin, kWidth - kMargin, y, text, ink);
}

// A squiggle standing for one or more gibberish syllables.
int squiggle(Canvas& c, int x, int cy, int ink) {
  const int w = 22;
  fillBands(x, x + w,
            [&](int sx, int& top, int& bottom) {
              int t = (sx - px(x)) * 1024 / px(w);  // one full wave
              int yc = px(cy) + px(4) * isin(t) / 1024;
              top = yc - px(1) - 8, bottom = yc + px(1) + 8;
              return true;
            },
            [&](int xx, int yy, int level) { plotInk(c, xx, yy, level, ink); });
  return x + w;
}

void drawMumble(Canvas& c, const Mumble& m) {
  const int gap = 8, sq = 22;
  bool hasWord = m.word && *m.word && m.at >= 0;
  int before = hasWord ? m.at : m.syllables, after = hasWord ? m.syllables - m.at : 0;
  before = before > 3 ? 3 : before < 0 ? 0 : before;
  after = after > 3 ? 3 : after < 0 ? 0 : after;
  if (!hasWord && before == 0) before = 3;
  int wordW = hasWord ? stringWidth(kLarge, m.word) : 0;
  int maxWord = kWidth - 2 * kMargin - (before + after) * (sq + gap);
  if (wordW > maxWord) wordW = maxWord;
  int total = (before + after) * (sq + gap) + wordW - (hasWord ? 0 : gap);
  int x = (kWidth - total) / 2, cy = kBubbleCy;
  for (int i = 0; i < before; ++i) x = squiggle(c, x, cy, kInkGrey) + gap;
  if (hasWord) x = drawStringFit(c, kLarge, x, cy - kLarge.baseline + 8, m.word, kInkAmber, maxWord) + gap;
  for (int i = 0; i < after; ++i) x = squiggle(c, x, cy, kInkGrey) + gap;
}

// Status-strip icons, 16 px boxes with (x, y) at the top left.
void iconNoApp(Canvas& c, int x, int y) {  // a plug on its cord, pointing at nothing
  uint8_t g = inkAt(kInkGrey, kLevels);
  c.fillRect(x, y + 7, 5, 2, g);        // cord
  c.fillRect(x + 4, y + 3, 6, 10, g);   // body
  c.fillRect(x + 10, y + 5, 4, 2, g);   // prongs
  c.fillRect(x + 10, y + 9, 4, 2, g);
}
void iconQuiet(Canvas& c, int x, int y) {  // a speaker with a slash
  uint8_t g = inkAt(kInkGrey, kLevels);
  c.fillRect(x + 1, y + 5, 4, 6, g);
  c.fillTriangle(x + 4, y + 8, x + 9, y + 2, x + 9, y + 14, g);
  for (int i = 0; i < 9; ++i) c.fillRect(x + 6 + i, y + 3 + i, 2, 2, g);
}
void iconFocus(Canvas& c, int x, int y) {  // a target
  fillRing(c, px(x + 8), px(y + 8), px(7), px(5), kInkGrey);
  fillCircle(c, px(x + 8), px(y + 8), px(5) / 2, kInkGrey);
}
void iconBattery(Canvas& c, int x, int y) {  // an almost empty battery
  uint8_t g = inkAt(kInkGrey, kLevels);
  c.fillRect(x, y + 4, 14, 1, g);
  c.fillRect(x, y + 11, 14, 1, g);
  c.fillRect(x, y + 4, 1, 8, g);
  c.fillRect(x + 13, y + 4, 1, 8, g);
  c.fillRect(x + 14, y + 6, 2, 4, g);
  c.fillRect(x + 2, y + 6, 3, 4, inkAt(kInkAmber, kLevels));
}

void capitalised(const char* in, char* out, size_t n) {
  std::snprintf(out, n, "%s", in);
  if (out[0] >= 'a' && out[0] <= 'z') out[0] = char(out[0] - 'a' + 'A');
}

}  // namespace

void drawStrip(Canvas& c, const Strip& s) {
  if (s.pressed) {
    c.fillRect(kMargin, kStripTop, kWidth - 2 * kMargin, 2, inkAt(kInkAmber, kLevels));
  } else {
    c.fillRect(kMargin, kStripTop, kWidth - 2 * kMargin, 1, inkAt(kInkDim, kLevels));
  }
  const int cy = kStripCy, ty = cy - 10;
  int x = kMargin;
  char buf[24];
  if (s.wait > 0) {
    fillCircle(c, px(x + 5), px(cy), px(5), kInkAmber);
    std::snprintf(buf, sizeof(buf), "%d needs you", s.wait);
    x = drawString(c, kSmall, x + 15, ty, buf, kInkAmber) + 14;
  }
  if (s.busy > 0) {
    fillRing(c, px(x + 5), px(cy), px(5), px(3), kInkGrey);
    std::snprintf(buf, sizeof(buf), "%d", s.busy);
    drawString(c, kSmall, x + 15, ty, buf, kInkGrey);
  }
  int ix = kWidth - kMargin - 16;
  if (s.noApp) iconNoApp(c, ix, cy - 8), ix -= 22;
  if (s.quiet) iconQuiet(c, ix, cy - 8), ix -= 22;
  if (s.focus) iconFocus(c, ix, cy - 8), ix -= 22;
  if (s.lowBattery) iconBattery(c, ix, cy - 8);
}

// An empty bowl: the lower half of a ring, with a rim.
void drawBowl(Canvas& c, int cx, int cy) {
  fillRing(c, px(cx), px(cy), px(16), px(13), kInkGrey);
  c.fillRect(cx - 17, cy - 17, 35, 17, kBlack);
  c.fillRect(cx - 18, cy - 1, 37, 2, inkAt(kInkGrey, kLevels));
}

// Where the bowl sits: beside the face, just above the strip.
constexpr int kBowlX = kWidth - 52, kBowlY = kStripTop - 24;

void drawFaceScreen(Canvas& c, const Pose& p, const Mumble* mumble, const Strip& s, bool bowl) {
  c.fill(kBlack);
  placeFace(c, p);
  if (bowl && !mumble) drawBowl(c, kBowlX, kBowlY);
  if (mumble) drawMumble(c, *mumble);
  drawStrip(c, s);
}

void drawNeedsYou(Canvas& c, const Pose& p, const Attention& a, const Strip& s) {
  c.fill(kBlack);
  placeFace(c, p);
  // Two lines in the bubble: who, then what, with "+N more" at its end.
  const int whoY = kBubbleCy - 22, whatY = kBubbleCy;
  char who[48];
  std::snprintf(who, sizeof(who), "%s \xC2\xB7 %s", a.agent, a.project);
  drawStringFit(c, kSmall, kMargin, whoY, who, kInkAmber, kWidth - 2 * kMargin);
  drawString(c, kSmall, kMargin, whatY, "needs you on the Mac", kInkText);
  if (a.more > 0) {
    char more[16];
    std::snprintf(more, sizeof(more), "+%d more", a.more);
    drawString(c, kSmall, kWidth - kMargin - stringWidth(kSmall, more), whatY, more, kInkGrey);
  }
  drawStrip(c, s);
}

// The threads list: one row per session, with the agent's name on its first
// row, the project, and the status at the right.
constexpr int kListTop = 10, kRow = 22, kAgentW = 72;  // an 8-letter agent fits

void drawThreads(Canvas& c, const Thread* threads, int n, const Strip& s) {
  c.fill(kBlack);
  if (n <= 0) {
    centred(c, kSmall, (kStripTop - kSmall.h) / 2, "no sessions", kInkGrey);
    drawStrip(c, s);
    return;
  }
  if (n > 8) n = 8;
  // Agents in order of their most urgent row, then first appearance; rows
  // that need you first within each agent.
  auto rank = [](char st) { return st == 'w' ? 0 : st == 'b' ? 1 : 2; };
  int order[8], agents = 0;
  const char* names[8];
  int best[8];
  for (int i = 0; i < n; ++i) {
    int k = 0;
    while (k < agents && std::strcmp(names[k], threads[i].agent)) ++k;
    if (k == agents) names[agents] = threads[i].agent, best[agents] = 3, order[agents] = agents, ++agents;
    if (rank(threads[i].status) < best[k]) best[k] = rank(threads[i].status);
  }
  for (int i = 1; i < agents; ++i) {  // stable insertion sort by urgency
    for (int j = i; j > 0 && best[order[j]] < best[order[j - 1]]; --j) {
      int t = order[j];
      order[j] = order[j - 1], order[j - 1] = t;
    }
  }
  // A little space between agents, as much as the rows leave (at most 6 px).
  int gap = agents > 1 ? (kStripTop - 4 - kListTop - n * kRow) / (agents - 1) : 0;
  gap = gap < 0 ? 0 : gap > 6 ? 6 : gap;
  const int projectX = kMargin + kAgentW;
  int y = kListTop;
  for (int g = 0; g < agents; ++g) {
    const char* agent = names[order[g]];
    bool first = true;
    for (int r = 0; r < 3; ++r) {
      for (int i = 0; i < n; ++i) {
        const Thread& t = threads[i];
        if (std::strcmp(t.agent, agent) || rank(t.status) != r || y + kRow > kStripTop) continue;
        if (first) {
          char title[16];
          capitalised(agent, title, sizeof(title));
          drawStringFit(c, kSmall, kMargin, y, title, kInkGrey, kAgentW - 8);
          first = false;
        }
        const char* status = r == 0 ? "needs you" : r == 1 ? "working" : "idle";
        int ink = r == 0 ? kInkAmber : r == 1 ? kInkGrey : kInkDim;
        int sw = stringWidth(kSmall, status) + (r == 0 ? 14 : 0);
        drawStringFit(c, kSmall, projectX, y, t.project, kInkText, kWidth - kMargin - sw - 8 - projectX);
        drawString(c, kSmall, kWidth - kMargin - sw, y, status, ink);
        if (r == 0) fillCircle(c, px(kWidth - kMargin - 4), px(y + 10), px(4), kInkAmber);
        y += kRow;
      }
    }
    y += gap;
  }
  drawStrip(c, s);
}

// Stats: the progress ring on the left with the level inside it; the name
// and the days together on the right.
constexpr int kRingR = 62, kRingInner = 52;
constexpr int kRingCx = kMargin + kRingR + 6, kRingCy = kStripTop / 2;
constexpr int kStatsTextX = kRingCx + kRingR + 18;  // "1234 days together" fits

void drawStats(Canvas& c, const Stats& st, const Strip& s) {
  c.fill(kBlack);
  const int cx = px(kRingCx), cy = px(kRingCy), r = px(kRingR), inner = px(kRingInner);
  fillRing(c, cx, cy, r, inner, kInkDim);
  int prog = st.prog < 0 ? 0 : st.prog > 100 ? 100 : st.prog;
  int end = prog * 1024 / 100;
  if (end > 0) {
    int x0 = (cx - r) / kSub - 1, y0 = (cy - r) / kSub - 1;
    sampleShape(x0, y0, x0 + 2 * r / kSub + 3, y0 + 2 * r / kSub + 3,
                [&](int sx, int sy) {
                  int64_t dx = sx - cx, dy = sy - cy, d2 = dx * dx + dy * dy;
                  if (d2 >= int64_t(r) * r || d2 < int64_t(inner) * inner) return false;
                  return clockAngle(int(dx), int(dy)) < end;
                },
                [&](int x, int y, int level) { plotInk(c, x, y, level, kInkAmber); });
  }
  const int ringL = kRingCx - kRingInner, ringR = kRingCx + kRingInner;
  centred(c, kSmall, ringL, ringR, kRingCy - 28, "level", kInkGrey);
  char buf[24];
  std::snprintf(buf, sizeof(buf), "%d", st.level);
  centred(c, kLarge, ringL, ringR, kRingCy - 12, buf, kInkText);

  // A name too long for the large font drops to the small one.
  const char* name = st.name && *st.name ? st.name : "Boop";
  const int room = kWidth - kMargin - kStatsTextX;
  const Font& nameFont = stringWidth(kLarge, name) <= room ? kLarge : kSmall;
  drawStringFit(c, nameFont, kStatsTextX, kRingCy - 34 + (&nameFont == &kSmall ? 8 : 0), name, kInkText, room);
  std::snprintf(buf, sizeof(buf), st.days == 1 ? "%d day together" : "%d days together", st.days);
  drawStringFit(c, kSmall, kStatsTextX, kRingCy + 8, buf, kInkGrey, room);
  drawStrip(c, s);
}

}  // namespace render
