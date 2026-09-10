#pragma once
#include "anim.h"

// Cosmetic skin colors on the RGB332 canvas lattice.
struct SkinColor { const char* name; uint16_t c; };
static const SkinColor SKIN_COLORS[] = {
  {"coral",    animRGB(255, 109,  82)},
  {"amber",    animRGB(255, 182,  36)},
  {"mint",     animRGB(109, 219, 146)},
  {"sky",      animRGB( 73, 146, 255)},
  {"lavender", animRGB(182, 146, 255)},
  {"rose",     animRGB(255, 109, 173)},
  {"sand",     animRGB(219, 182, 109)},
  {"teal",     animRGB( 36, 182, 173)},
};

inline uint16_t skinColor565(const char* name) {
  if (name && name[0]) {
    for (const auto& e : SKIN_COLORS) {
      if (strcmp(e.name, name) == 0) return e.c;
    }
  }
  return LIGHTGREY;
}

