# Fuzzes boop-sim with random Mac, tool and junk lines (a do with every
# play, id, ttl and args shape; the clock moving back too) and checks that
# every do with an id that fits a line gets exactly one ended.
#   python3 fuzz_turn.py LINES SEED PATH_TO_SIM
import json, random, subprocess, sys, collections
seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
rnd = random.Random(seed)
NAMES = ["react","task_complete","reply_ready","starting","stopped","error","helper_return","listening","stop_listening","poked","tap_spam","cheer","oops",""]
TAKES = ["previous.go","previous.finish","new.d14","new.d12","banana",7,None]
MOODS = ["proud","grumpy","calm","sad","nope",3]
lines = []
t = 0
next_id = 1
ids = []
def args():
    a = {}
    if rnd.random() < 0.5:
        s = {}
        if rnd.random() < 0.8: s["take"] = rnd.choice(TAKES)
        if rnd.random() < 0.2: s["then"] = rnd.choice(TAKES)
        a["say"] = s
    if rnd.random() < 0.5: a["mood"] = rnd.choice(MOODS)
    if rnd.random() < 0.3: a["loops"] = rnd.choice([1,2,6,9,0,-1,2.5,"x",1e10])
    if rnd.random() < 0.3: a["variant"] = rnd.choice([1,2,3,9,0,-5,"x"])
    if rnd.random() < 0.2: a["who"] = {"agent": rnd.choice(["claude","codex","x"*30]), "thread": "t"*rnd.randint(0,60)}
    if rnd.random() < 0.2: a["outcome"] = rnd.choice(["success","failure","meh"])
    if rnd.random() < 0.2: a["ctx"] = rnd.choice(["new_task","session","continuation","x"])
    if rnd.random() < 0.05: a["pad"] = "p" * rnd.randint(100, 440)
    return a
for i in range(int(sys.argv[1])):
    r = rnd.random()
    if r < 0.12:
        st = {"t":"state","base":rnd.choice(["idle","working","asleep"]),"mood":rnd.choice(MOODS[:4]),"vol":rnd.choice([0,6,10])}
        if rnd.random() < 0.15: st["attn"] = {"agent":"codex","project":"p","id":rnd.randint(1,5)}
        lines.append(json.dumps(st))
    elif r < 0.55:
        d = {"t":"do"}
        if rnd.random() < 0.9:
            d["id"] = next_id; ids.append(next_id); next_id += 1
        elif rnd.random() < 0.5:
            d["id"] = rnd.choice([0,-1,2.5,"7",2147483648])
        d["name"] = rnd.choice(NAMES)
        pm = rnd.random()
        if pm < 0.3: d["play"] = "now"
        elif pm < 0.7: d["play"] = "next"
        elif pm < 0.95: d["play"] = "if_free"
        else: d["play"] = "later"
        if rnd.random() < 0.3: d["ttl"] = rnd.choice([1,100,1000,5000,60000,0,70000,"x"])
        if rnd.random() < 0.8: d["args"] = args()
        elif rnd.random() < 0.5: d["args"] = rnd.choice(["str", 5, [1,2], None])
        line = json.dumps(d)
        if len(line.encode()) > 512 and "id" in d and d["id"] in ids: ids.remove(d["id"])  # the device drops it whole
        lines.append(line)
    elif r < 0.80:
        t += rnd.choice([1,10,50,200,1000,3000,6000,20000])
        if rnd.random() < 0.03: t = max(0, t - 5000)  # back in time
        lines.append(json.dumps({"t":"dbg.clock","freeze":t}))
    elif r < 0.86:
        lines.append(json.dumps({"t":"dbg.press","ms":rnd.choice([50,100,600,40000])}))
    elif r < 0.89:
        lines.append(json.dumps({"t":"dbg.touch","x":rnd.randint(-10,400),"y":rnd.randint(-10,300),"ms":rnd.choice([50,200])}))
    elif r < 0.93:
        lines.append(json.dumps({"t":"dbg.state"}))
    elif r < 0.935:
        lines.append(json.dumps({"t":"dbg.reset"})); t = 0
    elif r < 0.96:
        lines.append(rnd.choice(["", "{", "junk", '{"t":7}', '{"t":"moment","anim":"cheer"}', '{"t":"dbg.nope"}', '{"t":"do"}', "x"*600]))
    else:
        lines.append(json.dumps({"t":"dbg.ping"}))
lines.append(json.dumps({"t":"dbg.reset"}))
data = ("\n".join(lines) + "\n").encode()
import time; t0=time.time()
p = subprocess.run([sys.argv[3] if len(sys.argv) > 3 else "sim-asan"], input=data, capture_output=True)
print("took", round(time.time()-t0,1))
out = p.stdout.decode(errors="replace").splitlines()
err = p.stderr.decode(errors="replace")
ended = collections.Counter()
for l in out:
    if l.startswith('{"t":"ev","kind":"ended"'):
        ended[json.loads(l)["data"]["id"]] += 1
bad = [i for i in ids if ended[i] != 1]
extra = [i for i in ended if i not in set(ids)]
print(f"seed {seed}: {len(lines)} lines, exit {p.returncode}, {len(ids)} ids, ended {sum(ended.values())}, wrong {len(bad)} {bad[:5]}, extra {extra[:5]}")
if err.strip(): print(err[:3000])
