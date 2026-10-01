import subprocess, time, os, sys, json, statistics
exe = sys.argv[1]
payload = json.dumps({"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/tmp/jetpack","tool_name":"Bash","tool_input":{"command":"cd app && swift test"}}).encode()
env = dict(os.environ, BOOP_SOCKET="/tmp/nonexistent-boop.sock")
ts=[]
for i in range(60):
    t=time.perf_counter()
    subprocess.run([exe,"claude"], input=payload, env=env)
    ts.append((time.perf_counter()-t)*1000)
ts=ts[5:]
ts.sort()
print("p50 %.2f ms p90 %.2f ms" % (statistics.median(ts), ts[int(len(ts)*0.9)]))
