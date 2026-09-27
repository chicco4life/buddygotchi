#include "render/font.h"

#include "fonts.h"
#include "render/palette.h"

namespace render {

const Font& kSmall = kFontSmall;
const Font& kLarge = kFontLarge;

namespace {

// U+00C0 to U+00FF (UTF-8 C3 80 to C3 BF), each as its nearest plain
// letter, so "café" shows as "cafe" rather than "caf?".
constexpr char kLatin1[] = "AAAAAAACEEEEIIIIDNOOOOOxOUUUUYPsaaaaaaaceeeeiiiidnooooo/ouuuuypy";
static_assert(sizeof(kLatin1) == 64 + 1, "one letter per code point");

// The glyph index for the character at `p`, advancing `p`; -1 at the end.
int nextGlyph(const char*& p) {
  unsigned char c = static_cast<unsigned char>(*p);
  if (!c) return -1;
  ++p;
  unsigned char next = static_cast<unsigned char>(*p);
  if (c == 0xC2 && next == 0xB7) {
    ++p;
    return 95;  // "·", the first extra after '~'
  }
  if (c == 0xC3 && (next & 0xC0) == 0x80) {
    ++p;
    return kLatin1[next - 0x80] - 0x20;
  }
  if (c >= 0x80) {  // skip the rest of any other UTF-8 sequence
    while ((static_cast<unsigned char>(*p) & 0xC0) == 0x80) ++p;
    return '?' - 0x20;
  }
  return c >= 0x20 && c <= 0x7E ? c - 0x20 : '?' - 0x20;
}

void drawGlyph(Canvas& c, const Font& f, int x, int y, int g, int ink) {
  int rowBytes = (f.w + 1) / 2;
  const uint8_t* src = f.data + size_t(g) * rowBytes * f.h;
  uint8_t* px = c.pixels();
  for (int row = 0; row < f.h; ++row) {
    int yy = y + row;
    if (yy < 0 || yy >= kHeight) continue;
    for (int col = 0; col < f.w; ++col) {
      int xx = x + col;
      if (xx < 0 || xx >= kWidth) continue;
      uint8_t b = src[row * rowBytes + col / 2];
      int v = (col & 1) ? (b & 15) : (b >> 4);
      int level = (v * kLevels + 7) / 15;
      if (level > 0) px[yy * kWidth + xx] = inkAt(ink, level);
    }
  }
}

}  // namespace

int drawString(Canvas& c, const Font& f, int x, int y, const char* text, int ink) {
  for (int g; (g = nextGlyph(text)) >= 0; x += f.w) drawGlyph(c, f, x, y, g, ink);
  return x;
}

int stringWidth(const Font& f, const char* text) {
  int n = 0;
  while (nextGlyph(text) >= 0) ++n;
  return n * f.w;
}

int drawStringFit(Canvas& c, const Font& f, int x, int y, const char* text, int ink, int maxWidth) {
  if (stringWidth(f, text) <= maxWidth) return drawString(c, f, x, y, text, ink);
  int room = maxWidth / f.w - 2;  // leave space for ".."
  for (int g; room > 0 && (g = nextGlyph(text)) >= 0; --room, x += f.w) drawGlyph(c, f, x, y, g, ink);
  for (int i = 0; i < 2; ++i, x += f.w) drawGlyph(c, f, x, y, '.' - 0x20, ink);
  return x;
}

}  // namespace render
