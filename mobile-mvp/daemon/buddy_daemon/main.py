"""Entrypoint. ``python -m buddy_daemon`` or ``buddy-daemon``."""

from __future__ import annotations

import asyncio
import logging
import signal
from pathlib import Path

from aiohttp import web

from .bridge import Bridge
from .config import Config
from .hook_upstream import HookUpstream
from .pairing import PairingManager
from .ws_server import SESSION_ID, build_app


def _setup_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-5s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )


async def _run() -> None:
    _setup_logging()
    log = logging.getLogger("buddy_daemon")
    config = Config.from_env()

    state_dir = Path(config.state_dir) if config.state_dir else Path.home() / ".buddy-daemon"
    state_dir.mkdir(parents=True, exist_ok=True)
    pairing = PairingManager(
        state_path=state_dir / "pairing-state.json",
        ttl_s=config.pairing_code_ttl_s,
    )
    code = pairing.rotate_code()

    hook_upstream = HookUpstream()
    bridge = Bridge(config=config, upstream=hook_upstream)

    web_root = _locate_web_root()
    app = build_app(
        config=config,
        bridge=bridge,
        pairing=pairing,
        hook_upstream=hook_upstream,
        web_root=web_root,
    )

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, config.http_host, config.http_port)
    await site.start()

    await bridge.start()

    _banner(log, config=config, code=code)

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:
            pass

    try:
        await stop.wait()
    finally:
        log.info("shutting down")
        await bridge.stop()
        await runner.cleanup()


def _banner(log: logging.Logger, *, config: Config, code: str) -> None:
    host = _display_host(config.http_host)
    port = config.http_port
    bar = "=" * 56
    log.info(bar)
    log.info("buddy-daemon  session=%s", SESSION_ID)
    log.info("Web UI         http://%s:%d/", host, port)
    log.info("WebSocket      ws://%s:%d/ws", host, port)
    log.info("Hook endpoint  http://%s:%d/hook/request  (POST)", host, port)
    log.info("Health         http://%s:%d/healthz", host, port)
    log.info("")
    log.info("Pairing code   %s   (valid %ds)", code, config.pairing_code_ttl_s)
    log.info(bar)


def _display_host(host: str) -> str:
    return "localhost" if host in ("0.0.0.0", "::") else host


def _locate_web_root() -> Path | None:
    """Locate ``mobile-mvp/web/`` from any sensible starting dir.

    We avoid hard-coding an absolute path so ``pip install -e`` and
    copy-deploy both work. First match wins:

    1. ``$BUDDY_WEB_ROOT`` if set and contains ``index.html``.
    2. ``<repo>/mobile-mvp/web`` relative to this file.
    3. None (web UI disabled; daemon still serves /ws and /hook).
    """
    import os

    override = os.environ.get("BUDDY_WEB_ROOT")
    if override:
        p = Path(override).expanduser().resolve()
        if (p / "index.html").is_file():
            return p

    # __file__ is .../mobile-mvp/daemon/buddy_daemon/main.py
    candidate = Path(__file__).resolve().parents[2] / "web"
    if (candidate / "index.html").is_file():
        return candidate
    return None


def main() -> None:
    try:
        asyncio.run(_run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
