"""Pairing codes + per-client bearer tokens.

MVP policy:

* On boot, the daemon generates one pairing code, prints it, and keeps
  it valid until first successful use or TTL expiry.
* After successful hello with a valid code, the client's ``clientId``
  gets a random bearer token. Future hellos may use ``token`` instead
  of ``pairingCode``.
* Tokens persist to a JSON file so a daemon restart doesn't invalidate
  already-paired phones. Deleting the file forces re-pairing.
* Pairing codes are NOT persisted; they die with the process.

A ``clientId`` with no token and no pairingCode gets ``E_PAIRING_REQUIRED``.
A ``clientId`` with a bad token gets ``E_PAIRING_INVALID``.
"""

from __future__ import annotations

import json
import secrets
import string
import time
from dataclasses import dataclass
from pathlib import Path
from threading import Lock

_ALPHABET = string.ascii_uppercase + string.digits
_CODE_LEN = 6
_TOKEN_BYTES = 24


def _mk_code() -> str:
    # Avoid ambiguous chars to make typing on a phone easier.
    ambiguous = set("O0I1")
    pool = [c for c in _ALPHABET if c not in ambiguous]
    return "".join(secrets.choice(pool) for _ in range(_CODE_LEN))


def _mk_token() -> str:
    return secrets.token_urlsafe(_TOKEN_BYTES)


@dataclass(slots=True)
class PairingOutcome:
    ok: bool
    error: str | None = None
    issued_token: str | None = None


class PairingManager:
    def __init__(self, *, state_path: Path, ttl_s: int) -> None:
        self._state_path = state_path
        self._ttl_s = ttl_s
        self._lock = Lock()
        self._code: str | None = None
        self._code_issued_at: float = 0.0
        self._tokens: dict[str, str] = self._load()

    # --- code lifecycle ---

    def rotate_code(self) -> str:
        with self._lock:
            self._code = _mk_code()
            self._code_issued_at = time.time()
            return self._code

    def current_code(self) -> str | None:
        with self._lock:
            if self._code is None:
                return None
            if time.time() - self._code_issued_at > self._ttl_s:
                self._code = None
                return None
            return self._code

    # --- auth ---

    def authorize(
        self,
        *,
        client_id: str,
        pairing_code: str | None,
        token: str | None,
    ) -> PairingOutcome:
        with self._lock:
            if token is not None:
                expected = self._tokens.get(client_id)
                if expected is None or not secrets.compare_digest(expected, token):
                    return PairingOutcome(ok=False, error="E_PAIRING_INVALID")
                return PairingOutcome(ok=True)

            if pairing_code is None:
                return PairingOutcome(ok=False, error="E_PAIRING_REQUIRED")

            code = self._code
            fresh = (
                code is not None
                and time.time() - self._code_issued_at <= self._ttl_s
            )
            if not fresh or code is None:
                return PairingOutcome(ok=False, error="E_PAIRING_INVALID")
            if not secrets.compare_digest(code, pairing_code.strip().upper()):
                return PairingOutcome(ok=False, error="E_PAIRING_INVALID")

            new_token = _mk_token()
            self._tokens[client_id] = new_token
            # Code is single-use by default; rotate on next request.
            self._code = None
            self._save()
            return PairingOutcome(ok=True, issued_token=new_token)

    # --- persistence ---

    def _load(self) -> dict[str, str]:
        try:
            raw = self._state_path.read_text(encoding="utf-8")
        except FileNotFoundError:
            return {}
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        if not isinstance(data, dict):
            return {}
        return {str(k): str(v) for k, v in data.items() if isinstance(v, str)}

    def _save(self) -> None:
        self._state_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self._state_path.with_suffix(self._state_path.suffix + ".tmp")
        tmp.write_text(json.dumps(self._tokens), encoding="utf-8")
        tmp.replace(self._state_path)
