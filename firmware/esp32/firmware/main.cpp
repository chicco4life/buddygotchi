#include "hal/hal.h"
#include <esp_log.h>
#include <esp_system.h>
#include <esp_mac.h>
#include "guard.h"
#include "ble_bridge.h"
#include "data.h"
#include "anim.h"
#include "presence.h"
#include "skin-colors.h"
#include "palette.h"
SET_LOOP_TASK_STACK_SIZE(16384);
#ifndef FW_VERSION
#define FW_VERSION "dev"
#endif
#ifndef GIT_SHA
#define GIT_SHA "unknown"
#endif
BuddyCanvas spr(HAL_CANVAS_PARENT);
TamaState tama;
static char btName[16] = "Buddy";
static bool screenOff = false, napping = false;
static uint8_t brightness = 210;
// Sampled every 2 s in loop(); render and posture read the cache (ADC is slow).
static int battery = -999; static bool charging = false;
static uint32_t cardAt = 0, stateAt = 0, overlayAt = 0, bubbleUntil = 0, bootAt = 0;
static uint32_t localBoopUntil = 0, dizzyUntil = 0, perkUntil = 0, shakeHeadUntil = 0;
static uint32_t lastInput = 0, statsUntil = 0, lastPet = 0;
static int statsPage = 0;
static uint32_t statsAt = 0;
static uint32_t localBoopAt = 0, dashboardAt = 0;
// The heart's own clock. Both rules live here rather than in the renderer:
// one heart per boop, and never more than one every 2.5 s. A long petting
// session should read as an affectionate beat now and then, not as a stream.
static uint32_t heartAt = 0;
static void grantHeart(uint32_t now) {
  if (!heartAt || (int32_t)(now - heartAt) >= 2500) heartAt = now;
}
static bool bubbleDismissed = false, cardDismissed = false;
static char localBubble[64] = "", posture[7] = "desk";
static uint32_t localBubbleUntil = 0, drawCount = 0;
static bool imuInjected = false, imuSeen = false;
static float ax = 0, ay = 0, az = 1, ix = 0, iy = 0, iz = 1, shakeEnergy = 0, motionEnergy = 0;
static uint32_t imuSample = 0, faceDownAt = 0, faceUpAt = 0, postureAt = 0;
static char candidatePosture[7] = "desk";
static bool lastLinked = false, lastSecure = false;
static AnimSpring cardSpring, squish;
enum Ritual : uint8_t { R_NONE, R_FIRST_WAKE, R_COLOR, R_LEVEL, R_LEVEL_AWAIT, R_STREAK, R_RETIRE };
static Ritual ritual = R_NONE;
static uint32_t ritualAt = 0;
static const uint16_t ritualDuration[] = {0, 0, 600, 1500, 1500, 1500, 2400};
static const char* const ritualNames[] = {"none", "firstWake", "firstWake", "levelUp", "levelUp", "streak", "retire"};
// Retirement leaves no active ritual, no frame, and an uncompleted wake.
// Boot and explicit wake reset instead enter R_FIRST_WAKE.
static bool isRetired() { return ritual==R_NONE && firstWake && !haveFrame; }
static uint32_t linkAt = 0;
bool isRetiring() { return ritual == R_RETIRE; }
static bool levelRitual() { return ritual == R_LEVEL || ritual == R_LEVEL_AWAIT; }
static bool linkFlash=false;
static Cosmetics oldCosmetic;
static bool systemCard() { return blePasskey() || otaActive() || (tama.card.kind[0] && !cardDismissed); }
static bool hasCard() { return systemCard() || (dataConnected() && tama.card.id[0] && !cardDismissed); }
static bool bubbleVisible() { return (!bubbleDismissed && tama.bubble[0] && before(nowMs(), bubbleUntil)) || before(nowMs(), localBubbleUntil); }
static const char* bubbleText() { return before(nowMs(), localBubbleUntil) ? localBubble : tama.bubble; }
static void sendCmd(const char* json) {
  Serial.println(json);
  if (bleConnected() && bleSecure()) {
    bleWrite((const uint8_t*)json, strlen(json)); bleWrite((const uint8_t*)"\n", 1);
  }
}
static void sendDoc(JsonDocument& d) { char buf[512]; serializeJson(d, buf, sizeof(buf)); sendCmd(buf); }
static void telemetry(JsonDocument& d);
void sendStatus() {
  JsonDocument d; telemetry(d); d["ack"] = "status"; d["ok"] = true;
  d["name"] = btName; d["secure"] = bleSecure(); sendDoc(d);
}
void sendUnpairAck() {
  bleClearBonds(); JsonDocument d; d["ack"] = "unpair"; d["ok"] = true; sendDoc(d);
}
void beginRetire() {
  if (isRetiring() || isRetired()) return;
  ritual=R_RETIRE; ritualAt=stateAt=nowMs();
}
static void resetFirstWake() {
  saveFirstWake(true);
  ritual=R_FIRST_WAKE; ritualAt=stateAt=nowMs();
}
static void ritualTick() {
  uint32_t now=nowMs();
  switch (ritual) {
    case R_COLOR:
      if (now-ritualAt>=ritualDuration[ritual]) { ritual=R_NONE; saveFirstWake(false); }
      break;
    case R_LEVEL: case R_LEVEL_AWAIT: case R_STREAK:
      if (now-ritualAt>=ritualDuration[ritual]) ritual=R_NONE;
      break;
    case R_RETIRE:
      if (now-ritualAt<ritualDuration[ritual]) break;
      {
        Preferences p;
        if (p.begin("creature-v2",false)) { p.clear(); p.end(); }
        tama=TamaState{}; firstWake=true; haveFrame=false; _rtcValid=false;
        ritual=R_NONE;
        localBoopUntil=dizzyUntil=perkUntil=statsUntil=0;
        bubbleUntil=localBubbleUntil=0; cardDismissed=bubbleDismissed=false;
        stateAt=now; spr.fillSprite(BLACK);
        sendCmd("{\"ack\":\"retire\"}");
      }
      break;
    case R_NONE: case R_FIRST_WAKE: break;
  }
}
static float colorAmount(uint32_t now) {
  return firstWake ? (ritual==R_COLOR ? animClamp((float)(now-ritualAt)/ritualDuration[R_COLOR],0,1) : 0) : 1;
}
static float cosmeticAmount(uint32_t now) {
  return ritual==R_LEVEL && memcmp(&oldCosmetic,&tama.cosmetic,sizeof(Cosmetics)) ? animClamp(((float)(now-ritualAt)-900)/600,0,1) : 1;
}
static const char* ritualName() {
  if (isRetiring()) return ritualNames[ritual];
  if (isRetired()) return ritualNames[R_NONE];
  if (firstWake) return ritualNames[R_FIRST_WAKE];
  if (hasCard()) return ritualNames[R_NONE];
  if (ritual!=R_NONE && nowMs()-ritualAt<ritualDuration[ritual]) return ritualNames[ritual];
  if (!strcmp(tama.overlay,"greet") && nowMs()-overlayAt<2200 &&
      (!strcmp(tama.state,"idle") || !strcmp(tama.state,"working") || !strcmp(tama.state,"done"))) return "greet";
  return ritualNames[R_NONE];
}
static uint16_t skinTint(const Cosmetics& c) {
  return c.skin[0] ? skinColor565(c.skin) : LIGHTGREY;
}
static void sendBattery() {
  JsonDocument d; d["cmd"] = "battery"; d["pct"] = battery;
  d["charging"] = halIsCharging(); sendDoc(d);
}
struct Note { uint16_t hz, ms, at; };
struct Motif { const char* name; uint8_t n; Note notes[4]; bool cheer; };
static const Motif motifs[] = {
  {"needs-you",2,{{880,90,0},{1245,100,120}},false},
  {"hop",1,{{1319,100,0}},true},
  {"cheer",2,{{1175,100,0},{1568,120,130}},true},
  {"dance",4,{{1047,90,0},{1319,90,120},{1568,90,240},{2093,140,360}},true},
  {"uhoh",1,{{220,220,0}},false},
  {"greet",2,{{784,100,0},{1047,140,140}},false},
  {"boop",3,{{988,55,0},{1175,55,80},{988,65,160}},false},
  {"nudge",3,{{880,110,0},{1245,130,150},{1245,160,330}},false}
};
static int soundIndex = -1;
static uint8_t soundNote = 0;
static uint32_t soundAt = 0, lastSound = 0, lastCheerSound = 0, soundsPlayed = 0;
static bool sounded = false, cheered = false;
static void sound(int index) {
  uint32_t now = nowMs();
  if (!tama.mute || napping || !strcmp(tama.state,"asleep") || tama.focus ||
      (sounded && now-lastSound < 1000) || (motifs[index].cheer && cheered && now-lastCheerSound < 10000)) return;
  soundIndex = index; soundNote = 0; soundAt = lastSound = now; sounded = true; ++soundsPlayed;
  if (motifs[index].cheer) { cheered = true; lastCheerSound = now; }
}
static void soundTick() {
  if (soundIndex < 0) return;
  const Motif& m = motifs[soundIndex];
  if (!tama.mute || napping || !strcmp(tama.state,"asleep") || tama.focus) { halSilence(); soundIndex = -1; return; }
  while (soundNote < m.n && nowMs()-soundAt >= m.notes[soundNote].at) {
    const Note& n = m.notes[soundNote++]; halTone(n.hz, n.ms);
  }
}
static void wake() {
  if (screenOff) { halDisplayWake(); screenOff = false; }
  napping = false; faceDownAt = 0; lastInput = nowMs();
}
#include "glance.h"
void onFrame(const TamaState& next, bool skinSupplied) {
  uint32_t now = nowMs();
  bool cosmeticsChanged=memcmp(&next.cosmetic,&tama.cosmetic,sizeof(Cosmetics));
  if (!dataConnected()) { linkAt=now; linkFlash=true; }
  if (isRetired()) { ritual=firstWake?R_FIRST_WAKE:R_NONE; ritualAt=now; }
  bool firstSignal=firstWake && ritual!=R_COLOR && (skinSupplied || strcmp(next.state,"asleep"));
  bool milestone=next.snap.streak!=tama.snap.streak &&
    (next.snap.streak==7 || next.snap.streak==30 || next.snap.streak==100);
  if (firstSignal) { ritual=R_COLOR; ritualAt=now; }
  else if (!firstWake && milestone) { ritual=R_STREAK; ritualAt=now; }
  bool nudgeAdvanced = next.nudgeRung > tama.nudgeRung && !strcmp(next.card.id,tama.card.id);
  bool changed = strcmp(next.state,tama.state) || strcmp(next.cheer,tama.cheer);
  bool newCard = strcmp(next.card.id,tama.card.id) || strcmp(next.card.kind,tama.card.kind);
  if (newCard) {
    cardAt = now; cardDismissed = false;
    if (next.card.present()) { wake(); napping = false; dizzyUntil = 0; }
  }
  if (strcmp(next.bubble,tama.bubble)) { bubbleUntil = now + 4000; bubbleDismissed = false; }
  bool overlayChanged = strcmp(next.overlay,tama.overlay) || next.greetLevel != tama.greetLevel;
  if (overlayChanged) {
    overlayAt = now; squish.vel = -3.0f-next.greetLevel;
    // The app's own boop, and the warmest greeting, are the other two things
    // that earn a heart. They go through the same cooldown as a local tap.
    if (!strcmp(next.overlay,"boop") || (!strcmp(next.overlay,"greet") && next.greetLevel>=3))
      grantHeart(now);
  }
  // Any visible change restarts the presentation phase, so periodic motion
  // (and `clock settle`) is anchored to what is on screen, not just the state.
  bool visualChanged = changed || strcmp(next.effort,tama.effort) || strcmp(next.uhoh,tama.uhoh)
    || overlayChanged
    || cosmeticsChanged || milestone || firstSignal || strcmp(next.posture,tama.posture);
  if (visualChanged) stateAt = now;
  if (changed) lastInput = now;   // only a state change counts as activity for the dim ladder
  // Sound sees the incoming state/volume, never the previous frame's mute.
  glanceFrame(next);
  tama = next;
  if (nudgeAdvanced && hasCard() && !systemCard()) sound(next.nudgeRung == 2 ? 7 : 0);
  else if (newCard && next.card.id[0]) sound(0);
  else if (changed && !strcmp(next.state,"needsYou")) sound(0);
  else if (changed && !strcmp(next.state,"done")) sound(!strcmp(next.cheer,"dance") ? 3 : !strcmp(next.cheer,"cheer") ? 2 : 1);
  else if (changed && !strcmp(next.state,"uhoh")) sound(4);
  else if (overlayChanged && !hasCard() && strcmp(next.state,"asleep") && strcmp(next.state,"uhoh")) {
    if (!strcmp(next.overlay,"greet")) sound(5);
    if (!strcmp(next.overlay,"boop")) sound(6);
  }
}
static void boop(bool hold) {
  if (hasCard()) return;
  uint32_t now = nowMs();
  if (hold && lastPet && now-lastPet < 2000) return;
  if (hold) lastPet = now;
  if (!before(now,localBoopUntil)) { localBoopAt = now; grantHeart(now); }
  localBoopUntil = now + 1400; squish.vel = -5.0f; sound(6);
  JsonDocument d; d["cmd"] = "boop"; d["hold"] = hold; sendDoc(d);
}
static void clearBubble() { bubbleDismissed = true; localBubbleUntil = 0; }
static void pageStats() { if (!before(nowMs(),statsUntil)) statsAt=nowMs(); statsPage = before(nowMs(),statsUntil) ? (statsPage+1)%2 : 0; statsUntil = nowMs()+10000; }
static void primaryTap() {
  if (hasCard()) {
    if (!systemCard()) cardDismissed=true;
    return;
  }
  if(threadPage>=0) { threadPage=-1; return; }
  if (bubbleVisible()) { clearBubble(); return; }
  if (!detailTap()) boop(false);
}
static void secondaryTap() {
  if(threadPage>=0) { threadPage=-1; return; }
  if (hasCard()) { if (!systemCard()) cardDismissed = true; return; }
  if (bubbleVisible()) { clearBubble(); return; }
  if (before(nowMs(),statsUntil) || !strcmp(posture,"travel")) { pageStats(); return; }
  shakeHeadUntil = nowMs()+600;
}
// One coordinate path for panel touches and USB-only navigation tests.
// A visible table owns the tap before hidden bubbles or the last-finished link.
static void panelTap(int x,int y) {
  lastInput=nowMs();
  if(screenOff||napping) { wake(); return; }
  if(threadPage>=0 && !hasCard()) {
    if(detailPages()>1 && y>=HAL_H-48 && x>=HAL_W/2)
      threadPage=(threadPage+1)%detailPages();
    else threadPage=-1;
    return;
  }
  if(tama.recentCount && !hasCard() && !noticeVisible() &&
     strcmp(tama.state,"uhoh") && y>=HAL_H-35 && dataConnected()) {
    threadPage=(tama.threadCount+2)/3; noticeUntil=0; statsUntil=0; clearBubble();
  } else primaryTap();
}
struct Button {
  bool down = false, guard = false, fired = false, focusSent = false, shutdown = false;
  uint32_t at = 0, injectedUntil = 0, visualAt = 0, releasedAt = 0;
  float releasedHold = 0;
  bool injected = false;
  char cardId[24] = "";
};
static Button buttons[HAL_BTN_COUNT];
static uint32_t pendingTapAt = 0;
static bool pendingTap = false;
static const char btnNames[] = {'a','b','m'};
static void buttonsTick() {
  uint32_t real = millis(), now = nowMs();
  for (int i=0;i<HAL_BTN_COUNT;++i) {
    Button& b = buttons[i];
    bool injectedRelease = b.injected && !before(real,b.injectedUntil);
    if (injectedRelease) b.injected = false;
    bool down = b.injected || halButtonDown((HalButton)i);
    if (down && !b.down) {
      b.at = real; b.visualAt=now; b.releasedHold=0; b.fired = b.focusSent = b.shutdown = false;
      b.guard = screenOff || napping;
      strlcpy(b.cardId,tama.card.id,sizeof(b.cardId));
      wake();
    }
    if (down) {
      uint32_t held = real-b.at;
      bool sameCard = !strcmp(b.cardId,tama.card.id);
      if (i == 0 && !b.fired && !b.guard && sameCard) {
        if (!hasCard() && held >= 1000) { boop(true); b.fired=true; }
      }
      if (i == 0 && b.fired && !b.cardId[0] && !b.guard && !hasCard() && held >= 1000) {
        if (!before(now,localBoopUntil)) localBoopAt=now;
        localBoopUntil=now+300;
      }
      if (i != 0 && held >= 1000 && !b.focusSent) {
        tama.focus = !tama.focus; JsonDocument d; d["cmd"]="focus"; d["on"]=tama.focus; sendDoc(d);
        b.focusSent = b.fired = true;
      }
      if (i != 0 && held >= 3000 && !b.shutdown) {
        strlcpy(localBubble,"night night",sizeof(localBubble)); localBubbleUntil=now+600; b.shutdown=true;
      }
      if (i != 0 && held >= 3600 && b.shutdown && !screenOff) { halDisplaySleep(); screenOff=true; }
    }
    if (!down && b.down) {
      b.releasedAt=now;
      lastInput = now;
      if (b.shutdown && !screenOff) { halDisplaySleep(); screenOff=true; }
      if (!b.fired && !b.guard && !strcmp(b.cardId,tama.card.id)) {
        if (i == 0) {
          if (hasCard()) primaryTap();
          else if (pendingTap && real-pendingTapAt <= 300) {
            pendingTap=false;
            if (!strcmp(posture,"travel")) pageStats();
            else primaryTap();
          } else { pendingTap=true; pendingTapAt=real; }
        } else secondaryTap();
      }
      b.shutdown=false;
    }
    b.down=down;
    if (injectedRelease) Serial.printf("<<PRESS %c up>>\n",btnNames[i]);
  }
  if (pendingTap && real-pendingTapAt > 300) { pendingTap=false; if (!hasCard()) primaryTap(); }
}
static void motionEvent(const char* event) {
  JsonDocument d; d["cmd"]="motion"; d["m"]=event; sendDoc(d);
}
static void setPosture(const char* p) {
  if (!strcmp(posture,p)) return;
  strlcpy(posture,p,sizeof(posture)); JsonDocument d; d["cmd"]="posture"; d["p"]=p; sendDoc(d);
}
static void motionTick() {
  uint32_t now=nowMs();
  static uint32_t poll=0;
  if (now-poll < 50) return;
  poll=now;
  float x,y,z;
  bool valid=imuInjected;
  if (valid) { x=ix; y=iy; z=iz; } else valid=halImuRead(&x,&y,&z);
  if (valid) {
    float delta = imuSeen ? fabsf(x-ax)+fabsf(y-ay)+fabsf(z-az) : 0;
    motionEnergy=motionEnergy*0.8f+delta;
    ax=x; ay=y; az=z; imuSeen=true; imuSample=now;
    float mag=sqrtf(x*x+y*y+z*z);
    shakeEnergy=shakeEnergy*0.8f+fabsf(mag-1.0f);
    if (!hasCard()) {
      if (shakeEnergy>2.5f && !before(now,dizzyUntil)) { dizzyUntil=now+3000; motionEvent("shake"); }
      if (delta>0.45f && mag>0.7f && mag<2.0f && shakeEnergy<1.2f && !before(now,dizzyUntil) && !before(now,perkUntil)) { perkUntil=now+1000; stateAt=now; motionEvent("pickup"); }
      if (z < -0.75f) {
        faceUpAt=0; if (!faceDownAt) faceDownAt=now;
        if (!napping && now-faceDownAt>=2000) { napping=true; motionEvent("flip"); }
      } else {
        faceDownAt=0; if (!faceUpAt) faceUpAt=now;
        if (napping && now-faceUpAt>=700) { napping=false; motionEvent("flip"); }
      }
    } else { faceDownAt=faceUpAt=0; napping=false; dizzyUntil=perkUntil=0; }
  } else if (napping && now-imuSample>5000) napping=false;
  if (tama.posture[0]) { setPosture(tama.posture); postureAt=now; return; }
  bool travel = (!dataConnected() && !charging && now-dataLastLiveMs()>60000) || shakeEnergy>1.2f || motionEnergy>1.2f;
  const char* want=travel?"travel":(valid && az>0.3f && az<0.85f)?"perch":(valid && (fabsf(az)>=0.85f || fabsf(az)<0.25f))?"desk":posture;
  if (strcmp(candidatePosture,want)) { strlcpy(candidatePosture,want,sizeof(candidatePosture)); postureAt=now; }
  if (now-postureAt>=2500) setPosture(candidatePosture);
}
#include "face.h"
// Screen priority stack (UX-DEVICE §16), highest first. UHOH is a bubble that
// outranks the stats cards; it draws like BUBBLE.
enum Layer : uint8_t { L_OFF, L_SYSTEM, L_CARD, L_UHOH, L_STATS, L_BUBBLE, L_OVERLAY, L_FACE, L_DASHBOARD, L_COMPLETION };
static const char* const layerNames[] = {"off","system","card","uhoh","stats","bubble","overlay","face","threads","completion"};
static bool dashboardWanted() {
  return dataConnected() && !napping && !firstWake && threadPage>=0;
}
static float dashboardAmount=0;
static uint32_t dashboardTick=0;
static Layer screenLayer() {
  if (screenOff) return L_OFF;
  if (systemCard()) return L_SYSTEM;
  if (hasCard()) return L_CARD;
  if (eq(tama.state,"uhoh") && bubbleVisible()) return L_UHOH;
  if (before(nowMs(),statsUntil)) return L_STATS;
  if (dashboardWanted()) return L_DASHBOARD;
  if (noticeVisible()) return L_COMPLETION;
  if (bubbleVisible()) return L_BUBBLE;
  if (calmOverlay() && ((tama.overlay[0] && nowMs()-overlayAt<(eq(tama.overlay,"greet")?2200u:1400u)) || before(nowMs(),localBoopUntil))) return L_OVERLAY;
  return L_FACE;
}
// Two UTF-8-aware lines using the Korean font already bundled in LGFX.
static void textLines(const char* text,int x,int y,int width,int lines=2,float size=1.0f,uint16_t ink=BOOP_PAPER) {
  spr.setFont(&fonts::efontKR_16); spr.setTextSize(size); spr.setTextDatum(TL_DATUM); spr.setTextColor(ink);
  spr.setTextWrap(false);
  char line[128]={0}; size_t used=0; int lineW=0;
  const unsigned char* p=(const unsigned char*)text;
  while (*p && lines>0) {
    size_t n=(*p<0x80)?1:(*p<0xe0)?2:(*p<0xf0)?3:4;
    size_t available=0;
    while(available<n && p[available]) ++available;
    if(available!=n || used+n>=sizeof(line)) break;
    char glyph[5]={0}; memcpy(glyph,p,n);
    int glyphW=spr.textWidth(glyph);
    if (lineW+glyphW>width && used) {
      if (lines==1) {
        while (used && spr.textWidth(line)+spr.textWidth("…")>width) {
          do { --used; } while (used && ((unsigned char)line[used]&0xc0)==0x80);
          line[used]=0;
        }
        spr.drawString(String(line)+"…",x,y); return;
      }
      line[used]=0; spr.drawString(line,x,y); y+=animPx(20*size); --lines; used=0; lineW=0;
      if (!lines) break;
    }
    memcpy(line+used,p,n); used+=n; line[used]=0; lineW+=glyphW; p+=n;
  }
  if (lines>0 && used) spr.drawString(line,x,y);
}
static void textRight(const char* text,int right,int y,uint16_t ink) {
  spr.setFont(&fonts::efontKR_16); spr.setTextSize(1);
  textLines(text,right-spr.textWidth(text),y,HAL_W,1,1,ink);
}
static int cardY() { int h=systemCard()?132:88; return HAL_H-h+animPx((1-animClamp(cardSpring.pos,0,1))*h); }
static void drawCard(uint32_t now) {
  int y=cardY();
  uint16_t ink=faceInk(now);
  char line[96];
  if (systemCard()) {
    if (blePasskey()) { snprintf(line,sizeof(line),"pair: %06lu",(unsigned long)blePasskey()); textLines(line,30,y+10,HAL_W-60,1,1.5f,ink); }
    else if (otaActive()) { snprintf(line,sizeof(line),"update %lu / %lu",(unsigned long)otaProgress(),(unsigned long)otaTotal()); textLines(line,30,y+10,HAL_W-60,1,1.5f,ink); }
    else { textLines(tama.card.kind,30,y+10,HAL_W-60,1,1.5f,ink); textLines(tama.card.text,30,y+42,HAL_W-60,2,1,ink); }
    return;
  }
  int left=30, right=HAL_W-left;
  int textWidth=right-left;
  int toolWidth=textWidth;
  // One hairline across the top of the footer. No pill and no box — §16 is
  // right that 8-bit fills read as mud — but the rule separates the question
  // from the face without filling anything, the same way the board's does.
  spr.drawFastHLine(left,y,textWidth,animMix(BLACK,ink,0.28f));
  if(tama.card.of>1) {
    snprintf(line,sizeof(line),"%d of %d",tama.card.n,tama.card.of);
    textRight(line,left+textWidth,y+18,BOOP_PAPER_SOFT);
    toolWidth-=spr.textWidth(line)+16;
  }
  // Tool and gloss share the left edge; the tool was indented 14 px past it
  // and the two lines read as a ragged pair. The gloss steps down to the
  // softer ink so the tool name is what the eye lands on first.
  textLines(tama.card.tool,left,y+14,max(16,toolWidth),1,1.5f,ink);
  textLines(tama.card.gloss,left,y+46,textWidth,2,1,BOOP_PAPER_SOFT);
}
static void drawStats(uint32_t now) {
  uint16_t ink=faceInk(now);
  int x=HAL_W/3+12, right=HAL_W-20, width=right-x;
  char line[128];
  if(statsPage==0) {
    textLines(tama.snap.name,x,72,width,1,1.5f,ink);
    snprintf(line,sizeof(line),"%lu-day streak",(unsigned long)tama.snap.streak);
    textLines(line,x,108,width,1,1,ink);
    snprintf(line,sizeof(line),"%lu XP",(unsigned long)tama.snap.xp);
    textRight(line,right,158,ink);
  } else {
    snprintf(line,sizeof(line),"%lu days together",(unsigned long)tama.snap.days); textLines(line,x,76,width,1,1,ink);
    snprintf(line,sizeof(line),"%lu turns",(unsigned long)tama.snap.tasks); textLines(line,x,114,width,1,1,ink);
    textLines(tama.snap.biggest,x,152,width,1,1,ink);
    snprintf(line,sizeof(line),"today: %lu",(unsigned long)tama.snap.today); textLines(line,x,190,width,1,1,ink);
  }
}
static const char* sourceName(int source) {
  static const char* names[]={"Codex","Claude","Cursor","Other"};
  return names[min(3,max(0,source))];
}
static void drawThreads() {
  int sessionPages=(tama.threadCount+2)/3;
  int pages=detailPages();
  if(threadPage>=pages) threadPage=max(0,pages-1);
  bool history=threadPage>=sessionPages;
  int start=(history?threadPage-sessionPages:threadPage)*3;
  constexpr int inset=40, width=HAL_W-2*inset;
  char line[96];
  snprintf(line,sizeof(line),"%s  %d/%d",history?"Recently finished":"Threads",threadPage+1,max(1,pages));
  textLines(line,inset,24,width,1,2);
  static const char* states[]={"Idle","Working","Needs you","Error"};
  for(int row=0;row<3;++row) {
    int i=start+row;
    if(i>=(history?tama.recentCount:tama.threadCount)) break;
    const char* title=history?tama.recent[i].title:tama.threads[i].title;
    int source=history?tama.recent[i].source:tama.threads[i].source;
    int status=history?0:tama.threads[i].status;
    int y=64+row*56;
    snprintf(line,sizeof(line),"%s · %s",sourceName(source),history?"Finished":states[status]);
    textLines(line,inset,y,width,1,1,status==2?BOOP_AMBER:BOOP_PAPER_SOFT);
    textLines(title,inset,y+20,width,1,2);
  }
  int omitted=max(0,tama.threadTotal-(int)tama.threadCount);
  textLines("Back",inset,HAL_H-40,width,1,1,BOOP_PAPER_SOFT);
  if(omitted) {
    snprintf(line,sizeof(line),"+%d on Mac",omitted);
    textLines(line,HAL_W/2-50,HAL_H-40,140,1,1,BOOP_PAPER_SOFT);
  }
  if(pages>1) textRight("Next >",HAL_W-inset,HAL_H-40,BOOP_PAPER_SOFT);
}
static void drawCompletion(uint32_t now) {
  if(!tama.recentCount) return;
  char line[80];
  if(tama.notice.count>1) snprintf(line,sizeof(line),"%d finished · %s",tama.notice.count,sourceName(tama.recent[0].source));
  else snprintf(line,sizeof(line),"%s finished",sourceName(tama.recent[0].source));
  textLines(line,24,18,HAL_W-48,1,1,BOOP_PAPER);
  // Only text slides on an additional arrival; the field and cheer continue.
  int offset=animPx(8*(1-animClamp((now-noticeTextAt)/180.0f,0,1)));
  textLines(tama.recent[0].title,24,HAL_H-112+offset,HAL_W-48,2,2);
  if(tama.notice.count>1 && tama.recentCount>1) {
    snprintf(line,sizeof(line),"%s · %s",sourceName(tama.recent[1].source),tama.recent[1].title);
    textLines(line,24,HAL_H-34,HAL_W-48,1,1,BOOP_PAPER_SOFT);
  }
}
static void render() {
  uint32_t now=nowMs();
  if (isRetired()) {
    halSetBrightness(0);
    if (!screenOff) halPresent(spr);
    ++drawCount;
    return;
  }
  Layer layer=screenLayer();
  uint16_t tint=animMix(skinTint(oldCosmetic),skinTint(tama.cosmetic),cosmeticAmount(now));
  // RGB332 needs at least one channel step to keep a tint visible.
  uint16_t field=BLACK;
  // Field wash. These mix factors are chosen against the REAL quantization
  // path, not the endpoint lattice: animMix lerps in RGB565, and the 8-bit
  // canvas then TRUNCATES to RGB332 (R5>>2, G6>>3, B5>>3). A blend therefore
  // quantizes far more coarsely than animRGB's comment implies, and it loses
  // hue as it darkens because R and G shed different numbers of bits.
  //
  // That had bitten both states. A 0.14 mix toward AMBER (255,182,36) landed
  // on (36,0,0) — and so did uh-oh's 0.18 mix toward RED, so "needs you" and
  // "uh-oh" were rendering the identical colour. Mixing toward AMBER_DEEP
  // (a lower G/R ratio) and clearing the R5 >= 8 threshold keeps the wash
  // amber: rest is (72,36,0), and the second nudge rung peaks at (109,72,0).
  // Uh-oh sits at the same brightness in pure red, (72,0,0) rising to
  // (109,0,0), so the two now differ by hue rather than not at all.
  //
  // The gentle first-rung breath (0.40 -> 0.51) stays inside one bucket and
  // renders flat. That is a lattice limit, not an oversight, and it was true
  // before this change too: the face breathes, so the field need not. §8.
  if (eq(tama.state,"needsYou") || hasCard()) field=animMix(BLACK,BOOP_AMBER_DEEP,0.40f+animPulse01(now-stateAt,tama.nudgeRung == 2 ? 1200 : 3500)*(tama.nudgeRung == 2 && !cardDismissed ? 0.22f : 0.11f));
  else if(eq(tama.state,"uhoh")) field=animMix(BLACK,BOOP_RED,0.28f+animPulse01(now-stateAt,4000)*0.12f);
  else if(layer==L_COMPLETION) {
    float fadeIn=animClamp((now-noticeAt)/250.0f,0,1);
    float fadeOut=animClamp((noticeUntil-now)/600.0f,0,1);
    field=animMix(BLACK,BOOP_SAGE,0.44f*min(fadeIn,fadeOut));
  }
  if(field!=BLACK && tama.cosmetic.skin[0]) field=animMix(field,animMix(BLACK,tint,0.22f),0.2f);
  field=animMix(BLACK,field,colorAmount(now));
  // One whole-field flash: 300 ms toward the skin, then 300 ms back.
  if (!hasCard() && levelRitual() && now-ritualAt<600) {
    uint32_t age=now-ritualAt;
    // Peak at 0.3 so it reads as a flash of light, not a full-screen colour.
    float flash=(age<300?age/300.0f:(600-age)/300.0f)*0.3f;
    field=animMix(field,tama.cosmetic.skin[0]?tint:BOOP_AMBER,flash);
  }
  spr.fillSprite(field);
  bool base=layer==L_FACE || layer==L_OVERLAY;
  bool beside=layer==L_STATS || layer==L_BUBBLE || layer==L_UHOH;
  float compact=beside?1:0;
  if(layer==L_STATS) { float u=animClamp((now-statsAt)/300.0f,0,1); compact=u*u*(3-2*u); }
  if(layer!=L_DASHBOARD) {
    // Completion gets a smaller cheerful face above the large title.
    faceDraw(now,base,layer==L_COMPLETION?1:compact,layer==L_STATS,0);
  }
  if(layer==L_DASHBOARD) drawThreads();
  else if(layer==L_COMPLETION) drawCompletion(now);
  else if(base && dataConnected() && !napping &&
          (eq(tama.state,"idle") || eq(tama.state,"working") || eq(tama.state,"done"))) {
    char label[96];
    if(tama.workingCount()>0) {
      snprintf(label,sizeof(label),"%d working · tap for threads",tama.workingCount());
      textLines(label,24,HAL_H-53,HAL_W-48,1,1,BOOP_PAPER_SOFT);
    }
    if(tama.recentCount) {
      snprintf(label,sizeof(label),"Last finished: %s",tama.recent[0].title);
      textLines(label,24,HAL_H-27,HAL_W-48,1,1,BOOP_PAPER_SOFT);
    }
  }
  // Scope sits above the calm face, clear of working and last-finished footers.
  // Detail pages, completion notices and higher-priority layers cover it.
  if (layer==L_FACE && tama.scope[0] && dataConnected() && !napping &&
      (eq(tama.state,"idle") || eq(tama.state,"working") || eq(tama.state,"done")))
    textLines(tama.scope,24,24,HAL_W-48,2,1,BOOP_PAPER_SOFT);
  if (eq(posture,"travel") && battery>=0 && battery<25) {
    spr.fillSmoothRoundRect(HAL_W-30,HAL_H-27,20,10,2,BOOP_PAPER_DIM);
    spr.fillRect(HAL_W-28,HAL_H-25,4,6,BOOP_AMBER);
  }
  if (!bleBonded() || !dataConnected() || (linkFlash && now-linkAt<800))
    presenceDrawLinkGlyph(spr,now-stateAt,BOOP_SKY,linkFlash && now-linkAt<800);
  if (layer==L_SYSTEM || layer==L_CARD) drawCard(now);
  else if(layer==L_STATS) drawStats(now);
  else if(layer==L_BUBBLE || layer==L_UHOH) { int x=HAL_W/3+12; uint16_t ink=faceInk(now); textLines(bubbleText(),x+12,HAL_H/2-20,HAL_W-x-40,2,1,ink); }
  if (guardSafeTier()) { textLines("safe mode - USB rescue",28,18,HAL_W-56,1); }
  float fade=isRetiring()?1-animClamp((float)(now-ritualAt)/ritualDuration[R_RETIRE],0,1):1;
  halSetBrightness(brightness*fade);
  if (!screenOff) halPresent(spr);
  ++drawCount;
}
static void telemetry(JsonDocument& d) {
#ifdef BOOP_USB_ONLY
  d["usbOnly"]=true;
#else
  d["usbOnly"]=false;
#endif
  d["contract"]=WIRE_CONTRACT; d["board"]=HAL_BOARD_NAME; d["fw"]=FW_VERSION; d["git"]=GIT_SHA;
  d["up"]=millis(); d["heap"]=ESP.getFreeHeap(); d["heapMin"]=ESP.getMinFreeHeap(); d["heapBig"]=ESP.getMaxAllocHeap();
  d["reset"]=guardResetReason(); d["panics"]=guardPanicsTotal(); d["early"]=guardEarlyCrashes(); d["safe"]=guardSafeTier();
  uint32_t avg,max; halFrameStats(&avg,&max); d["frameUs"]=avg; d["frameMaxUs"]=max;
}
static void framed(const char* tag,JsonDocument& d) { Serial.printf("<<%s ",tag); serializeJson(d,Serial); Serial.println(">>"); }
static void dumpState() {
  JsonDocument d; telemetry(d);
  d["creature"]=tama.state; d["effort"]=tama.effort; d["cheer"]=tama.cheer; d["uhoh"]=tama.uhoh;
  d["overlay"]=tama.overlay; d["greetLevel"]=tama.greetLevel; d["nudgeRung"]=tama.nudgeRung; d["card"]=hasCard(); d["cardId"]=tama.card.id; d["armed"]=false;
  d["scope"]=tama.scope;
  d["bubble"]=bubbleVisible()?bubbleText():""; d["gift"]=false; d["focus"]=tama.focus; d["posture"]=posture;
  d["threadPage"]=threadPage; d["threadCount"]=tama.threadCount; d["recentCount"]=tama.recentCount;
  d["noticeVisible"]=noticeVisible(); d["noticeCount"]=tama.notice.count; d["noticeAge"]=nowMs()-noticeAt;
  d["dashboardAge"]=nowMs()-dashboardAt; d["dashboard"]=dashboardWanted(); d["workingCount"]=tama.workingCount(); d["idleCount"]=tama.idleCount();
  d["dots"]=tama.dots; d["dotAlert"]=tama.dotAlert; d["mute"]=tama.mute; d["screenOff"]=screenOff; d["brightness"]=screenOff?0:brightness;
  d["presence"]=presenceName(); d["napping"]=napping; d["dizzy"]=before(nowMs(),dizzyUntil); d["frozen"]=clockFrozen;
  d["now"]=nowMs(); d["badFrames"]=badFrames; d["parseFails"]=_parseFailCount; d["lineOverflows"]=_lineOverflowCount;
  d["bleDrops"]=bleRxDropped(); d["connected"]=dataConnected(); d["feedback"]=""; d["layer"]=layerNames[screenLayer()];
  d["stats"]=before(nowMs(),statsUntil); d["statsPage"]=statsPage; d["snapName"]=tama.snap.name;
  d["snapTasks"]=tama.snap.tasks; d["skin"]=tama.cosmetic.skin; d["firstWake"]=firstWake;
  d["accessory"]=tama.cosmetic.accessory; d["silhouette"]=tama.cosmetic.silhouette;
  d["ritual"]=ritualName(); d["grey"]=firstWake && ritual!=R_COLOR;
  d["colorProgress"]=colorAmount(nowMs()); d["cosmeticProgress"]=cosmeticAmount(nowMs());
  d["level"]=tama.snap.level; d["streak"]=tama.snap.streak;
  d["pickup"]=before(nowMs(),perkUntil) && !hasCard(); d["pose"]=poseName();
  d["sound"]=soundIndex>=0?motifs[soundIndex].name:""; d["soundCount"]=soundsPlayed; d["soundNote"]=soundNote;
  d["drawCount"]=drawCount; d["touchReady"]=halTouchReady(); d["imuReady"]=halImuReady();
  d["rtcValid"]=dataRtcValid();
  d["shutdownStage"]=(buttons[1].shutdown||buttons[2].shutdown)?"night night":
    ((buttons[1].down&&buttons[1].focusSent)||(buttons[2].down&&buttons[2].focusSent))?"focus":"none";
  framed("STATE",d);
}

