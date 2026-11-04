/* ---------------- 3D walking directions (Map / Live view) ---------------- */
function openDirections(s){
 explain("directions");closeSheet();
 const f=$("#full");f.innerHTML=`<div style="position:absolute;inset:0;background:#cfe3ff"><canvas id="nav3d" style="position:absolute;inset:0;width:100%;height:100%;display:block"></canvas>
  <div style="position:absolute;top:58px;left:0;right:0;display:flex;flex-direction:column;align-items:center;gap:10px;z-index:3">
   <div class="glass" style="border-radius:99px;padding:9px 16px;font-size:13px;font-weight:600;max-width:86%;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">Walking to ${s.venue}</div>
   <div class="glass" style="border-radius:99px;padding:4px;display:flex;gap:2px" role="tablist">
    <button id="mMap" class="navseg on" role="tab" aria-selected="true">Map</button><button id="mLive" class="navseg" role="tab" aria-selected="false">Live view</button></div></div>
  <button class="round glass" id="navX" aria-label="End directions" style="position:absolute;top:58px;left:16px;width:40px;height:40px;color:var(--ink);z-index:4">✕</button>
  <div id="navStep" class="glass" style="position:absolute;left:16px;right:16px;top:150px;border-radius:22px;padding:12px 14px;display:flex;gap:12px;align-items:center;z-index:3;transition:opacity .3s">
   <div id="navArrow" style="width:44px;height:44px;border-radius:14px;background:var(--brand);color:#fff;display:grid;place-items:center;font-size:22px;flex:none;transition:transform .4s">↑</div>
   <div style="min-width:0"><b id="navTitle" style="display:block;font-size:16px">Head north on S Olive St</b><span id="navSub" class="mute" style="font-size:13px">120 m</span></div></div>
  <div style="position:absolute;left:0;right:0;bottom:0;background:#fff;border-radius:30px 30px 0 0;padding:10px 20px 38px;z-index:3;box-shadow:0 -8px 30px rgba(0,0,0,.12)">
   <div class="grab" style="width:38px;height:5px;border-radius:3px;background:#c7c7cc;margin:0 auto 12px"></div>
   <div style="display:flex;align-items:center;gap:14px"><div style="flex:1"><div class="big" style="font-size:28px" id="navEta">${walk(s)} min</div><div class="mute" style="font-size:13px" id="navMeta">${miles(s)} · ${st.rental?s.ret+" free return slots":s.ch+" chargers ready"} · ${s.spot}</div></div>
   <button class="btn pri" style="width:auto;padding:0 22px;height:46px" id="navGo">${st.rental?"Return here":"Scan to rent"}</button></div>
   <div class="mute" style="font-size:12px;margin-top:10px;text-align:center">Swipe up for step-by-step</div></div></div>`;
 requestAnimationFrame(()=>f.classList.add("open"));
 const style=document.createElement("style");style.textContent=`.navseg{height:32px;padding:0 14px;border-radius:99px;font-size:13px;font-weight:600;color:var(--ink)}.navseg.on{background:var(--brand);color:#fff}`;f.appendChild(style);
 const scene3d=build3D($("#nav3d"),s);
 const setMode=m=>{scene3d.mode(m);$("#mMap").classList.toggle("on",m==="map");$("#mLive").classList.toggle("on",m==="live");$("#mMap").setAttribute("aria-selected",m==="map");$("#mLive").setAttribute("aria-selected",m==="live");vib()};
 $("#mMap").onclick=()=>setMode("map");$("#mLive").onclick=()=>setMode("live");
 $("#navX").onclick=()=>{scene3d.stop();closeFull()};
 $("#navGo").onclick=()=>{scene3d.stop();f.classList.remove("open");setTimeout(()=>{render();st.rental?startReturn(s):startRent(s)},450)};
 setTimeout(()=>setMode("live"),2600);
}
function build3D(cv,s){
 if(!window.THREE){return{mode(){},stop(){}}}
 const W=cv.clientWidth,H=cv.clientHeight;
 const R=new THREE.WebGLRenderer({canvas:cv,antialias:true});R.setPixelRatio(Math.min(2,devicePixelRatio));R.setSize(W,H,false);
 R.outputEncoding=THREE.sRGBEncoding;R.shadowMap.enabled=true;R.shadowMap.type=THREE.PCFSoftShadowMap;
 const sc=new THREE.Scene();
 // sky gradient
 const sky=document.createElement("canvas");sky.width=2;sky.height=256;const g=sky.getContext("2d");const gr=g.createLinearGradient(0,0,0,256);gr.addColorStop(0,"#8fb8ff");gr.addColorStop(.55,"#cfe3ff");gr.addColorStop(1,"#f4f8ff");g.fillStyle=gr;g.fillRect(0,0,2,256);
 sc.background=new THREE.CanvasTexture(sky);sc.fog=new THREE.Fog(0xe6efff,60,170);
 const cam=new THREE.PerspectiveCamera(55,W/H,.1,400);
 sc.add(new THREE.HemisphereLight(0xffffff,0xb7c7e6,.85));
 const sun=new THREE.DirectionalLight(0xffffff,.9);sun.position.set(-40,70,30);sun.castShadow=true;sun.shadow.mapSize.set(1024,1024);Object.assign(sun.shadow.camera,{left:-80,right:80,top:80,bottom:-80});sc.add(sun);
 const M=c=>new THREE.MeshStandardMaterial({color:c,roughness:.85});
 const ground=new THREE.Mesh(new THREE.PlaneGeometry(400,400),M(0xe9ede4));ground.rotation.x=-Math.PI/2;ground.receiveShadow=true;sc.add(ground);
 // streets: path goes north along x=0 from z=10 to z=-60, then east along z=-60 to x=40
 const road=M(0x5c6474),walkM=M(0xd9dde6),line=new THREE.MeshBasicMaterial({color:0xffffff});
 const addRoad=(x,z,w,d)=>{const m=new THREE.Mesh(new THREE.BoxGeometry(w,.05,d),road);m.position.set(x,.025,z);m.receiveShadow=true;sc.add(m)};
 addRoad(0,-40,8,140);addRoad(10,-60,120,8);addRoad(-10,-10,120,7);addRoad(30,-30,7,90);
 for(let z=20;z>-110;z-=6){const d=new THREE.Mesh(new THREE.BoxGeometry(.25,.06,2.6),line);d.position.set(0,.06,z);sc.add(d)}
 for(let x=-40;x<70;x+=6){const d=new THREE.Mesh(new THREE.BoxGeometry(2.6,.06,.25),line);d.position.set(x,.06,-60);sc.add(d)}
 // buildings
 const pal=[0xf3f6fb,0xdfe9fb,0xbcd6ff,0xffd9a8,0xf7c4d6,0xc9f0dd,0xfff2c9];
 let seed=7;const rnd=()=>{seed=(seed*16807)%2147483647;return seed/2147483647};
 const block=(cx,cz,sx,sz)=>{for(let i=0;i<4;i++){const w=4+rnd()*5,d=4+rnd()*5,h=4+rnd()*rnd()*26;const b=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),M(pal[Math.floor(rnd()*pal.length)]));b.position.set(cx+(rnd()-.5)*sx,h/2,cz+(rnd()-.5)*sz);b.castShadow=b.receiveShadow=true;sc.add(b);
   // window bands
   if(h>8){const band=new THREE.Mesh(new THREE.BoxGeometry(w+.05,.5,d+.05),new THREE.MeshStandardMaterial({color:0x7aa7ff,roughness:.3,metalness:.2}));for(let y=3;y<h-1;y+=3){const c=band.clone();c.position.set(b.position.x,y,b.position.z);sc.add(c)}}}};
 [[-14,-30],[-14,-48],[14,-30],[14,-46],[-14,10],[14,8],[-14,-78],[14,-78],[46,-44],[46,-78],[-30,-30],[-30,-75],[60,-25]].forEach(([x,z])=>block(x,z,10,12));
 // trees
 const tr=(x,z)=>{const t=new THREE.Mesh(new THREE.CylinderGeometry(.25,.3,2,6),M(0x8a6a4f));t.position.set(x,1,z);const c=new THREE.Mesh(new THREE.IcosahedronGeometry(1.7,0),M(0x6cc58a));c.position.set(x,3.2,z);c.castShadow=true;sc.add(t,c)};
 for(let z=14;z>-56;z-=9){tr(-5.6,z);tr(5.6,z-4)}for(let x=8;x<40;x+=9){tr(x,-65.5)}
 // the kiosk at the destination (x=26,z=-64.5, on the left when walking east)
 const k=new THREE.Group();const body=new THREE.Mesh(new THREE.BoxGeometry(1.4,3.6,.5),M(0xffffff));body.position.y=1.8;body.castShadow=true;
 const scr=new THREE.Mesh(new THREE.PlaneGeometry(1.1,1.6),new THREE.MeshBasicMaterial({color:0x0080f6}));scr.position.set(0,2.6,.26);
 const slots=new THREE.Mesh(new THREE.PlaneGeometry(1.1,1),new THREE.MeshBasicMaterial({color:0x222831}));slots.position.set(0,1.1,.26);
 k.add(body,scr,slots);k.position.set(26,0,-65.2);sc.add(k);
 const beacon=new THREE.Mesh(new THREE.CylinderGeometry(1.6,1.6,.08,40),new THREE.MeshBasicMaterial({color:0x0080f6,transparent:true,opacity:.35}));beacon.position.set(26,.08,-63.6);sc.add(beacon);
 // route as a glowing ribbon with moving chevrons
 const pts=[new THREE.Vector3(0,.12,10),new THREE.Vector3(0,.12,-60),new THREE.Vector3(26,.12,-60),new THREE.Vector3(26,.12,-63)];
 const curve=new THREE.CurvePath();for(let i=0;i<pts.length-1;i++)curve.add(new THREE.LineCurve3(pts[i],pts[i+1]));
 const len=curve.getLength();
 const chev=document.createElement("canvas");chev.width=64;chev.height=64;const cg=chev.getContext("2d");cg.fillStyle="#3aa0ff";cg.fillRect(0,0,64,64);cg.strokeStyle="#ffffff";cg.lineWidth=9;cg.lineCap="round";cg.beginPath();cg.moveTo(14,44);cg.lineTo(32,22);cg.lineTo(50,44);cg.stroke();
 const ct=new THREE.CanvasTexture(chev);ct.wrapS=ct.wrapT=THREE.RepeatWrapping;
 const ribbon=[];curve.curves.forEach(c=>{const a=c.v1,b=c.v2,l=a.distanceTo(b);const m=new THREE.MeshBasicMaterial({map:ct.clone(),transparent:true,opacity:.92});m.map.needsUpdate=true;m.map.repeat.set(1,l/2.2);
  const p=new THREE.Mesh(new THREE.PlaneGeometry(2.2,l),m);p.rotation.x=-Math.PI/2;p.position.set((a.x+b.x)/2,.13,(a.z+b.z)/2);p.rotation.z=Math.atan2(b.x-a.x,-(b.z-a.z))*-1;sc.add(p);ribbon.push(m)});
 const glow=new THREE.Mesh(new THREE.TubeGeometry(curve,80,1.4,8,false),new THREE.MeshBasicMaterial({color:0x0080f6,transparent:true,opacity:.12}));sc.add(glow);
 // you
 const you=new THREE.Group();const dot=new THREE.Mesh(new THREE.SphereGeometry(.7,24,16),new THREE.MeshStandardMaterial({color:0x0080f6,emissive:0x0050c0,emissiveIntensity:.4}));dot.position.y=.9;
 const ring=new THREE.Mesh(new THREE.RingGeometry(1,1.5,40),new THREE.MeshBasicMaterial({color:0x0080f6,transparent:true,opacity:.35,side:THREE.DoubleSide}));ring.rotation.x=-Math.PI/2;ring.position.y=.15;you.add(dot,ring);sc.add(you);
 // camera rigs
 let mode="map",blend=0,target=0,running=true,t0=performance.now();
 const camMap={p:new THREE.Vector3(48,70,22),l:new THREE.Vector3(10,0,-34)},cp=new THREE.Vector3(),cl=new THREE.Vector3();
 const steps=[[0,"↑","Head north on S Olive St","70 m"],[.62,"↱","Turn right onto W 5th St","26 m"],[.9,"⌖","Kiosk on your left","Bar Counter Top · "+s.spot]];
 let lastStep=-1;
 function frame(now){if(!running)return;const T=(now-t0)/1000;const u=Math.min(.985,(T*1.15)%(len+12)/len);
  const pos=curve.getPointAt(Math.min(u,1)),ahead=curve.getPointAt(Math.min(u+.035,1));
  you.position.set(pos.x,0,pos.z);ring.scale.setScalar(1+.25*Math.sin(T*3));beacon.material.opacity=.25+.15*Math.sin(T*4);beacon.scale.setScalar(1+.15*Math.sin(T*4));
  ribbon.forEach(m=>m.map.offset.y=-T*1.2);
  blend+=(target-blend)*.045;
  const dir=ahead.clone().sub(pos).setY(0).normalize();
  const liveP=pos.clone().addScaledVector(dir,-4.2).setY(2.1),liveL=pos.clone().addScaledVector(dir,14).setY(1.2);
  const orbit=Math.sin(T*.12)*6;const mp=camMap.p.clone().add(new THREE.Vector3(orbit,0,0)),ml=camMap.l.clone().lerp(new THREE.Vector3(pos.x,0,pos.z),.25);
  cp.copy(mp).lerp(liveP,blend);cl.copy(ml).lerp(liveL,blend);cam.position.copy(cp);cam.lookAt(cl);cam.fov=55+10*blend;cam.updateProjectionMatrix();
  dot.visible=blend<.6;
  const si=steps.reduce((a,x,i)=>u>=x[0]?i:a,0);if(si!==lastStep){lastStep=si;const a=$("#navArrow");if(a){a.textContent=steps[si][1];$("#navTitle").textContent=steps[si][2];$("#navSub").textContent=steps[si][3];a.animate([{transform:"scale(.7)"},{transform:"scale(1)"}],{duration:350,easing:"cubic-bezier(.3,1.6,.5,1)"})}}
  const left=Math.max(0,Math.round((1-u)*walk(s)));const e=$("#navEta");if(e)e.textContent=(left<1?"Arriving":left+" min");
  R.render(sc,cam);requestAnimationFrame(frame)}
 requestAnimationFrame(frame);
 return{mode(m){mode=m;target=m==="live"?1:0},stop(){running=false;R.dispose()}};
}
