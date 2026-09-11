#pragma once
#include "anim.h"
#include "palette.h"
static void _faceEye(int cx, int cy, int w, int h, int r, uint16_t c) {
  if (h <= 10) {
    spr.fillSmoothRoundRect(cx - w / 2, cy - 4, w, 8, 4, c);   // closed lid
  } else {
    if (r > h / 2) r = h / 2;
    if (r > w / 2) r = w / 2;
    spr.fillSmoothRoundRect(cx - w / 2, cy - h / 2, w, h, r, c);
  }
}

// A furrowed brow: one short angled stroke above an eye, inner end dragged
// down. Only ever drawn while actually furrowing — the face has no brows at
// rest, so this appears with the effort and leaves with it rather than being
// a permanent feature that flattens.
//
// `side` is the direction from the OUTER end toward the inner one in x: +1
// for the left eye, -1 for the right. Same overlapping-dots stroke as the
// arch and the spiral, so it inherits their anti-aliasing.
static void _faceBrow(int cx, int cy, int w, int side, float amt, uint16_t c) {
  if (amt <= 0.02f) return;
  // 13 samples across ~63px is ~5px apart against a dot up to 10px wide, so
  // the stroke is solid. At 7 it came out visibly beaded.
  const int N = 13;
  int thick = animPx(2.6f + 1.4f * amt);
  // A shallow slant, not a V. Inner-ends-down is the same shape anger uses,
  // and at 16px of drop that is exactly what it read as; 7px keeps the
  // "leaning into it" tilt without the scowl. Effort is meant to look
  // strained, not annoyed.
  float drop = 7.0f * amt;
  for (int i = 0; i <= N; i++) {
    float u = (float)i / (float)N;                 // 0 = outer, 1 = inner
    spr.fillSmoothCircle(cx + side * animPx((u - 0.5f) * (float)w),
                         cy + animPx(u * drop), thick, c);
  }
}

// The happy "^" eye. A parabolic arch drawn as overlapping dots, where
// `rise` is the whole morph: 0 is a flat closed lid, and raising it arches
// the same stroke upward. That means going happy is just the existing lid
// animation plus a rising arch — the transition eases in and out for free,
// the same way waking from sleep does, instead of cutting between two
// different eye drawings.
static void _faceEyeArch(int cx, int cy, int w, float rise, int thick, uint16_t c) {
  // 16, not fewer. Sampling is uniform in X but the parabola's arc length
  // exceeds its chord, so the dots spread out toward the ends where the
  // curve is steepest — dropping to 8 left the arch visibly beaded. At 34
  // fills a frame this is not worth trading appearance for.
  const int N = 16;
  for (int i = 0; i <= N; i++) {
    float u = (float)i / (float)N * 2.0f - 1.0f;      // -1..1
    spr.fillSmoothCircle(cx + animPx(u * (float)w * 0.5f),
                         cy - animPx(rise * (1.0f - u * u)),
                         thick, c);
  }
}

