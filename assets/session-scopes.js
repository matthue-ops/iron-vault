/* Browser session partitioning only. Stored routing aliases never authorize an account. */
(function(root){
 'use strict';
 const PREFIX='iv-auth:v1:',ALIAS='iv-gym-session-alias:v1:',clients=new WeakMap();let bootstrap=0;
 const valid=value=>typeof value==='string'&&/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,159}$/.test(value);
 function read(storage,key){try{return storage?.getItem(key);}catch(_){return null;}}
 function context(location=root.location,storage=root.localStorage,{provider=false}={}){
  const path=location?.pathname||'',query=new URLSearchParams(location?.search||''),gym=/^\/g\/([a-zA-Z0-9][a-zA-Z0-9_-]{0,159})\//.exec(path);
  if(gym)return {kind:'gym',gymId:gym[1],realm:'gym:'+gym[1],storageKey:PREFIX+'gym:'+gym[1]};
  const master=provider||path.startsWith('/_provider/')||/^\/gym\/index(?:\.html)?$/.test(path)||(/^\/gym\/reports(?:\.html)?$/.test(path)&&['index','superadmin'].includes(query.get('from')));
  if(master)return {kind:'provider',gymId:null,realm:'provider',storageKey:PREFIX+'provider'};
  const token=query.get('key'),alias=valid(token)?read(storage,ALIAS+token):null;
  if(valid(alias))return {kind:'gym',gymId:alias,realm:'gym:'+alias,storageKey:PREFIX+'gym:'+alias};
  return {kind:'bootstrap',gymId:null,realm:null,storageKey:null};
 }
 function createClient(sdk,url,key,options={}){
  const scope=context(root.location,root.localStorage,options),persistent=scope.kind!=='bootstrap';
  if(persistent)scope.storageKey=PREFIX+new URL(url).host+':'+scope.realm;
  const client=sdk.createClient(url,key,{auth:{storageKey:scope.storageKey||'iv-auth-bootstrap:v1:'+(++bootstrap),persistSession:persistent,autoRefreshToken:persistent,detectSessionInUrl:false}});
  clients.set(client,Object.freeze(scope));return client;
 }
 function rememberGym(gym){
  if(!valid(gym?.id)||!valid(gym?.token))return;
  try{root.localStorage?.setItem(ALIAS+gym.token,gym.id);}catch(_){/* Scoped URLs do not depend on aliases/storage being available. */}
 }
 function handoff(gym){
  if(!valid(gym?.id)||!valid(gym?.token))return false;
  rememberGym(gym);const path='/g/'+encodeURIComponent(gym.id)+'/login';
  if(root.location.pathname===path||root.location.pathname===path+'.html')return false;
  const url=new URL(root.location.href);url.pathname=path;url.searchParams.set('key',gym.token);url.searchParams.delete('gym');
  // Preserve recovery/verification fragments for the canonical page; never consume them here.
  root.location.replace(url.pathname+url.search+url.hash);return true;
 }
 function metadata(client){return clients.get(client)||null;}
 const api=Object.freeze({createClient,context,rememberGym,handoff,metadata});root.IronVaultSessionScopes=api;
 if(typeof module==='object'&&module.exports)module.exports=api;
})(globalThis);
