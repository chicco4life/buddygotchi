// Boop base-design authoring source. Outputs a self-contained SVG; not device runtime code.
// Public design inputs remain mood and state. No external dependencies.
const palette = {ink:"#F8F7EF",black:"#000000",cheek:"#F1787D",blue:"#7BB4EF",amber:"#F4BC50",dim:"#68685E",prop:"#A9A99B"};
const label = s => s.replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase());
const esc = s => String(s).replaceAll("&","&amp;").replaceAll('"',"&quot;").replaceAll("<","&lt;");
const r=(x,y,w,h,c=palette.ink)=>'<rect x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'" fill="'+c+'"/>';
const p=(d,c=palette.ink)=>'<path d="'+d+'" fill="'+c+'"/>';
const block=(x,y,w,h,c=palette.ink)=>p('M'+(x+1)+' '+y+'h'+(w-2)+'v1h1v'+(h-2)+'h-1v1h-'+(w-2)+'v-1h-1V'+(y+1)+'h1Z',c);
const move=(values,dur,keys,repeat="indefinite")=>'<animateTransform attributeName="transform" type="translate" values="'+values+'" keyTimes="'+keys+'" dur="'+dur+'s" repeatCount="'+repeat+'" calcMode="discrete" fill="freeze"/>';
const show=(values,dur,keys,repeat="indefinite")=>'<animate attributeName="opacity" values="'+values+'" keyTimes="'+keys+'" dur="'+dur+'s" repeatCount="'+repeat+'" calcMode="discrete" fill="freeze"/>';
function fourEye(x,y,w=40,h=40) {
 const a=(w-4)/2,b=(h-4)/2;
 return block(x,y,a,b)+block(x+a+4,y,a,b)+block(x,y+b+4,a,b)+block(x+a+4,y+b+4,a,b);
}
function lid(x,y,w,kind,right=false,soften=false) {
 if(kind==="grumpy"||kind==="determined"){
  const step=kind==="grumpy"?(soften?3:4):(soften?1:2);
  return Array.from({length:5},(_,i)=>r(x+i*w/5,y,w/5,2+(right?4-i:i)*step,palette.black)).join("");
 }
 if(kind==="sad") return Array.from({length:5},(_,i)=>r(x+i*w/5,y,w/5,2+(right?i:4-i)*(soften?3:4),palette.black)).join("");
 return "";
}
function eyeShapes(mood,state) {
 let left=[68,70,40,40],right=[212,70,40,40];
 if(mood==="excited"){left=[66,62,44,48];right=[210,62,44,48];}
 if(mood==="proud"){left=[68,70,40,40];right=[212,74,40,36];}
 if(mood==="curious"){left=[70,74,36,36];right=[210,66,44,44];}
 if(mood==="determined"){left=[68,76,40,32];right=[212,76,40,32];}
 if(mood==="grumpy"){left=[68,72,40,40];right=[212,72,40,40];}
 if(mood==="sad"){left=[68,68,40,44];right=[212,68,40,44];}
 if(state==="needs_you") {left[1]-=4;right[1]-=2;left[3]+=4;right[3]+=2;}
 if(state==="listening") {left[1]-=2;right[1]-=2;left[3]+=2;right[3]+=2;}
 if(state==="task_complete"&&["determined","grumpy","sad"].includes(mood)){left[1]-=2;right[1]-=2;left[3]+=4;right[3]+=4;}
 let art=fourEye(...left)+fourEye(...right);
 if(["determined","grumpy","sad"].includes(mood)) art+=lid(left[0],left[1],left[2],mood,false,["needs_you","task_complete","listening"].includes(state))+lid(right[0],right[1],right[2],mood,true,["needs_you","task_complete","listening"].includes(state));
 if(mood==="proud") {
   art+=r(left[0],left[1],left[2],state==="listening"?8:12,palette.black)+r(right[0],right[1],right[2],state==="needs_you"?2:5,palette.black);
 }
 if(mood==="happy") {
   const smile=state==="task_complete"?8:4;
   art+=r(left[0]+4,left[1]+left[3]-smile,left[2]-8,smile,palette.black)+r(right[0]+4,right[1]+right[3]-smile,right[2]-8,smile,palette.black);
 }
 if(state==="working"&&["happy","excited","curious"].includes(mood)) {
   art+=r(left[0],left[1],left[2],mood==="excited"?8:4,palette.black)+r(right[0],right[1],right[2],4,palette.black);
 }
 return art;
}
function mouth(mood,state) {
 const c=palette.ink;
 if(state==="task_complete"&&mood==="determined")return p("M149 130h4v3h14v-3h4v7h-22Z",c);
 if(state==="task_complete"&&mood==="grumpy")return p("M146 134h20v-3h7v4h-4v3h-23Z",c);
 if(state==="task_complete"&&mood==="curious")return p("M149 131h4v3h14v-3h4v7h-22Z",c);
 if(state==="task_complete"&&mood==="proud")return p("M142 132h24v-5h11v5h-7v5h-28Z",c);
 if(state==="needs_you"&&mood==="curious")return p("M153 128h14v12h-14Zm4 4v4h6v-4Z",c);
 if(state==="needs_you"&&mood==="grumpy")return block(150,134,20,5,c);
 if(state==="asleep"||state==="no_app") return block(149,132,22,4);
 if(mood==="happy")return p("M146 128h4v4h20v-4h4v8h-28Z",c);
 if(mood==="excited") {
   if(state==="listening"||state==="idle")return p("M145 127h4v4h22v-4h4v8h-30Z",c);
   return p("M145 126h5v4h20v-4h5v12h-5v4h-20v-4h-5Z",c);
 }
 if(mood==="proud")return p("M145 132h19v-4h10v4h-6v4h-23Z",c);
 if(mood==="curious")return p("M151 130h14v4h-10v4h-8v-4h4Z",c);
 if(mood==="determined")return block(149,132,22,5,c);
 if(mood==="grumpy")return p("M145 134h5v-4h20v4h5v4h-8v-4h-14v4h-8Z",c);
 if(mood==="sad"){
   if(state==="task_complete")return p("M149 130h4v4h14v-4h4v8h-22Z",c);
   if(state==="listening"||state==="idle")return p("M149 134h5v-4h12v4h5v4h-8v-4h-6v4h-8Z",c);
   return p("M147 132h6v-4h14v4h6v10h-6v-4h-14v4h-6Z",c);
 }
 return "";
}
function cheeks(mood,state) {
 const y=mood==="excited"?122:mood==="sad"?126:124;
 return block(54,y,12,8,palette.cheek)+block(70,y,12,8,palette.cheek)+block(238,y,12,8,palette.cheek)+block(254,y,12,8,palette.cheek);
}
function tears(state) {
 const corners=r(74,110,8,3,palette.blue)+r(236,110,8,3,palette.blue);
 if(state==="idle"||state==="listening")return corners;
 const drop=p("M1 0h4v4h2v6H0V4h1Z",palette.blue);
 const travel=move("0 0;0 0;0 4;0 10;0 18;0 24;0 0;0 0",6,"0;0.3;0.35;0.4;0.45;0.5;0.55;1");
 const fade=show("0;1;1;0;0",6,"0;0.3;0.48;0.53;1");
 return corners+'<g transform="translate(74 112)"><g>'+travel+fade+drop+'</g></g>'+
 '<g transform="translate(237 112)"><g>'+move("0 0;0 0;0 4;0 12;0 20;0 0;0 0",6,"0;0.65;0.7;0.75;0.8;0.85;1")+show("0;1;1;0;0",6,"0;0.65;0.78;0.83;1")+drop+'</g></g>';
}
function eyes(mood,state) {
 if(state==="asleep") return block(68,94,40,5)+block(212,94,40,5);
 if(state==="no_app")return block(68,94,40,8)+block(212,94,40,8);
 const period=state==="listening"?8:state==="idle"?7.2:6.8;
 const open=eyeShapes(mood,state);
 const closed=block(68,99,40,5)+block(212,99,40,5);
 return '<g>'+show("1;0;1;1",period,"0;0.76;0.79;1")+open+'</g><g opacity="0">'+show("0;1;0;0",period,"0;0.76;0.79;1")+closed+'</g>';
}
function faceMotion(mood,state) {
 if(state==="asleep"||state==="no_app") return move("0 0;0 -1;0 -2;0 -1;0 0;0 0",8,"0;0.18;0.35;0.52;0.7;1");
 if(state==="idle")return move("0 0;0 0;0 -1;0 0;0 0",9,"0;0.3;0.35;0.5;1");
 if(state==="listening")return move("0 0;0 0;0 -2;0 -2;0 0;0 0",9,"0;0.2;0.25;0.4;0.45;1");
 if(state==="needs_you"){
  const shifts={happy:"0 0;0 -3;0 -1;0 0",excited:"0 0;0 -6;0 1;0 0",proud:"0 0;0 -3;0 -2;0 0",curious:"0 0;2 -2;2 0;0 0",determined:"0 0;0 -2;0 -1;0 0",grumpy:"0 0;-2 1;0 1;0 0",sad:"0 0;0 2;0 -1;0 0"};
  return move(shifts[mood],1.6,"0;0.2;0.55;1","1");
 }
 if(state==="task_complete"){
  const shifts={happy:"0 0;-3 -2;3 -2;0 0;0 0",excited:"0 0;0 -9;0 -3;0 1;0 0",proud:"0 0;0 6;0 8;0 3;0 0",curious:"0 0;2 0;2 -2;0 0;0 0",determined:"0 0;0 -2;0 2;0 1;0 0",grumpy:"0 0;0 2;-1 1;0 0;0 0",sad:"0 0;0 2;0 3;0 1;0 0"};
  return move(shifts[mood],mood==="proud"?2.8:2,"0;0.2;0.45;0.7;1","1");
 }
 const shifts={
 happy:["0 0;0 -1;0 0;0 1;0 0",2.4,"0;0.2;0.4;0.6;1"],
 excited:["0 0;0 2;0 0;0 2;0 0;0 -2;0 0;0 0",1.8,"0;0.12;0.24;0.36;0.48;0.6;0.72;1"],
 proud:["0 0;0 0;2 -2;2 -2;0 0",7,"0;0.5;0.6;0.8;1"],
 curious:["0 0;-2 1;-2 1;2 -1;0 0",5,"0;0.2;0.4;0.65;1"],
 determined:["0 0;0 1;0 0;0 1;0 0",2.6,"0;0.22;0.44;0.66;1"],
 grumpy:["0 0;0 0;0 -3;0 3;0 1;0 0;0 0",4.2,"0;0.5;0.58;0.64;0.7;0.8;1"],
 sad:["0 0;0 1;0 0;0 0;0 -2;0 1;0 0",5.2,"0;0.2;0.35;0.6;0.65;0.7;1"]};
 return move(shifts[mood][0],shifts[mood][1],shifts[mood][2]);
}
function keyboard(mood) {
 let art=block(91,168,138,28,palette.dim)+r(95,168,130,24,palette.black);
 const speed={happy:1.2,excited:.65,proud:1.6,curious:1.8,determined:1.1,grumpy:1.35,sad:1.7}[mood];
 for(let row=0;row<2;row++)for(let col=0;col<9;col++){
  const x=98+col*14,y=172+row*9;
  art+='<g>'+r(x,y,10,5,palette.dim);
  if((row*9+col)%3===0) art+='<g opacity="0">'+show(col%2?"0;1;0;0":"1;0;0;1",speed,"0;0.25;0.5;1")+r(x,y+1,10,4,palette.ink)+'</g>';
  art+='</g>';
 }
 art+=r(134,191,52,3,palette.prop);
 if(mood==="excited") art+='<g opacity="0">'+show("0;1;0;0",1.8,"0;0.3;0.45;1")+r(99,157,3,6,palette.prop)+r(215,157,3,6,palette.prop)+r(90,162,5,3,palette.prop)+r(223,162,5,3,palette.prop)+'</g>';
 if(mood==="grumpy") {
  art+='<g opacity="0">'+show("0;1;1;0;0",4.2,"0;0.63;0.76;0.83;1")+
  '<g>'+move("0 0;0 0;4 -10;8 -14;12 -8;14 0;0 0",4.2,"0;0.63;0.68;0.72;0.76;0.81;1")+block(206,170,9,6,palette.ink)+'</g>'+r(88,174,4,3,palette.dim)+r(231,176,4,3,palette.dim)+'</g>';
 }
 return '<g data-part="keyboard">'+art+'</g>';
}
function requestTile() {
 return '<g data-part="request-cue">'+move("0 4;0 2;0 0;0 0",1,"0;0.3;0.6;1","1")+
 p("M141 164h38v24h-11v6h-6v-6h-21Z",palette.amber)+r(144,167,32,18,palette.black)+
 r(153,169,12,3,palette.amber)+r(165,172,3,5,palette.amber)+r(159,175,6,3,palette.amber)+r(157,178,4,2,palette.amber)+r(157,182,4,3,palette.amber)+'</g>';
}
function resultTile(mood) {
 let s='<g data-part="result-cue">'+move("0 6;0 3;0 0;0 0",1.4,"0;0.25;0.5;1","1")+
 p("M146 162h20l8 8v24h-28Z",palette.ink)+p("M149 165h14v8h8v18h-22Z",palette.black)+r(153,177,13,3,palette.prop)+r(153,183,9,3,palette.prop)+
 p("M137 185h4v12h38v-12h4v16h-46Z",palette.dim)+'</g>';
 if(["happy","excited","proud"].includes(mood)) s+='<g opacity="0">'+show("0;1;1;0;0",2.4,"0;0.15;0.45;0.75;1","1")+r(128,167,3,3,palette.amber)+r(187,177,3,3,palette.amber)+r(180,157,3,3,palette.ink)+'</g>';
 return s;
}
function listeningCue() {
 return '<g data-part="listening-cue">'+p("M143 168h7v3h-4v12h4v3h-7Z",palette.blue)+p("M170 168h7v18h-7v-3h4v-12h-4Z",palette.blue)+r(157,174,6,6,palette.blue)+'</g>';
}
function disconnectedCue(){
 return '<g data-part="disconnected-cue">'+p("M145 174h9v3h-6v8h6v3h-9Z",palette.dim)+p("M166 174h9v14h-9v-3h6v-8h-6Z",palette.dim)+r(154,177,3,3,palette.dim)+r(163,182,3,3,palette.dim)+r(158,173,3,3,palette.dim)+r(158,188,3,3,palette.dim)+'</g>';
}
function scene(mood,state){
 const quiet=state==="asleep"||state==="no_app";
 const effective=quiet?"happy":mood;
 let face=eyes(effective,state)+cheeks(effective,state);
 let lips=mouth(effective,state);
 if(mood==="sad"&&!quiet&&state!=="idle"&&state!=="listening") lips='<g>'+move("0 0;1 0;0 0;-1 0;0 0;0 0",3.8,"0;0.2;0.28;0.36;0.44;1")+lips+'</g>';
 face+='<g data-part="mouth">'+lips+'</g>';
 if(mood==="sad"&&!quiet)face+='<g data-part="tears">'+tears(state)+'</g>';
 let s='<g data-part="face">'+faceMotion(effective,state)+face+'</g>';
 if(state==="working")s+=keyboard(mood);
 if(state==="needs_you")s+=requestTile();
 if(state==="task_complete")s+=resultTile(mood);
 if(state==="listening")s+=listeningCue();
 if(state==="no_app")s+=disconnectedCue();
 if(state==="asleep")s+='<g fill="'+palette.dim+'">'+p("M270 64h14v3h-4v3h-4v3h8v3h-14v-3h4v-3h4v-3h-8Z",palette.dim)+'</g>';
 return s;
}
function renderSVG(mood,state) {
 const id="boop-"+mood+"-"+state;
 const desc=state==="asleep"?"Shared peaceful sleep, independent of mood. Closed pixel eyes and a slow two-pixel breath.":
 state==="no_app"?"Shared disconnected rest, independent of mood. Low eyes and a persistent broken-link marker.":
 label(mood)+" Boop in "+label(state)+". Four-block warm-white eyes, coral cheeks, pixel-stepped motion and a consistent state cue. Silent design review.";
 const art=scene(mood,state);
 let still=art.replace(/<animateTransform\b[^>]*\/>/g,"").replace(/<animate\b[^>]*\/>/g,"");
 // Preserve the normal open-eye pose and omit decorative layers whose base opacity is zero.
 return '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240" id="'+id+'" data-mood="'+mood+'" data-state="'+state+'" role="img" aria-labelledby="'+id+'-title '+id+'-desc" shape-rendering="crispEdges">\n'+
 '<title id="'+id+'-title">'+label(mood)+" · "+label(state)+'</title>\n<desc id="'+id+'-desc">'+esc(desc)+'</desc>\n'+
 '<style>#'+id+' .boop-still{display:none}@media(prefers-reduced-motion:reduce){#'+id+':not([data-motion="on"]) .boop-motion{display:none}#'+id+':not([data-motion="on"]) .boop-still{display:inline}}</style>\n'+
 '<rect width="320" height="240" fill="#000000"/>\n<g class="boop-motion">'+art+'</g>\n<g class="boop-still">'+still+'</g>\n</svg>\n';
}
export {renderSVG, label, palette};