static void restoreLogLevel() {
#if defined(CORE_DEBUG_LEVEL) && CORE_DEBUG_LEVEL >= 5
  esp_log_level_set("*", ESP_LOG_VERBOSE);
#elif defined(CORE_DEBUG_LEVEL) && CORE_DEBUG_LEVEL == 4
  esp_log_level_set("*", ESP_LOG_DEBUG);
#elif defined(CORE_DEBUG_LEVEL) && CORE_DEBUG_LEVEL == 3
  esp_log_level_set("*", ESP_LOG_INFO);
#elif defined(CORE_DEBUG_LEVEL) && CORE_DEBUG_LEVEL == 2
  esp_log_level_set("*", ESP_LOG_WARN);
#elif defined(CORE_DEBUG_LEVEL) && CORE_DEBUG_LEVEL == 1
  esp_log_level_set("*", ESP_LOG_ERROR);
#else
  esp_log_level_set("*", ESP_LOG_NONE);
#endif
}

static uint32_t crc32Update(uint32_t crc, const uint8_t* data, size_t len) {
  crc = ~crc;
  for (size_t i = 0; i < len; i++) {
    crc ^= data[i];
    for (uint8_t bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ (0xEDB88320UL & (-(int32_t)(crc & 1)));
    }
  }
  return ~crc;
}

