#!/usr/bin/env python3
"""Worktree-local headless lifecycle and command environment."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import secrets
import signal
import socket
import subprocess
import time
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[2]
KEY = hashlib.sha256(str(ROOT).encode()).hexdigest()[:16]
BASE = Path('/tmp') / f'boop-dev-{os.getuid()}-{KEY}'


def live(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('action', choices=['start', 'stop', 'run', 'status'])
    ap.add_argument('command', nargs=argparse.REMAINDER)
    args = ap.parse_args()
    BASE.mkdir(mode=0o700, exist_ok=True)
    with (BASE / 'lifecycle.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        metadata = BASE / 'instance.json'
        info = json.loads(metadata.read_text()) if metadata.exists() else None
        if info and live(info['pid']):
            actual = subprocess.check_output(['ps', '-p', str(info['pid']), '-o', 'command='], text=True)
            if info['binary'] not in actual or '--headless' not in actual:
                raise SystemExit('Stale PID metadata: process identity differs; refusing to use or stop it')
        if args.action == 'stop':
            if info and live(info['pid']):
                command = subprocess.check_output(['ps', '-p', str(info['pid']), '-o', 'command='], text=True)
                if info['binary'] not in command or '--headless' not in command:
                    raise SystemExit('Refusing to stop a PID that no longer belongs to this instance')
                os.kill(info['pid'], signal.SIGTERM)
                for _ in range(100):
                    if not live(info['pid']):
                        break
                    time.sleep(.1)
                else:
                    raise SystemExit('Instance did not stop; state retained')
            metadata.unlink(missing_ok=True)
            print(f'Stopped {BASE}')
            return
        if args.action == 'status':
            print(json.dumps({'directory': str(BASE), 'running': bool(info and live(info['pid'])), 'port': info['port'] if info else None}))
            return
        if not info or not live(info['pid']):
            if args.action == 'run':
                raise SystemExit('Start this worktree instance first')
            binary = os.environ.get('BOOP_BIN')
            if not binary:
                subprocess.run(['swift', 'build', '--product', 'Boop'], cwd=ROOT / 'app', check=True)
                bindir = subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=ROOT / 'app', text=True).strip()
                binary = str(Path(bindir) / 'Boop')
            binary = str(Path(binary).resolve())
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0))
                port = sock.getsockname()[1]
            if not Path(binary).is_file() or not os.access(binary, os.X_OK):
                raise SystemExit(f'Boop binary is not executable: {binary}')
            state = BASE / 'state'
            state.mkdir(mode=0o700, exist_ok=True)
            config = state / 'config.json'
            config.write_text(json.dumps({'port': port, 'token': secrets.token_hex(32)}))
            config.chmod(0o600)
            env = dict(os.environ, BOOP_STATE_DIR=str(state), BOOP_DEFAULTS_SUITE=f'com.boopcomputer.boop.dev.{KEY}')
            with (BASE / 'app.log').open('ab') as log:
                proc = subprocess.Popen([binary, '--headless'], env=env, stdout=log, stderr=log, start_new_session=True)
            info = {'pid': proc.pid, 'port': port, 'binary': binary}
            metadata.write_text(json.dumps(info))
            for _ in range(150):
                if proc.poll() is not None:
                    raise SystemExit(f'App exited; see {BASE / "app.log"}')
                try:
                    req = urllib.request.Request(f'http://127.0.0.1:{port}/state', headers={'X-Boop-Token': json.loads(config.read_text())['token']})
                    with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(req, timeout=.2) as response:
                        if response.status == 200:
                            break
                except (OSError, urllib.error.URLError):
                    time.sleep(.2)
            else:
                proc.terminate()
                proc.wait(timeout=10)
                raise SystemExit(f'App did not become ready; see {BASE / "app.log"}')
        if args.action == 'start':
            print(f'Headless instance ready: port {info["port"]}, files {BASE}')
            return
        command = args.command
        if command[:1] == ['--']:
            command = command[1:]
        if not command:
            raise SystemExit('run requires a command')
        env = dict(os.environ, BOOP_STATE_DIR=str(BASE / 'state'), BUDDY_PORT=str(info['port']), BOOP_DEFAULTS_SUITE=f'com.boopcomputer.boop.dev.{KEY}', BUDDY_E2E_CWD=str(ROOT))
        # Serialize scenarios within an instance, while other worktrees run freely.
        raise SystemExit(subprocess.run(command, env=env, cwd=ROOT).returncode)


if __name__ == '__main__':
    main()