// A tiny arm: a quadratic Bezier of overlapping dots running from a shoulder
// to a mitten hand. Same stroke as the brow and the happy arch, so it inherits
// their anti-aliasing and adds no new primitive to the renderer.
//
// The buddy has no body. Arms exist only while they are doing something — the
// same rule the brow follows — so the face still reads as two eyes floating on
// black at rest, and a wave is an event rather than a permanent feature.
//
// `ang` is measured from straight down, positive = swung outward and up: 0
// points at the floor, PI/2 is straight out sideways, ~2.2 rad is a raised
// wave. `side` is -1 for the left arm and +1 for the right. `bend` bows the
// curve into a soft elbow; a straight arm reads as a stick.
static void _faceArm(float sx, float sy, float ang, float len, float bend,
                     float thick, float handR, int side, uint16_t c) {
  if (len < 2.0f || thick < 0.5f) return;
  float dx = side * sinf(ang), dy = cosf(ang);
  float px = side * cosf(ang), py = -sinf(ang);      // perpendicular, for the elbow
  float hx = sx + dx * len, hy = sy + dy * len;
  float mx = sx + dx * len * 0.5f + px * bend * len;
  float my = sy + dy * len * 0.5f + py * bend * len;
  // Sample from the geometry, not a constant: the dots must overlap or the
  // arm reads as a string of beads. One sample per half-radius of travel,
  // which is what the brow and the arch each arrived at by hand.
  int N = (int)(len / (thick * 0.5f)) + 1;
  if (N < 6) N = 6;
  if (N > 28) N = 28;
  for (int i = 0; i <= N; i++) {
    float u = (float)i / (float)N, v = 1 - u;
    float x = v * v * sx + 2 * v * u * mx + u * u * hx;
    float y = v * v * sy + 2 * v * u * my + u * u * hy;
    spr.fillSmoothCircle(animPx(x), animPx(y),
                         max(1, animPx(thick * (1.0f - 0.26f * u))), c);
  }
  if (handR >= 0.8f) spr.fillSmoothCircle(animPx(hx), animPx(hy), max(1, animPx(handR)), c);
}

