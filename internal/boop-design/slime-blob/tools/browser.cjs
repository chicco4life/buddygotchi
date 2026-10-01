if(process.argv.includes('--help')){console.log('node tools/browser.cjs\nSee VALIDATION.md for Playwright/browser/URL/output overrides.');process.exit(0);}
const {chromium}=require(process.env.BOOP_PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path'),os=require('node:os');
const output=process.env.BOOP_QA_OUTPUT||fs.mkdtempSync(path.join(os.tmpdir(),'boop-slime-qa-'));
fs.mkdirSync(output,{recursive:true});
const url=process.env.BOOP_QA_URL||'http://127.0.0.1:4190/';
const catalog=JSON.parse(fs.readFileSync(path.join(__dirname,'../expressions.json'),'utf8'));
const browserOptions=process.env.BOOP_QA_BROWSER?{executablePath:process.env.BOOP_QA_BROWSER}:{};
const get=frame=>frame.evaluate(()=>document.getElementById('slime-jelly-base')._slimePreview.getState());
(async()=>{
 const browser=await chromium.launch({...browserOptions,headless:true,args:['--disable-background-networking','--disable-sync','--disable-extensions','--no-first-run','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 try{
  const page=await browser.newPage({viewport:{width:780,height:820},deviceScaleFactor:1});
  const errors=[];page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  page.on('response',r=>{if(r.status()>=400)errors.push('HTTP '+r.status()+' '+r.url());});
  await page.goto(url);
  const frame=page.mainFrame();
  await frame.waitForFunction(()=>document.getElementById('slime-jelly-base')?._slimePreview?.getState().frames>6);
  let state=await get(frame);
  assert.equal(state.rendering,'procedural-webgl',JSON.stringify(state));assert.equal(state.shaderError,'');
  assert.equal(state.emotions.length,42);assert.equal(state.expressions.length,44);assert.equal(state.referenceMapping.length,19);
  assert.equal(await page.locator('[data-sound-buttons] button').count(),10);
  await page.getByRole('button',{name:'Knock → ding',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector('[data-sound-status]').textContent.includes('sketch'));
  await page.getByRole('button',{name:'Stop sound',exact:true}).click();
  assert.equal(state.material,'simple-blue-translucent-gel');assert.equal(state.draftGraphImplemented,false);
  assert.deepEqual(state.expressions,Object.keys(catalog.expressions));
  await frame.getByRole('button',{name:'Pause',exact:true}).click();
  const faceImages=[];
  for(const id of state.expressions){
   await frame.getByLabel('Expression',{exact:true}).selectOption(id);
   await page.waitForTimeout(100);const s=await get(frame);
   assert.equal(s.expression,id);assert.equal(s.emotion,catalog.expressions[id].mood);
   assert.equal(s.weights[s.expressions.indexOf(id)],1);assert.ok(s.weights.every(Number.isFinite));
   assert.ok(Math.abs(s.weights.reduce((a,b)=>a+b,0)-1)<.001);
   assert.equal(await frame.getByLabel('Performance',{exact:true}).locator('option').count(),4);
   if(process.env.BOOP_CAPTURE_FACES!=='0'){
    await frame.locator('.slime-stage').screenshot({path:output+'/slime-kawaii-face-'+id.replace(':','-')+'.png'});
    const b=await frame.locator('.slime-stage').boundingBox();
    const crop=await page.screenshot({clip:{x:b.x+b.width*.20,y:b.y+b.height*.15,width:b.width*.60,height:b.height*.72}});
    faceImages.push({id,image:crop.toString('base64')});
   }
  }
  if(faceImages.length){
  const sheet=await browser.newPage({viewport:{width:1200,height:1600}});
  await sheet.setContent('<body style="margin:0;background:#151b22;color:white;font:14px sans-serif"><main style="display:grid;grid-template-columns:repeat(6,1fr);gap:6px;padding:8px">'+faceImages.map(({id,image})=>'<div><img style="display:block;width:100%;border-radius:8px" src="data:image/png;base64,'+image+'"><div style="padding:5px 2px">'+id+'</div></div>').join('')+'</main></body>');
  await sheet.screenshot({path:output+'/slime-expression-v3-contact-sheet.png',fullPage:true});await sheet.close();
  }
  await frame.getByLabel('Expression',{exact:true}).selectOption('happy');
  await frame.getByRole('button',{name:'Resume',exact:true}).click();
  const types=[];
  for(let i=0;i<3;i++){
   await frame.getByLabel('Performance',{exact:true}).selectOption(String(i));await page.waitForTimeout(380);
   const s=await get(frame);types.push(s.performance.type);
   assert.equal(s.performance.index,i);assert.ok(Object.values(s.actorChannels).some(m=>Math.abs(m.x)>.005));
  }
  assert.equal(new Set(types).size,3);
  await frame.getByLabel('Expression',{exact:true}).selectOption('pleased');
  await page.waitForTimeout(500);
  const box=await frame.locator('.slime-stage').boundingBox();
  const point={x:box.x+box.width*.60,y:box.y+box.height*.46};
  await page.mouse.move(point.x,point.y);await page.mouse.down();
  assert.equal((await get(frame)).grab.active,true,'Surface grab did not attach');
  await page.mouse.move(point.x+125,point.y-45,{steps:14});await page.waitForTimeout(350);
  state=await get(frame);assert.equal(state.expression,'pleased','Dragging must not switch mood');
  assert.equal(state.grab.dragged,true);assert.ok(Math.hypot(...state.grab.target)>.2);
  assert.ok(Math.hypot(...state.grab.pull.map(m=>m.x))>.2);
  assert.ok(Math.hypot(...state.grab.target)<=.641);
  await page.screenshot({path:output+'/slime-expression-v3-drag.png'});
  await page.mouse.move(box.x+box.width-4,box.y+4,{steps:4});
  assert.ok(Math.hypot(...(await get(frame)).grab.target)<=.641,'Pull target must remain bounded at the stage edge');
  await page.mouse.up();
  await frame.waitForFunction(()=>!document.getElementById('slime-jelly-base')._slimePreview.getState().grab.active,null,{timeout:3000});
  state=await get(frame);assert.equal(state.grab.active,false);assert.deepEqual(state.grab.target,[0,0,0]);
  await frame.waitForFunction(()=>document.getElementById('slime-jelly-base')._slimePreview.getState().grab.pull.every(m=>Math.abs(m.x)<.006&&Math.abs(m.v)<.025),null,{timeout:10000});
  assert.equal((await get(frame)).expression,'pleased');
  await page.mouse.move(box.x+4,box.y+4);await page.mouse.down();assert.equal((await get(frame)).grab.active,false);await page.mouse.up();
  const cdp=await page.context().newCDPSession(page);
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:point.x,y:point.y,id:5}]});
  assert.equal((await get(frame)).grab.pointerType,'touch');assert.equal((await get(frame)).grab.active,true);
  await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:point.x-80,y:point.y+20,id:5}]});
  await page.waitForTimeout(200);assert.equal((await get(frame)).grab.dragged,true);
  await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  assert.equal((await get(frame)).grab.active,false);assert.equal((await get(frame)).expression,'pleased');
  await page.mouse.move(point.x,point.y);await page.mouse.down();
  await frame.locator('.slime-stage').dispatchEvent('pointercancel',{pointerId:1,pointerType:'mouse'});
  await page.mouse.up();assert.equal((await get(frame)).grab.active,false);
  await page.setViewportSize({width:360,height:850});await page.waitForTimeout(350);
  assert.ok(await frame.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await page.screenshot({path:output+'/slime-expression-v3-mobile.png'});
  await page.emulateMedia({reducedMotion:'reduce'});
  await frame.getByRole('button',{name:'Shake',exact:true}).click();await page.waitForTimeout(150);
  assert.equal((await get(frame)).expression,'pleased');assert.deepEqual(errors,[]);
  const fallbackBrowser=await chromium.launch({...browserOptions,headless:true,args:['--disable-background-networking','--disable-sync','--disable-extensions','--no-first-run','--disable-webgl']});
  try{
  const fallback=await fallbackBrowser.newPage({viewport:{width:360,height:850}});
  await fallback.goto(url);const ff=fallback.mainFrame();
  await ff.waitForFunction(()=>document.getElementById('slime-jelly-base')?._slimePreview?.getState().frames>4);
  assert.equal((await get(ff)).rendering,'procedural-canvas-fallback');
  await ff.getByRole('button',{name:'Pause',exact:true}).click();
  for(const id of ['happy','crying','frightened','speechless:tearful']){
   await ff.getByLabel('Expression',{exact:true}).selectOption(id);assert.equal((await get(ff)).expression,id);
  }
  await fallback.screenshot({path:output+'/slime-expression-v3-fallback.png'});await fallback.close();
  }finally{await fallbackBrowser.close();}
  console.log(JSON.stringify({shader:'pass',expressions:44,canonicalMoods:42,references:19,happyGestures:types,drag:'pass',boundedPull:'pass',releaseSettling:'pass',mobile:'pass',reducedMotion:'pass',fallback:'pass',manualSoundUI:'pass',errors,output}));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
