// Claude Buddy web client. Vanilla ES module, no deps.
//
// Protocol: ../schema/ws-protocol.ts (hello/welcome/snapshot/patch/decide/ack).
// State:    ../schema/state.ts
//
// Storage:
//   localStorage.buddyToken    bearer token issued by the daemon at pair time
//   localStorage.buddyClientId stable id for this browser profile

import {
  BUDDIES,
  BUDDY_ORDER,
  DEFAULT_BUDDY,
  overlayFor,
  renderFrame,
} from "./buddy.js";
import { paintOverlay, resizeOverlay } from "./particles.js";

/** @typedef {{id:string,tool:string,hint:string,arrivedAt:number,decidedBy?:{clientId:string,decision:string,at:number}|null}} Prompt */
/** @typedef {{version:number,updatedAt:number,desktop:{status:string},sessions:{total:number,running:number,waiting:number},msg:string,entries:string[],tokens:number,tokensToday:number,prompt:Prompt|null,pet:{state:string},owner:string,lastSignal:string|null}} BuddyState */

const LS = {
  TOKEN: "buddyToken",
  CLIENT_ID: "buddyClientId",
  SPECIES: "buddySpecies",
};

const els = {
  pairView: document.getElementById("pair-view"),
  liveView: document.getElementById("live-view"),
  pairForm: document.getElementById("pair-form"),
  code: document.getElementById("code"),
  pairSubmit: document.getElementById("pair-submit"),
  pairError: document.getElementById("pair-error"),
  localCodeHint: document.getElementById("local-code-hint"),
  localCode: document.getElementById("local-code"),
  useLocalCode: document.getElementById("use-local-code"),
  petArt: document.getElementById("pet-art"),
  petOverlay: document.getElementById("pet-overlay"),
  petLabel: document.getElementById("pet-label"),
  petSpecies: document.getElementById("pet-species"),
  petPrev: document.getElementById("pet-prev"),
  petNext: document.getElementById("pet-next"),
  link: document.getElementById("link"),
  idleCard: document.getElementById("idle-card"),
  idleTitle: document.getElementById("idle-title"),
  idleSub: document.getElementById("idle-sub"),
  promptCard: document.getElementById("prompt-card"),
  promptSource: document.getElementById("prompt-source"),
  promptTool: document.getElementById("prompt-tool"),
  promptHint: document.getElementById("prompt-hint"),
  decidedLine: document.getElementById("decided-line"),
  approve: document.getElementById("approve"),
  deny: document.getElementById("deny"),
  status: document.getElementById("status-line"),
  unpair: document.getElementById("unpair"),
  dbgState: document.getElementById("dbg-state"),
  dbgSignal: document.getElementById("dbg-signal"),
  dbgSession: document.getElementById("dbg-session"),
  dbgVersion: document.getElementById("dbg-version"),
  dbgEntries: document.getElementById("dbg-entries"),
};

/** @type {WebSocket|null} */
let ws = null;
/** @type {BuddyState|null} */
let state = null;
let backoff = 500;
let reqSeq = 0;
const newReqId = () => `r${Date.now()}-${++reqSeq}`;

function getClientId() {
  let id = localStorage.getItem(LS.CLIENT_ID);
  if (!id) {
    id = "web-" + crypto.randomUUID().slice(0, 12);
    localStorage.setItem(LS.CLIENT_ID, id);
  }
  return id;
}

function getToken() { return localStorage.getItem(LS.TOKEN); }
function setToken(t) { localStorage.setItem(LS.TOKEN, t); }
function clearToken() { localStorage.removeItem(LS.TOKEN); }

function wsUrl() {
  const scheme = location.protocol === "https:" ? "wss" : "ws";
  return `${scheme}://${location.host}/ws`;
}

function showPairView() {
  els.liveView.hidden = true;
  els.pairView.hidden = false;
  els.pairError.hidden = true;
  els.code.focus();
  maybeShowLocalCode();
}

async function maybeShowLocalCode() {
  try {
    const resp = await fetch("/pair/current", { cache: "no-store" });
    if (!resp.ok) return;
    const body = await resp.json();
    if (typeof body.code === "string" && body.code.length === 6) {
      els.localCode.textContent = body.code;
      els.localCodeHint.hidden = false;
      els.useLocalCode.hidden = false;
    }
  } catch {
    // Non-loopback clients (phone on LAN) will get 403; that's expected.
  }
}

