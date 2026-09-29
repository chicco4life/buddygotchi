"""Fixed 30-take supplemental batch. No automatic retries; private masters stay outside Git.

plan is offline. generate needs --execute, an external cache and the existing audition
tools directory (audition.py owns local API credential loading and the accepted DSP).
import is offline and idempotent. Original phase1/deferred plans are never modified.
"""
import argparse
from array import array
import fcntl
import hashlib
import importlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
import wave

import compress as c

ROOT = Path(__file__).resolve().parents[1]
BATCH = 'swear-expansion-v1'
PLAN = ROOT / 'plans' / (BATCH + '.json')
VOICE = 'rErOatUrNIU3vfNcLl6Z'
CAP = 2500

def read(p):
    return json.loads(p.read_text())

def plan():
    d = read(ROOT/'dictionary.json')
    slots = []
    directions = {
        'sad': ('[sad] [softly]', 'Deflated and quiet after a long effort; a small falling sigh, never a shout.'),
        'wounded': ('[sad] [whispering]', 'Hurt and small: a short wince rather than an angry curse.'),
        'whiny': ('[whining] [softly]', 'Sorry for itself, lightly stretched, soft and not piercing.'),
    }
    for e in d['entries']:
        if e['id'] not in ['explicit.'+x for x in ['shit','fuck','damn','crap','shiba']]:
            continue
        assert e['requires']=='failure_confirmed' and e['explicit'] is True
        for mood, (tags, direction) in directions.items():
            for variant in ('contained','trailing'):
                ident = f'{e["id"]}__{mood}__{variant}'
                script = tags + ' ' + ('[sighs] ' if variant=='trailing' else '') + e['text'] + ('....' if variant=='trailing' else '.')
                slots.append(dict(performanceId=ident,recordingId=BATCH+'.'+ident,entryId=e['id'],mood=mood,variant=variant,script=script,direction=direction,seed=int(hashlib.sha256(ident.encode()).hexdigest()[:8],16)%2147483647))
    assert len(slots)==30
    result = dict(version=1,batch=BATCH,voiceId=VOICE,modelId='eleven_v4',profiles=['robot-soft'],creditCap=CAP,
                  inputCharacters=sum(len(s['script']) for s in slots),slots=slots,
                  note='Supplemental slots, disjoint from frozen phase1 and deferred plans. Tags are performance requests, not guaranteed emotion presets. All takes require listening review.')
    if PLAN.exists():
        assert read(PLAN)==result, 'Frozen plan differs; create a new revision instead'
    else:
        c.write_json(PLAN,result)
    return result

def generate(p,cache,source_tools):
    sys.path.insert(0,str(source_tools))
    a = importlib.import_module('audition')
    ledger_path=cache/'ledger.json'
    digest=c.sha(PLAN)
    ledger=read(ledger_path) if ledger_path.exists() else dict(planSha256=digest,baseline=a.subscription(),takes={})
    assert ledger['planSha256']==digest
    assert ledger['baseline']['tier']!='free'
    c.write_json(ledger_path,ledger)
    published={r.get('performanceId') for r in read(ROOT/'manifest.json')['recordings']}
    for s in p['slots']:
        ident=s['performanceId']; old=ledger['takes'].get(ident); master=cache/(ident+'.mp3')
        if old:
            assert old['status']=='saved' and master.exists() and c.sha(master)==old['sha256'], 'Uncertain prior attempt: inspect history manually, never auto-retry'
            continue
        assert ident not in published, 'Already published: refusing duplicate generation'
        time.sleep(5)  # Pace accounting + TTS; never retry an uncertain paid request.
        now=a.subscription(); spent=now['character_count']-ledger['baseline']['character_count']
        reserve=10*len(s['script'])
        assert 0<=spent and spent+reserve<=CAP and now['character_limit']-now['character_count']>=reserve, 'Credit guard reached'
        take=dict(status='attempted',script=s['script'])
        ledger['takes'][ident]=take;c.write_json(ledger_path,ledger)
        data,headers=a.request('/v1/text-to-speech/'+VOICE+'?output_format=mp3_44100_128',dict(text=s['script'],model_id='eleven_v4',seed=s['seed']))
        assert 'audio/' in next((v for k,v in headers.items() if k.lower()=='content-type'),'') and len(data)>100
        temp=master.with_suffix('.mp3.tmp');temp.write_bytes(data);temp.replace(master)
        take.update(status='saved',sha256=c.sha(master));c.write_json(ledger_path,ledger)
        print('Saved',ident,flush=True)
    ledger['after']=a.subscription();c.write_json(ledger_path,ledger)
    print('Account credit delta:',ledger['after']['character_count']-ledger['baseline']['character_count'],flush=True)
    # Match existing phase1 DSP and shared normalization, but persist ONLY soft WAV.
    rendered=[]
    for s in p['slots']:
        ident=s['performanceId'];master=cache/(ident+'.mp3');target=cache/(ident+'.wav')
        raw=cache/(ident+'-decoded.wav');soft=cache/(ident+'-soft16.wav');resampled=cache/(ident+'-11025.wav')
        subprocess.run(['afconvert','-f','WAVE','-d','LEI16@44100','-c','1',str(master),str(raw)],check=True,capture_output=True)
        with wave.open(str(raw)) as w:
            rate=w.getframerate();x=array('h',w.readframes(w.getnframes()))
        if sys.byteorder!='little': x.byteswap()
        xs=[v/32768 for v in x]
        versions=[a.process(xs,rate,k) for k in ('original','robot-soft','robot-grain')]
        level=min(a.rms(xs),.07)
        levels=[level/max(a.rms(v),1e-12) for v in versions]
        peak=max(max(abs(x) for x in v)*g for v,g in zip(versions,levels))
        gain=min(1,.55/max(peak,1e-12))
        a.write_wav(soft,[x*levels[1]*gain for x in versions[1]],rate)
        c.run(['afconvert','-f','WAVE','-d','LEI16@11025','-c','1','-r','127',str(soft),str(resampled)])
        c.quantize(resampled,target);stats=c.wav_stats(target)
        assert 0<stats['rms']<=.073 and stats['peak']<=.59
        rendered.append(dict(**s,seconds=stats['seconds'],file=dict(path='audio-pcm8/robot-soft/'+s['recordingId']+'.wav',bytes=target.stat().st_size,sha256=c.sha(target),encoding=dict(container='wav',codec='pcm_u8',bitsPerSample=8,sampleRate=11025,channels=1,silence=128),sourceSha256=c.sha(soft),recipe=c.RECIPE,decoded=stats),master=dict(bytes=master.stat().st_size,sha256=c.sha(master),encoding=dict(container='mp3',nominalBitrate=128000,sampleRate=44100),storage='local-archive-not-distributed')))
    c.write_json(cache/'rendered.json',dict(planSha256=digest,recordings=rendered))

