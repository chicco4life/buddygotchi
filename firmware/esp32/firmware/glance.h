#pragma once
// Local presentation deadlines never depend on host wall-clock time.
static int threadPage=-1;
static bool glanceBaseline=true;
static uint32_t noticeAt=0, noticeUntil=0, noticeSeen=0, noticeRevision=0, noticeTextAt=0;
static bool noticeVisible() {
  return noticeUntil && before(nowMs(),noticeUntil) && dataConnected() && !napping && !screenOff &&
    !hasCard() && strcmp(tama.state,"uhoh") && strcmp(tama.state,"asleep") && threadPage<0;
}
static void glanceFrame(const TamaState& next) {
  uint32_t now=nowMs();
  bool permitted=!systemCard() && !next.card.present() && strcmp(next.state,"needsYou") && strcmp(next.state,"uhoh") && strcmp(next.state,"asleep");
  if (!next.notice.id || !permitted || threadPage>=0) noticeUntil=0;
  if (next.notice.id && next.notice.id!=noticeSeen) {
    noticeSeen=next.notice.id;
    // Baseline after startup/reconnect: retain history, never replay a cheer.
    if (!glanceBaseline && dataConnected() && permitted && threadPage<0) {
      noticeAt=now-next.notice.age;
      noticeUntil=now+next.notice.left;
      stateAt=noticeAt;
      lastInput=now;
    }
  } else if (noticeUntil && next.notice.id && before(now,noticeUntil)) {
    if(next.notice.count>tama.notice.count) {
      if(before(noticeUntil,now+2000)) noticeUntil=now+2000;
      if(before(noticeAt+8000,noticeUntil)) noticeUntil=noticeAt+8000;
    }
    // An authoritative shorter deadline is respected; repeated frames don't extend it.
    if(before(now+next.notice.left,noticeUntil)) noticeUntil=now+next.notice.left;
  }
  glanceBaseline=false;
  uint32_t revision=next.recentCount?next.recent[0].sequence:0;
  if(revision!=noticeRevision) { noticeRevision=revision; noticeTextAt=now; }
  if(!permitted || !dataConnected() || (!next.threadCount && !next.recentCount)) threadPage=-1;
}
static int detailPages() {
  return (tama.threadCount+2)/3+(tama.recentCount+2)/3;
}
static bool detailTap() {
  if(threadPage>=0) { threadPage=-1; return true; }
  if(dataConnected() && strcmp(tama.state,"uhoh") && strcmp(tama.state,"needsYou") && strcmp(tama.state,"asleep") && (tama.workingCount()>0 || tama.recentCount) && detailPages()) {
    threadPage=0; noticeUntil=0; statsUntil=0; bubbleDismissed=true; localBubbleUntil=0; return true;
  }
  return false;
}
