"""Daemon configuration.

For MVP, config is env-var driven with sensible defaults. A YAML loader
can be added later without touching call sites.
"""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Config:
    http_host: str = "0.0.0.0"
    http_port: int = 8080

    # Loopback TCP port used by the test fixture upstream (tests only;
    # never bound by the production daemon).
    fake_upstream_host: str = "127.0.0.1"
    fake_upstream_port: int = 8765

    # Desktop is considered "stale" if no heartbeat for this long.
    stale_timeout_ms: int = 30_000

    # Pairing code TTL. Code is printed on boot and can be rotated via
    # GET /pair/current (loopback only). Default 24h keeps demo sessions
    # from expiring mid-work.
    pairing_code_ttl_s: int = 24 * 3600

    # Rate limit: min ms between a given client's decide messages.
    decide_min_interval_ms: int = 500

    # Optional: expose /raw for inbound-line debugging. Off by default.
    debug_raw: bool = False

    # Where pairing tokens etc. are persisted. Defaults to ~/.buddy-daemon
    # when empty; set BUDDY_STATE_DIR to override (useful in sandboxed
    # environments / CI).
    state_dir: str = ""

    @classmethod
    def from_env(cls) -> "Config":
        def i(name: str, default: int) -> int:
            raw = os.environ.get(name)
            return int(raw) if raw else default

        def s(name: str, default: str) -> str:
            return os.environ.get(name, default)

        def b(name: str, default: bool) -> bool:
            raw = os.environ.get(name)
            if raw is None:
                return default
            return raw.lower() in ("1", "true", "yes", "on")

        return cls(
            http_host=s("BUDDY_HTTP_HOST", "0.0.0.0"),
            http_port=i("BUDDY_HTTP_PORT", 8080),
            fake_upstream_host=s("BUDDY_FAKE_HOST", "127.0.0.1"),
            fake_upstream_port=i("BUDDY_FAKE_PORT", 8765),
            stale_timeout_ms=i("BUDDY_STALE_MS", 30_000),
            pairing_code_ttl_s=i("BUDDY_PAIRING_TTL_S", 24 * 3600),
            decide_min_interval_ms=i("BUDDY_DECIDE_MIN_MS", 500),
            debug_raw=b("BUDDY_DEBUG_RAW", False),
            state_dir=s("BUDDY_STATE_DIR", ""),
        )