struct FacePose {
  float eyeH=80, eyeW=64, gazeX=0, gazeY=0, brow=0, arc=0;
  float bob=0, lean=0, tilt=0, blush=0, sweat=0, mouth=0;
  // Arms. `armL`/`armR` are reach in units of 54 px at full face scale; 0 is
  // no arm at all. `angL`/`angR` are the swing, in radians from straight down.
  float armL=0, armR=0, angL=0, angR=0;
  bool rightEyeClosed=false;
};
static FacePose facePose;
static uint32_t microAt=0, nextMicro=120000;
static int microKind=0;
static bool eq(const char* a,const char* b) { return strcmp(a,b)==0; }
static const char* visibleCheer() { return noticeVisible()?tama.notice.cheer:tama.cheer; }
static uint32_t cheerDuration() { return eq(visibleCheer(),"dance")?2500:eq(visibleCheer(),"cheer")?2500:1500; }
static bool calmOverlay() { return !hasCard() && !napping && (eq(tama.state,"idle") || eq(tama.state,"working") || eq(tama.state,"done")); }
enum PerchMotion : uint8_t { P_STILL, P_DANGLE, P_TIP, P_LAND, P_POP };
struct PerchPose {
  const char* state;
  const char* modifier;
  const char* name;
  FacePose delta;
  PerchMotion motion;
};
// eyeW is a scale delta; the remaining numeric channels are additive.
static const PerchPose perchPoses[] = {
  {"idle", "", "dangle", {0,0}, P_DANGLE},
  {"working", "grinding", "grip", {0,0,0,4,0,0,0,13}, P_STILL},
  {"working", "", "lean", {0,0,0,4,0,0,0,6}, P_STILL},
  {"needsYou", "", "peer-tip", {0,0}, P_TIP},
  {"done", "dance", "jump-land", {0,0}, P_LAND},
  {"done", "", "hop", {0,0}, P_STILL},
  {"uhoh", "", "sag", {0,0,0,0,0,0,0,6}, P_STILL},
  {"asleep", "", "curl", {0,-0.15f,0,0,0,0,0,6}, P_STILL},
  {"", "greet", "pop-up", {0,0}, P_POP}
};
static const char* chosenPoseName="asleep";
static const char* poseName() { return chosenPoseName; }
static void applyPerch(FacePose& p, const PerchPose& row, uint32_t age) {
  p.eyeW*=1+row.delta.eyeW;
  p.gazeY+=row.delta.gazeY; p.lean+=row.delta.lean;
  switch (row.motion) {
    case P_DANGLE: p.gazeY=2+6*cosf(age*ANIM_TAU/8000.0f); p.gazeX*=0.5f; break;
    case P_TIP: p.gazeY=18; p.tilt=animClamp(age*0.001f-0.5f,0,1)*0.14f; break;
    case P_LAND: break; // The done motion already supplies the landing.
    case P_POP: {
      float wave=sinf(age/2200.0f*3.14159265f);
      p.lean+=30*(1-wave)-12*wave;
      break;
    }
    case P_STILL: break;
  }
  chosenPoseName=row.name;
}
static void faceSimulate(uint32_t now,float dt) {
  // All lower layers advance even when covered. A frozen clock does not
  // integrate springs (AnimSpring intentionally substitutes a dt for zero).
  bool card=hasCard();
  if (dt>0) { cardSpring.step(card?1:0,4,0.65f,dt); squish.step(0,3,0.55f,dt); }
  else { cardSpring.pos=card?1:0; }
  if (eq(tama.state,"idle") && !card && (int32_t)(now-lastInput)>=10000 && (int32_t)(now-nextMicro)>=0) {
    microAt=now; microKind=(microKind+1)%5;
    nextMicro=now+(eq(posture,"travel")?90000:120000);
  }
  FacePose p;
  // Phase from state entry, not boot: a screenshot frozen N ms after a frame
  // lands on the same phase every run.
  float phase=(now-stateAt)*0.001f;
  p.bob=sinf((now-stateAt)*ANIM_TAU/1400.0f)*3;
  p.gazeX=sinf(phase*0.31f)*6; p.gazeY=cosf(phase*0.23f)*2;
  const char* state = (!dataConnected() && !presenceGraced(now)) ? "idle" : noticeVisible()?"done":tama.state;
  if (napping || eq(state,"asleep")) {
    p.eyeH=7; p.bob=sinf(phase*0.7f)*2; p.gazeX=0; p.gazeY=4;
    if (before(now,localBoopUntil) && !napping) p.eyeH=18; // sleeper's peek, no hearts
  } else if (eq(state,"working")) {
    // Reading: eyes narrow a little and the gaze hops between two spots low
    // on the page every 1.6 s (the pose easing turns the hop into a glance).
    // Small offsets, so the pair stays centred on the screen.
    bool right=((now-stateAt)/1600)%2==1;
    p.gazeX=right?7:-8; p.gazeY=6; p.lean=3; p.eyeH=68; p.bob=sinf(phase*1.4f)*2;
    if (eq(tama.effort,"hard") || eq(tama.effort,"grinding")) { p.brow=1; p.sweat=1; p.eyeH=58; }
    if (eq(tama.effort,"grinding")) p.bob+=sinf(phase*37)*1.5f;
  } else if (eq(state,"needsYou")) {
    p.eyeH=96; p.eyeW=72; p.gazeX=0; p.gazeY=-2; p.lean=-4;
  } else if (eq(state,"done")) {
    p.arc=22; p.eyeH=7; p.mouth=1;
    uint32_t age=now-(noticeVisible()?noticeAt:stateAt);
    if (age<cheerDuration()) {
      float progress=(float)age/cheerDuration();
      // Both arms go up for the celebration and swing in opposition, which is
      // what makes it read as a cheer rather than as a two-armed shrug.
      float up=animClamp(age/220.0f,0,1)*animClamp((cheerDuration()-age)/280.0f,0,1);
      float swing=sinf(age*ANIM_TAU*1.8f/1000.0f);
      if (eq(visibleCheer(),"dance")) {
        p.bob-=fabsf(sinf(age*ANIM_TAU*2/1000.0f))*18;
        p.tilt=0.25f*sinf(age*ANIM_TAU*1.5f/1000.0f); p.blush=1;
        p.armL=p.armR=up*0.88f; p.angL=2.55f+0.26f*swing; p.angR=2.55f-0.26f*swing;
      } else if (eq(visibleCheer(),"cheer")) {
        p.bob-=21*animBounce(age%450,450)*(age<900);
        p.tilt=0.12f*sinf(progress*ANIM_TAU*2); p.blush=1;
        p.armL=p.armR=up*0.82f; p.angL=2.45f+0.20f*swing; p.angR=2.45f-0.20f*swing;
      } else p.bob-=21*animBounce(age,600);
    }
  } else if (eq(state,"uhoh")) {
    p.eyeH=36; p.gazeX=-6; p.gazeY=8; p.lean=10; p.bob=sinf(phase)*2; p.mouth=-1;
  }
  chosenPoseName=state;
  if (eq(posture,"perch")) {
    const char* modifier=eq(state,"working")?tama.effort:tama.cheer;
    for (const auto& row:perchPoses) {
      if (eq(state,row.state) && (!row.modifier[0] || eq(modifier,row.modifier))) {
        applyPerch(p,row,now-stateAt); break;
      }
    }
  }
  if (firstWake && ritual!=R_COLOR && !card) {
    uint32_t age=now-ritualAt;
    p=FacePose{}; p.bob=sinf(age*0.0014f)*3;
    p.eyeH=age<1200?7:age<2200?35:66;
    if ((age>=2600 && age<2720) || (age>=2920 && age<3040)) p.eyeH=7;
    if (age>=3200 && age<4000) { p.eyeH=96; p.mouth=1; p.bob-=sinf((age-3200)*0.0039f)*8; }
    if (age>=4000) { bool glance=((age-4000)/1300)%2==0; p.gazeX=glance?28:0; p.gazeY=glance?-25:0; p.mouth=1; }
  } else if (!dataConnected() && eq(state,"idle")) {
    p.gazeX+=12; p.gazeY-=7;
  }
  if (eq(state,"idle") && microAt && now-microAt<1800) {
    float u=(now-microAt)/1800.0f, wave=sinf(u*3.14159265f);
    if (microKind==0) { p.eyeH*=1-wave*0.9f; p.mouth=wave*2; }
    if (microKind==1) { p.gazeX=sinf(u*ANIM_TAU)*20; p.gazeY=wave*20; }
    if (microKind==2) { p.bob+=sinf(u*ANIM_TAU*2)*6; p.arc=wave*12; }
    if (microKind==3) { p.gazeX*=1-wave; p.gazeY-=wave*8; }
    if (microKind==4) p.tilt=wave*0.15f;
  }
  bool booping=calmOverlay() && (before(now,localBoopUntil) ||
    (eq(tama.overlay,"boop") && now-overlayAt<1400));
  bool greeting=calmOverlay() && eq(tama.overlay,"greet") && now-overlayAt<2200;
  if (booping) {
    uint32_t age=now-(before(now,localBoopUntil)?localBoopAt:overlayAt);
    p.eyeH*=age<250?0.6f:0.6f+0.4f*animPop((age-250)/150.0f);
    p.arc=0; p.mouth=1;
  } else if (greeting) {
    uint32_t age=now-overlayAt;
    p.blush=tama.greetLevel>=2?1:0; p.mouth=1;
    if (tama.greetLevel==1) {
      p.arc=0;
      float u=animClamp(age/600.0f,0,1);
      p.eyeH=66-59*sinf(u*ANIM_TAU/2);
    } else {
      uint32_t duration=tama.greetLevel==3?450:600;
      uint32_t end=tama.greetLevel==3?900:600;
      float bounce=age<end?animBounce(age%duration,duration):0;
      p.bob-=16*bounce; p.eyeH*=1-0.25f*bounce;
    }
    // One arm, raised and waving. The wave runs for the whole greeting window
    // rather than only the bounce, because a hand that appears and vanishes
    // inside 600 ms reads as a glitch rather than as a hello.
    float out=animClamp(age/240.0f,0,1)*animClamp((2200.0f-age)/320.0f,0,1);
    p.armR=out*0.88f; p.angR=2.50f+0.30f*sinf(age*ANIM_TAU*2.2f/1000.0f);
    if(eq(posture,"perch")) {
      for (const auto& row:perchPoses) if (eq(row.modifier,"greet")) applyPerch(p,row,age);
    }
  }
  if (before(now,dizzyUntil) && !card) {
    uint32_t age=now-(dizzyUntil-3000);
    p.gazeX+=10*sinf(age*ANIM_TAU*3/1000.0f);
  }
  if (card && tama.nudgeRung > 0 && !cardDismissed) p.lean += 4;
  if (before(now,perkUntil) && !card) { p.lean-=8; p.eyeH=96; chosenPoseName="pickup"; }
  if (before(now,shakeHeadUntil)) p.gazeX+=sinf(phase*24)*14;
  if (!napping && !eq(state,"asleep") && !eq(state,"done") && !booping && !greeting && (now-stateAt)%5100<110) p.eyeH=7;
  if (isRetiring() && now-ritualAt>=600 && now-ritualAt<850) p.eyeH=7;
  p.rightEyeClosed=(eq(tama.state,"asleep") && before(now,localBoopUntil)) ||
    (firstWake && ritual!=R_COLOR && now-ritualAt<2200);
  facePose.rightEyeClosed=p.rightEyeClosed;
  // Pose channels ease independently; a frozen clock gives dt=0, so a
  // settled pose stays bit-for-bit stable for screenshots.
#define EASE(part) facePose.part=dt==0?p.part:animEase(facePose.part,p.part,12,dt)
  EASE(eyeH); EASE(eyeW); EASE(gazeX); EASE(gazeY); EASE(brow); EASE(arc);
  EASE(bob); EASE(lean); facePose.tilt=p.tilt; EASE(blush); EASE(sweat); EASE(mouth);
  // Reach eases so an arm grows and retracts; the swing is applied straight,
  // because easing a 2 Hz wave at rate 12 damps it into a twitch.
  EASE(armL); EASE(armR);
  facePose.angL=p.angL; facePose.angR=p.angR;
#undef EASE
}
// One heart: two lobes and a point. The lobes are lifted slightly above the
// shoulder line and the point runs a little long — at RGB332 and this size
// that is the difference between reading as a heart and reading as a blob.
static void heart(int x,int y,int r,uint16_t c) {
  int lobe=max(1,animPx(r*0.58f)), off=animPx(r*0.52f), lift=animPx(r*0.17f);
  spr.fillSmoothCircle(x-off,y-lift,lobe,c);
  spr.fillSmoothCircle(x+off,y-lift,lobe,c);
  spr.fillTriangle(x-animPx(r*1.02f),y,x+animPx(r*1.02f),y,x,y+animPx(r*1.36f),c);
}
static uint16_t faceInk(uint32_t now) {
  uint16_t tint=animMix(skinTint(oldCosmetic),skinTint(tama.cosmetic),cosmeticAmount(now));
  const char* state=(!dataConnected() && !presenceGraced(now))?"idle":tama.state;
  bool asleep=napping || eq(state,"asleep");
  // Blend visible inks, never a low fraction of light over black.
  uint16_t base=asleep?BOOP_PAPER_DIM:BOOP_PAPER;
  return animMix(BOOP_PAPER_FAINT,animMix(base,tint,tama.cosmetic.skin[0]?(asleep?0.3f:0.55f):0),colorAmount(now));
}
// Rendering tables are eye-relative; data.h retains the stable wire IDs.
struct EyeAccessoryPart {
  CosmeticPrimitive kind;
  int16_t x,y,w,h,r,y2;
  constexpr EyeAccessoryPart(CosmeticPrimitive k=C_RECT,int16_t px=0,int16_t py=0,
      int16_t pw=0,int16_t ph=0,int16_t pr=0,int16_t py2=0)
    : kind(k),x(px),y(py),w(pw),h(ph),r(pr),y2(py2) {}
};
static const struct { uint8_t count; EyeAccessoryPart parts[4]; } eyeAccessories[] = {
  {0,{}},
  {3,{{C_ROUND_RECT,-2,-20,4,22,2},{C_ELLIPSE,-9,-17,10,5},{C_ELLIPSE,8,-23,10,5}}},
  {1,{{C_ROUND_RECT,-43,0,86,10,5}}},
  {4,{{C_ROUND_RECT,-24,0,48,7,3},{C_TRIANGLE,-24,2,-18,-12,-8,2},
       {C_TRIANGLE,-8,2,0,-16,8,2},{C_TRIANGLE,8,2,18,-12,24,2}}}
};
static void faceDraw(uint32_t now,bool showSparks,float compact=0,bool proud=false,float dashboard=0) {
  FacePose p=facePose;
  float scale=(1-0.56f*compact)*(1-0.58f*dashboard);
  if(dashboard>0) {
    // A readable little invitation: anticipate, nod twice at IDLE, look
    // back and smile, then rest. Counts never move or pulse with the face.
    uint32_t age=(now-dashboardAt)%5600;
    float anticipate=age>=400 && age<900?sinf((age-400)*PI/500.0f):0;
    float nod=age>=900 && age<2300?powf(sinf((age-900)*PI/700.0f),2):0;
    float happy=age>=2500 && age<3500?sinf((age-2500)*PI/1000.0f):0;
    p.gazeX=0; p.gazeY=5*nod;
    p.tilt=0.06f*nod; p.bob=6*nod-3*happy; p.lean=0;
    p.sweat=p.brow=0; p.blush=happy;
    p.mouth=1; p.arc=24*happy;
    p.eyeW=64+10*anticipate+6*nod;
    p.eyeH=64-22*anticipate-18*nod;
    if(age>=4700 && age<4830) p.eyeH=7;
    // A little arm reaches out and gestures down across the board, tapping
    // twice on the beat of the nod. Cast `age` before subtracting: it is
    // unsigned, and `age-1150` below 1150 wraps to a colossal positive.
    float reach=animClamp(((float)age-1150.0f)/260.0f,0,1)
               *animClamp((4400.0f-(float)age)/320.0f,0,1);
    float tap=(age>=1500&&age<1900)?sinf((age-1500)*PI/400.0f)
             :(age>=2150&&age<2550)?sinf((age-2150)*PI/400.0f):0;
    p.armL=reach*1.55f; p.angL=0.52f+0.20f*tap; p.armR=0;
  }
  if (proud) { p.arc=22; p.eyeH=7; p.mouth=1; p.gazeX=p.gazeY=p.tilt=0; p.blush=p.sweat=p.brow=p.armL=p.armR=0; }
  float cardAmount=cardSpring.pos;
  // The compact landscape footer leaves room for a lower, larger face.
  float footerAmount=systemCard()?0:animClamp(cardAmount,0,1);
  int lift=animPx(cardAmount*(systemCard()?47:25));
  int cy=HAL_H/2-10-lift+animPx(p.bob+p.lean), cx=animPx(HAL_W/2.0f+(HAL_W/6.0f-HAL_W/2.0f)*compact+p.gazeX*scale);
  cx=animPx(cx*(1-dashboard)+(HAL_W*83/100)*dashboard);
  cy=animPx(cy*(1-dashboard)+(46+p.bob)*dashboard);
  if(noticeVisible()) { cx=HAL_W/2; cy=91+animPx(p.bob*0.4f); }
  float reveal=cosmeticAmount(now);
  const Cosmetics& shape=reveal<0.5f?oldCosmetic:tama.cosmetic;
  float spacing=silhouettes[shape.silhouetteId].spacing*scale;
  // Silhouettes affect only eye size and spacing, never the anchor.
  float eyeScale=shape.silhouetteId==1?1.08f:shape.silhouetteId==2?0.9f:1;
  eyeScale*=1+0.20f*footerAmount;
  p.eyeW*=scale*eyeScale; p.eyeH*=scale*eyeScale; p.arc*=scale;
  uint16_t ink=faceInk(now);
  if(!hasCard()) {
    const auto& accessory=eyeAccessories[shape.accessoryId];
    int ax=cx, ay=cy-animPx(p.eyeH/2+30*scale);
    if(shape.accessoryId==1) { ax=cx-animPx(spacing+p.eyeW/2); ay=cy-animPx(p.eyeH/2+8*scale); }
    if(shape.accessoryId==2) ay=cy+animPx(72*scale);
    for(uint8_t i=0;i<accessory.count;++i) {
      const auto& part=accessory.parts[i];
      int x=ax+animPx(part.x*scale),y=ay+animPx(part.y*scale),w=animPx(part.w*scale),h=animPx(part.h*scale);
      switch(part.kind) {
        case C_RECT: case C_ROUND_RECT: spr.fillSmoothRoundRect(x,y,w,h,max(1,animPx(part.r*scale)),ink); break;
        case C_ELLIPSE: spr.fillEllipse(x,y,w,h,ink); break;
        case C_TRIANGLE: spr.fillTriangle(x,y,ax+w,ay+h,ax+animPx(part.r*scale),ay+animPx(part.y2*scale),ink); break;
      }
    }
  }
  for (int side=-1;side<=1;side+=2) {
    int ex=cx+animPx(side*spacing*cosf(p.tilt)), ey=cy+animPx(p.gazeY+side*spacing*sinf(p.tilt));
    auto drawEye=[&](uint16_t eyeInk) {
    if (before(now,dizzyUntil) && !hasCard() && !proud) {
      spr.fillSmoothCircle(ex,ey,20,eyeInk);
    } else if (p.arc>2) _faceEyeArch(ex,ey,animPx(p.eyeW),p.arc,max(2,animPx(5*scale)),eyeInk);
    else _faceEye(ex,ey,animPx(p.eyeW),p.rightEyeClosed && side>0 ? 7 : animPx(p.eyeH),22,eyeInk);
    };
    drawEye(ink);
    if (!hasCard() && levelRitual() && now-ritualAt<900) {
      float sweep=cx+( (now-ritualAt)/900.0f*2-1)*(spacing+p.eyeW/2+20);
      // Repaint only eye geometry through a soft 40px band.
      // Both endpoints are bright inks, so low fractions stay visible.
      for(int dx=-20;dx<=20;dx+=2) {
        spr.setClipRect(animPx(sweep)+dx,0,2,HAL_H);
        drawEye(animMix(ink,BOOP_PAPER,0.8f*(1-fabsf(dx)/22)));
      }
      spr.clearClipRect();
    }
    _faceBrow(ex,ey-animPx(p.eyeH/2)-15,58,-side,p.brow,ink);
    if (p.blush>0.1f) {
      float cheekScale=dashboard>0?scale:1;
      spr.fillEllipse(ex,ey+animPx(50*cheekScale),max(2,animPx(20*cheekScale)),
                      max(1,animPx(6*cheekScale)),BOOP_ROSE);
    }
  }
  int my=cy+animPx(60*scale);
  if (p.mouth>1.2f) spr.drawEllipse(cx,my,9,13,ink);
  else if (p.mouth>0.2f) spr.fillArc(cx,my-animPx(5*scale),animPx(10*scale),animPx(13*scale),0,180,ink);
  else spr.fillSmoothRoundRect(cx-9,my,18,3,1,ink);
  // Arms are part of the face, drawn in the same ink. Never while a card is
  // up: the card owns the screen, and a waving hand beside the thing you have
  // to answer competes with it.
  if (!hasCard()) {
    for (int side=-1;side<=1;side+=2) {
      float reach=side<0?p.armL:p.armR;
      if (reach<=0.04f) continue;
      // Thickness follows sqrt(scale), not scale: a 1 px arm on the shrunken
      // dashboard buddy read as a scratch rather than as a limb.
      float grip=sqrtf(scale);
      // The shoulder hangs below and outside the eye, near mouth height. At
      // eye height the arm came out of the side of an eye and read as an
      // antenna; the gap is what makes it a limb on a body you cannot see.
      // The 6 px is deliberately NOT scaled: at dashboard size a purely
      // proportional gap closed to ~6 px and the arm grew out of the eye.
      _faceArm(cx+side*(spacing+p.eyeW*0.5f+14*scale+6), cy+animPx(52*scale),
               side<0?p.angL:p.angR, reach*52*scale, 0.16f,
               4.6f*grip, 6.6f*grip*animClamp(reach,0,1), side, ink);
    }
  }
  if (p.sweat>0.2f) {
    int x=cx+135, y=cy-25+((now-stateAt)%3000)*18/3000;
    uint16_t c=BOOP_SKY; spr.fillTriangle(x,y-9,x-5,y+1,x+5,y+1,c); spr.fillSmoothCircle(x,y+2,5,c);
  }
  if (!hasCard() && ritual==R_STREAK && now-ritualAt<ritualDuration[R_STREAK]) {
    int x=HAL_W-42,y=60,r=8+animPx(sinf((now-ritualAt)*0.008f)*3);
    uint16_t flame=BOOP_FLAME;
    spr.fillTriangle(x-r,y,x+3,y-24,x+r,y,flame); spr.fillSmoothCircle(x,y,r,flame);
  }
  uint32_t age=now-stateAt;
  if (!showSparks) return;
  int eyeTop=cy+animPx(p.gazeY-p.eyeH/2);
  if (eq(tama.state,"done") && eq(visibleCheer(),"dance") && age<cheerDuration()) {
    const uint16_t colors[]={BOOP_ROSE,BOOP_SAGE,BOOP_GOLD};
    // Each dot has its own start delay, height, and fall speed so they never
    // line up; a row of dots reads as a necklace, not confetti. Five rather
    // than six, radius 3 rather than 4, and each one fades out over its last
    // third instead of blinking off — six hard dots vanishing together was
    // what made the celebration look busy.
    for (int i=0;i<5;++i) {
      uint32_t h=animHash(i+3), delay=h%700;
      if (age<delay) continue;
      float t=(float)(age-delay)/(cheerDuration()-delay);
      int x=cx+(int)(animHash(i)%200)-100+animPx(6*sinf(age/300.0f+i));
      int y=eyeTop-40-(int)((h>>8)%40)+animPx((100+(int)((h>>16)%40))*t);
      spr.fillSmoothCircle(x,y,3,animMix(BLACK,colors[i%3],t>0.68f?animClamp((1-t)/0.32f,0,1):1));
    }
  }
  // One heart, from one clock. `heartAt` is granted in main.cpp, which applies
  // both rules there rather than here: one heart per boop, and never more than
  // one every 2.5 s. A minute of petting should read as an affectionate beat
  // now and then, not as a stream of hearts.
  if (calmOverlay() && heartAt && now-heartAt<1000) {
    uint32_t heartAge=now-heartAt;
    float amount=heartAge<170?animPop(heartAge/170.0f)
                :heartAge>=850?(1000-heartAge)/150.0f:1;
    // It rises diagonally off the SIDE of the face, not out of the gap
    // between the eyes. Centred, a heart sits on the face like a blemish
    // rather than reading as something the buddy is giving off; off to the
    // side it reads as emitted, and it stops competing with the eyes.
    // It rises diagonally off the LEFT side of the face, not out of the gap
    // between the eyes. Centred, a heart sits on the face like a blemish
    // rather than reading as something the buddy is giving off. It starts
    // low — beside the cheek, clear of the eye — and drifts up and outward.
    //
    // Left, because the greeting wave is the RIGHT arm and level-3 greet
    // grants a heart at the same time: on the same side they overlap, on
    // opposite sides the pose is balanced.
    float t=heartAge/1000.0f;
    int radius=animPx(14*amount*scale);
    int hx=cx-animPx(spacing+p.eyeW*0.5f+18*scale+34*t*scale);
    int hy=cy+animPx(p.gazeY+30*scale-64*t*scale);
    if (radius>0) heart(hx,hy,radius,BOOP_ROSE);
  }
}
