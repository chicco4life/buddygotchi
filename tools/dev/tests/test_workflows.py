import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'firmware/esp32/tools'))
import device_lease


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        from unittest.mock import patch
        self.leaseDirectory = tempfile.TemporaryDirectory()
        lock = Path(self.leaseDirectory.name) / 'device.lock'
        self.leasePatch = patch.multiple(device_lease, LOCK=lock, OWNER=lock.with_suffix('.json'))
        self.leasePatch.start()

    def tearDown(self):
        self.leasePatch.stop()
        self.leaseDirectory.cleanup()

    def test_reservation_blocks_other_process_and_allows_delegate(self):
        with device_lease.reserve() as token:
            code = 'import os\nfrom pathlib import Path\nimport device_lease\ndevice_lease.LOCK = Path(os.environ["BOOP_TEST_LEASE_PATH"])\ndevice_lease.OWNER = device_lease.LOCK.with_suffix(".json")\nwith device_lease.reserve(): print("acquired", flush=True)'
            env = dict(os.environ, PYTHONPATH=str(ROOT / 'firmware/esp32/tools'), BOOP_TEST_LEASE_PATH=str(device_lease.LOCK))
            delegated = subprocess.run([sys.executable, '-c', code], env=dict(env, BOOP_DEVICE_LEASE=token), capture_output=True, timeout=3)
            self.assertEqual(delegated.returncode, 0)
            env.pop('BOOP_DEVICE_LEASE', None)
            child = subprocess.Popen([sys.executable, '-c', code], env=env, stdout=subprocess.PIPE)
            time.sleep(.2)
            self.assertIsNone(child.poll())
        output, _ = child.communicate(timeout=3)
        self.assertIn(b'acquired', output)

    def test_restore_after_failed_scenario(self):
        spec = importlib.util.spec_from_file_location('device_runner', ROOT / 'tools/dev/device.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        from unittest.mock import patch
        from contextlib import nullcontext
        import json
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            restore = root / 'restore.sh'
            restore.write_text('#!/bin/sh\necho restored\n')
            restore.chmod(0o755)
            argv = ['device.py', '--restore', str(restore), '--evidence', str(root / 'evidence'), '--', sys.executable, '-c', 'raise SystemExit(7)']
            import signal
            old_int, old_term = signal.getsignal(signal.SIGINT), signal.getsignal(signal.SIGTERM)
            try:
                with patch.object(sys, 'argv', argv), patch.object(module, 'gui_running', return_value=False), patch.object(module, 'gui_claim', return_value=nullcontext()):
                    self.assertEqual(module.main(), 7)
            finally:
                signal.signal(signal.SIGINT, old_int)
                signal.signal(signal.SIGTERM, old_term)
            result = json.loads((root / 'evidence/result.json').read_text())
            self.assertEqual(result['scenario'], 7)
            self.assertEqual(result['restore'], 0)
            self.assertIn('restored', (root / 'evidence/restore.log').read_text())

class InstanceTests(unittest.TestCase):
    def test_two_worktrees_have_separate_authenticated_environments(self):
        import json
        import shutil
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            binary = base / 'Boop'
            binary.write_text('''#!/usr/bin/env python3
import http.server, json, os
from pathlib import Path
config = json.loads((Path(os.environ['BOOP_STATE_DIR']) / 'config.json').read_text())
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200 if self.headers.get('X-Boop-Token') == config['token'] else 401)
        self.end_headers()
        self.wfile.write(b'{}')
http.server.HTTPServer(('127.0.0.1', config['port']), Handler).serve_forever()
''')
            binary.chmod(0o755)
            if os.environ.get('BOOP_WORKFLOW_TEST_BINARY'):
                binary = Path(os.environ['BOOP_WORKFLOW_TEST_BINARY']).resolve()
            runners = []
            try:
                for name in ['first', 'second']:
                    root = base / name
                    folder = root / 'tools/dev'
                    folder.mkdir(parents=True)
                    runner = folder / 'instance.py'
                    shutil.copy(ROOT / 'tools/dev/instance.py', runner)
                    runners.append(runner)
                    subprocess.run([sys.executable, str(runner), 'start'], env=dict(os.environ, BOOP_BIN=str(binary)), check=True, capture_output=True, timeout=45)
                states = []
                for runner in runners:
                    code = 'import os,json; print(json.dumps([os.environ["BOOP_STATE_DIR"],os.environ["BUDDY_PORT"]]))'
                    state, port = json.loads(subprocess.check_output([sys.executable, str(runner), 'run', '--', sys.executable, '-c', code], text=True))
                    states.append((state, port, json.loads((Path(state) / 'config.json').read_text())['token']))
                for index in range(3):
                    self.assertNotEqual(states[0][index], states[1][index])
            finally:
                for runner in runners:
                    subprocess.run([sys.executable, str(runner), 'stop'], check=True, capture_output=True, timeout=15)


if __name__ == "__main__":
    unittest.main()
