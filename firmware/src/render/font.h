// The two anti-aliased fonts (the v1 build plan's F2): Geist Mono, generated into
// firmware/assets/fonts.h by internal/tools/fontgen. Monospaced, printable ASCII plus
// "·" (UTF-8 C2 B7). Accented Latin letters (U+00C0 to U+00FF) show as their
// plain letter and anything else as "?". Text is drawn over black with an
// ink ramp.
#pragma once
#include <cstdint>

#include "render/canvas.h"

namespace render {

struct Font {
  uint8_t w, h, baseline, count;
  const uint8_t* data;  // 4-bit coverage, high nibble first, row by row
};

extern const Font& kSmall;  // 8 × 18 cells, for the strip
extern const Font& kLarge;  // 13 × 30 cells, for the mumble's word

// Draws `text` with its cell's top-left at (x, y). Returns the x after it.
int drawString(Canvas& c, const Font& f, int x, int y, const char* text, int ink);
// Width in pixels; glyphs are counted, not bytes.
int stringWidth(const Font& f, const char* text);
// Draws at most `maxWidth` pixels of text, ending with "…" as ".." if cut.
int drawStringFit(Canvas& c, const Font& f, int x, int y, const char* text, int ink, int maxWidth);

}  // namespace render
