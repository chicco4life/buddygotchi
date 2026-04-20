// Closed set. Adding a code is a protocol change; removing one breaks
// clients. Every error surfaced to a web client MUST be one of these.

export type ErrorCode =
  | "E_BAD_MESSAGE"           // schema violation on [B]
  | "E_UNSUPPORTED"           // unknown cmd on [A] or unknown type on [B]
  | "E_PAIRING_REQUIRED"      // hello missing pairingCode or token
  | "E_PAIRING_INVALID"       // wrong code or expired token
  | "E_RATE_LIMIT"            // client exceeded decision frequency
  | "E_NO_ACTIVE_PROMPT"      // decide arrived but no prompt pending
  | "E_PROMPT_ID_MISMATCH"    // decide targets a prompt id that isn't current
  | "E_ALREADY_DECIDED"       // another client's decision already landed
  | "E_DESKTOP_DISCONNECTED"  // can't forward decision upstream
  | "E_BLE_WRITE_FAILED"      // desktop connected but NUS TX failed
  | "E_VERSION_SKEW";         // client's lastVersion is ahead of ours

export const ALL_ERROR_CODES: ErrorCode[] = [
  "E_BAD_MESSAGE",
  "E_UNSUPPORTED",
  "E_PAIRING_REQUIRED",
  "E_PAIRING_INVALID",
  "E_RATE_LIMIT",
  "E_NO_ACTIVE_PROMPT",
  "E_PROMPT_ID_MISMATCH",
  "E_ALREADY_DECIDED",
  "E_DESKTOP_DISCONNECTED",
  "E_BLE_WRITE_FAILED",
  "E_VERSION_SKEW",
];
