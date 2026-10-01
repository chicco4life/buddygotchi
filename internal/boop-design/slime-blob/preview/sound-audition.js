// Manual only; connecting sound to motion cue IDs is a later reviewed step.
(() => {
  const labels={squish:'Gel squish',bounce:'Soft landing',wobble:'Elastic wobble',poke:'Tiny poke',keyboard:'Crisp key',tear:'Tear plip',knock_ding:'Knock → ding',complete:'Success swell',failed:'Failure cue'};
  const menu=document.querySelector('[data-sound-buttons]'),status=document.querySelector('[data-sound-status]');
  let count=0;
  for(const [name,label] of Object.entries(labels)){
    const button=document.createElement('button');button.className='btn';button.type='button';button.textContent=label;
    button.addEventListener('click',async()=>{
      try{const result=await SlimeSFX.play(name,{variant:count++%3,seed:1729+count});status.textContent=label+' · sketch '+(result.variant+1)+' · '+result.duration.toFixed(2)+'s';}
      catch(error){status.textContent=error.message;}
    });menu.append(button);
  }
  const mute=document.createElement('button');mute.className='btn';mute.type='button';mute.textContent='Stop sound';mute.addEventListener('click',()=>{SlimeSFX.stop();status.textContent='Sound stopped.';});menu.append(mute);
  document.addEventListener('visibilitychange',()=>{if(document.hidden)SlimeSFX.stop();});
})();
