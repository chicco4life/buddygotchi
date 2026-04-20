#pragma once
#include <stdint.h>
#include <M5StickCPlus2.h>

struct Palette {
  uint16_t body, bg, text, textDim, ink;
};

bool characterInit(const char* name);
bool characterLoaded();

void characterSetState(uint8_t state);

void characterTick();
void characterInvalidate();
void characterClose();

void characterSetPeek(bool peek);
void characterRenderTo(lgfx::v1::LGFXBase* tgt, int cx, int cy);

const Palette& characterPalette();
