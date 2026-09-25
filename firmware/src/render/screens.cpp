#include "render/screens.h"

#include "render/palette.h"

namespace render {

void drawPlaceholderFace(Canvas& c) {
  c.fill(kBlack);
  c.fillRect(60, 120, 36, 60, kOat);
  c.fillRect(144, 120, 36, 60, kOat);
}

}  // namespace render
