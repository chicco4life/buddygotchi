# Every take in Federico's bank, sorted into two questions: how Boop feels (feeling) and what it's about (about).
import json,collections
d=json.load(open("dictionary.json")); man=json.load(open("manifest.json"))["recordings"]
ent={e["id"]:e for e in d["entries"]}
FEELING={"frustration":"upset","setback":"upset","deflate":"upset",
         "celebrate":"glad","delight":"glad","relief":"glad","pride":"glad","insight":"glad",
         "poke":"tickled"}
ABOUT={"begin":"start","delegate":"helpers","return":"helper back","retry":"retry",
       "work":"work","effort":"work","test":"tests","terminal":"command","tool":"tool",
       "search":"looking","analyze":"looking","ponder":"looking","plan":"planning",
       "success":"done","reply":"answer","stop":"stopped","wait":"waiting","idle":"quiet"}
MOODFIX={"relieved":"happy","amused":"happy","weary":"whiny"}; UNSPEC={"previous.go":"calm","previous.oi":"curious"}
def kind(e): return "swear" if e["explicit"] else {"nonverbal":"sound","word":"word","phrase":"phrase"}[e["category"]]
def finish(e):
    if e["requires"] in ("success_confirmed","fix_confirmed","tests_passed","insight_confirmed"): return "success"
    if e["explicit"] or e["text"]=="Uff": return "failure"
    return None
sel=[]
for r in man:
    e=ent[r["entryId"]]; it=e["intent"]
    q,a=("feeling",FEELING[it]) if it in FEELING else ("about",ABOUT[it]) if it in ABOUT else ("attention","attention")
    m=UNSPEC.get(r["id"]) or MOODFIX.get(r["mood"],r["mood"])
    sel.append(dict(id=r["id"],text=e["text"].rstrip("."),question=q,answer=a,kind=kind(e),mood=m,finish=finish(e),seconds=r["seconds"],intent=it,requires=e["requires"]))
json.dump(sel,open("selection3.json","w"),indent=0)
moods="calm happy excited proud curious engaged determined annoyed irritated grumpy whiny wounded sad".split()
g=collections.defaultdict(list)
for s in sel: g[(s["question"],s["answer"],s["mood"])].append(s)
print(len(sel),"takes,",round(sum(s["seconds"] for s in sel)/60),"min")
for q,answers in (("feeling",list(dict.fromkeys(FEELING.values()))),("about",list(dict.fromkeys(ABOUT.values()))),("attention",["attention"])):
    print(f"\n{q}"); print(f'{"":13}'+"".join(f"{m[:4]:>5}" for m in moods))
    for a in answers:
        print(f'{a:13}'+"".join(f'{len(g[(q,a,m)]) or "·":>5}' for m in moods))
# ungated takes per feeling cell (what can play when the turn didn't finish with a success/failure)
print("\nfeeling cells with nothing ungated:",[(a,m) for a in ("upset","glad","tickled") for m in moods if not any(not s["finish"] for s in g[("feeling",a,m)])])
json.dump({f"{q}|{a}|{m}":{"n":len(v),"sw":sum(s["kind"]=="swear" for s in v),"ex":sorted({s["text"] for s in v})[:12]} for (q,a,m),v in g.items()},open("grid3.json","w"))
