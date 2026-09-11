#pragma once
#include "anim.h"

// The device half of the "Boop Cream" palette. The Mac app is cream paper with
// warm ink (app/Boop/Theme/BuddyTheme.swift); the device inverts the field and
// keeps the ink. Same family, each medium played to its strength:
//
//   * Black is free on AMOLED — the pixels are simply off. A cream field would
//     light all 456x280 of them, cost battery, glow in a dark room, and burn in
//     under a persistent dashboard.
//   * Pure WHITE ink on black is harsh at night. A warm cream reads as lamp
//     light and matches the Mac app's paper, so the two screens look related.
//
// EVERY constant here sits exactly on the RGB332 lattice the 8-bit canvas
// quantizes to (main.cpp calls spr.setColorDepth(8)). Off-lattice values snap
// silently and a carefully chosen tone becomes a different one:
//
//   R, G in {0, 36, 73, 109, 146, 182, 219, 255}
//   B    in {0, 82, 173, 255}          <- only four levels
//
// Blue is the scarce channel, which is why the palette is warm: creams, ambers
// and roses land exactly, while slates and periwinkles band badly.

// ---------------------------------------------------------------- ink
// The face, the text, the dashboard numbers. PAPER is the awake ink; the dimmer
// steps are for sleep, for pre-contact, and for labels that must recede.
#define BOOP_PAPER      animRGB(255, 219, 173)   // warm cream — the default ink
#define BOOP_PAPER_SOFT animRGB(219, 182, 146)   // secondary: labels, units
#define BOOP_PAPER_DIM  animRGB(146, 109,  82)   // asleep, or a zero count
#define BOOP_PAPER_FAINT animRGB( 73,  73,  73)  // grey before first contact

// ---------------------------------------------------- semantic trio (shared)
// These three mean the same thing here as they do in the Mac app.
#define BOOP_AMBER      animRGB(255, 182,  36)   // needs you
#define BOOP_AMBER_DEEP animRGB(182, 109,   0)   // the amber field wash
#define BOOP_SAGE       animRGB(109, 219, 146)   // done, idle-and-available
#define BOOP_ROSE       animRGB(255, 109, 173)   // affection: hearts, blush

// ------------------------------------------------------------- incidental
#define BOOP_SKY        animRGB( 73, 146, 255)   // link glyph, sweat drop
#define BOOP_RED        animRGB(255,  36,  36)   // uh-oh field wash
#define BOOP_GOLD       animRGB(255, 219,  82)   // confetti third tone
#define BOOP_FLAME      animRGB(255, 146,  36)   // streak mark

// The field is always black or a low mix toward it; see render() in main.cpp.
#define BOOP_FIELD      BLACK
