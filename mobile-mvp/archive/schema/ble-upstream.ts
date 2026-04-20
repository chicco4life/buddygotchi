// Boundary [A]: Claude desktop <-> daemon over BLE Nordic UART Service.
//
// This file is the authoritative TypeScript mirror of the protocol
// specified in ../../REFERENCE.md. We do not invent new messages here.
// Every field below maps 1:1 to the wire protocol.
//
// Wire format: UTF-8, one JSON object per line, \n terminated.

export type EpochSeconds = number;
export type TzOffsetSeconds = number;

// ---------------------------------------------------------------------------
// Desktop -> Device (unsolicited; no ack required from our side)
// ---------------------------------------------------------------------------

export interface TimeSync {
  time: [EpochSeconds, TzOffsetSeconds];
}

export interface Heartbeat {
  total: number;
  running: number;
  waiting: number;
  msg: string;
  entries: string[]; // newest first, capped by desktop
  tokens: number;
  tokens_today: number;
  prompt?: PendingPrompt;
}

export interface PendingPrompt {
  id: string;
  tool: string;
  hint: string;
}

// Turn events are fired per completed turn. We intentionally omit them
// from BuddyState per project decision; parser accepts and drops them.
export interface TurnEvent {
  evt: "turn";
  role: "assistant" | "user";
  content: unknown[];
}

// ---------------------------------------------------------------------------
// Desktop -> Device (commands requiring ack)
// ---------------------------------------------------------------------------

export type DesktopCommand =
  | { cmd: "status" }
  | { cmd: "name"; name: string }
  | { cmd: "owner"; name: string }
  | { cmd: "unpair" }
  // Folder push family. For MVP we do NOT ack char_begin; desktop
  // times out and informs the user. The remaining messages are listed
  // here for schema completeness.
  | { cmd: "char_begin"; name: string; total: number }
  | { cmd: "file"; path: string; size: number }
  | { cmd: "chunk"; d: string } // base64
  | { cmd: "file_end" }
  | { cmd: "char_end" };

// ---------------------------------------------------------------------------
// Device -> Desktop
// ---------------------------------------------------------------------------

export interface PermissionDecision {
  cmd: "permission";
  id: string;
  decision: "once" | "deny";
}

export interface Ack {
  ack: string; // echoes the original cmd string
  ok: boolean;
  n?: number;
  error?: string;
  data?: unknown; // used for status
}

export interface StatusAckData {
  name: string;
  sec: boolean;
  bat?: { pct: number; mV: number; mA: number; usb: boolean };
  sys?: { up: number; heap: number };
  stats?: { appr: number; deny: number; vel: number; nap: number; lvl: number };
}

// Discriminated union of every line the daemon may receive on NUS RX.
export type DesktopInbound =
  | TimeSync
  | Heartbeat
  | TurnEvent
  | DesktopCommand;

// Discriminated union of every line the daemon may write on NUS TX.
export type DeviceOutbound = PermissionDecision | Ack;
