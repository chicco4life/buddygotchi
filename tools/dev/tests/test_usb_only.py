"""USB-only runs must verify isolation and retain restoration on rejection."""
import importlib.util
import json
from pathlib import Path
import signal
import sys
import tempfile
import unittest
from contextlib import nullcontext
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('usb_runner', ROOT / 'tools/dev/device.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class USBOnlyTests(unittest.TestCase):
    def test_rejects_shipping_and_wrong_board(self):
        for info in ({'board': 'ws-amoled164'}, {'board': 'ws-amoled164', 'usbOnly': False},
                     {'board': 'other', 'usbOnly': True}):
            with patch('buddyctl.SerialBuddy') as serial:
                serial.return_value.__enter__.return_value.framed_json.return_value = info
                with self.assertRaises(RuntimeError):
                    runner.verify_usb_only()

    def test_accepts_explicit_debug_identity(self):
        info = {'board': 'ws-amoled164', 'usbOnly': True}
        with patch('buddyctl.SerialBuddy') as serial:
            serial.return_value.__enter__.return_value.framed_json.return_value = info
            self.assertEqual(runner.verify_usb_only(), info)

    def test_rejection_skips_scenario_but_restores_with_gui_open(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            restore = folder / 'restore.sh'
            restore.write_text('#!/bin/sh\necho restored\n')
            restore.chmod(0o755)
            evidence = folder / 'evidence'
            argv = ['device.py', '--usb-only', '--restore', str(restore),
                    '--evidence', str(evidence), '--', '/this-scenario-must-not-run']
            previous = {s: signal.getsignal(s) for s in (signal.SIGINT, signal.SIGTERM)}
            try:
                with patch.object(sys, 'argv', argv), \
                     patch.object(runner, 'reserve', return_value=nullcontext('test')), \
                     patch.object(runner, 'gui_claim', side_effect=AssertionError('must allow GUI')), \
                     patch.object(runner, 'gui_running', side_effect=AssertionError('must allow GUI')), \
                     patch.object(runner, 'verify_usb_only', side_effect=RuntimeError('normal firmware')):
                    self.assertEqual(runner.main(), 1)
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)
            result = json.loads((evidence / 'result.json').read_text())
            self.assertEqual(result['restore'], 0)
            self.assertNotIn('scenario', result)
            self.assertIn('restored', (evidence / 'restore.log').read_text())