static inline uint16_t rgb332to565(uint8_t c) {
  uint16_t r5 = (((c >> 5) & 7) * 31 + 3) / 7;
  uint16_t g6 = (((c >> 2) & 7) * 63 + 3) / 7;
  uint16_t b5 = ((c & 3) * 31 + 1) / 3;
  return (uint16_t)((r5 << 11) | (g6 << 5) | b5);
}

static void dumpScreenshot() {
  static const char b64[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

  esp_log_level_set("*", ESP_LOG_NONE);
  // The dump streams ~450KB and the host is actively reading it — restore
  // back-pressure for its duration, else the 0-timeout policy (which keeps
  // taps from freezing the pet) silently drops rows mid-stream.
  Serial.setTxTimeoutMs(250);

  int rot = halDisplayRotation();
  int w   = spr.width();
  int h   = spr.height();
  if (w <= 0 || w > 512 || h <= 0) {
    Serial.println("<<SCR_ERR bad-dims>>");
    restoreLogLevel();
    return;
  }

  Serial.printf("\n<<SCR_BEGIN W=%d H=%d ROT=%d FMT=RGB565LE>>\n", w, h, rot);

  uint8_t bytes[2 + 512 * 2];   // carried remainder + one row
  char enc[((sizeof(bytes) / 3) + 1) * 4];
  int nc = 0;                   // bytes carried from the previous row
  uint32_t crc = 0;
  uint32_t rawLen = 0;
  for (int y = 0; y < h; y++) {
    guardFeed();   // full dump takes several seconds of loop() time
    int n = nc;
    for (int x = 0; x < w; x++) {
      uint16_t px = rgb332to565((uint8_t)spr.readPixelValue(x, y));
      bytes[n++] = (uint8_t)(px & 0xFF);
      bytes[n++] = (uint8_t)(px >> 8);
    }
    crc = crc32Update(crc, bytes + nc, n - nc);
    rawLen += n - nc;
    int usable = (n / 3) * 3;
    int o = 0;
    for (int i = 0; i < usable; i += 3) {
      uint32_t v = ((uint32_t)bytes[i] << 16) | ((uint32_t)bytes[i+1] << 8) | (uint32_t)bytes[i+2];
      enc[o++] = b64[(v >> 18) & 0x3F];
      enc[o++] = b64[(v >> 12) & 0x3F];
      enc[o++] = b64[(v >>  6) & 0x3F];
      enc[o++] = b64[ v        & 0x3F];
    }
    Serial.write((const uint8_t*)enc, o);
    nc = n - usable;
    if (nc) memmove(bytes, bytes + usable, nc);
  }
  if (nc) {
    uint32_t v = ((uint32_t)bytes[0] << 16) | (nc > 1 ? ((uint32_t)bytes[1] << 8) : 0);
    char tail[4];
    tail[0] = b64[(v >> 18) & 0x3F];
    tail[1] = b64[(v >> 12) & 0x3F];
    tail[2] = nc > 1 ? b64[(v >> 6) & 0x3F] : '=';
    tail[3] = '=';
    Serial.write((const uint8_t*)tail, 4);
  }
  Serial.println();
  Serial.printf("<<SCR_END LEN=%lu CRC32=%08lx>>\n", (unsigned long)rawLen, (unsigned long)crc);
  Serial.setTxTimeoutMs(0);
  restoreLogLevel();
}

void handleSerialCommand(const char* line) {
  if (!strcmp(line,"firstwake reset")) { resetFirstWake(); Serial.println("<<FIRSTWAKE reset>>"); return; }
  if (!strcmp(line,"ping")) { JsonDocument d; telemetry(d); framed("PONG",d); return; }
  if (!strcmp(line,"state")) { dumpState(); return; }
  if (!strcmp(line,"screenshot")) { render(); dumpScreenshot(); return; }
#ifdef BOOP_USB_ONLY
  if (!strncmp(line,"tap ",4)) {
    int x,y; char junk;
    if(sscanf(line+4,"%d %d %c",&x,&y,&junk)==2 && x>=0 && x<HAL_W && y>=0 && y<HAL_H) {
      panelTap(x,y); Serial.println("<<TAP ok>>");
    } else Serial.println("<<TAP error>>");
    return;
  }
#endif
  if (!strncmp(line,"clock ",6)) {
    if (!strcmp(line+6,"clear")) clockClear();
    else if (!strcmp(line+6,"freeze")) clockFreeze();
    else if (!strncmp(line+6,"settle",6)) {
      // Freeze at an exact offset from state entry: bit-identical screenshots
      // regardless of how long the host took to get here.
      unsigned long offset=line[12]==' '?strtoul(line+13,nullptr,10):2500;
      clockFreezeAt(stateAt+offset);
    }
    else {
      char* end=nullptr; unsigned long value=strtoul(line+6,&end,10);
      if (end==line+6 || *end) { Serial.println("<<CLOCK error>>"); return; }
      clockFreezeAt(value);
    }
    ritualTick(); faceSimulate(nowMs(),0); render();
    Serial.printf("<<CLOCK {\"frozen\":%s,\"now\":%lu}>>\n",clockFrozen?"true":"false",(unsigned long)nowMs()); return;
  }
  if (!strcmp(line,"imu")) {
    JsonDocument d; d["ax"]=ax; d["ay"]=ay; d["az"]=az; d["injected"]=imuInjected; d["seen"]=imuSeen;
    d["napping"]=napping; d["dizzy"]=before(nowMs(),dizzyUntil); d["posture"]=posture; framed("IMU",d); return;
  }
  if (!strcmp(line,"imu clear")) { imuInjected=false; Serial.println("<<IMU inject cleared>>"); return; }
  if (!strncmp(line,"imu set ",8)) {
    float x,y,z; char junk;
    if(sscanf(line+8,"%f %f %f %c",&x,&y,&z,&junk)==3 && isfinite(x)&&isfinite(y)&&isfinite(z) && fabsf(x)<16 && fabsf(y)<16 && fabsf(z)<16) {
      ix=x;iy=y;iz=z;imuInjected=true; Serial.println("<<IMU inject>>");
    } else Serial.println("<<IMU error>>");
    return;
  }
  if (!strncmp(line,"press ",6) || !strncmp(line,"btn ",4)) {
    bool quick=!strncmp(line,"btn ",4); char name=0,junk; unsigned duration=120;
    int count=quick?sscanf(line+4,"%c %c",&name,&junk):sscanf(line+6,"%c %u %c",&name,&duration,&junk);
    if ((quick?count==1:count==2) && duration>=20 && duration<=10000) {
      for(int i=0;i<HAL_BTN_COUNT;++i) if(name==btnNames[i] && !buttons[i].injected && !buttons[i].down) {
        buttons[i].injected=true; buttons[i].injectedUntil=millis()+duration;
        Serial.printf("<<PRESS %c down>>\n",name); return;
      }
    }
    Serial.println("<<PRESS error>>"); return;
  }
  if (!strcmp(line,"guardclear")) { guardClear(); JsonDocument d; d["ok"]=true; framed("GUARDCLEAR",d); return; }
  if (!strcmp(line,"clearbonds")) { bleClearBonds(); Serial.println("<<CLEARBONDS ok>>"); return; }
  if (!strcmp(line,"reboot")) { Serial.println("<<REBOOT ok>>"); Serial.flush(); esp_restart(); }
  if (!strcmp(line,"hang")) { Serial.println("<<HANG>>"); while(true) delay(1000); }
  if (!strncmp(line,"deepsleep",9) && (!line[9] || line[9]==' ')) {
    char* end=nullptr; unsigned long ms=line[9]?strtoul(line+10,&end,10):0;
    if (line[9] && (end==line+10 || *end || ms>600000)) return;
    Serial.printf("<<DEEPSLEEP ok %lu>>\n",ms); Serial.flush(); bleStop(); halDeepSleep(ms); return;
  }
}
void setup() {
  Serial.setRxBufferSize(2048); Serial.begin(115200);
  Serial.setTxTimeoutMs(0);
  halInit(); guardInit(); loadPersistent(tama);
  if(guardSafeTier()<2) {
    uint8_t mac[6]={0}; esp_read_mac(mac,ESP_MAC_BT);
    snprintf(btName,sizeof(btName),"Buddy-%02X%02X",mac[4],mac[5]); bleInit(btName);
  }
  spr.setColorDepth(8); spr.setPsram(true);
  if(!spr.createSprite(HAL_W,HAL_H)) { Serial.println("[guard] canvas allocation failed"); return; }
  halSetBrightness(brightness); ritualAt=bootAt=lastInput=stateAt=nowMs();
  ritual=firstWake?R_FIRST_WAKE:R_NONE; faceSimulate(nowMs(),0); render();
}
void loop() {
  guardLoop(); halUpdate(); dataPoll(tama);
  uint32_t now=nowMs();
  presenceTick(now);
  bool linked=dataConnected(), secure=bleConnected()&&bleSecure();
  if((linked&&!lastLinked)||(secure&&!lastSecure)) { sendStatus(); sendBattery(); }
  if(!linked && lastLinked) {
    // Stale attention cards disappear when their data link is lost.
    threadPage=-1; noticeUntil=0;
    tama.card=Card{}; tama.overlay[0]=0;
    tama.posture[0]=0; clearBubble();
  }
  if((!linked && lastLinked) || (!secure && lastSecure)) { glanceBaseline=true; noticeUntil=0; }
  lastLinked=linked; lastSecure=secure;
  static bool priorSystem=false;
  bool sys=systemCard();
  if(sys&&!priorSystem) wake();
  priorSystem=sys;
  buttonsTick(); motionTick(); soundTick(); ritualTick();
  static uint32_t batteryAt=0;
  if (millis()-batteryAt>=2000) {
    batteryAt=millis(); int b=halBatteryPct(); bool c=halIsCharging();
    if(b!=battery || c!=charging) { battery=b;charging=c;sendBattery(); }
  }
  // Brightness (0-255). With only the eyes lit the panel reads darker than
  // the old body-and-field frames did, so the levels sit high. A state
  // change from the app stamps lastInput (frame apply), so a working buddy
  // never dims; a cosmetic update alone does not wake the panel.
  uint8_t target=hasCard()?255:(napping || eq(tama.state,"asleep"))?28:
    now-lastInput>=120000?90:210;
  if (!screenOff && brightness!=target) { brightness=target; }
  static uint32_t previous=0;
  float dt=previous?(now-previous)*0.001f:0.016f; previous=now;
  if(dt>0.05f) dt=0.016f;
  faceSimulate(now,dt);
  static bool touched=false;
  bool touch=halTouchDown();
  if(touch&&!touched) {
    int x=HAL_W/2,y=HAL_H/2;
    halTouchPoint(&x,&y);
    panelTap(x,y);
  }
  touched=touch;
  if(halPresentDue() && !screenOff && spr.width()>0) render();
  delay(HAL_LOOP_MS);
}