els.useLocalCode.addEventListener("click", () => {
  const v = (els.localCode.textContent || "").trim();
  if (v.length === 6) {
    els.code.value = v;
    els.pairForm.requestSubmit();
  }
});

function showLiveView() {
  els.pairView.hidden = true;
  els.liveView.hidden = false;
}

function setStatus(line) {
  els.status.textContent = line;
}

function setPetAndLink(s) {
  const st = s.pet.state;
  if (currentPetState !== st) {
    currentPetState = st;
    els.petArt.dataset.state = st;
    els.petLabel.dataset.state = st;
    els.petLabel.textContent = st;
  }
  els.link.textContent = s.desktop.status;
  els.link.dataset.status = s.desktop.status;
}

// --- Buddy species picker -----------------------------------------
let currentBuddyName =
  (BUDDIES[localStorage.getItem(LS.SPECIES)] && localStorage.getItem(LS.SPECIES)) ||
  DEFAULT_BUDDY.name;
let currentBuddy = BUDDIES[currentBuddyName];

function applyBuddy(name) {
  if (!BUDDIES[name]) return;
  currentBuddyName = name;
  currentBuddy = BUDDIES[name];
  localStorage.setItem(LS.SPECIES, name);
  els.petSpecies.textContent = name;
  document.documentElement.style.setProperty("--pet-color", currentBuddy.color);
  queueResize();
}

function cycleBuddy(dir) {
  const i = BUDDY_ORDER.indexOf(currentBuddyName);
  const next = BUDDY_ORDER[(i + dir + BUDDY_ORDER.length) % BUDDY_ORDER.length];
  applyBuddy(next);
}

els.petPrev.addEventListener("click", () => cycleBuddy(-1));
els.petNext.addEventListener("click", () => cycleBuddy(+1));

// --- Buddy animation loop + overlay particles ---------------------

let currentPetState = null;
const animStartMs = performance.now();
let resizeQueued = true;

function queueResize() { resizeQueued = true; }
window.addEventListener("resize", queueResize);

function tickBuddy() {
  const t = performance.now() - animStartMs;
  const state = currentPetState || "idle";
  const frame = renderFrame(currentBuddy, state, t);
  if (els.petArt.textContent !== frame) {
    els.petArt.textContent = frame;
  }
  if (resizeQueued) {
    resizeOverlay(els.petOverlay, els.petArt);
    resizeQueued = false;
  }
  paintOverlay(els.petOverlay, overlayFor(currentBuddy, state), t);
  requestAnimationFrame(tickBuddy);
}

applyBuddy(currentBuddyName);
requestAnimationFrame(tickBuddy);

// --- Debug panel ---------------------------------------------------

function renderDebug(s) {
  els.dbgState.textContent = s.pet.state;
  els.dbgSignal.textContent = s.lastSignal || "—";
  els.dbgVersion.textContent = String(s.version);

  const ol = els.dbgEntries;
  ol.textContent = "";
  for (const entry of s.entries) {
    const li = document.createElement("li");
    li.textContent = entry;
    ol.appendChild(li);
  }
}

// --- Render state --------------------------------------------------

function render(s) {
  state = s;
  setPetAndLink(s);
  renderDebug(s);
  const p = s.prompt;
  if (!p) {
    els.promptCard.hidden = true;
    els.idleCard.hidden = false;
    const running = s.sessions.running;
    els.idleTitle.textContent = running > 0 ? `running ${running}` : "nothing pending";
    els.idleSub.textContent = s.msg || "your buddy is watching. you'll see approval requests here.";
    return;
  }
  const src = (p.source && typeof p.source === "string") ? p.source : "other";
  els.idleCard.hidden = true;
  els.promptCard.hidden = false;
  els.promptSource.textContent = src;
  els.promptSource.dataset.src = src;
  els.promptTool.textContent = p.tool || "tool";
  els.promptHint.textContent = p.hint || "";
  if (p.decidedBy) {
    els.decidedLine.hidden = false;
    els.decidedLine.textContent =
      `decided: ${p.decidedBy.decision} by ${p.decidedBy.clientId}`;
    els.approve.disabled = true;
    els.deny.disabled = true;
  } else {
    els.decidedLine.hidden = true;
    els.approve.disabled = false;
    els.deny.disabled = false;
  }
}

function applyPatch(changes) {
  if (!state) return;
  const next = { ...state, ...changes };
  render(next);
}

