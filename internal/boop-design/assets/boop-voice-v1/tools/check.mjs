import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {loadBank,choices,resolveChoice,assemble} from '../select.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
if(process.argv.includes('--help')){console.log('node tools/check.mjs\nChecks the self-contained voice bank offline; writes exact storage-report.json. No API, playback or device calls.');process.exit(0);}
const b=loadBank(),records=b.manifest.recordings,entries=new Map(b.dictionary.entries.map(e=>[e.id,e]));
assert.equal(records.length,2722);assert.equal(new Set(records.map(r=>r.id)).size,2722);assert.equal(entries.size,387);
assert.equal(b.manifest.voiceId,'rErOatUrNIU3vfNcLl6Z');
let peak=0,maxRms=0,wavCount=0,mp3Bytes=0;const profiles={original:0,'robot-soft':0,'robot-grain':0};
const expectedIndex={byState:{},byMood:{},byIntent:{},byEntry:{}};
const add=(bucket,key,id)=>(bucket[key]??=[]).push(id);
function checkedFile(file){
 assert(!path.isAbsolute(file.path)&&!file.path.split('/').includes('..'));
 const bytes=fs.readFileSync(path.join(root,file.path));assert.equal(bytes.length,file.bytes);assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),file.sha256,file.path);return bytes;
}
for(const r of records){
 assert(entries.has(r.entryId));const e=entries.get(r.entryId);
 for(const s of e.states)add(expectedIndex.byState,s,r.id);add(expectedIndex.byMood,r.mood,r.id);add(expectedIndex.byIntent,e.intent,r.id);add(expectedIndex.byEntry,e.id,r.id);
 assert.equal(r.generation.voiceId,b.manifest.voiceId);assert.equal(r.generation.modelId,'eleven_v4');mp3Bytes+=checkedFile(r.master).length;
 assert.equal(r.routineDurationEligible,r.seconds<=b.dictionary.policy.maxSeconds);
 for(const [profile,file] of Object.entries(r.files)){
  const bytes=checkedFile(file);assert.equal(bytes.toString('ascii',0,4),'RIFF');assert.equal(bytes.toString('ascii',8,12),'WAVE');
  let p=12,pcm,format;
  while(p+8<=bytes.length){const name=bytes.toString('ascii',p,p+4),n=bytes.readUInt32LE(p+4);if(name==='fmt ')format=bytes.subarray(p+8,p+8+n);if(name==='data')pcm=bytes.subarray(p+8,p+8+n);p+=8+n+n%2;}
  assert(format&&pcm);assert.equal(format.readUInt16LE(0),1);assert.equal(format.readUInt16LE(2),1);assert.equal(format.readUInt32LE(4),44100);assert.equal(format.readUInt16LE(14),16);assert(Math.abs(pcm.length/2/44100-r.seconds)<1/44100);
  let power=0;for(let i=0;i<pcm.length;i+=2){const x=pcm.readInt16LE(i)/32768;peak=Math.max(peak,Math.abs(x));power+=x*x;}maxRms=Math.max(maxRms,Math.sqrt(power/(pcm.length/2)));profiles[profile]+=bytes.length;wavCount++;
 }
}
assert.deepEqual(b.index,expectedIndex);assert.equal(wavCount,8166);assert(peak<=.551);assert(maxRms<=.0701);
const phase=JSON.parse(fs.readFileSync(path.join(root,'plans/phase1.json'))),later=JSON.parse(fs.readFileSync(path.join(root,'plans/deferred.json')));
const phaseIds=new Set(phase.slots.map(s=>s.performanceId)),laterIds=new Set(later.slots.map(s=>s.id));
assert.equal(phaseIds.size,2702);assert.equal(laterIds.size,4421);assert.equal(new Set([...phaseIds,...laterIds]).size,7123);assert.equal(later.authorized,false);
assert.equal(new Set(records.map(r=>r.performanceId).filter(Boolean)).size,2702);
for(const s of phase.slots){const r=records.find(r=>r.id===s.recordingId);assert(r);assert.equal(r.performanceId,s.performanceId);assert.equal(r.script,s.script);assert.equal(r.mood,s.mood);}
const review=JSON.parse(fs.readFileSync(path.join(root,'review/phase1-audio.json')));assert.equal(review.recorded.length,2702);
for(const t of review.recorded){const r=records.find(r=>r.id===t.id);assert.equal(t.master_sha256,r.master.sha256);for(const [k,p] of Object.entries(t.files))assert.equal(p,'../'+r.files[k].path);}
const fullOptions=choices(b,{state:'starting',mood:'excited',facts:['task_started']},{audition:true});assert(fullOptions.length<=9&&fullOptions.some(c=>c.id==='new.d02'));
assert(choices(b,{state:'working',mood:'grumpy',facts:['work_active']},{audition:true}).length>1);
assert.equal(new Set(records.map(r=>r.master.sha256)).size,2722);
// Keep the original small fixture's exact join/shortlist expectations while the
// full-bank integrity and coverage checks above exercise the expanded manifest.
{
const b=loadBank();b.manifest.recordings=b.manifest.recordings.filter(r=>r.sourceBatch!=='robot-dictionary-phase1');
const pilotIds=new Set(b.manifest.recordings.map(r=>r.id));
for(const bucket of Object.values(b.index))for(const key of Object.keys(bucket))bucket[key]=bucket[key].filter(id=>pilotIds.has(id));
const ctx={state:'starting',mood:'excited',facts:['task_started']};
assert.deepEqual(choices(b,ctx).map(c=>c.id),['silence']);
const offered=choices(b,ctx,{audition:true});assert(offered.some(c=>c.id==='new.d02'));assert(offered.length<=9);
assert.equal(resolveChoice(offered,'invented').id,'silence');
for(const context of [{...ctx,facts:[]},{...ctx,state:'asleep'},{...ctx,mood:'nonexistent'},{...ctx,stale:true},{...ctx,recentTakeIds:['new.d02']},{...ctx,recentFamilies:['go']}])assert.equal(choices(b,context,{audition:true}).length,1);
assert.equal(choices(b,{state:'task_complete',mood:'proud',facts:['failure_confirmed']},{audition:true,phrases:true,rare:true}).some(c=>c.label==='Done'),false);
assert(!choices(b,{state:'task_complete',mood:'grumpy',facts:['failure_confirmed']},{audition:true,rare:true}).some(c=>c.explicit));
assert(choices(b,{state:'task_complete',mood:'grumpy',facts:['failure_confirmed']},{audition:true,rare:true,explicit:true}).some(c=>c.explicit));
assert(!choices(b,{state:'needs_you',mood:'grumpy',facts:['pending_request','failure_confirmed']},{audition:true,rare:true,explicit:true}).some(c=>c.explicit));
assert(assemble(b,['new.d02'],ctx,{audition:true}));assert.equal(assemble(b,['new.d02','new.d02'],ctx,{audition:true}),null);
assert.equal(assemble(b,['new.d20'],{state:'task_complete',mood:'proud',facts:['success_or_poke']},{audition:true,rare:true}),null);
const happy={state:'task_complete',mood:'happy',facts:['success_confirmed']};
const joined=assemble(b,['new.d13','new.d19'],happy,{audition:true});assert(joined);assert(joined.seconds<=2.8);assert.equal(joined.clips[1].at,records.find(r=>r.id==='new.d13').seconds+.18);
assert.equal(assemble(b,['new.d13','previous.finish'],happy,{audition:true}),null); // too long together
const happyChoices=choices(b,happy,{audition:true});assert.equal(new Set(happyChoices.map(c=>c.entryId)).size,happyChoices.length);
// Synthetic fixture proves topic and join guards independently of sparse pilot coverage.
const fixture=structuredClone(b),e=fixture.dictionary.entries.find(e=>e.id==='word.begin.go');e.topic='build';
assert.equal(choices(fixture,ctx,{audition:true}).length,1);assert(choices(fixture,{...ctx,topic:'build'},{audition:true}).length>1);
}
const plain=JSON.stringify({dictionary:b.dictionary,manifest:b.manifest,index:b.index});assert(!plain.includes('/Users/'));assert(!plain.includes('xi-api-key'));
const walk=dir=>fs.readdirSync(dir,{withFileTypes:true}).flatMap(d=>{assert(!d.isSymbolicLink());const p=path.join(dir,d.name);return d.isDirectory()?walk(p):[p];});
const report={version:2,generatedOn:'2026-09-29',distinctRecordedTakes:2722,latestBatchNewTakes:2682,phase1Slots:2702,reusedPilotSlots:20,additionalLegacyTakes:20,deferredSlots:4421,plannedDictionaryEntries:387,plannedPerformanceSlots:7123,
 wavFiles:8166,mp3Masters:2722,totalRecordedSeconds:records.reduce((n,r)=>n+r.seconds,0),audioBytesByProfile:profiles,defaultRuntimeWavBytes:profiles['robot-soft'],mp3MasterBytes:mp3Bytes,
 allAudioBytes:Object.values(profiles).reduce((n,v)=>n+v,0)+mp3Bytes,recordedMoodCounts:Object.fromEntries(Object.entries(b.index.byMood).map(([k,v])=>[k,v.length])),
 peak,maxRms,packagePayloadBytes:0,metadataAndCodeBytes:0,totalFiles:0,measure:'Sum of file lengths, including this report; excludes directory blocks and .git compression. One DSP profile suffices at runtime.',checks:'passed'};
const reportPath=path.join(root,'storage-report.json');
for(let pass=0;pass<5;pass++){
 fs.writeFileSync(reportPath,JSON.stringify(report,null,2)+'\n');const files=walk(root);report.packagePayloadBytes=files.reduce((n,p)=>n+fs.statSync(p).size,0);report.metadataAndCodeBytes=report.packagePayloadBytes-report.allAudioBytes;report.totalFiles=files.length;
}
assert.equal(JSON.parse(fs.readFileSync(reportPath)).packagePayloadBytes,report.packagePayloadBytes);
console.log(JSON.stringify(report,null,2));
