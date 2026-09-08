"""Offline host contract checks; requires cryptography, no serial device."""
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519

TOOLS = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS))
from verify_sig import verify_reply
import buddyctl


class SignatureTests(unittest.TestCase):
    def fixture(self, algorithm):
        if algorithm == "p256":
            key = ec.generate_private_key(ec.SECP256R1())
            public = key.public_key().public_bytes(serialization.Encoding.X962,
                                                   serialization.PublicFormat.UncompressedPoint)
        else:
            key = ed25519.Ed25519PrivateKey.generate()
            public = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        unit = dict(ack="unit", ok=True, alg=algorithm, pub=base64.b64encode(public).decode(),
                    unit=hashlib.sha256(public).hexdigest()[:16])
        reply = dict(ack="sign", ok=True, unit=unit["unit"], day="2026-09-09", xp=2**63-1, nonce="aB12")
        message = (unit["unit"] + "|2026-09-09|9223372036854775807|aB12").encode()
        signature = key.sign(message, ec.ECDSA(hashes.SHA256())) if algorithm == "p256" else key.sign(message)
        reply["sig"] = base64.b64encode(signature).decode()
        return unit, reply

    def test_verification_and_tampering(self):
        for algorithm in ("p256", "ed25519"):
            unit, reply = self.fixture(algorithm)
            self.assertTrue(verify_reply(reply, unit))
            for field, value in (("xp", 0), ("day", "2026-09-10"), ("nonce", "ab12"),
                                 ("sig", "AA=="), ("unit", "0"*16), ("ok", False)):
                self.assertFalse(verify_reply({**reply, field: value}, unit))
            other, _ = self.fixture(algorithm)
            self.assertFalse(verify_reply(reply, other))
            self.assertFalse(verify_reply(reply, {**unit, "alg": "unknown"}))
            self.assertFalse(verify_reply(reply, {**unit, "pub": "!"}))

    def test_invalid_inputs(self):
        unit, reply = self.fixture("p256")
        for field, values in {"xp": [-1, True, 1.5, "1", 2**63],
                              "nonce": ["", "a", "aa|bb", "aa\0b", "ab"*33],
                              "day": ["2026-9-09", "2026-09-09\0", None]}.items():
            for value in values:
                self.assertFalse(verify_reply({**reply, field: value}, unit))
        for invalid in (None, [], {}, "bad"):
            self.assertFalse(verify_reply(invalid, unit))
            self.assertFalse(verify_reply(reply, invalid))

    def test_cli(self):
        unit, reply = self.fixture("p256")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "unit.json"
            path.write_text(json.dumps(unit))
            for valid in (True, False):
                if not valid:
                    reply["xp"] = 0
                result = subprocess.run([sys.executable, str(TOOLS / "verify_sig.py"), "--unit", str(path), "-"],
                                        input=json.dumps(reply), capture_output=True, text=True)
                self.assertEqual(result.returncode, 0 if valid else 1, result.stderr)
                self.assertEqual(json.loads(result.stdout), {"ok": valid})

    def test_command_parser_and_partial_reply(self):
        args = buddyctl.build_parser().parse_args(["sign", "--day", "2026-09-09", "--xp", "12"])
        self.assertEqual(args.xp, 12)
        self.assertIsNone(args.nonce)
        self.assertEqual(buddyctl.build_parser().parse_args(["unit"]).cmd, "unit")
        self.assertIsNone(buddyctl.json_reply(b'{"ack":"unit"}', "unit"))
        self.assertEqual(buddyctl.json_reply(b'log\n{"cmd":"battery"}\n{"ack":"unit","ok":true}\n', "unit"),
                         {"ack": "unit", "ok": True})


if __name__ == "__main__":
    unittest.main()
