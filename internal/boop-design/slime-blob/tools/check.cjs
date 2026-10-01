const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),vm=require('node:vm'),crypto=require('node:crypto');
if(process.argv.includes('--help')){console.log('node tools/check.cjs\nOffline graph/coverage/export/motion/sound/link checks; no browser or production runtime.');process.exit(0);}
const root=path.resolve(__dirname,'..'),read=name=>JSON.parse(fs.readFileSync(path.join(root,name),'utf8'));
const g=read('emotion-graph.json'),c=read('expressions.json'),s=read('state-plan.json'),cov=read('coverage.json'),trans=read('transitions.json'),sound=read('sound/sound-plan.json');
const ids=Object.keys(g.nodes);
assert.equal(ids.length,42);assert.equal(Object.keys(c.expressions).length,44);assert.equal(c.referenceMapping.length,19);
assert.equal(g.holdAlwaysAvailable,true);assert.equal(g.maxEdgesPerDecision,1);assert.equal(g.maxDestinationChoices,8);
assert.equal(g.implementation.runtimeChanged,false);assert.equal(g.implementation.productionEnumsChanged,false);
assert.deepEqual([...g.schema.stateNames].sort(),s.states.map(v=>v.id).sort());assert.equal(new Set(s.states.map(v=>v.id)).size,22);
const retained=read('../boop-mood-spectrum-v2/mood-graph.json');assert.deepEqual([...g.retainedMoodIds].sort(),Object.keys(retained.nodes).sort());
assert.equal(g.deletedMoodIds.length,0);assert.equal(g.newMoodIds.length,29);
assert.deepEqual(Object.keys(sound.moodProfiles).sort(),[...ids].sort());
const expectedEdges=new Map();let ordinary=0,dramatic=0;
for(const [id,n] of Object.entries(g.nodes)){
  const destinations=[...n.ordinary,...n.dramatic];assert.equal(new Set(destinations).size,destinations.length);assert.ok(destinations.length<=8);
  for(const category of ['ordinary','dramatic'])for(const to of n[category]){
    assert.ok(ids.includes(to));assert.notEqual(to,id);expectedEdges.set(id+'->'+to,category);category==='ordinary'?ordinary++:dramatic++;
  }
  const reached=new Set([id]),pending=[id];while(pending.length)for(const next of g.nodes[pending.pop()].ordinary)if(!reached.has(next)){reached.add(next);pending.push(next);}
  assert.equal(reached.size,42,'Ordinary graph not strongly connected from '+id);
  assert.equal(c.expressions[id].mood,id);assert.equal(c.expressions[id].performances.length,3);assert.ok(c.expressions[id].art.note.length>10);
}
assert.equal(expectedEdges.size,295);assert.equal(trans.edges.length,expectedEdges.size);assert.equal(new Set(trans.edges.map(v=>v.id)).size,295);
for(const e of trans.edges){assert.equal(expectedEdges.get(e.id),e.category);assert.equal(e.variants.length,3);assert.equal(e.status,'planned-continuous-bridge');}
for(const ladder of Object.values(g.intensityLadders))for(let i=1;i<ladder.length;i++)assert.ok(g.nodes[ladder[i-1]].ordinary.includes(ladder[i]));
assert.equal(cov.cells.length,42*22);assert.equal(new Set(cov.cells.map(v=>v.id)).size,cov.cells.length);
for(const row of cov.cells){
  const state=s.states.find(v=>v.id===row.state);assert.ok(ids.includes(row.mood)&&state);assert.equal(row.id,row.mood+'.'+row.state);
  assert.equal(row.variations.length,3);assert.deepEqual(row.requiredHostFacts,s.hostFacts[row.state]||{});
  assert.deepEqual(row.factVariations,state.factVariations||{});
  for(const choices of Object.values(row.factVariations))for(const variations of Object.values(choices)){assert.equal(variations.length,3);assert.equal(new Set(variations).size,3);}
  assert.ok(row.status.startsWith('planned-'));assert.equal(row.audioPolicy,state.audioPolicy);
  if(state.scene==='rest'){assert.equal(row.mode,'explicit-quiet-alias');assert.equal(row.audioPolicy,'silent');}
}
const script=fs.readFileSync(path.join(root,'preview/slime.js'),'utf8');new vm.Script(script);new vm.Script(fs.readFileSync(path.join(root,'preview/sound-audition.js'),'utf8'));
assert.ok(!script.includes('window.openai'),'Standalone preview must not depend on conversation host');
const sandbox={window:{}};vm.runInNewContext(fs.readFileSync(path.join(root,'preview/catalog.js'),'utf8'),sandbox);
assert.equal(JSON.stringify(sandbox.window.SlimeCatalog),JSON.stringify(c),'Run tools/build.cjs: stale preview catalogue');
const shader=script.match(/const fs=`([\s\S]*?)`;/)[1];
const provenance=read('contracts/source-provenance.json');assert.equal(crypto.createHash('sha256').update(shader).digest('hex'),provenance.materialFragmentSha256,'Export changed original gel material');
require('./check-motion.cjs');
const fx=require('../sound/sfx.js');let soundRenders=0,maxPeak=0;
for(const name of Object.keys(fx.recipes))for(const variant of [0,1,2]){
  const a=fx.render(name,{variant,seed:53}),b=fx.render(name,{variant,seed:53});assert.deepEqual(a.data,b.data,'Seed must replay');
  assert.ok(a.duration>0&&a.duration<=3);assert.ok(a.data.length>100);assert.ok(a.data[0]===0);
  assert.ok(a.data.every(Number.isFinite));const peak=a.data.reduce((m,n)=>Math.max(m,Math.abs(n)),0);assert.ok(peak>0&&peak<=.8);maxPeak=Math.max(maxPeak,peak);soundRenders++;
  assert.ok(fx.render(name,{gain:0}).data.every(v=>v===0),'Mute must be silence');
}
assert.throws(()=>fx.render('not-a-recipe'),RangeError);
const walk=dir=>fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);
for(const file of walk(root)){
  const text=fs.readFileSync(file,'utf8');assert.ok(!text.includes('/Users/'+'work/')&&!text.includes('/var/'+'folders/'),'Workstation path leaked: '+file);
  if(file.endsWith('.md'))for(const match of text.matchAll(/\]\(([^)]+)\)/g)){
    const href=match[1];if(/^(https?:|mailto:|#)/.test(href))continue;
    const target=path.resolve(path.dirname(file),decodeURIComponent(href.split('#')[0]));assert.ok(fs.existsSync(target),'Broken link '+href+' in '+file);
  }
}
console.log(JSON.stringify({status:'OFFLINE PACKAGE PASS',moods:42,expressions:44,states:22,cells:cov.cells.length,edges:expectedEdges.size,ordinary,dramatic,soundRenders,maxPeak,links:'pass',productionChanged:false}));
