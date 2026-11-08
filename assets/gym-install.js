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
  const scope='/g/'+encodeURIComponent(gym.id)+'/';
  return {id:gym.id,name,scope,launch:scope+'login?key='+encodeURIComponent(gym.token),manifest:scope+'manifest.webmanifest?'+query,storageKey:PREFIX+gym.id,icon:image?'https://uarvhalocgyrikjbrloh.supabase.co/storage/v1/object/public/iv-gym-images/'+image[1]+'/icon-192.png':'/assets/app-icons/gym-192.png'};
 }
 function standalone(){return !!(root.navigator?.standalone||root.matchMedia?.('(display-mode: standalone)').matches||root.matchMedia?.('(display-mode: fullscreen)').matches);}
 function recovery(location){return /(?:iv_recovery|iv_verify|access_token|token_hash|type=recovery|error_description)/.test(location.hash+' '+location.search);}
 const recovering=recovery(root.location||{hash:'',search:''});
 function read(key){try{return root.localStorage.getItem(key);}catch(_){return null;}}
 function write(key,value){try{root.localStorage.setItem(key,value);}catch(_){/* Installation never depends on storage access. */}}
 let current=null,pending=null,dialog=null,button=null,menu=null,restoreFocus=null;
 function inside(){return !!current&&(root.location.pathname||'').startsWith(current.scope);}
 function installed(){return standalone()&&inside();}
 function knownInstalled(){return current&&read(current.storageKey)==='installed-scoped';}
 function remember(value){if(current)write(current.storageKey,value);}
 function close(){if(dialog?.open)dialog.close();restoreFocus?.focus?.();}
 function reset(){close();dialog?.remove?.();menu?.remove?.();dialog=null;button=null;menu=null;current=null;pending=null;root.document?.getElementById('gym-app-manifest')?.remove?.();}
 function text(tag,content){const n=root.document.createElement(tag);n.textContent=content;return n;}
 function help(message){const node=root.document.getElementById('gym-install-guidance');if(node){node.hidden=false;node.textContent=message;node.scrollIntoView?.({block:'nearest'});}}
 function instructions(){
  const ua=root.navigator.userAgent||'';
  if(/iPad|iPhone|iPod/.test(ua)||(/Macintosh/.test(ua)&&root.navigator.maxTouchPoints>1))return 'On iPhone or iPad, open this link in Safari. Tap Share, then Add to Home Screen. If shown, leave Open as Web App enabled and tap Add.';
  return 'If Chrome does not open an install prompt, use its three-dot menu, then Install and create shortcut. If it says already installed, open the app or try this portal in a new Chrome tab. A shortcut opens in Chrome. You can continue in this browser.';
 }
 function show(guidance=false){
  if(!current||installed())return;
  if(!dialog?.open)restoreFocus=menu?.open?root.document.getElementById('gym-install-toggle'):root.document.activeElement;
  if(menu)menu.open=false;
  if(!dialog){
   dialog=root.document.createElement('dialog');dialog.id='gym-install-dialog';dialog.setAttribute('aria-labelledby','gym-install-title');
   const title=text('h2','');title.id='gym-install-title';
   const intro=text('p','Open this portal from an app icon, or continue in this browser. Use your account for this portal with either option.');intro.id='gym-install-intro';
   const status=text('p','');status.id='gym-install-guidance';status.setAttribute('role','status');status.setAttribute('aria-live','polite');status.hidden=true;
   const actions=text('div','');actions.className='gym-install-actions';
   const install=text('button','Install app');install.type='button';install.id='gym-install-confirm';install.addEventListener('click',installApp);
   const skip=text('button','Continue in browser');skip.type='button';skip.id='gym-install-continue';skip.addEventListener('click',()=>{remember('browser');close();});
   actions.append(install,skip);dialog.append(title,intro,status,actions);root.document.body.append(dialog);
   dialog.addEventListener('cancel',()=>remember('browser'));
  }
  root.document.getElementById('gym-install-title').textContent='Install '+current.name+'?';
  root.document.getElementById('gym-install-guidance').hidden=!guidance;
  if(guidance)help(pending?'Ready to install. Tap Install app to continue.':(!inside()?'Tap Install app to open this portal’s installation page first. ':'')+instructions());
  if(!dialog.open&&dialog.showModal)dialog.showModal();
 }
 async function installApp(){
  const target=current?.id;remember('browser');
  const prompt=pending;pending=null;
  if(!prompt){
   if(!inside()){root.location.assign(current.launch+(current.launch.includes('?')?'&':'?')+'install=1');return;}
   show(true);return;
  }
  const control=root.document.getElementById('gym-install-confirm');if(control)control.disabled=true;
  help('Waiting for the browser installation confirmation…');let timeout;
  try{
   const response=(async()=>{await prompt.prompt();return prompt.userChoice;})();
   const result=await Promise.race([response,new Promise((_,reject)=>{timeout=root.setTimeout(()=>reject(Error('No browser response')),10000);})]);
   if(current?.id!==target)return;
   if(result.outcome==='accepted')remember('requested');close();
  }catch(_){if(current?.id===target){show(true);help('Installation is not confirmed yet. Check any browser confirmation first. '+instructions());}}
  finally{root.clearTimeout(timeout);if(control)control.disabled=false;}
 }
 function addMenu(){
  if(menu)return;
  const d=root.document;menu=d.createElement('details');menu.id='gym-install-menu';
  const toggle=text('summary','⋮');toggle.id='gym-install-toggle';toggle.setAttribute('aria-label','Portal options');toggle.title='Portal options';
  const panel=text('div','');panel.className='gym-install-menu-panel';
  button=text('button','Install app');button.type='button';button.id='gym-install-open';button.addEventListener('click',()=>show(!pending));panel.append(button);menu.append(toggle,panel);
  const host=d.querySelector('header > div');
  if(host){host.classList.add('iv-install-header');let actions=d.getElementById('iv-install-header-actions');if(!actions){actions=text('div','');actions.id='iv-install-header-actions';const logout=d.getElementById('btn-super-logout');if(logout&&logout.parentElement===host)actions.append(logout);host.append(actions);}actions.append(menu);}
  else{menu.classList.add('gym-install-menu-floating');d.body.append(menu);}
 }
 function activate(next,{offer=false,menu:withMenu=false}={}){
  try{
   const changed=current?.id!==next.id;if(changed)reset();current=next;const d=root.document;
   let manifest=d.getElementById('gym-app-manifest');if(!manifest){manifest=d.createElement('link');manifest.id='gym-app-manifest';manifest.rel='manifest';d.head.append(manifest);}
   if(manifest.getAttribute('href')!==next.manifest)manifest.href=next.manifest;
   for(const [name,content]of [['theme-color','#10b981'],['mobile-web-app-capable','yes'],['apple-mobile-web-app-capable','yes'],['apple-mobile-web-app-title',next.name]]){
    let node=d.querySelector('meta[name="'+name+'"]');if(!node){node=d.createElement('meta');node.name=name;d.head.append(node);}node.content=content;
   }
   let icon=d.querySelector('link[rel="apple-touch-icon"]');if(!icon){icon=d.createElement('link');icon.rel='apple-touch-icon';d.head.append(icon);}icon.href=next.icon;
   if(installed()){remember('installed-scoped');close();if(menu)menu.hidden=true;return;}
   if(withMenu){addMenu();menu.hidden=knownInstalled();}
   const requested=new URLSearchParams(root.location.search).get('install')==='1';
   if(requested&&!recovering&&!recovery(root.location)){
    const clean=new URL(root.location.href);clean.searchParams.delete('install');
    root.history?.replaceState?.(root.history.state,'',clean.pathname+clean.search+clean.hash);
   }
   if(!recovering&&!recovery(root.location)&&(requested||offer&&!read(next.storageKey)))show(requested);
  }catch(_){/* Installation must never block the existing portal. */}
 }
 function configure(gym,{offer=false}={}){const next=details(gym);if(!next){reset();return;}activate(next,{offer,menu:offer});}
 function configureProvider(){activate({id:'provider',name:'Iron Vault Admin',scope:'/_provider/',launch:'/_provider/index',manifest:'/_provider/manifest.webmanifest',storageKey:'iv-provider-install:v1',icon:'/assets/app-icons/provider-192.png'},{menu:true});}
 if(root.addEventListener){
  root.addEventListener('beforeinstallprompt',event=>{if(!current)return;event.preventDefault();pending=event;if(menu&&!installed())menu.hidden=false;if(dialog?.open)help('Ready to install. Tap Install app to continue.');});
  root.addEventListener('appinstalled',()=>{pending=null;remember('installed-scoped');close();if(menu)menu.hidden=true;});
  root.addEventListener('storage',event=>{if(current&&event.key===current.storageKey&&event.newValue){close();if(menu)menu.hidden=event.newValue==='installed-scoped';}});
  root.document?.addEventListener?.('click',event=>{if(menu?.open&&!menu.contains(event.target))menu.open=false;});
  root.document?.addEventListener?.('keydown',event=>{if(event.key==='Escape'&&menu?.open){menu.open=false;root.document.getElementById('gym-install-toggle')?.focus();}});
 }
 const api=Object.freeze({configure,configureProvider,details,standalone,recovery});root.IronVaultGymInstall=api;
 if(typeof module==='object'&&module.exports)module.exports=api;
})(globalThis);