def import_batch(p,cache):
    rendered=read(cache/'rendered.json');assert rendered['planSha256']==c.sha(PLAN)
    assert [r['performanceId'] for r in rendered['recordings']]==[s['performanceId'] for s in p['slots']]
    d=read(ROOT/'dictionary.json');m=read(ROOT/'manifest.json');review=read(ROOT/'review/phase1-audio.json')
    entries={e['id']:e for e in d['entries']}
    phase=read(ROOT/'plans/phase1.json');later=read(ROOT/'plans/deferred.json')
    frozen={s['performanceId'] for s in phase['slots']}|{s['id'] for s in later['slots']}
    assert not frozen.intersection(s['performanceId'] for s in p['slots'])
    for r in rendered['recordings']:
        e=entries[r['entryId']];assert e['explicit'] and e['requires']=='failure_confirmed'
        if r['mood'] not in e['moods']: e['moods'].append(r['mood'])
        source=cache/(r['performanceId']+'.wav');assert c.sha(source)==r['file']['sha256']
        record=dict(id=r['recordingId'],entryId=r['entryId'],mood=r['mood'],moodStatus='intended; listening review pending',variant=r['variant'],script=r['script'],seconds=r['seconds'],routineDurationEligible=r['seconds']<=d['policy']['maxSeconds'],reviewStatus='unreviewed-by-ear',performanceId=r['performanceId'],sourceBatch=BATCH,generation=dict(voiceId=VOICE,modelId='eleven_v4',seed=r['seed'],language='auto'),files={'robot-soft':r['file']},master=r['master'])
        existing=next((x for x in m['recordings'] if x['performanceId']==r['performanceId']),None)
        if existing: assert existing==record, 'Existing performance differs; no overwrite'
        else: m['recordings'].append(record)
        target=ROOT/r['file']['path']
        if target.exists(): assert c.sha(target)==r['file']['sha256']
        else: shutil.copyfile(source,target)
        if not any(x['performance']==r['performanceId'] for x in review['recorded']):
            review['recorded'].append(dict(id=record['id'],entry=e['id'],mood=r['mood'],script=r['script'],keyword=e['text'],states=e['states'],category=e['category'],explicit=True,seconds=r['seconds'],files={'robot-soft':'../'+r['file']['path']},bank=BATCH,variant=r['variant'],performance=r['performanceId'],reviewStatus=record['reviewStatus'],moodStatus=record['moodStatus'],routineDurationEligible=record['routineDurationEligible'],master_sha256=r['master']['sha256']))
    d['stats']['plannedPerformances']=7123+30
    d['stats']['inputCharacters']=133970+p['inputCharacters']
    m['scope']['supplementalSwearTakes']=30
    review['summary'].update(selected=2732,ready=2732,supplementalSwearTakes=30)
    index=dict(byState={},byMood={},byIntent={},byEntry={})
    for r in m['recordings']:
        e=entries[r['entryId']]
        for state in e['states']: index['byState'].setdefault(state,[]).append(r['id'])
        for bucket,key in [('byMood',r['mood']),('byIntent',e['intent']),('byEntry',e['id'])]:index[bucket].setdefault(key,[]).append(r['id'])
    for name,obj in [('dictionary.json',d),('manifest.json',m),('index.json',index),('review/phase1-audio.json',review)]:c.write_json(ROOT/name,obj)
    print('Imported 30 supplemental robot-soft takes; original plans and audio unchanged.')

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('command',choices=['plan','generate','import']);ap.add_argument('--cache',type=Path);ap.add_argument('--audition-tools',type=Path);ap.add_argument('--execute',action='store_true')
    args=ap.parse_args();p=plan()
    if args.command=='plan': print(json.dumps({k:v for k,v in p.items() if k!='slots'},indent=2));return
    assert args.cache and args.cache.is_absolute()
    cache=args.cache.resolve();repo=ROOT.parents[3]
    assert cache!=repo and repo not in cache.parents, 'Cache must be outside repository'
    cache.mkdir(parents=True,exist_ok=True)
    with (cache/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        if args.command=='generate':
            assert args.execute and args.audition_tools, 'Paid calls require --execute and existing audition tools'
            generate(p,cache,args.audition_tools)
        else: import_batch(p,cache)

if __name__=='__main__':main()
