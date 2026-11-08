/* Installation is optional. No authentication, API calls or private-data caching here. */
(function(root){
 'use strict';
 const PREFIX='iv-gym-install:v1:';
 const valid=value=>typeof value==='string'&&/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,159}$/.test(value);
 function details(gym){
  if(!gym||!valid(gym.id)||!valid(gym.token)||gym.status==='PROVISIONING')return null;
  const name=String(gym.gymName||'Gym').replace(/[\u0000-\u001f\u007f]/g,'').trim().slice(0,100)||'Gym';
  const query=new URLSearchParams({gym:gym.id,key:gym.token,name});
  const image=/^https:\/\/uarvhalocgyrikjbrloh\.supabase\.co\/storage\/v1\/object\/public\/iv-gym-images\/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})\/logo$/.exec(gym.logo||'');
  if(image)query.set('image',image[1]);
  return {id:gym.id,name,manifest:'/gym-app.webmanifest?'+query,storageKey:PREFIX+gym.id};
 }
 function standalone(){return !!(root.navigator?.standalone||root.matchMedia?.('(display-mode: standalone)').matches||root.matchMedia?.('(display-mode: fullscreen)').matches);}
 function recovery(location){return /(?:iv_recovery|iv_verify|access_token|token_hash|type=recovery|error_description)/.test(location.hash+' '+location.search);}
 const recovering=recovery(root.location||{hash:'',search:''});
 function read(key){try{return root.localStorage.getItem(key);}catch(_){return null;}}
 function write(key,value){try{root.localStorage.setItem(key,value);}catch(_){/* Installation never depends on storage access. */}}
 let current=null,pending=null,dialog=null,button=null,restoreFocus=null;
 function remember(value){if(current)write(current.storageKey,value);}
 function close(){if(dialog?.open)dialog.close();restoreFocus?.focus?.();}
 function reset(){close();dialog?.remove();button?.remove();dialog=null;button=null;current=null;pending=null;root.document?.getElementById('gym-app-manifest')?.remove();}
 function text(tag,content){const n=root.document.createElement(tag);n.textContent=content;return n;}
 function show(help=false){
  if(!current||standalone())return;
  restoreFocus=root.document.activeElement;
  if(!dialog){
   dialog=root.document.createElement('dialog');dialog.id='gym-install-dialog';dialog.setAttribute('aria-labelledby','gym-install-title');
   const title=text('h2','');title.id='gym-install-title';
   const intro=text('p','Open your gym from an app icon, or keep using this browser. Both use the same account.');intro.id='gym-install-intro';
   const guidance=text('p','');guidance.id='gym-install-guidance';guidance.setAttribute('role','status');guidance.hidden=true;
   const actions=text('div','');actions.className='gym-install-actions';
   const install=text('button','Install app');install.type='button';install.id='gym-install-confirm';install.addEventListener('click',installApp);
   const skip=text('button','Continue in browser');skip.type='button';skip.id='gym-install-continue';skip.addEventListener('click',()=>{remember('browser');close();});
   actions.append(install,skip);dialog.append(title,intro,guidance,actions);root.document.body.append(dialog);
   dialog.addEventListener('cancel',()=>remember('browser'));
  }
  root.document.getElementById('gym-install-title').textContent='Install '+current.name+'?';
  const guidance=root.document.getElementById('gym-install-guidance');guidance.hidden=!help;
  if(help)guidance.textContent=instructions();
  if(!dialog.open&&dialog.showModal)dialog.showModal();
 }
 function instructions(){
  const ua=root.navigator.userAgent||'';
  if(/iPad|iPhone|iPod/.test(ua)||(/Macintosh/.test(ua)&&root.navigator.maxTouchPoints>1))return 'On iPhone or iPad, open this gym link in Safari. Tap Share, then Add to Home Screen. If shown, leave Open as Web App enabled and tap Add.';
  return 'Use your browser menu and look for Install app or Add to Home Screen. If it only offers a shortcut, open this gym link in an updated Chrome or Edge browser. QR scanner browsers may need Open in browser first. You can always continue in this browser.';
 }
 async function installApp(){
  const target=current?.id;
  remember('browser');
  const prompt=pending;pending=null;
  if(!prompt){show(true);return;}
  const control=root.document.getElementById('gym-install-confirm');if(control)control.disabled=true;
  try{
   await prompt.prompt();const result=await prompt.userChoice;
   if(current?.id!==target)return;
   if(result.outcome==='accepted'){remember('requested');close();}
   else{close();}
  }catch(_){show(true);}
  finally{if(control)control.disabled=false;}
 }
 function configure(gym,{offer=false}={}){
  try{
   const next=details(gym);if(!next){reset();return;}
   const changed=current?.id!==next.id;if(changed)reset();current=next;
   const d=root.document;
   let manifest=d.getElementById('gym-app-manifest');if(!manifest){manifest=d.createElement('link');manifest.id='gym-app-manifest';manifest.rel='manifest';d.head.append(manifest);}
   if(manifest.getAttribute('href')!==next.manifest)manifest.href=next.manifest;
   for(const [name,content]of [['theme-color','#10b981'],['mobile-web-app-capable','yes'],['apple-mobile-web-app-capable','yes'],['apple-mobile-web-app-title',next.name]]){
    let node=d.querySelector('meta[name="'+name+'"]');if(!node){node=d.createElement('meta');node.name=name;d.head.append(node);}node.content=content;
   }
   if(!d.querySelector('link[rel="apple-touch-icon"]')){const icon=d.createElement('link');icon.rel='apple-touch-icon';icon.href='/assets/app-icons/gym-192.png';d.head.append(icon);}
   if(standalone()){remember('installed');close();if(button)button.hidden=true;return;}
   if(offer){
    if(!button){button=text('button','Install app');button.type='button';button.id='gym-install-open';button.addEventListener('click',()=>show(!pending));(d.querySelector('main')||d.body).append(button);}
    button.hidden=read(next.storageKey)==='installed';
    // Never interrupt verification/reset forms. No automatic native browser prompt.
    if(!read(next.storageKey)&&!recovering&&!recovery(root.location))show();
   }
  }catch(_){/* An install failure must not block the existing portal. */}
 }
 if(root.addEventListener){
  root.addEventListener('beforeinstallprompt',event=>{if(!current)return;event.preventDefault();pending=event;if(button&&!standalone())button.hidden=false;});
  root.addEventListener('appinstalled',()=>{pending=null;remember('installed');close();if(button)button.hidden=true;});
  root.addEventListener('storage',event=>{if(current&&event.key===current.storageKey&&event.newValue){close();if(button)button.hidden=event.newValue==='installed';}});
 }
 const api=Object.freeze({configure,details,standalone,recovery});root.IronVaultGymInstall=api;
 if(typeof module==='object'&&module.exports)module.exports=api;
})(globalThis);
