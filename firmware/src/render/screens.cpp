#include "render/screens.h"

#include <cstdio>

#include "render/font.h"
#include "render/palette.h"
#include "render/raster.h"

namespace render {

namespace {

constexpr int kMargin = 12;

// The face's centre and scale. The centre is the eyes', and the mouth hangs
// below them, so the eyes sit kFaceDrop (face.h) above the middle of their
// space. Alone, the face is centred in the space above the strip; with a
// bubble it moves up into the space above the bubble and shrinks, but only
// so far that the needs-you face, which leans in, keeps the idle face's size.
constexpr int kFaceCy = kStripTop / 2 - kFaceDrop;
constexpr int kFaceBubbleScale = 850;
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
  const int gap = 8, sq = 22, room = kWidth - 2 * kMargin;
  bool hasWord = m.word && *m.word && m.at >= 0;
  int before = hasWord ? m.at : m.syllables, after = hasWord ? m.syllables - m.at : 0;
  before = before > 3 ? 3 : before < 0 ? 0 : before;
  after = after > 3 ? 3 : after < 0 ? 0 : after;
  if (!hasWord && before == 0) before = 3;
  int wordW = hasWord ? stringWidth(kLarge, m.word) : 0;
  // The word is the one thing that means something; the squiggles are
  // decoration. They make room for it, one at a time from the side with
  // more, before the word is ever cut.
  while (hasWord && before + after > 0 && (before + after) * (sq + gap) + wordW > room) {
    if (before >= after) --before;
    else --after;
  }
  int maxWord = room - (before + after) * (sq + gap);
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

}  // namespace

void drawStrip(Canvas& c, const Strip& s) {
  // An empty strip is bare glass: no divider under the face.
  if (s.wait <= 0 && s.busy <= 0 && !s.noApp && !s.quiet) return;
  c.fillRect(kMargin, kStripTop, kWidth - 2 * kMargin, 1, inkAt(kInkDim, kLevels));
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
  if (s.quiet) iconQuiet(c, ix, cy - 8);
}

void drawFaceScreen(Canvas& c, const Pose& p, const Mumble* mumble, const Strip& s) {
  c.fill(kBlack);
  placeFace(c, p);
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

}  // namespace render
