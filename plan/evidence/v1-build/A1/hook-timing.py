import json, os, socket, subprocess, sys, threading, time, statistics
hook = sys.argv[1]
fixture = sys.argv[2]
home = "/tmp/boop-a1/home"
os.makedirs(home, exist_ok=True)
payloads = [l for l in open(fixture).read().splitlines() if l.strip()]
big = json.dumps({"hook_event_name": "PostToolUse", "session_id": "big", "cwd": "/w/x", "tool_name": "Read",
                  "tool_response": "x" * 1_000_000})

def run(data, env):
    t = time.perf_counter()
    p = subprocess.run([hook, "claude"], input=data.encode(), env=env, capture_output=True)
    return (time.perf_counter() - t) * 1000, p.returncode, p.stdout, p.stderr

def report(name, results):
    ms = [r[0] for r in results]
    ok = all(r[1] == 0 and r[2] == b"" and r[3] == b"" for r in results)
    print(f"{name}: n={len(ms)} p50={statistics.median(ms):.1f} ms p95={sorted(ms)[int(len(ms)*0.95)-1]:.1f} ms max={max(ms):.1f} ms exit0+silent={ok}")
    return max(ms), ok

# 1. No app: default socket path under a temporary HOME, nothing listening.
env = {"HOME": home, "PATH": "/usr/bin:/bin"}
no_app = [run(payloads[i % len(payloads)], env) for i in range(40)]
m1, ok1 = report("no app (socket missing)", no_app)

# 2. A stale socket file with nothing listening.
stale = "/tmp/boop-a1/stale.sock"
s = socket.socket(socket.AF_UNIX); 
if os.path.exists(stale): os.unlink(stale)
s.bind(stale); s.close()  # bound but never listening
env2 = dict(env, BOOP_SOCKET=stale)
m2, ok2 = report("stale socket file", [run(payloads[0], env2) for _ in range(20)])

# 3. An app that's listening: every line arrives, and nothing sensitive in it.
live = "/tmp/boop-a1/live.sock"
if os.path.exists(live): os.unlink(live)
srv = socket.socket(socket.AF_UNIX); srv.bind(live); srv.listen(64)
got = []
def serve():
    while True:
        try: c, _ = srv.accept()
        except OSError: return
        buf = b""
        while True:
            d = c.recv(4096)
            if not d: break
            buf += d
        c.close(); got.append(buf)
threading.Thread(target=serve, daemon=True).start()
env3 = dict(env, BOOP_SOCKET=live)
res = [run(p, env3) for p in payloads]
m3, ok3 = report("app listening", res)
time.sleep(0.2)
lines = [json.loads(g) for g in got]
print(f"  received {len(lines)}/{len(payloads)} lines; any PRIVATE text: {any('PRIVATE' in g.decode() for g in got)}")
print("  first:", got[0].decode().strip())
print("  third:", got[2].decode().strip())

# 4. A 1 MB payload: capped, drained, still one line.
m4, ok4 = report("1 MB payload, app listening", [run(big, env3) for _ in range(5)])
time.sleep(0.2)
print("  last:", got[-1].decode().strip())
srv.close()
print("PASS" if m1 < 50 and m2 < 50 and ok1 and ok2 and ok3 and ok4 and len(lines) == len(payloads) else "FAIL")
