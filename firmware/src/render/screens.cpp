#include "render/screens.h"

#include <cstdio>

#include "render/font.h"
#include "render/palette.h"
#include "render/raster.h"

namespace render {

namespace {

constexpr int kMargin = 12;

// The middle of the bubble and of the strip.
constexpr int kBubbleCy = (kBubbleTop + kStripTop) / 2;
constexpr int kStripCy = (kStripTop + kHeight) / 2;

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
  before = clamp(before, 0, 3);
  after = clamp(after, 0, 3);
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

}  // namespace

void drawStrip(Canvas& c, const Strip& s) {
  // An empty strip is bare glass: no divider under the face.
  if (s.wait <= 0 && s.busy <= 0 && !s.noApp) return;
  c.fillRect(kMargin, kStripTop, kWidth - 2 * kMargin, 1, inkAt(kInkDim, kLevels));
  const int cy = kStripCy, ty = cy - 10;
  int x = kMargin;
  char buf[24];
  if (s.wait > 0) {
    fillCircle(c, px(x + 5), px(cy), px(5), kInkAmber);
    if (s.agent && *s.agent) {
      // Who needs you, cut to leave room for "+N" and the working count.
      char more[12] = "";
      if (s.more > 0) std::snprintf(more, sizeof(more), "+%d", s.more);
      std::snprintf(buf, sizeof(buf), "%d", s.busy);
      int room = kWidth - kMargin - (x + 15) - (more[0] ? stringWidth(kSmall, more) + 8 : 0) -
                 (s.busy > 0 ? 29 + stringWidth(kSmall, buf) : 0);
      char who[48];
      std::snprintf(who, sizeof(who), "%s \xC2\xB7 %s", s.agent, s.project);
      x = drawStringFit(c, kSmall, x + 15, ty, who, kInkAmber, room);
      if (more[0]) x = drawString(c, kSmall, x + 8, ty, more, kInkGrey);
      x += 14;
    } else {
      std::snprintf(buf, sizeof(buf), "%d needs you", s.wait);
      x = drawString(c, kSmall, x + 15, ty, buf, kInkAmber) + 14;
    }
  }
  if (s.busy > 0) {
    fillRing(c, px(x + 5), px(cy), px(5), px(3), kInkGrey);
    std::snprintf(buf, sizeof(buf), "%d", s.busy);
    drawString(c, kSmall, x + 15, ty, buf, kInkGrey);
  }
  if (s.noApp) iconNoApp(c, kWidth - kMargin - 16, cy - 8);
}

void drawFaceScreen(Canvas& c, const SceneShow& face, const Mumble* mumble, const Strip& s) {
  c.fill(kBlack);
  drawScene(c, face);
  if (mumble) drawMumble(c, *mumble);
  drawStrip(c, s);
}

}  // namespace render
