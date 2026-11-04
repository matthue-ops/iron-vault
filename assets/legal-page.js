/* Public legal pages use a separate nonpersistent client; no member session is changed. */
(function(){
 'use strict';
 const kind=document.currentScript.dataset.document,params=new URLSearchParams(location.search),token=params.get('key');
 const status=document.getElementById('legal-page-status');
 const client=supabase.createClient('https://uarvhalocgyrikjbrloh.supabase.co','eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVhcnZoYWxvY2d5cmlramJybG9oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMwNjU0MTEsImV4cCI6MjEwODY0MTQxMX0.PSPxbpMV2ZwBobalxd4SkxgqbgQHbUhR1nlESXLb5hk',{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
 (async()=>{try{
  if(!token)throw Error('Open these documents from your gym’s signup page.');
  const args={p_token:token};for(const [param,key] of [['platform','p_platform'],['gym','p_gym']])if(params.get(param))args[key]=params.get(param);
  const bundle=await IronVaultLegal.call(client,'iv_legal_public',args);
  if(!bundle?.platform||!bundle?.gym)throw Error('Published documents are unavailable for this gym or version. Contact the gym before registering.');
  document.getElementById('legal-back').href='/gym/login.html?key='+encodeURIComponent(token);
  document.getElementById('legal-other').href=IronVaultLegal.url(kind==='terms'?'privacy':'terms',token,bundle);
  IronVaultLegal.display(document.getElementById('legal-page-content'),[bundle.platform,bundle.gym],kind);status.textContent='Platform and gym documents below apply together. These are the published versions linked by your gym.';
 }catch(error){status.textContent=error.message;}})();
})();
