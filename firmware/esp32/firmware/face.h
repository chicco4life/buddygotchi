#pragma once
#include "anim.h"
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

struct FacePose {
  float eyeH=66, eyeW=53, gazeX=0, gazeY=0, brow=0, arc=0;
  float bob=0, lean=0, tilt=0, blush=0, sweat=0, mouth=0;
};
static FacePose facePose;
static uint32_t microAt=0, nextMicro=120000;
static int microKind=0;
static bool eq(const char* a,const char* b) { return strcmp(a,b)==0; }
static uint32_t cheerDuration() { return eq(tama.cheer,"dance")?4000:eq(tama.cheer,"cheer")?2500:1500; }
static bool calmOverlay() { return !hasCard() && !napping && (eq(tama.state,"idle") || eq(tama.state,"working") || eq(tama.state,"done")); }
static const char* poseName() {
  if (before(nowMs(),perkUntil) && !hasCard()) return "pickup";
  if (!eq(posture,"perch")) return tama.state;
  if (calmOverlay() && eq(tama.overlay,"greet") && nowMs()-overlayAt<2200) return "pop-up";
  if (eq(tama.state,"idle")) return "dangle";
  if (eq(tama.state,"working")) return eq(tama.effort,"grinding")?"grip":"lean";
  if (eq(tama.state,"needsYou")) return "peer-tip";
  if (eq(tama.state,"done")) return eq(tama.cheer,"dance")?"jump-land":"hop";
  if (eq(tama.state,"uhoh")) return "sag";
  return "curl";
}
static void faceSimulate(uint32_t now,float dt) {
  // All lower layers advance even when covered. A frozen clock does not
  // integrate springs (AnimSpring intentionally substitutes a dt for zero).
  bool card=hasCard();
  if (dt>0) { cardSpring.step(card?1:0,4,0.65f,dt); squish.step(0,3,0.55f,dt); }
  if (eq(tama.state,"idle") && !card && (int32_t)(now-lastInput)>=10000 && (int32_t)(now-nextMicro)>=0) {
    microAt=now; microKind=(microKind+1)%5;
    nextMicro=now+(eq(posture,"travel")?90000:120000);
  }
  FacePose p;
  // Phase from state entry, not boot: a screenshot frozen N ms after a frame
  // lands on the same phase every run.
  float phase=(now-stateAt)*0.001f;
  p.bob=sinf(phase*1.4f)*3;
  p.gazeX=sinf(phase*0.31f)*11; p.gazeY=cosf(phase*0.23f)*3;
  const char* state = (!dataConnected() && !presenceGraced(now)) ? "idle" : tama.state;
  if (napping || eq(state,"asleep")) {
    p.eyeH=7; p.bob=sinf(phase*0.7f)*2; p.gazeX=0; p.gazeY=4;
    if (before(now,localBoopUntil) && !napping) p.eyeH=18; // sleeper's peek, no hearts
  } else if (eq(state,"working")) {
    p.gazeX=-17; p.gazeY=12; p.lean=5;
    if (eq(tama.effort,"hard") || eq(tama.effort,"grinding")) { p.brow=1; p.sweat=1; p.eyeH=50; }
    if (eq(tama.effort,"grinding")) p.bob+=sinf(phase*37)*1.5f;
  } else if (eq(state,"needsYou")) {
    p.eyeH=83; p.eyeW=61; p.gazeX=0; p.gazeY=-2; p.lean=-5;
  } else if (eq(state,"done")) {
    p.arc=22; p.eyeH=7; p.mouth=1;
    uint32_t age=now-stateAt;
    if (age<cheerDuration()) {
      float progress=(float)age/cheerDuration();
      p.bob-=fabsf(sinf(progress*ANIM_TAU*(eq(tama.cheer,"dance")?3:1)))*21;
      if (eq(tama.cheer,"cheer")) p.tilt=progress*ANIM_TAU;
      if (eq(tama.cheer,"dance")) p.tilt=sinf(progress*ANIM_TAU*3)*0.4f;
      if (eq(tama.cheer,"dance")) { p.blush=1; p.gazeX=sinf(phase*10)*20; }
    } else if (giftPending()) { p.arc=9; p.eyeH=35; p.gazeX=20; p.gazeY=-7; }
  } else if (eq(state,"uhoh")) {
    p.eyeH=30; p.gazeX=-10; p.gazeY=14; p.lean=12; p.bob=sinf(phase)*2; p.mouth=-1;
  }
  if (eq(posture,"perch")) {
    if(eq(state,"idle")) { p.gazeY=(now-stateAt)%8000<6500?14:-8; p.gazeX*=0.5f; }
    else if(eq(state,"working")) { p.lean+=eq(tama.effort,"grinding")?13:6; p.gazeY+=4; }
    else if(eq(state,"needsYou")) { p.gazeY=18; p.tilt=animClamp(phase-0.5f,0,1)*0.14f; }
    else if(eq(state,"uhoh")) p.lean+=6;
    else if(eq(state,"asleep")) { p.lean+=6; p.eyeW*=0.85f; }
    else if(eq(state,"done") && eq(tama.cheer,"dance") && now-stateAt<4000) p.bob+=sinf((now-stateAt)*0.018f)*4;
  }
  if (firstWake && !coloring && !card) {
    uint32_t age=now-wakeAt;
    p=FacePose{}; p.bob=sinf(age*0.0014f)*3;
    p.eyeH=age<1200?7:age<2200?35:66;
    if ((age>=2600 && age<2720) || (age>=2920 && age<3040)) p.eyeH=7;
    if (age>=3200 && age<4000) { p.eyeH=83; p.mouth=1; p.bob-=sinf((age-3200)*0.0039f)*8; }
    if (age>=4000) { bool glance=((age-4000)/1300)%2==0; p.gazeX=glance?28:0; p.gazeY=glance?-25:0; p.mouth=1; }
  } else if (!dataConnected() && eq(state,"idle")) {
    p.gazeX+=12; p.gazeY-=7;
  }
  if (eq(state,"idle") && microAt && now-microAt<1800) {
    float u=(now-microAt)/1800.0f, wave=sinf(u*3.14159265f);
    if (microKind==0) { p.eyeH*=1-wave*0.9f; p.mouth=wave*2; }
    if (microKind==1) { p.gazeX=sinf(u*ANIM_TAU)*30; p.gazeY=wave*30; }
    if (microKind==2) { p.bob+=sinf(u*ANIM_TAU*2)*6; p.arc=wave*12; }
    if (microKind==3) { p.gazeX*=1-wave; p.gazeY-=wave*8; }
    if (microKind==4) p.tilt=wave*0.15f;
  }
  bool affection=calmOverlay() && (before(now,localBoopUntil) ||
    (tama.overlay[0] && now-overlayAt<(eq(tama.overlay,"greet")?2200u:1400u)));
  if (affection) {
    p.blush=1; p.mouth=1;
    if(!eq(tama.overlay,"greet")) p.bob+=sinf((now-overlayAt)*0.014f)*expf(-((float)(now-overlayAt))*0.003f)*14;
    if (eq(tama.overlay,"greet")) {
      float u=(now-overlayAt)/2200.0f, wave=sinf(u*3.14159265f);
      p.blush=tama.greetLevel>=2?1:0; p.gazeX=wave*15; p.mouth=1;
      if(tama.greetLevel==1) { p.eyeH=66-55*wave; p.mouth=2*wave; p.lean=-12*wave; }
      if(tama.greetLevel>=2) { p.bob-=fabsf(sinf(u*ANIM_TAU*2))*(tama.greetLevel==3?28:16); p.eyeH*=1-0.45f*wave; }
      if(eq(posture,"perch")) p.lean+=30*(1-wave)-12*wave;
    } else p.eyeH*=0.7f+0.2f*sinf(phase*8);
  }
  if (before(now,perkUntil) && !card) { p.lean-=8; p.eyeH=83; }
  if (before(now,shakeHeadUntil)) p.gazeX+=sinf(phase*24)*14;
  if (!napping && !eq(state,"asleep") && !eq(state,"done") && (now-stateAt)%5100<110) p.eyeH=7;
  if (retiring && now-retireAt>=600 && now-retireAt<850) p.eyeH=7;
  // Pose channels ease independently; a frozen clock gives dt=0, so a
  // settled pose stays bit-for-bit stable for screenshots.
#define EASE(part) facePose.part=dt==0?p.part:animEase(facePose.part,p.part,12,dt)
  EASE(eyeH); EASE(eyeW); EASE(gazeX); EASE(gazeY); EASE(brow); EASE(arc);
  EASE(bob); EASE(lean); facePose.tilt=p.tilt; EASE(blush); EASE(sweat); EASE(mouth);
#undef EASE
}
static void heart(int x,int y,int r,uint16_t c) {
  spr.fillSmoothCircle(x-r/2,y,r/2+1,c); spr.fillSmoothCircle(x+r/2,y,r/2+1,c);
  spr.fillTriangle(x-r,y+1,x+r,y+1,x,y+r+2,c);
}
static void faceDraw(uint32_t now,bool showSparks) {
  const FacePose& p=facePose;
  if(clockFrozen) cardSpring.pos=hasCard()?1:0;
  int lift=animPx(cardSpring.pos*47);
  int cy=HAL_H/2-10-lift+animPx(p.bob+p.lean), cx=HAL_W/2+animPx(p.gazeX);
  float reveal=cosmeticAmount(now), color=colorAmount(now);
  const Cosmetics& shape=reveal<0.5f?oldCosmetic:tama.cosmetic;
  bool round=eq(shape.silhouette,"round"), tall=eq(shape.silhouette,"tall");
  float spacing=round?73:tall?78:85;
  if(tall) cy-=8;
  uint16_t tint=animMix(skinTint(oldCosmetic),skinTint(tama.cosmetic),reveal);
  uint16_t ink=animMix(animRGB(146,146,146),animMix(animRGB(219,219,219),tint,tama.cosmetic.skin[0]?0.55f:0),color);
  uint16_t body=animMix(BLACK,animMix(LIGHTGREY,tint,color),0.12f);
  int rx=round?135:tall?106:148, ry=round?108:tall?118:96;
  spr.fillEllipse(cx,cy+12,rx,ry,body);
  // Sweep clipped to the body ellipse, with no frame-history dependency.
  bool shimmer=!hasCard() && ((coloring && now-colorAt<600) || (levelActive && now-levelAt<900));
  if(shimmer) {
    float u=coloring?(now-colorAt)/600.0f:(now-levelAt)/900.0f;
    int x=animPx(-rx+2*rx*u);
    for(int dx=-8;dx<=8;++dx) {
      float f=(float)(x+dx)/rx;
      if(fabsf(f)<1) { int h=animPx(ry*sqrtf(1-f*f)); spr.drawLine(cx+x+dx,cy+12-h,cx+x+dx,cy+12+h,animMix(body,ink,0.3f)); }
    }
  }
  if(!hasCard()) {
    uint16_t accessoryInk=animMix(body,ink,reveal);
    int top=cy-85;
    if(eq(shape.accessory,"sprout")) {
      spr.fillRect(cx-2,top-18,4,22,accessoryInk);
      spr.fillEllipse(cx-12,top-15,12,6,accessoryInk); spr.fillEllipse(cx+12,top-21,12,6,accessoryInk);
    } else if(eq(shape.accessory,"crown")) {
      spr.fillRect(cx-27,top,54,9,accessoryInk);
      for(int i=-1;i<=1;++i) spr.fillTriangle(cx+i*18-9,top,cx+i*18,top-20,cx+i*18+9,top,accessoryInk);
    } else if(eq(shape.accessory,"scarf")) {
      spr.fillRoundRect(cx-70,cy+75,140,12,5,accessoryInk); spr.fillRoundRect(cx+43,cy+82,13,22,4,accessoryInk);
    }
  }
  for (int side=-1;side<=1;side+=2) {
    int ex=cx+animPx(side*spacing*cosf(p.tilt)), ey=cy+animPx(p.gazeY+side*spacing*sinf(p.tilt));
    if (before(now,dizzyUntil) && !hasCard()) {
      for (int k=-2;k<=2;++k) { spr.drawLine(ex-20,ey-20+k,ex+20,ey+20+k,ink); spr.drawLine(ex-20,ey+20+k,ex+20,ey-20+k,ink); }
    } else if (p.arc>2) _faceEyeArch(ex,ey,animPx(p.eyeW),p.arc,5,ink);
    else _faceEye(ex,ey,animPx(p.eyeW),eq(tama.state,"asleep") && before(now,localBoopUntil) && side>0 ? 7 : (firstWake && !coloring && now-wakeAt<2200 && side>0)?7:animPx(p.eyeH),18,ink);
    _faceBrow(ex,ey-animPx(p.eyeH/2)-15,58,-side,p.brow,ink);
    if (p.blush>0.1f) spr.fillEllipse(ex,ey+43,18,6,animMix(BLACK,animRGB(255,109,173),p.blush));
  }
  int my=cy+52;
  if (p.mouth>1.2f) spr.drawEllipse(cx,my,9,13,ink);
  else if (p.mouth>0.2f) spr.fillArc(cx,my-5,10,13,0,180,ink);
  else spr.fillRoundRect(cx-9,my,18,3,1,ink);
  if (p.sweat>0.2f) {
    int x=cx+135, y=cy-25+((now-stateAt)%1500)*18/1500;
    uint16_t c=animRGB(73,146,255); spr.fillTriangle(x,y-9,x-5,y+1,x+5,y+1,c); spr.fillSmoothCircle(x,y+2,5,c);
  }
  if (eq(posture,"perch")) {
    bool kick=eq(tama.state,"idle");
    bool tucked=napping || eq(tama.state,"asleep") || (eq(tama.state,"working") && eq(tama.effort,"grinding"));
    for(int side=-1;side<=1;side+=2) {
      int x=cx+side*48, y=cy+85+(kick?animPx(sinf((now-stateAt)*0.0015f+side)*5):0);
      spr.fillRoundRect(x,y,10,tucked?8:21,4,ink);
    }
  }
  if (!hasCard() && streakActive && now-streakAt<1500) {
    int x=HAL_W-42,y=60,r=8+animPx(sinf((now-streakAt)*0.008f)*3);
    uint16_t flame=animRGB(255,146,36);
    spr.fillTriangle(x-r,y,x+3,y-24,x+r,y,flame); spr.fillSmoothCircle(x,y,r,flame);
  }
  if (!showSparks) return;
  uint32_t age=now-stateAt;
  if (eq(tama.state,"done") && age<cheerDuration()) {
    if (eq(tama.cheer,"hop") || !tama.cheer[0]) {
      int r=30+age*100/1500; spr.drawCircle(cx,cy,r,animMix(BLACK,GREEN,0.18f*(1-age/1500.0f)));
    } else {
      int count=eq(tama.cheer,"dance")?32:16;
      for(int i=0;i<count;++i) {
        uint32_t h=animHash(i+17); int x=(h%HAL_W+age*(i%3-1)/35+HAL_W*4)%HAL_W;
        int y=((h>>9)%HAL_H+age/(10+i%6))%HAL_H;
        spr.fillRect(x,y,4,6,animRGB(100+h%155,140+(h>>8)%115,82+(h>>16)%170));
      }
    }
  }
  if (calmOverlay() && (before(now,localBoopUntil) || ((eq(tama.overlay,"boop") && now-overlayAt<1400) || (eq(tama.overlay,"greet") && tama.greetLevel==3 && now-overlayAt<2200)))) {
    for(int i=0;i<3;++i) heart(cx-130+i*125,cy-55-((now-overlayAt)/40+i*17)%35,6,animRGB(255,109,173));
  }
  if (giftPending() && !(eq(tama.state,"done") && age<cheerDuration())) {
    int x=HAL_W-62,y=HAL_H/2+26+animPx(sinf((now-stateAt)*0.002f)*4);
    spr.drawCircle(x,y,16,animRGB(109,73,0)); spr.fillSmoothCircle(x,y,9,animRGB(255,219,82));
    spr.fillSmoothCircle(x-3,y-3,2,WHITE);
  }
}
