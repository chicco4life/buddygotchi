(() => {
  const root = document.getElementById('slime-jelly-base');
  const stage = root.querySelector('.slime-stage');
  const canvas = root.querySelector('canvas');
  const status = root.querySelector('[data-status]');
  const pauseButton = root.querySelector('[data-pause]');
  const expressionSelect = root.querySelector('[data-expression]');
  const profiles = window.SlimeCatalog.expressions;
  const referenceMapping = window.SlimeCatalog.referenceMapping;
  const familyTitles = window.SlimeCatalog.familyTitles;
  const emotions = Object.keys(profiles);
  const moodIds = emotions.filter(id=>!id.includes(':'));
  const titles = emotions.map(id=>profiles[id].label);
  const saved = null; // Standalone audition: no host SDK or persisted app state.
  const savedEmotion = saved?.privateContent?.expression || saved?.modelContent?.expression || saved?.modelContent?.emotion;
  const previewAliases = {unimpressed:'speechless',hurt:'wounded',shook:'stunned',naughty:'mischievous'};
  let emotion = emotions.includes(savedEmotion) ? savedEmotion : previewAliases[savedEmotion] || 'calm';
  const weights = new Float32Array(emotions.length);
  weights[emotions.indexOf(emotion)]=1;
  expressionSelect.replaceChildren();
  for(const family of [...Object.keys(familyTitles),'reference']){
    const group=document.createElement('optgroup');group.label=family==='reference'?'Reference face alternates':familyTitles[family];
    for(const id of emotions.filter(id=>profiles[id].family===family)){
      const option=document.createElement('option');option.value=id;option.textContent=profiles[id].label;group.append(option);
    }
    expressionSelect.append(group);
  }
  expressionSelect.value = emotion;
  const performanceSelect=root.querySelector('[data-performance]');
  let chosenPerformance=saved?.privateContent?.performance||'auto';
  let actor=null,nextPerformance=1,performanceCount=0,lastPerformance=-1;
  const actorChannels={lean:{x:0,v:0},squash:{x:0,v:0},ripple:{x:0,v:0},lift:{x:0,v:0},roll:{x:0,v:0},forward:{x:0,v:0}};
  const grab={active:false,id:null,point:[0,.2],anchor:null,start:null,dragged:false,pointerType:null,target:[0,0,0],pull:[{x:0,v:0},{x:0,v:0},{x:0,v:0}]};
  const faceCanvas=document.createElement('canvas');faceCanvas.width=512;faceCanvas.height=512;
  const faceContext=faceCanvas.getContext('2d');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  // BOOP_MOTION_V1_BEGIN configuration
  const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));
  const spring = (frequency, damping) => ({x:0, v:0, frequency, damping});
  const modes = {lean:spring(11,4.6), squash:spring(13,4.5), ripple:spring(18,5.3), dent:spring(16,6.0)};
  // BOOP_MOTION_V1_END configuration
  let gl = null, draw = null, paused = false, hidden = document.hidden;
  let time = 0, lastTime = 0, contact = {x:0,y:.20}, reactionUntil = 0;
  let nextBlink = 2.8, blinkAt = -10, gaze = 0, gazeTarget = 0, nextLook = 4.5;
  let frames = 0, shaderError = '', rendering = 'initializing';
  let randomSeed = 1729;
  const rand = () => {randomSeed = (Math.imul(randomSeed,1664525)+1013904223)>>>0;return randomSeed/4294967296;};
  function updateStatus(action='resting'){
    const text=titles[emotions.indexOf(emotion)]+' · '+(paused?'paused':action);
    if(status.textContent!==text)status.textContent=text;
  }
  function setEmotion(name, immediate=false, remember=true){
    name=previewAliases[name]||name;if(!emotions.includes(name))return;
    emotion=name;expressionSelect.value=name;actor=null;nextPerformance=time+.4;lastPerformance=-1;updatePerformanceMenu();
    if(immediate)for(let i=0;i<weights.length;i++)weights[i]=Number(emotions[i]===name);
    updateStatus();
    if(remember)rememberChoice();
    if(draw)draw();
  }
  updateStatus();updatePerformanceMenu();

  // Additive V2 audition layers. The locked V1 integrator and dome are untouched.
  function rememberChoice(){ /* No host writes in this standalone audition. */ }
  function updatePerformanceMenu(){
    performanceSelect.replaceChildren();
    const auto=document.createElement('option');auto.value='auto';auto.textContent='Auto · varied quiet intervals';performanceSelect.append(auto);
    profiles[emotion].performances.forEach((p,i)=>{const option=document.createElement('option');option.value=String(i);option.textContent=p.label;performanceSelect.append(option);});
    if(!['auto','0','1','2'].includes(chosenPerformance))chosenPerformance='auto';
    performanceSelect.value=chosenPerformance;
  }
  function perform(index){
    const choices=profiles[emotion].performances;
    let selected=index===undefined?(chosenPerformance==='auto'?Math.floor(rand()*3):Number(chosenPerformance)):Number(index);
    if(chosenPerformance==='auto'&&index===undefined&&selected===lastPerformance)selected=(selected+1+Math.floor(rand()*2))%3;
    selected=clamp(selected,0,2);lastPerformance=selected;
    actor={...choices[selected],index:selected,start:time,cursor:0,expression:emotion};
    performanceCount++;reactionUntil=time+actor.duration;
    updateStatus(actor.label.toLowerCase());
    nextPerformance=time+actor.duration+7+rand()*8;
  }
  function advanceExtensions(dt){
    if(grab.active&&grab.focusWasAcquired&&document.hasFocus&&!document.hasFocus())releaseGrab(null,true);
    if(!grab.active&&time>=nextPerformance)perform();
    if(actor&&actor.expression===emotion){
      const age=time-actor.start;
      while(actor.cursor<actor.cues.length&&age>=actor.cues[actor.cursor][0]){
        const [,channel,velocity]=actor.cues[actor.cursor++];
        actorChannels[channel].v+=velocity*(reduced.matches?.18:1);
      }
    }
    for(const [name,m] of Object.entries(actorChannels)){
      let left=dt;const frequency=name==='lift'?11:name==='roll'?10:9;
      while(left>0){const h=Math.min(left,1/240);m.v+=(-frequency*frequency*m.x-6.4*m.v)*h;m.x+=m.v*h;left-=h;}
      const limit=name==='lift'?.24:name==='roll'?.12:name==='forward'?.18:.42;
      m.x=clamp(m.x,-limit,limit);m.v=clamp(m.v,-5,5);
    }
    for(let i=0;i<3;i++){
      const m=grab.pull[i];let left=dt;
      while(left>0){const h=Math.min(left,1/240);m.v+=(256*(grab.target[i]-m.x)-8*m.v)*h;m.x+=m.v*h;left-=h;}
      m.x=clamp(m.x,-.72,.72);m.v=clamp(m.v,-6,6);
    }
  }
  function posture(){
    let lean=0,squash=0,ripple=0;
    for(let i=0;i<weights.length;i++){
      const mood=profiles[emotions[i]].mood,w=weights[i];
      const low={lazy:-.04,bored:-.022,tired:-.032,exhausted:-.10,disappointed:-.035,sad:-.055,crying:-.045,wounded:-.055,frightened:-.045,shy:-.025,comfy:-.02}[mood]||0;
      const high={proud:.05,determined:.022,hopeful:.025,engaged:.012}[mood]||0;
      squash+=w*(low+high);
      if(!reduced.matches){
        if(mood==='excited')squash+=w*.012*Math.sin(time*4.3);
        if(mood==='scared'||mood==='frightened'){const amplitude=mood==='scared'?.014:.026;lean+=w*amplitude*Math.sin(time*13)*(.35+.65*Math.pow(Math.sin(time*.75),2));}
        if(mood==='crying')squash+=w*.01*Math.sin(time*3.1);
        if(mood==='irritated')lean+=w*.008*Math.sin(time*6.1)*Math.pow(Math.max(0,Math.sin(time*.7)),4);
      }
    }
    return [lean,squash,ripple];
  }
  function composePose(){
    const base=pose(),p=posture();
    return [base[0]+actorChannels.lean.x+p[0],base[1]+actorChannels.squash.x+p[1],base[2]+actorChannels.ripple.x+p[2],base[3]];
  }
  function lifePose(){return [Math.max(0,actorChannels.lift.x),actorChannels.roll.x,actorChannels.forward.x];}
  // Individually art-directed V3 faces: pupil-free, broad and low-set.
  function paintFace(){
    const ctx=faceContext;
    ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,512,512);
    ctx.setTransform(256,0,0,-256,256,256);ctx.scale(1.24,1.24);
    const ink='#0d2b48',water='#c5edf5',tearInk='#70b8d4';
    const age=actor?time-actor.start:100;
    const activity=actor&&age<actor.duration?Math.sin(Math.PI*Math.min(1,age/actor.duration)):0;
    const motion=reduced.matches?0:1,blinkValue=blink();
    function stroke(commands,width=.027,color=ink){
      ctx.beginPath();ctx.strokeStyle=color;ctx.lineWidth=width;ctx.lineCap='round';ctx.lineJoin='round';
      for(const [kind,...v] of commands){
        if(kind==='M')ctx.moveTo(...v);else if(kind==='L')ctx.lineTo(...v);else if(kind==='Q')ctx.quadraticCurveTo(...v);else if(kind==='C')ctx.bezierCurveTo(...v);
      }ctx.stroke();
    }
    const q=(a,b,c,width=.027,color=ink)=>stroke([['M',...a],['Q',...b,...c]],width,color);
    const c=(a,b,d,e,width=.027,color=ink)=>stroke([['M',...a],['C',...b,...d,...e]],width,color);
    function egg(x,y,rx,ry,fill=ink,angle=0,edge=0){
      ctx.save();ctx.translate(x,y);ctx.rotate(angle);ctx.beginPath();ctx.ellipse(0,0,rx,ry,0,0,Math.PI*2);
      ctx.fillStyle=fill;ctx.fill();if(edge){ctx.strokeStyle=ink;ctx.lineWidth=edge;ctx.stroke();}ctx.restore();
    }
    function bean(rx,ry,angle=0){egg(0,0,rx,ry,ink,angle);}
    function eyeArc(width=.128,height=.092,weight=.031){q([-width,-.018],[0,height],[width,-.018],weight);}
    function droop(width=.128,depth=.069,weight=.030){q([-width,.030],[-.014,-depth],[width,.017],weight);}
    function squeeze(width=.109,weight=.030){
      c([-width,.049],[-.035,.042],[.020,.014],[.067,-.004],weight);
      c([.067,-.004],[.015,-.008],[-.040,-.030],[-width,-.055],weight);
    }
    function softWaterEye(rx,ry,angle=0){
      egg(0,0,rx,ry,water,angle,.016);
      ctx.save();ctx.rotate(angle);q([-rx*.65,-ry*.6],[0,-ry*.94],[rx*.7,-ry*.48],.008,'rgba(113,178,206,.55)');ctx.restore();
    }
    function cloudEye(){
      ctx.beginPath();ctx.moveTo(-.112,-.026);
      ctx.bezierCurveTo(-.133,.073,-.069,.145,.013,.122);
      ctx.bezierCurveTo(.101,.133,.142,.043,.093,-.021);
      ctx.bezierCurveTo(.123,-.075,.050,-.103,.014,-.071);
      ctx.bezierCurveTo(-.021,-.109,-.090,-.093,-.103,-.054);
      ctx.bezierCurveTo(-.184,-.103,-.177,-.018,-.112,-.026);
      ctx.closePath();ctx.fillStyle=water;ctx.fill();ctx.strokeStyle=tearInk;ctx.lineWidth=.013;ctx.stroke();
    }
    function wSmile(width=.076,height=.038,weight=.023,smirk=0){
      q([-width,.014],[-width*.51,-height],[0,.017],weight);
      q([0,.017],[width*.47,-height*.94],[width,.014+smirk],weight);
    }
    function roundedOpen(width,depth,{pale=false,tilt=0,tongue=false}={}){
      ctx.save();ctx.rotate(tilt);ctx.beginPath();ctx.moveTo(-width,.040);
      ctx.quadraticCurveTo(0,.054,width,.040);
      ctx.bezierCurveTo(width*.95,-depth,width*.40,-depth,0,-depth);
      ctx.bezierCurveTo(-width*.40,-depth,-width*.95,-depth,-width,.040);ctx.closePath();
      ctx.fillStyle=pale?water:ink;ctx.fill();ctx.strokeStyle=ink;ctx.lineWidth=.022;ctx.lineJoin='round';ctx.stroke();
      if(tongue){ctx.save();ctx.clip();egg(width*.06,-depth+.025,width*.71,.036,'#afdde8');ctx.restore();}
      ctx.restore();
    }
    function littleMouth(kind,pulse,side){
      if(kind==='tiny-ring')egg(0,0,.018,.026,'rgba(153,216,236,.6)',0,.014);
      else if(kind==='little-bean')roundedOpen(.046,.061,{tongue:true});
      else if(kind==='baby-w')wSmile(.076,.037,.023);
      else if(kind==='tiny-frown')q([-.031,-.010],[0,.031],[.031,-.010],.021);
      else if(kind==='baby-yawn')egg(0,-.015,.036,.049,ink);
      else if(kind==='spent-pout')q([-.046,.005],[0,-.006],[.040,-.009],.023);
      else if(kind==='happy-u')roundedOpen(.076,.121+Math.max(0,pulse)*.010,{pale:true});
      else if(kind==='wide-laugh')roundedOpen(.135,.107+Math.max(0,pulse)*.012,{tilt:-.075,tongue:true});
      else if(kind==='crooked-grin')roundedOpen(.086,.060,{tilt:-.19,tongue:true});
      else if(kind==='small-u-line')q([-.044,.012],[0,-.029],[.044,.012],.022);
      else if(kind==='firm-w')wSmile(.062,.024,.024,.007);
      else if(kind==='tilted-o')egg(0,0,.020,.031,water,.23,.017);
      else if(kind==='little-triangle'||kind==='shook-triangle'||kind==='tiny-triangle'){
        const width=kind==='tiny-triangle'?.031:.037;
        stroke([['M',-width,.014],['Q',0,.022,width,.014],['Q',width*.7,-.024,0,-.037],['Q',-width*.7,-.024,-width,.014]],.019);
      }
      else if(kind==='crooked-pout')q([-.043,-.003],[.010,.020],[.042,-.017],.023);
      else if(kind==='curled-smirk'){wSmile(.075,.032,.024,.030);q([.074,.041],[.090,.054],[.096,.071],.018);}
      else if(kind==='puckered-three'){
        c([-.033,.053],[.061,.064],[.074,.008],[.006,.005],.024);
        c([.006,.005],[.076,.006],[.059,-.060],[-.032,-.048],.024);
      }
      else if(kind==='tiny-v')q([-.028,.014],[0,-.048],[.028,.014],.021);
      else if(kind==='awkward-w'){ctx.rotate(.10);wSmile(.058,.031,.022,.008);}
      else if(kind==='warm-w')wSmile(.068,.036,.023);
      else if(kind==='small-pout')q([-.032,-.010],[0,.030],[.032,-.010],.023);
      else if(kind==='pushed-pout')q([-.036,.006],[.026,.011],[.043,-.021],.025);
      else if(kind==='tense-pout'){q([-.052,-.012],[0,.034],[.047,-.009],.023);}
      else if(kind==='grumpy-pout'){
        q([-.065,-.020],[-.028,.039],[0,.010],.025);
        q([0,.010],[.029,.039],[.065,-.020],.025);
      }
      else if(kind==='protest-bean')roundedOpen(.074,.075+Math.max(0,pulse)*.012,{tongue:true});
      else if(kind==='sad-pout')q([-.035,-.015],[0,.028],[.035,-.015],.022);
      else if(kind==='quivering-pout'){
        q([-.047,-.014],[-.020,.031],[0,.007+pulse*.006],.023);
        q([0,.007+pulse*.006],[.021,.031],[.047,-.014],.023);
      }
      else if(kind==='complaining-pout'){
        ctx.beginPath();ctx.moveTo(-.062,-.010);ctx.quadraticCurveTo(-.034,.047,0,.023);
        ctx.quadraticCurveTo(.035,.047,.061,-.010);ctx.quadraticCurveTo(0,-.052,-.062,-.010);
        ctx.fillStyle=ink;ctx.fill();ctx.save();ctx.clip();egg(0,-.036,.040,.025,'#afdde8');ctx.restore();
      }
      else if(kind==='hurt-pout')q([-.033,-.013],[0,.033],[.033,-.013],.022);
      else if(kind==='uneasy-wave'||kind==='fear-wave'||kind==='small-waver'){
        const width=kind==='fear-wave'?.079:kind==='small-waver'?.062:.058;
        const height=kind==='fear-wave'?.032:.024;
        stroke([['M',-width,-.006],['Q',-width*.72,height,-width*.36,.002],['Q',0,-height*.62,width*.34,.004],['Q',width*.71,height,width,-.006]],.023);
      }
      else if(kind==='frightened-pout'){
        c([-.070,-.026],[-.045,.081],[.046,.081],[.070,-.026],.024);
        q([-.021,.009],[-.008,-.010],[-.009,-.019],.015);
        q([.021,.009],[.008,-.010],[.009,-.019],.015);
      }
      else if(kind==='round-gasp')egg(0,-.008,.035,.047,ink);
      else if(kind==='tiny-caret')q([-.030,-.013],[0,.030],[.030,-.013],.021);
      else if(kind==='exhale-bean')roundedOpen(.048,.050,{tongue:true});
      else if(kind==='side-blep'){
        q([-.053,.004],[.009,.035],[.051,-.013],.023);
        q([.019,-.008],[.021,-.036],[.039,-.026],.017,'#a9d5df');
      }
      else if(kind==='blank-line')q([-.041,0],[0,-.002],[.041,0],.022);
    }
    for(let i=0;i<weights.length;i++){
      if(weights[i]<.002)continue;
      const id=emotions[i],p=profiles[id],a=p.art,mood=p.mood;
      ctx.save();ctx.globalAlpha=weights[i];
      const act=actor?.expression===id?activity:0;
      const pulse=motion*act*Math.sin(age*(mood==='excited'?8.5:4.2));
      let glance=gaze;
      if(actor?.expression===id&&['slow-look','side-eye','scan','peek','hide-peek'].includes(actor.type))glance+=motion*act*.017*Math.sin(age*2.3);
      if(mood==='embarrassed')glance-=.019;
      // Graphic oval cheeks, not barely visible glossy shader freckles.
      if(a.cheeks!=='none'){
        const alpha=ctx.globalAlpha;
        const rosy=a.cheeks==='blush',hatch=a.cheeks==='hatch',soft=a.cheeks==='soft';
        const opacity=rosy?.42:hatch?.31:soft?.18:a.cheeks==='freckles'?.22:.12;
        for(const side of [-1,1]){
          ctx.globalAlpha=alpha*opacity*(1+act*.12);
          egg(side*.435,-.053,rosy?.101:.080,rosy?.041:.032,'#f0a5bb',-.08*side);
          if(rosy||hatch){ctx.globalAlpha=alpha*(rosy?.45:.28);for(let j=-1;j<=1;j++)q([side*.435+j*.026-.007,-.039],[side*.435+j*.026,-.054],[side*.435+j*.026+.007,-.073],.012,'#bc7895');}
          if(a.cheeks==='freckles'){ctx.globalAlpha=alpha*.40;for(const [x,y,r] of [[.46,-.087,.010],[.49,-.063,.011],[.43,-.100,.007]])egg(side*x,y,r,r,'#508caf');}
          if(a.cheeks==='strain'||a.cheeks==='effort'){ctx.globalAlpha=alpha*.30;q([side*.437-.02,-.047],[side*.437-.01,-.061],[side*.437,-.075],.011);}
        }
        ctx.globalAlpha=alpha;
      }
      // Tears are individually shaped to the eyes and are drawn behind lids.
      if(p.tears!=='none'){
        for(const side of [-1,1]){
          const x=side*a.eyeX,start=a.eyeY-(mood==='frightened'?.027:mood==='crying'?.005:.040);
          const broad=p.tears==='sheets',thin=p.tears==='thin';
          const width=broad?(mood==='frightened'?.090:.078):thin?.021:.019;
          const strength=p.tears==='occasional'?.30+.26*Math.pow(Math.max(0,Math.sin(time*.8)),4):1;
          ctx.save();ctx.globalAlpha*=strength;
          if(broad||thin||p.tears==='occasional'){
            const end=broad?-.49:-.42,wave=motion*.009*Math.sin(time*2.7+side);
            const fill=ctx.createLinearGradient(x,start,x,end);
            fill.addColorStop(0,'rgba(173,225,243,.55)');fill.addColorStop(.65,'rgba(117,201,235,.41)');fill.addColorStop(1,'rgba(98,181,224,.06)');
            ctx.beginPath();ctx.moveTo(x-width,start);
            ctx.bezierCurveTo(x-width-wave,-.12,x-width+wave,-.28,x-width*.82,end+.045);
            ctx.quadraticCurveTo(x-width*.5,end-.02,x,end);
            ctx.quadraticCurveTo(x+width*.6,end-.02,x+width*.8,end+.045);
            ctx.bezierCurveTo(x+width+wave,-.28,x+width-wave,-.12,x+width,start);ctx.closePath();
            ctx.fillStyle=fill;ctx.fill();
            q([x-width*.52,start-.013],[x-width*.7+wave,-.10],[x-width*.42,-.18],broad?.009:.006,'rgba(215,245,253,.35)');
            q([x+width*.5,-.24],[x+width*.3-wave,-.29],[x+width*.5,-.34],broad?.009:.006,'rgba(206,239,251,.27)');
            if(!reduced.matches&&broad){const fall=(time*.46+(side<0?0:.37))%1;egg(x+wave,-.09-fall*.41,.015,.027,'rgba(194,239,250,.5)');}
          }else{
            egg(x-side*.054,a.eyeY-.061,.031,.023,water,0,.009);
            if(!reduced.matches){const fall=(time*.24+(side<0?0:.43))%1;egg(x+side*.025,-.08-fall*.28,.015,.025,'rgba(168,225,244,.7)');}
          }ctx.restore();
        }
      }
      for(const side of [-1,1]){
        ctx.save();ctx.translate(side*a.eyeX+glance,a.eyeY);
        const wink=actor?.expression===id&&actor.type==='wink'&&age>.45&&age<1.2&&side===-1;
        ctx.scale(side===1?-1:1,1-.86*(wink?1:blinkValue));
        const type=a.eyes;
        if(type==='soft-dot')bean(.035,.049);
        else if(type==='comfy-dash')bean(.042,.014,-.035);
        else if(type==='lazy-equals'){q([-.100,.028],[0,.034],[.100,.024],.023);q([-.100,-.014],[0,-.009],[.100,-.016],.023);}
        else if(type==='bored-bean')bean(.066,.026,.055);
        else if(type==='sleepy-lid')droop(.112,.041,.030);
        else if(type==='spent-lid')droop(.140,.090,.032);
        else if(type==='pleased-bean')bean(.073,.022,-.43);
        else if(type==='happy-dot')bean(.043,.046);
        else if(type==='laugh-lid')eyeArc(.128,.123,.033);
        else if(type==='amused-wink'){if(side===-1)eyeArc(.112,.083,.032);else bean(.045,.053);}
        else if(type==='curious-eggs'){const swing=motion*Math.sin(time*2);bean(.037+side*swing*.009,.049+side*swing*.022);}
        else if(type==='attentive-eggs')bean(.034,.058);
        else if(type==='gentle-resolve'){bean(.035,.056);q([-.070,.103],[.008,.117],[.062,.133],.020);}
        else if(type==='puzzled-eggs'){bean(side===-1?.026:.042,side===-1?.046:.065);if(side===-1)q([-.051,.102],[.005,.137],[.064,.128],.019);}
        else if(type==='baffled-eggs'){bean(side===-1?.045:.029,side===-1?.073:.042);if(side===1)q([-.043,.108],[.003,.112],[.053,.087],.018);}
        else if(type==='skeptical-lids'){
          if(side===-1){q([-.115,.028],[0,.023],[.098,-.007],.029);bean(.036,.015,.0);}
          else bean(.063,.026,-.25);
        }
        else if(type==='smug-lids'){bean(.070,.018,.23);q([-.065,.003],[.013,-.024],[.073,.019],.021);}
        else if(type==='cheeky-beans')bean(.054,.018,-.49);
        else if(type==='bashful-squeeze'){c([-.090,.037],[-.040,.032],[.015,.000],[.049,-.019],.027);c([.049,-.019],[.006,-.018],[-.040,-.031],[-.076,-.039],.026);}
        else if(type==='averted-eggs')bean(.026,.045,.11);
        else if(type==='warm-lids')eyeArc(.118,.087,.030);
        else if(type==='longing-beans'){bean(.029,.043,-.16);q([-.052,.099],[.010,.103],[.058,.130],.018);}
        else if(type==='annoyed-beans')bean(side===-1?.071:.054,side===-1?.024:.030,side===-1?.07:-.05);
        else if(type==='irritated-beans')bean(.072,.023,-.22+motion*act*.024*Math.sin(age*12));
        else if(type==='grumpy-beans')bean(.088,.026,-.39);
        else if(type==='angry-squeeze')squeeze(.115,.032);
        else if(type==='letdown-lids')droop(.097,.035,.029);
        else if(type==='sad-lids')droop(.128,.077,.029);
        else if(type==='crying-lids')droop(.139,.091,.032);
        else if(type==='pleading-eyes'){bean(.044,.059,-.18);q([-.058,.112],[.008,.108],[.074,.152],.021);q([-.051,-.047],[0,-.075],[.047,-.040],.017,tearInk);}
        else if(type==='hurt-eggs')bean(.024,.050);
        else if(type==='cautious-eggs'){bean(.030,.050,side===-1?-.10:.07);if(side===-1)q([-.040,.101],[.006,.119],[.050,.110],.016);}
        else if(type==='scared-water'){softWaterEye(.084,.080);egg(-.091,-.045,.033,.023,water,0,.014);}
        else if(type==='puffy-clouds')cloudEye();
        else if(type==='surprise-dots')bean(.043,.058);
        else if(type==='shook-ovals')softWaterEye(.045,.029,-.03);
        else if(type==='stare-lids'){q([-.118,.027],[0,.014],[.112,.013],.032);q([.005,.010],[.001,-.008],[.004,-.038],.025);}
        else if(type==='hopeful-eggs')bean(.037,.060,-.09);
        else if(type==='released-lids')eyeArc(.128,.089,.029);
        else if(type==='uneasy-almonds')softWaterEye(.080,.050,-.26);
        else if(type==='wince-lids')squeeze(.094,.028);
        else if(type==='overloaded-eggs'){bean(side===-1?.039:.028,side===-1?.069:.051);q([-.049,.108],[.001,.110],[.049,.091],.017);}
        else if(type==='rosy-beans')bean(.041,.016,-.18);
        else if(type==='blank-water')softWaterEye(.039,.019);
        ctx.restore();
      }
      if(a.cheeks==='strain'){
        const alpha=ctx.globalAlpha;ctx.globalAlpha=alpha*.35;
        q([-.015,.200],[-.002,.208],[.013,.200],.012);ctx.globalAlpha=alpha;
      }
      ctx.save();ctx.translate(0,a.mouthY);
      if(['happy','excited','amused'].includes(mood))ctx.scale(1+pulse*.035,1+pulse*.05);
      littleMouth(a.mouth,pulse,glance);ctx.restore();ctx.restore();
    }
    ctx.setTransform(1,0,0,1,0,0);
  }


  function advance(dt){
    time += dt;
    // BOOP_MOTION_V1_BEGIN integration
    for(const m of Object.values(modes)){
      let left = dt;
      while(left>0){const h=Math.min(left,1/240);m.v+=(-m.frequency*m.frequency*m.x-m.damping*m.v)*h;m.x+=m.v*h;left-=h;}
      m.x=clamp(m.x,-.72,.72);m.v=clamp(m.v,-9,9);
    }
    // BOOP_MOTION_V1_END integration
    // BOOP_MOTION_V1_BEGIN face-timing
    if(time>nextBlink){blinkAt=time;nextBlink=time+3+rand()*4;}
    if(time>nextLook){gazeTarget=(rand()-.5)*.028;nextLook=time+3.2+rand()*4;}
    gaze+=(gazeTarget-gaze)*(1-Math.exp(-dt*3));
    const smoothing=1-Math.exp(-dt*(reduced.matches?35:14));
    for(let i=0;i<weights.length;i++)weights[i]+=(Number(emotions[i]===emotion)-weights[i])*smoothing;
    // BOOP_MOTION_V1_END face-timing
    advanceExtensions(dt);
    if(time>reactionUntil&&!paused)updateStatus();
  }
  // BOOP_MOTION_V1_BEGIN idle-pose
  function blink(){
    const age=time-blinkAt;
    return age>=0&&age<.24 ? Math.pow(Math.sin(Math.PI*age/.24),2) : 0;
  }
  function pose(){
    const breathe=reduced.matches?0:Math.sin(time*1.65)*.011;
    return [modes.lean.x, modes.squash.x+breathe, modes.ripple.x, modes.dent.x];
  }
  // BOOP_MOTION_V1_END idle-pose
  function impulse(kind, x=0, y=.2){
    if(paused){paused=false;pauseButton.textContent='Pause';pauseButton.setAttribute('aria-pressed','false');}
    if(kind==='poke')setEmotion(emotions[(emotions.indexOf(emotion)+1)%emotions.length]);
    // BOOP_MOTION_V1_BEGIN excitation
    contact={x:clamp(x,-.85,.85),y:clamp(y,-.25,.65)};
    const strength=reduced.matches?.25:1;
    modes.lean.v=clamp(modes.lean.v+(kind==='shake'?4.5:(x>=0?-2.6:2.6))*strength,-8,8);
    modes.squash.v=clamp(modes.squash.v-(kind==='shake'?2.6:3.5)*strength,-8,8);
    modes.ripple.v=clamp(modes.ripple.v+(kind==='shake'?5:3.5)*strength,-8,8);
    modes.dent.v=clamp(modes.dent.v+(kind==='shake'?0:4.8)*strength,-8,8);
    // BOOP_MOTION_V1_END excitation
    reactionUntil=time+3.8;updateStatus(kind==='shake'?'wobbling':'poked');
  }
  function matrixMultiply(a,b){
    const out=new Float32Array(16);
    for(let c=0;c<4;c++)for(let r=0;r<4;r++)for(let k=0;k<4;k++)out[c*4+r]+=a[k*4+r]*b[c*4+k];
    return out;
  }
  function projection(aspect){
    const f=1/Math.tan(.42), n=.1, z=20;
    return new Float32Array([f/aspect,0,0,0,0,f,0,0,0,0,(z+n)/(n-z),-1,0,0,2*z*n/(n-z),0]);
  }
  const eye=[0,1.45,3.3], target=[0,.74,0];
  function viewMatrix(){
    const sub=(a,b)=>a.map((v,i)=>v-b[i]);
    const unit=a=>{const n=Math.hypot(...a);return a.map(v=>v/n);};
    const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
    const dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0);
    const z=unit(sub(eye,target)),x=unit(cross([0,1,0],z)),y=cross(z,x);
    return new Float32Array([x[0],y[0],z[0],0,x[1],y[1],z[1],0,x[2],y[2],z[2],0,-dot(x,eye),-dot(y,eye),-dot(z,eye),1]);
  }
  function createGL(){
    gl=canvas.getContext('webgl',{alpha:true,antialias:true,premultipliedAlpha:false,preserveDrawingBuffer:true});
    if(!gl)throw new Error('WebGL unavailable');
    const vs=`
      precision highp float;
      attribute vec2 aParam;
      uniform mat4 uMatrix;
      uniform vec4 uModes;
      uniform vec2 uContact;
      uniform float uShell;
      uniform vec3 uGrab;
      uniform vec2 uGrabPoint;
      uniform vec3 uLife;
      varying vec3 vPosition;
      varying vec3 vNormal;
      varying vec3 vBase;
      // BOOP_MOTION_V1_BEGIN deformation
      vec3 shape(vec2 uv){
        float t=uv.x, p=uv.y;
        float sy=sin(t), cy=cos(t);
        float raw=.56+.91*cy;
        float y=.5*(raw+sqrt(raw*raw+.0032))+.019;
        float sx=1.0/sqrt(max(.76,1.0+uModes.y*.52));
        float radius=sy*(1.10-.07*cy);
        float x=radius*cos(p),z=radius*.77*sin(p);
        float h=y/1.49;
        float organic=.015*sin(p*3.0+cy*2.0)*sy;
        x*=1.0+organic;
        float ripple=uModes.z*.055*sy*sin(p*3.0+t*2.5);
        x=(x+ripple*cos(p))*sx;
        z=(z+ripple*sin(p))*sx;
        y*=1.0+uModes.y*.52;
        x+=uModes.x*.34*h*h;
        z+=uModes.x*.09*h;
        float front=smoothstep(.35,.9,sin(p));
        vec2 samplePoint=vec2(sy*cos(p),cy);
        vec2 distanceToContact=(samplePoint-uContact)*vec2(3.9,3.1);
        float dent=exp(-dot(distanceToContact,distanceToContact));
        z-=uModes.w*.12*dent*front;
        x+=uModes.w*.025*x*front;
        return vec3(x,y,z);
      }
      // BOOP_MOTION_V1_END deformation
      // Local surface grab and emotion acting compose around the locked dome.
      vec3 extendedShape(vec2 uv){
        vec3 pos=shape(uv);
        vec2 rest=vec2(sin(uv.x)*cos(uv.y),cos(uv.x));
        float front=smoothstep(.05,.78,sin(uv.y));
        vec2 distanceToGrab=(rest-uGrabPoint)*vec2(1.8,1.65);
        float local=exp(-dot(distanceToGrab,distanceToGrab))*front;
        float h=clamp(pos.y/1.49,0.0,1.0);
        pos+=uGrab*(.78*local+.13*h*h);
        float y=pos.y-.62,x=pos.x,c=cos(uLife.y),s=sin(uLife.y);
        pos.x=x*c-y*s;pos.y=max(.018,x*s+y*c+.62+uLife.x);
        pos.z+=uLife.z*h*h;
        return pos;
      }
      void main(){
        vec3 pos=extendedShape(aParam);
        float t=aParam.x,p=aParam.y;
        vec3 dT=extendedShape(vec2(min(3.14149,t+.003),p))-extendedShape(vec2(max(.0001,t-.003),p));
        vec3 dP=extendedShape(vec2(t,p+.003))-extendedShape(vec2(t,p-.003));
        vec3 normal=cross(dP,dT);
        if(length(normal)<.000001)normal=vec3(0.0,cos(t)>0.0?1.0:-1.0,0.0);
        vNormal=normalize(normal);
        vPosition=pos;
        vBase=vec3(sin(t)*cos(p),cos(t),sin(t)*sin(p));
        vec3 shellPosition=(pos-vec3(0.0,.70,0.0))*uShell+vec3(0.0,.70,0.0);
        gl_Position=uMatrix*vec4(shellPosition,1.0);
      }
    `;
    const fs=`
      precision highp float;
      uniform vec3 uEye;
      uniform float uBlink;
      uniform float uGaze;
      uniform sampler2D uBackdrop;
      uniform vec2 uResolution;
      uniform sampler2D uFaceTexture;
      uniform float uTime;
      uniform vec4 uModes;
      varying vec3 vPosition;
      varying vec3 vNormal;
      varying vec3 vBase;
      float oval(vec2 q,vec2 radius){return 1.0-smoothstep(.92,1.06,length(q/radius));}
      float stroke(vec2 p,vec2 a,vec2 b,float width){
        vec2 d=b-a;
        float h=clamp(dot(p-a,d)/dot(d,d),0.0,1.0);
        return 1.0-smoothstep(width,width+.005,length(p-a-h*d));
      }
      // Capsule distances give every drawn line round ends and round joins.
      float happyEye(vec2 p){return max(stroke(p,vec2(-.072,.063),vec2(.056,0.0),.022),stroke(p,vec2(.056,0.0),vec2(-.072,-.048),.022));}
      float flatEye(vec2 p){return max(stroke(p,vec2(-.084,.023),vec2(.084,.023),.019),stroke(p,vec2(.010,.023),vec2(.010,-.047),.017));}
      float pointedEye(vec2 p){return stroke(p,vec2(-.065,.031),vec2(.049,-.016),.025);}
      float closedEye(vec2 p){
        float a=stroke(p,vec2(-.086,-.018),vec2(-.039,.029),.022);
        float b=stroke(p,vec2(-.039,.029),vec2(.017,.042),.022);
        return max(max(a,b),stroke(p,vec2(.017,.042),vec2(.082,.015),.022));
      }
      float wSmile(vec2 p){
        float a=max(stroke(p,vec2(-.093,-.128),vec2(-.060,-.158),.015),stroke(p,vec2(-.060,-.158),vec2(-.030,-.158),.015));
        a=max(a,stroke(p,vec2(-.030,-.158),vec2(0.0,-.130),.015));
        float b=max(stroke(p,vec2(0.0,-.130),vec2(.030,-.158),.015),stroke(p,vec2(.030,-.158),vec2(.060,-.158),.015));
        return max(max(a,b),stroke(p,vec2(.060,-.158),vec2(.093,-.128),.015));
      }
      void main(){
        vec3 N=normalize(vNormal),V=normalize(uEye-vPosition);
        vec3 L=normalize(vec3(-2.7,4.5,3.3)-vPosition);
        vec3 H=normalize(L+V);
        float nl=max(dot(N,L),0.0),nv=max(dot(N,V),0.0);
        // Screen-space transmission: the live studio and contact shadow are
        // sampled through a bent ray. Nothing here is a stored image asset.
        vec2 uv=gl_FragCoord.xy/uResolution;
        // Approximate a refracted chord through the persistent dome. Eight
        // samples integrate only smooth blue light: no inner cap or organs;
        // they are live shader functions, not textures or a video sequence.
        vec3 T=refract(-V,N,1.0/1.34);
        vec3 radii=vec3(1.10,.91,.847);
        vec3 q=(vPosition-vec3(0.0,.56,0.0))/radii, d=T/radii;
        float a=dot(d,d), b=dot(q,d), c=dot(q,q)-1.0;
        float disc=sqrt(max(b*b-a*c,0.0));
        float entry=max(0.0,(-b-disc)/a);
        float exit=max(entry,(-b+disc)/a);
        float thickness=min(exit-entry,2.4);
        vec2 bend=vec2(N.x,N.y*.78)*(.029+.040*thickness);
        vec2 refractedUV=clamp(uv-bend,vec2(.003),vec2(.997));
        vec3 backdrop=texture2D(uBackdrop,refractedUV).rgb;
        // Smooth, unfocused transmitted light inside one clear gel body.
        // No anatomical shapes, stripes, rings or separate inner object.
        float pulse=1.0+.03*sin(uTime*.95);
        vec3 throughput=vec3(1.0),volume=vec3(0.0);
        float stepLength=thickness/8.0;
        for(int i=0;i<8;i++){
          vec3 p=vPosition+T*(entry+stepLength*(float(i)+.5));
          // Keep the interior anchored to the same deforming body.
          p.y/=1.0+uModes.y*.52;
          float height=p.y/1.49;
          p.x=(p.x-uModes.x*.34*height*height)*sqrt(max(.76,1.0+uModes.y*.52));
          p.z=(p.z-uModes.x*.09*height)*sqrt(max(.76,1.0+uModes.y*.52));
          float inside=smoothstep(.028,.085,p.y);
          vec3 corePoint=(p-vec3(-.045,.46,-.08))*vec3(1.6,2.35,2.0);
          float core=exp(-dot(corePoint,corePoint)*1.7);
          vec3 lightPoint=(p-vec3(-.22,.83,-.09))*vec3(1.05,1.22,1.50);
          float softLight=exp(-dot(lightPoint,lightPoint)*1.25);
          float density=(.024+.025*core)*inside;
          vec3 emission=vec3(.040,.29,.85)*(.12+.20*core+.32*softLight);
          volume+=throughput*emission*stepLength*inside*pulse;
          throughput*=exp(-vec3(.52,.16,.035)*density*stepLength);
        }
        vec3 color=backdrop*throughput+volume;
        color+=vec3(.008,.055,.15)*nl*(.10+.09*thickness);
        vec3 R=reflect(-V,N);
        vec3 environment=mix(vec3(.08,.20,.44),vec3(.45,.80,1.0),smoothstep(-.20,.80,R.y));
        float fresnel=.020+.980*pow(1.0-nv,5.0);
        color=mix(color,environment,fresnel*.16);
        // Broad rectangular softboxes, plus a small crisp glint: wet jelly,
        // not a matte blue toy. Reflections move with the deforming normals.
        vec3 boxDirection=normalize(vec3(-.58,.80,.62));
        vec3 boxHorizontal=normalize(cross(boxDirection,vec3(0.0,1.0,0.0)));
        vec3 boxVertical=cross(boxHorizontal,boxDirection);
        float softbox=(1.0-smoothstep(.15,.24,abs(dot(R,boxHorizontal))))
                     *(1.0-smoothstep(.075,.14,abs(dot(R,boxVertical))))
                     *smoothstep(.80,.93,dot(R,boxDirection));
        float rimbox=pow(max(dot(R,normalize(vec3(.90,.38,-.24))),0.0),65.0);
        float spec=pow(max(dot(N,H),0.0),145.0);
        color+=vec3(.55,.84,1.0)*(softbox*.10+spec*.08);
        color+=vec3(.16,.61,1.0)*rimbox*.23;
        color+=vec3(.12,.52,1.10)*pow(1.0-nv,4.0)*.62;
        // Convert lit gel radiance for display before applying the crisp
        // graphic face. This avoids murky teal while keeping the ink dark.
        color=pow(vec3(1.0)-exp(-max(color,vec3(0.0))*1.25),vec3(.454545));
        float front=smoothstep(.59,.76,vBase.z);
        vec2 faceUV=(vBase.xy*.92+vec2(1.0))*.5;
        vec4 faceInk=texture2D(uFaceTexture,faceUV);
        color=mix(color,faceInk.rgb,faceInk.a*front);
        float alpha=.84+.13*pow(nv,.55);
        gl_FragColor=vec4(color,alpha);
      }
    `;
    function compile(type,source){const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(s));return s;}
    function program(vertex,fragment){const p=gl.createProgram();gl.attachShader(p,compile(gl.VERTEX_SHADER,vertex));gl.attachShader(p,compile(gl.FRAGMENT_SHADER,fragment));gl.linkProgram(p);if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(p));return p;}
    const body=program(vs,fs);
    const faceTexture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,faceTexture);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,512,512,0,gl.RGBA,gl.UNSIGNED_BYTE,null);
    const rings=42,sectors=72,params=[],indices=[];
    for(let y=0;y<=rings;y++)for(let x=0;x<=sectors;x++)params.push(Math.PI*(.00005+(1-.0001)*y/rings),Math.PI*2*x/sectors);
    for(let y=0;y<rings;y++)for(let x=0;x<sectors;x++){const a=y*(sectors+1)+x,b=a+sectors+1;indices.push(a,b,a+1,a+1,b,b+1);}
    const vertexBuffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,vertexBuffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(params),gl.STATIC_DRAW);
    const indexBuffer=gl.createBuffer();gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,indexBuffer);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,new Uint16Array(indices),gl.STATIC_DRAW);
    const at=gl.getAttribLocation(body,'aParam');
    const uniforms={};for(const name of ['uMatrix','uModes','uContact','uEye','uBlink','uGaze','uBackdrop','uResolution','uFaceTexture','uTime','uShell','uGrab','uGrabPoint','uLife'])uniforms[name]=gl.getUniformLocation(body,name);
    const fullscreenVS=`attribute vec2 aPosition;varying vec2 vUV;void main(){vUV=aPosition*.5+.5;gl_Position=vec4(aPosition,0.0,1.0);}`;
    const studio=program(fullscreenVS,`precision highp float;void main(){gl_FragColor=vec4(0.0,0.0,0.0,1.0);}`);
    const screen=program(fullscreenVS,`precision highp float;varying vec2 vUV;uniform sampler2D uTexture;void main(){gl_FragColor=texture2D(uTexture,vUV);}`);
    const quad=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);
    const studioAt=gl.getAttribLocation(studio,'aPosition'),screenAt=gl.getAttribLocation(screen,'aPosition');
    const screenTexture=gl.getUniformLocation(screen,'uTexture');
    // Quarter-resolution separable bloom spreads bright blue light into
    // the surrounding black. Unlike enlarged silhouette shells it cannot
    // produce concentric halo outlines or turn the whole body into a lamp.
    const blur=program(fullscreenVS,`precision highp float;varying vec2 vUV;uniform sampler2D uTexture;uniform vec2 uStep;uniform float uExtract;
      vec3 sampleLight(vec2 uv){vec3 c=texture2D(uTexture,uv).rgb;float brightness=max(c.r,max(c.g,c.b));return c*mix(1.0,smoothstep(.30,.78,brightness),uExtract);}
      void main(){vec3 c=sampleLight(vUV)*.227027;c+=(sampleLight(vUV+uStep*1.384615)+sampleLight(vUV-uStep*1.384615))*.316216;c+=(sampleLight(vUV+uStep*3.230769)+sampleLight(vUV-uStep*3.230769))*.070270;gl_FragColor=vec4(c,1.0);}`);
    const composite=program(fullscreenVS,`precision highp float;varying vec2 vUV;uniform sampler2D uScene;uniform sampler2D uBloom;void main(){vec3 c=texture2D(uScene,vUV).rgb;vec3 glow=texture2D(uBloom,vUV).rgb;gl_FragColor=vec4(min(c+glow*.50,vec3(1.0)),1.0);}`);
    const blurAt=gl.getAttribLocation(blur,'aPosition'),compositeAt=gl.getAttribLocation(composite,'aPosition');
    const blurTexture=gl.getUniformLocation(blur,'uTexture'),blurStep=gl.getUniformLocation(blur,'uStep'),blurExtract=gl.getUniformLocation(blur,'uExtract');
    const compositeScene=gl.getUniformLocation(composite,'uScene'),compositeBloom=gl.getUniformLocation(composite,'uBloom');
    function newTarget(){
      const texture=gl.createTexture(),framebuffer=gl.createFramebuffer();
      gl.bindTexture(gl.TEXTURE_2D,texture);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
      return {texture,framebuffer};
    }
    const sceneTarget=newTarget(),bloomA=newTarget(),bloomB=newTarget(),sceneDepth=gl.createRenderbuffer();
    function resizeTarget(target,w,h){
      gl.bindTexture(gl.TEXTURE_2D,target.texture);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,w,h,0,gl.RGBA,gl.UNSIGNED_BYTE,null);
      gl.bindFramebuffer(gl.FRAMEBUFFER,target.framebuffer);
      // On viewport changes the old depth attachment temporarily has a
      // different size. Detach it until its matching allocation is ready.
      if(target===sceneTarget)gl.framebufferRenderbuffer(gl.FRAMEBUFFER,gl.DEPTH_ATTACHMENT,gl.RENDERBUFFER,null);
      gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,target.texture,0);
      if(gl.checkFramebufferStatus(gl.FRAMEBUFFER)!==gl.FRAMEBUFFER_COMPLETE)throw new Error('Bloom framebuffer unavailable');
    }
    const backdropTexture=gl.createTexture(),backdropTarget=gl.createFramebuffer();
    let targetWidth=0,targetHeight=0;
    gl.bindTexture(gl.TEXTURE_2D,backdropTexture);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
    const shadow=program(`attribute vec3 aPosition;uniform mat4 uMatrix;varying vec2 vXZ;void main(){vXZ=aPosition.xz;gl_Position=uMatrix*vec4(aPosition,1.0);}`,`precision highp float;varying vec2 vXZ;void main(){float d=dot(vXZ*vec2(.9,1.45),vXZ*vec2(.9,1.45));float a=.18*exp(-d*1.4)+.22*exp(-d*9.0);gl_FragColor=vec4(0.0,0.0,0.0,a);}`);
    const floor=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,floor);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-4,0,-4,4,0,-4,-4,0,4,-4,0,4,4,0,-4,4,0,4]),gl.STATIC_DRAW);
    const floorAt=gl.getAttribLocation(shadow,'aPosition');
    const floorMatrix=gl.getUniformLocation(shadow,'uMatrix');
    const camera=viewMatrix();
    draw=()=>{
      gl.activeTexture(gl.TEXTURE0);
      if(targetWidth!==canvas.width||targetHeight!==canvas.height){
        targetWidth=canvas.width;targetHeight=canvas.height;
        gl.bindTexture(gl.TEXTURE_2D,backdropTexture);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,targetWidth,targetHeight,0,gl.RGBA,gl.UNSIGNED_BYTE,null);
        gl.bindFramebuffer(gl.FRAMEBUFFER,backdropTarget);gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,backdropTexture,0);
        if(gl.checkFramebufferStatus(gl.FRAMEBUFFER)!==gl.FRAMEBUFFER_COMPLETE)throw new Error('Transmission framebuffer unavailable');
        resizeTarget(sceneTarget,targetWidth,targetHeight);
        gl.bindRenderbuffer(gl.RENDERBUFFER,sceneDepth);gl.renderbufferStorage(gl.RENDERBUFFER,gl.DEPTH_COMPONENT16,targetWidth,targetHeight);gl.framebufferRenderbuffer(gl.FRAMEBUFFER,gl.DEPTH_ATTACHMENT,gl.RENDERBUFFER,sceneDepth);
        resizeTarget(bloomA,Math.max(1,Math.ceil(targetWidth/4)),Math.max(1,Math.ceil(targetHeight/4)));
        resizeTarget(bloomB,Math.max(1,Math.ceil(targetWidth/4)),Math.max(1,Math.ceil(targetHeight/4)));
      }
      gl.bindFramebuffer(gl.FRAMEBUFFER,backdropTarget);
      gl.viewport(0,0,canvas.width,canvas.height);gl.disable(gl.BLEND);gl.disable(gl.DEPTH_TEST);
      gl.useProgram(studio);gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(studioAt);gl.vertexAttribPointer(studioAt,2,gl.FLOAT,false,0,0);gl.drawArrays(gl.TRIANGLES,0,3);
      const matrix=matrixMultiply(projection(canvas.width/canvas.height),camera);
      gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);gl.disable(gl.DEPTH_TEST);
      gl.useProgram(shadow);gl.uniformMatrix4fv(floorMatrix,false,matrix);gl.bindBuffer(gl.ARRAY_BUFFER,floor);gl.enableVertexAttribArray(floorAt);gl.vertexAttribPointer(floorAt,3,gl.FLOAT,false,0,0);gl.drawArrays(gl.TRIANGLES,0,6);
      gl.bindFramebuffer(gl.FRAMEBUFFER,sceneTarget.framebuffer);gl.clearColor(0,0,0,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
      gl.disable(gl.BLEND);gl.useProgram(screen);gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(screenAt);gl.vertexAttribPointer(screenAt,2,gl.FLOAT,false,0,0);
      gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,backdropTexture);gl.uniform1i(screenTexture,0);gl.drawArrays(gl.TRIANGLES,0,3);
      gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.enable(gl.CULL_FACE);gl.frontFace(gl.CW);gl.cullFace(gl.BACK);
      gl.useProgram(body);gl.bindBuffer(gl.ARRAY_BUFFER,vertexBuffer);gl.enableVertexAttribArray(at);gl.vertexAttribPointer(at,2,gl.FLOAT,false,0,0);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,indexBuffer);
      gl.uniformMatrix4fv(uniforms.uMatrix,false,matrix);gl.uniform4fv(uniforms.uModes,composePose());gl.uniform2f(uniforms.uContact,contact.x,contact.y);gl.uniform3fv(uniforms.uEye,eye);gl.uniform1f(uniforms.uBlink,blink());gl.uniform1f(uniforms.uGaze,gaze);
      gl.uniform1i(uniforms.uBackdrop,0);gl.uniform2f(uniforms.uResolution,canvas.width,canvas.height);paintFace();gl.activeTexture(gl.TEXTURE2);gl.bindTexture(gl.TEXTURE_2D,faceTexture);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,true);gl.texSubImage2D(gl.TEXTURE_2D,0,0,0,gl.RGBA,gl.UNSIGNED_BYTE,faceCanvas);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,false);gl.uniform1i(uniforms.uFaceTexture,2);gl.activeTexture(gl.TEXTURE0);
      gl.uniform3fv(uniforms.uGrab,grab.pull.map(m=>m.x));gl.uniform2fv(uniforms.uGrabPoint,grab.point);gl.uniform3fv(uniforms.uLife,lifePose());gl.uniform1f(uniforms.uTime,reduced.matches?0:time);gl.uniform1f(uniforms.uShell,1);
      gl.drawElements(gl.TRIANGLES,indices.length,gl.UNSIGNED_SHORT,0);
      gl.disable(gl.CULL_FACE);gl.disable(gl.DEPTH_TEST);gl.disable(gl.BLEND);
      const bloomWidth=Math.max(1,Math.ceil(canvas.width/4)),bloomHeight=Math.max(1,Math.ceil(canvas.height/4));
      gl.bindFramebuffer(gl.FRAMEBUFFER,bloomA.framebuffer);gl.viewport(0,0,bloomWidth,bloomHeight);
      gl.useProgram(blur);gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(blurAt);gl.vertexAttribPointer(blurAt,2,gl.FLOAT,false,0,0);
      gl.bindTexture(gl.TEXTURE_2D,sceneTarget.texture);gl.uniform1i(blurTexture,0);gl.uniform2f(blurStep,1.4/bloomWidth,0);gl.uniform1f(blurExtract,1);gl.drawArrays(gl.TRIANGLES,0,3);
      gl.bindFramebuffer(gl.FRAMEBUFFER,bloomB.framebuffer);gl.bindTexture(gl.TEXTURE_2D,bloomA.texture);gl.uniform2f(blurStep,0,1.4/bloomHeight);gl.uniform1f(blurExtract,0);gl.drawArrays(gl.TRIANGLES,0,3);
      gl.bindFramebuffer(gl.FRAMEBUFFER,null);gl.viewport(0,0,canvas.width,canvas.height);
      gl.useProgram(composite);gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(compositeAt);gl.vertexAttribPointer(compositeAt,2,gl.FLOAT,false,0,0);
      gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,sceneTarget.texture);gl.uniform1i(compositeScene,0);gl.activeTexture(gl.TEXTURE1);gl.bindTexture(gl.TEXTURE_2D,bloomB.texture);gl.uniform1i(compositeBloom,1);gl.drawArrays(gl.TRIANGLES,0,3);gl.activeTexture(gl.TEXTURE0);
    };
    rendering='procedural-webgl';
  }
  function createFallback(){
    const replacement=document.createElement('canvas');replacement.setAttribute('role','img');replacement.setAttribute('aria-label',canvas.getAttribute('aria-label'));canvas.replaceWith(replacement);
    const ctx=replacement.getContext('2d');
    draw=()=>{
      const w=replacement.width,h=replacement.height;
      ctx.fillStyle='#000';ctx.fillRect(0,0,w,h);
      const [lean,squash,ripple]=composePose(),sx=1/Math.sqrt(1+squash*.52),sy=1+squash*.52;
      ctx.save();ctx.translate(w*.5,h*.74);ctx.scale(w/4.5,h/3.35);
      const shadow=ctx.createRadialGradient(0,0,.1,0,0,1.35);shadow.addColorStop(0,'rgba(0,0,0,.6)');shadow.addColorStop(1,'rgba(0,0,0,0)');ctx.fillStyle=shadow;ctx.save();ctx.scale(1,.21);ctx.beginPath();ctx.arc(0,0,1.4,0,Math.PI*2);ctx.fill();ctx.restore();
      const pull=grab.pull.map(m=>m.x),life=lifePose();ctx.translate(pull[0]*.35,-pull[1]*.35-life[0]);ctx.rotate(-life[1]);
      ctx.transform(sx+Math.abs(pull[0])*.12,0,lean*.25-pull[0]*.18,sy+Math.abs(pull[1])*.12,0,0);ctx.beginPath();
      ctx.moveTo(-.95,-.025);ctx.bezierCurveTo(-1.20-ripple*.08,-.18,-1.05,-1.20,-.18,-1.48);ctx.bezierCurveTo(.80,-1.70,1.32,-.65,1.03,-.15);ctx.bezierCurveTo(.99,.15,-.70,.12,-.95,-.025);ctx.closePath();
      const gel=ctx.createRadialGradient(-.25,-.94,.10,.10,-.61,1.15);gel.addColorStop(0,'rgba(109,190,255,.64)');gel.addColorStop(.45,'rgba(48,136,238,.53)');gel.addColorStop(.84,'rgba(61,156,244,.42)');gel.addColorStop(1,'rgba(146,213,255,.66)');ctx.shadowColor='rgba(77,171,255,.50)';ctx.shadowBlur=w*.023;ctx.fillStyle=gel;ctx.fill();ctx.strokeStyle='rgba(146,213,255,.64)';ctx.lineWidth=.015;ctx.stroke();ctx.shadowBlur=0;
      ctx.save();ctx.clip();const shine=ctx.createRadialGradient(-.44,-1.11,0,-.44,-1.11,.37);shine.addColorStop(0,'rgba(248,255,255,.94)');shine.addColorStop(1,'rgba(231,252,255,0)');ctx.fillStyle=shine;ctx.fillRect(-1.4,-1.8,2.8,1.9);ctx.restore();
      paintFace();ctx.drawImage(faceCanvas,-1,-1.54,2,1.66);
      ctx.restore();
    };
    root._fallbackCanvas=replacement;rendering='procedural-canvas-fallback';
  }
  try{createGL();}catch(error){shaderError=String(error.message);createFallback();}
  function size(){
    const active=root._fallbackCanvas||canvas,rect=stage.getBoundingClientRect(),ratio=Math.min(devicePixelRatio||1,1.5);
    active.width=Math.max(1,Math.round(rect.width*ratio));active.height=Math.max(1,Math.round(rect.height*ratio));draw();
  }
  const observer=new ResizeObserver(size);observer.observe(stage);size();
  root.querySelector('[data-poke]').addEventListener('click',()=>impulse('poke'));
  root.querySelector('[data-shake]').addEventListener('click',()=>impulse('shake'));
  expressionSelect.addEventListener('change',()=>setEmotion(expressionSelect.value,paused));
  root.querySelector('[data-perform]').addEventListener('click',()=>{if(paused){paused=false;pauseButton.textContent='Pause';pauseButton.setAttribute('aria-pressed','false');}perform();});
  performanceSelect.addEventListener('change',()=>{chosenPerformance=performanceSelect.value;rememberChoice();if(!paused)perform();});
  pauseButton.addEventListener('click',()=>{if(grab.active)releaseGrab(null,true);paused=!paused;pauseButton.textContent=paused?'Resume':'Pause';pauseButton.setAttribute('aria-pressed',String(paused));updateStatus();});

  const dot3=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0);
  const unit3=a=>{const n=Math.hypot(...a);return a.map(v=>v/n);};
  const cross3=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
  const cameraForward=unit3(target.map((v,i)=>v-eye[i]));
  const cameraRight=unit3(cross3(cameraForward,[0,1,0])),cameraUp=cross3(cameraRight,cameraForward);
  function pointerRay(event){
    const rect=stage.getBoundingClientRect();
    const nx=(event.clientX-rect.left)/rect.width*2-1,ny=1-(event.clientY-rect.top)/rect.height*2;
    return unit3(cameraForward.map((v,i)=>v+cameraRight[i]*nx*(rect.width/rect.height)*Math.tan(.42)+cameraUp[i]*ny*Math.tan(.42)));
  }
  function hitSurface(event){
    if(root._fallbackCanvas){
      const rect=stage.getBoundingClientRect();
      const x=((event.clientX-rect.left)/rect.width-.5)*4.5,y=(.74-(event.clientY-rect.top)/rect.height)*3.35;
      const q=x*x/(1.1*1.1)+(y-.56)*(y-.56)/(.91*.91);
      if(q>1||y<.06)return null;
      return [x,y,.847*Math.sqrt(Math.max(0,1-q))];
    }
    const ray=pointerRay(event),r=[1.1,.91,.847],center=[0,.56,0];
    const o=eye.map((v,i)=>(v-center[i])/r[i]),d=ray.map((v,i)=>v/r[i]);
    const a=dot3(d,d),b=dot3(o,d),c=dot3(o,o)-1,disc=b*b-a*c;
    if(disc<0)return null;
    const distance=(-b-Math.sqrt(disc))/a;if(distance<=0)return null;
    const point=eye.map((v,i)=>v+distance*ray[i]);
    return point[1]>.07&&point[2]>.03?point:null;
  }
  function startGrab(event){
    if(grab.active||event.button>0)return;
    const point=hitSurface(event);if(!point)return;
    if(paused){paused=false;pauseButton.textContent='Pause';pauseButton.setAttribute('aria-pressed','false');}
    window.focus?.();grab.focusWasAcquired=Boolean(document.hasFocus?.());
    grab.active=true;grab.id=event.pointerId;grab.anchor=point;grab.point=[point[0]/1.1,(point[1]-.56)/.91];
    grab.start=[event.clientX,event.clientY,performance.now()];grab.dragged=false;grab.pointerType=event.pointerType;
    grab.target=[0,0,0];stage.setPointerCapture(event.pointerId);updateStatus('holding');event.preventDefault();
  }
  function moveGrab(event){
    if(!grab.active||event.pointerId!==grab.id)return;
    if(event.pointerType==='mouse'&&event.buttons===0){releaseGrab(event,true);return;}
    if(Math.hypot(event.clientX-grab.start[0],event.clientY-grab.start[1])>5)grab.dragged=true;
    let delta;
    if(root._fallbackCanvas){
      const rect=stage.getBoundingClientRect();delta=[(event.clientX-grab.start[0])/rect.width*4.5,-(event.clientY-grab.start[1])/rect.height*3.35,0];
    }else{
      const ray=pointerRay(event),distance=dot3(grab.anchor.map((v,i)=>v-eye[i]),cameraForward)/dot3(ray,cameraForward);
      delta=eye.map((v,i)=>v+distance*ray[i]-grab.anchor[i]);
    }
    const length=Math.hypot(...delta),scale=length>.64?.64/length:1;
    grab.target=delta.map(v=>v*scale*(reduced.matches?.35:1));
    updateStatus(grab.dragged?'stretching':'holding');event.preventDefault();
  }
  function releaseGrab(event,cancel=false){
    if(!grab.active||(event&&event.pointerId!==grab.id))return;
    const id=grab.id,wasTap=!cancel&&!grab.dragged&&performance.now()-grab.start[2]<350;
    const [x,y]=grab.point;grab.active=false;grab.id=null;grab.target=[0,0,0];
    if(stage.hasPointerCapture(id))stage.releasePointerCapture(id);
    nextPerformance=Math.max(nextPerformance,time+3);
    if(wasTap)impulse('poke',x,y);
    else {reactionUntil=time+2.5;updateStatus(cancel?'released':'springing back');}
  }
  stage.addEventListener('pointerdown',startGrab);
  stage.addEventListener('pointermove',moveGrab);
  stage.addEventListener('pointerup',event=>releaseGrab(event));
  stage.addEventListener('pointercancel',event=>releaseGrab(event,true));
  stage.addEventListener('lostpointercapture',event=>releaseGrab(event,true));
  const onBlur=()=>releaseGrab(null,true);
  const onPointerFinish=event=>releaseGrab(event,event.type==='pointercancel');
  window.addEventListener('blur',onBlur);
  document.addEventListener('pointerup',onPointerFinish,true);
  document.addEventListener('pointercancel',onPointerFinish,true);
  const onVisibility=()=>{hidden=document.hidden;lastTime=0;if(hidden)releaseGrab(null,true);};document.addEventListener('visibilitychange',onVisibility);
  canvas.addEventListener('webglcontextlost',event=>{event.preventDefault();paused=true;status.textContent='Paused';});
  canvas.addEventListener('webglcontextrestored',()=>{try{createGL();paused=false;lastTime=0;size();}catch(error){shaderError=String(error.message);}});
  function frame(stamp){
    if(!root.isConnected){observer.disconnect();document.removeEventListener('visibilitychange',onVisibility);window.removeEventListener('blur',onBlur);document.removeEventListener('pointerup',onPointerFinish,true);document.removeEventListener('pointercancel',onPointerFinish,true);return;}
    // BOOP_MOTION_V1_BEGIN frame-step
    const dt=lastTime?clamp((stamp-lastTime)/1000,0,.045):0;lastTime=stamp;
    if(!hidden&&!paused){advance(dt);draw();frames++;}
    // BOOP_MOTION_V1_END frame-step
    requestAnimationFrame(frame);
  }
  root._slimePreview={
    poke:(x=0,y=.2)=>impulse('poke',x,y),shake:()=>impulse('shake'),setEmotion:name=>setEmotion(name,paused),
    perform:index=>perform(index),
    getState:()=>({rendering,shaderError,material:rendering==='procedural-webgl'?'simple-blue-translucent-gel':'layered-luminous-gel',
      postprocessBloom:rendering==='procedural-webgl',emotion:profiles[emotion].mood,expression:emotion,
      emotions:[...moodIds],expressions:[...emotions],referenceMapping,draftGraphImplemented:false,
      weights:Array.from(weights),time,frames,paused,performanceCount,performance:actor?{label:actor.label,type:actor.type,index:actor.index,age:time-actor.start}:null,
      actorChannels:Object.fromEntries(Object.entries(actorChannels).map(([k,m])=>[k,{x:m.x,v:m.v}])),
      grab:{active:grab.active,pointerType:grab.pointerType,dragged:grab.dragged,point:[...grab.point],target:[...grab.target],pull:grab.pull.map(m=>({x:m.x,v:m.v}))},
      modes:Object.fromEntries(Object.entries(modes).map(([k,m])=>[k,{x:m.x,v:m.v}]))})
  };
  window.slimePreview = root._slimePreview;
  requestAnimationFrame(frame);
})();
