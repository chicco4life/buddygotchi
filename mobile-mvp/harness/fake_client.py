#!/usr/bin/env python3
"""WebSocket client that prints BuddyState transitions and lets you decide.

Type ``approve`` or ``deny`` at the prompt to send a decision for the
currently pending prompt.

Usage:
    python harness/fake_client.py --pairing-code ABCDEF
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import uuid

import aiohttp


class Client:
    def __init__(
        self,
        *,
        url: str,
        pairing_code: str | None,
        token: str | None,
        auto: str | None = None,
        client_id: str | None = None,
    ) -> None:
        self._url = url
        self._pairing_code = pairing_code
        self._token = token
        self._client_id = client_id or f"harness-{uuid.uuid4().hex[:8]}"
        self._prompt_id: str | None = None
        self._ws: aiohttp.ClientWebSocketResponse | None = None
        self._auto = auto  # "approve" | "deny" | None

    async def run(self) -> None:
        async with aiohttp.ClientSession() as session:
            async with session.ws_connect(self._url) as ws:
                self._ws = ws
                await self._hello()
                recv_task = asyncio.create_task(self._recv_loop())
                if self._auto is not None:
                    # Headless auto mode: stay connected until the server
                    # or the user (SIGINT) stops us; we never read stdin.
                    await recv_task
                    return
                input_task = asyncio.create_task(self._input_loop())
                done, pending = await asyncio.wait(
                    [recv_task, input_task], return_when=asyncio.FIRST_COMPLETED
                )
                for t in pending:
                    t.cancel()

    async def _hello(self) -> None:
        payload = {
            "type": "hello",
            "protocolVersion": 1,
            "clientId": self._client_id,
        }
        if self._token is not None:
            payload["token"] = self._token
        if self._pairing_code is not None:
            payload["pairingCode"] = self._pairing_code
        assert self._ws is not None
        await self._ws.send_json(payload)

    async def _recv_loop(self) -> None:
        assert self._ws is not None
        async for msg in self._ws:
            if msg.type != aiohttp.WSMsgType.TEXT:
                continue
            obj = json.loads(msg.data)
            t = obj.get("type")
            if t == "welcome":
                print(f"[welcome] session={obj.get('sessionId')}", file=sys.stderr)
                if obj.get("issuedToken"):
                    print(f"[token]   {obj['issuedToken']}", file=sys.stderr)
                self._render_state(obj["state"])
            elif t == "snapshot":
                self._render_state(obj["state"])
            elif t == "patch":
                print(
                    f"[patch] v{obj['prevVersion']} -> v{obj['version']}: "
                    f"{', '.join(obj['changes'].keys())}",
                    file=sys.stderr,
                )
                changes = obj["changes"]
                if "prompt" in changes:
                    p = changes["prompt"]
                    self._prompt_id = p["id"] if p else None
                    if p:
                        print(
                            f"  prompt = {p['tool']!r} :: {p['hint']!r}",
                            file=sys.stderr,
                        )
                        if self._auto and p.get("decidedBy") is None:
                            decision = (
                                "once" if self._auto == "approve" else "deny"
                            )
                            await self._decide(decision)
                            print(
                                f"  [auto] sent decision={decision}", file=sys.stderr
                            )
                    else:
                        print("  prompt cleared", file=sys.stderr)
                if "pet" in changes:
                    print(f"  pet = {changes['pet']['state']}", file=sys.stderr)
                if "desktop" in changes:
                    print(f"  desktop = {changes['desktop']['status']}", file=sys.stderr)
            elif t == "ack":
                print(
                    f"[ack] reqId={obj.get('reqId')} ok={obj['ok']}"
                    + (f" error={obj['error']}" if obj.get("error") else ""),
                    file=sys.stderr,
                )
            else:
                print(f"[?] {obj}", file=sys.stderr)

    def _render_state(self, s: dict) -> None:
        self._prompt_id = s["prompt"]["id"] if s.get("prompt") else None
        print(
            f"[state v{s['version']}] desktop={s['desktop']['status']} "
            f"pet={s['pet']['state']} prompt={self._prompt_id or '-'} "
            f"running={s['sessions']['running']} waiting={s['sessions']['waiting']}",
            file=sys.stderr,
        )

    async def _input_loop(self) -> None:
        loop = asyncio.get_event_loop()
        while True:
            line = await loop.run_in_executor(None, sys.stdin.readline)
            if not line:
                return
            cmd = line.strip().lower()
            if cmd in ("approve", "a", "once"):
                await self._decide("once")
            elif cmd in ("deny", "d"):
                await self._decide("deny")
            elif cmd in ("quit", "exit"):
                return
            else:
                print("[usage] approve | deny | quit", file=sys.stderr)

    async def _decide(self, decision: str) -> None:
        if self._ws is None or self._prompt_id is None:
            print("[skip] no active prompt", file=sys.stderr)
            return
        await self._ws.send_json(
            {
                "type": "decide",
                "reqId": uuid.uuid4().hex[:8],
                "promptId": self._prompt_id,
                "decision": decision,
            }
        )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="ws://127.0.0.1:8080/ws")
    ap.add_argument("--pairing-code", dest="pairing_code", default=None)
    ap.add_argument("--token", default=None)
    ap.add_argument(
        "--auto",
        choices=["approve", "deny"],
        default=None,
        help="auto-decide every pending prompt (headless testing)",
    )
    ap.add_argument(
        "--client-id",
        dest="client_id",
        default=None,
        help="stable client id; keep constant across runs when reusing --token",
    )
    args = ap.parse_args()
    if not args.pairing_code and not args.token:
        ap.error("need --pairing-code or --token")
    try:
        asyncio.run(
            Client(
                url=args.url,
                pairing_code=args.pairing_code,
                token=args.token,
                auto=args.auto,
                client_id=args.client_id,
            ).run()
        )
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
