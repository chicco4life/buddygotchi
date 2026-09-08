#!/usr/bin/env python3
"""Verify a signing reply with a trusted unit reply.

Dependency: /tmp/hilvenv/bin/python -m pip install cryptography
Usage: python tools/verify_sig.py --unit unit.json reply.json
The unit file must come from a trusted device/provisioning channel. A signature
proves possession of that key, not the truth of host-supplied XP or manufacture.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
from pathlib import Path


def verify_reply(reply: dict, unit: dict) -> bool:
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric import ec, ed25519

    try:
        if reply.get("ack") != "sign" or reply.get("ok") is not True:
            return False
        if unit.get("ack") != "unit" or unit.get("ok") is not True:
            return False
        public = base64.b64decode(unit["pub"], validate=True)
        identity = hashlib.sha256(public).digest()[:8].hex()
        if unit["unit"] != identity or reply["unit"] != identity:
            return False
        day, xp, nonce = reply["day"], reply["xp"], reply["nonce"]
        if not isinstance(day, str) or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", day):
            return False
        if type(xp) is not int or not 0 <= xp <= 2**63-1:
            return False
        if not isinstance(nonce, str) or not re.fullmatch(r"(?:[0-9a-fA-F]{2}){1,32}", nonce):
            return False
        message = f"{identity}|{day}|{xp}|{nonce}".encode("ascii")
        signature = base64.b64decode(reply["sig"], validate=True)
        if unit["alg"] == "p256":
            if len(public) != 65 or public[0] != 4:
                return False
            key = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), public)
            key.verify(signature, message, ec.ECDSA(hashes.SHA256()))
        elif unit["alg"] == "ed25519":
            ed25519.Ed25519PublicKey.from_public_bytes(public).verify(signature, message)
        else:
            return False
        return True
    except (InvalidSignature, ValueError, TypeError, KeyError, AttributeError):
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reply", help="sign reply JSON file, or - for stdin")
    parser.add_argument("--unit", required=True, help="trusted unit reply JSON file")
    args = parser.parse_args()
    try:
        unit = json.loads(Path(args.unit).read_text())
        reply = json.load(sys.stdin) if args.reply == "-" else json.loads(Path(args.reply).read_text())
        valid = verify_reply(reply, unit)
    except ImportError:
        print("Install dependency: /tmp/hilvenv/bin/python -m pip install cryptography", file=sys.stderr)
        return 2
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    print(json.dumps({"ok": valid}))
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
