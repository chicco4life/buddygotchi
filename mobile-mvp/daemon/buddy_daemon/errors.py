"""Closed set of error codes. Mirrors ``../../schema/errors.ts`` exactly.

Any string surfaced to a WS client as an error MUST be one of these.
"""

from __future__ import annotations

from typing import Final, Literal

ErrorCode = Literal[
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
]

ALL_ERROR_CODES: Final[tuple[ErrorCode, ...]] = (
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
)
