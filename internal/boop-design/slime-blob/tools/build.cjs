// Deterministic mechanical exports; no packages/network/model needed.
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
if(process.argv.includes('--help')){console.log('node tools/build.cjs\nRebuilds catalog.js, MOODS.md, coverage.json and transitions.json from design JSON.');process.exit(0);}
const read=name=>JSON.parse(fs.readFileSync(path.join(root,name),'utf8'));
const write=(name,value)=>fs.writeFileSync(path.join(root,name),typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');
const graph=read('emotion-graph.json'),catalog=read('expressions.json'),plan=read('state-plan.json');
write('preview/catalog.js','// Generated from ../expressions.json by tools/build.cjs; no network or host SDK.\nwindow.SlimeCatalog = '+JSON.stringify(catalog)+';\n');
const rows=[];
for(const mood of Object.keys(graph.nodes))for(const state of plan.states){
  const quiet=state.scene==='rest';
  rows.push({id:mood+'.'+state.id,mood,state:state.id,scene:state.scene,expression:quiet?'shared-sleeping-face':mood,
    mode:quiet?'explicit-quiet-alias':'composed-active-cell',variations:state.variations.map(v=>state.id+'.'+v),
    requiredHostFacts:plan.hostFacts[state.id]||{},factVariations:state.factVariations||{},moodSoundProfile:mood,audioPolicy:state.audioPolicy,
    status:quiet?'planned-shared-rest':'planned-state-layer',faceStatus:quiet?'planned-shared-sleeping-face':'candidate-art-present',review:'pending-integrated-animation-and-sound'});
}
write('coverage.json',{version:1,status:'IMPLEMENTATION CHECKLIST, NOT COMPLETED ASSETS',cells:rows});
const edges=[];
for(const [from,node] of Object.entries(graph.nodes))for(const category of ['ordinary','dramatic'])for(const to of node[category]){
  const dramatic=category==='dramatic';
  edges.push({id:from+'->'+to,from,to,category,
    faceFrom:from,faceTo:to,status:'planned-continuous-bridge',
    variants:dramatic?['bounded-recoil-retarget','compress-release-retarget','brief-freeze-retarget']:['soft-retarget','gather-settle-retarget','brief-blink-retarget'],
    preserve:['actor','rest-shape','material','spring-position','spring-velocity','activity-truth','pending-alert'],
    cue:dramatic?'fresh-edge-specific-evidence-required':'context-and-pacing-required',audio:'silent-by-default; material accent only on a permitted visible contact'});
}
write('transitions.json',{version:1,status:'PLANNED EDGE CHOREOGRAPHY, NOT EXECUTED GRAPH POLICY',edges});
let md='# Slime mood inventory and directed traversal\n\nGenerated from [emotion-graph.json](emotion-graph.json) and [expressions.json](expressions.json).\nEdit those inputs and run tools/build.cjs; do not edit this export by hand.\n\nOrdinary neighbors still require context/pacing. Dramatic neighbors require fresh\nstrong edge-specific evidence. Staying is implicit at every node. Families and\nintensity labels are static design metadata, not LLM-selected numeric controls.\nFaces are V3 review candidates; body descriptions below are choreography targets.\n\n';
for(const [family,group] of Object.entries(graph.families)){
  md+='## '+group.label+'\n\n';
  for(const id of group.moods){
    const n=graph.nodes[id],e=catalog.expressions[id];
    md+='### '+e.label+' (`'+id+'`)\n\n';
    md+='**Meaning:** '+n.meaning+'\n\n';
    md+='**Strength / activation / persistence:** '+n.intensityWithinFamily+' / '+n.activation+' / '+n.temporalClass+'.\n\n';
    md+='**Face:** '+e.art.note+'\n\n';
    md+='**Body intent:** '+n.bodyPerformance+'\n\n';
    md+='**Current gesture recipes:** '+e.performances.map(p=>p.label+' ('+p.duration+' s)').join('; ')+'.\n\n';
    md+='**Entry evidence:** '+n.entryCues.join('; ')+'.\n\n';
    md+='**Ordinary →** '+n.ordinary.map(v=>'`'+v+'`').join(', ')+'.\n\n';
    md+='**Dramatic →** '+(n.dramatic.length?n.dramatic.map(v=>'`'+v+'`').join(', '):'none')+'.\n\n';
  }
}
md+='## Reference face alternates (not graph nodes)\n\n';
for(const [id,e] of Object.entries(catalog.expressions).filter(([id])=>id.includes(':')))md+='- `'+id+'` → mood `'+e.mood+'`: '+e.art.note+'\n';
md+='\n## Supplied references and their mappings\n\n';
for(const r of catalog.referenceMapping)md+='- '+r.reference+' → expression `'+r.expression+'`, mood `'+r.mood+'`'+(r.relatedMood?' (related `'+r.relatedMood+'`)':'')+'.\n';
write('MOODS.md',md);
console.log(JSON.stringify({export:'complete',moods:Object.keys(graph.nodes).length,expressions:Object.keys(catalog.expressions).length,stateCells:rows.length,edges:edges.length}));