// --- WS lifecycle --------------------------------------------------

function connect() {
  const token = getToken();
  if (!token) {
    showPairView();
    return;
  }
  showLiveView();
  setStatus("connecting…");
  ws = new WebSocket(wsUrl());

  ws.addEventListener("open", () => {
    backoff = 500;
    setStatus("authenticating…");
    send({
      type: "hello",
      protocolVersion: 1,
      clientId: getClientId(),
      token,
    });
  });

  ws.addEventListener("message", (ev) => {
    let msg;
    try { msg = JSON.parse(ev.data); } catch { return; }
    onMessage(msg);
  });

  ws.addEventListener("close", () => {
    setStatus("disconnected · reconnecting");
    ws = null;
    setTimeout(connect, backoff);
    backoff = Math.min(8000, Math.round(backoff * 1.6));
  });

  ws.addEventListener("error", () => {});
}

function send(obj) {
  if (!ws || ws.readyState !== WebSocket.OPEN) return;
  ws.send(JSON.stringify(obj));
}

function onMessage(msg) {
  switch (msg.type) {
    case "welcome":
      setStatus(`paired · session ${msg.sessionId ?? ""}`);
      els.dbgSession.textContent = msg.sessionId ?? "—";
      if (msg.issuedToken) setToken(msg.issuedToken);
      if (msg.state) render(msg.state);
      break;
    case "snapshot":
      if (msg.state) render(msg.state);
      break;
    case "patch":
      applyPatch(msg.changes || {});
      break;
    case "ack":
      if (msg.ok === false) {
        if (msg.error === "E_PAIRING_INVALID" || msg.error === "E_PAIRING_REQUIRED") {
          clearToken();
          setStatus("pairing rejected");
          if (ws) ws.close();
          showPairView();
          els.pairError.hidden = false;
          els.pairError.textContent = "pairing invalid or expired. enter a fresh code.";
        } else {
          setStatus(`error: ${msg.error || "unknown"}`);
        }
      }
      break;
  }
}

// --- Pair flow -----------------------------------------------------

els.pairForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const code = els.code.value.trim().toUpperCase();
  if (!code || code.length !== 6) {
    els.pairError.textContent = "need a 6-character code";
    els.pairError.hidden = false;
    return;
  }
  els.pairSubmit.disabled = true;
  els.pairError.hidden = true;

  try {
    const token = await pairWithCode(code);
    setToken(token);
    connect();
  } catch (err) {
    els.pairError.textContent = String(err.message || err);
    els.pairError.hidden = false;
  } finally {
    els.pairSubmit.disabled = false;
  }
});

function pairWithCode(code) {
  return new Promise((resolve, reject) => {
    const sock = new WebSocket(wsUrl());
    let settled = false;
    const done = (fn) => { if (!settled) { settled = true; fn(); try { sock.close(); } catch {} } };
    sock.addEventListener("open", () => {
      sock.send(JSON.stringify({
        type: "hello",
        protocolVersion: 1,
        clientId: getClientId(),
        pairingCode: code,
      }));
    });
    sock.addEventListener("message", (ev) => {
      let msg; try { msg = JSON.parse(ev.data); } catch { return; }
      if (msg.type === "welcome" && msg.issuedToken) {
        done(() => resolve(msg.issuedToken));
      } else if (msg.type === "ack" && msg.ok === false) {
        done(() => reject(new Error(msg.error || "pairing failed")));
      }
    });
    sock.addEventListener("close", () => done(() => reject(new Error("connection closed"))));
    sock.addEventListener("error", () => done(() => reject(new Error("connection error"))));
    setTimeout(() => done(() => reject(new Error("pairing timed out"))), 7000);
  });
}

// --- Decisions -----------------------------------------------------

els.approve.addEventListener("click", () => decide("once"));
els.deny.addEventListener("click", () => decide("deny"));

function decide(decision) {
  if (!state || !state.prompt || state.prompt.decidedBy) return;
  els.approve.disabled = true;
  els.deny.disabled = true;
  send({
    type: "decide",
    reqId: newReqId(),
    promptId: state.prompt.id,
    decision,
  });
}

// --- Unpair --------------------------------------------------------

els.unpair.addEventListener("click", () => {
  clearToken();
  try { ws && ws.close(); } catch {}
  showPairView();
  setStatus("disconnected");
});

// --- Boot ----------------------------------------------------------

connect();
