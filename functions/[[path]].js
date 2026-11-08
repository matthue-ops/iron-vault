/* Preserve file-first routing and readable single-segment gym URLs on Pages. */
export async function onRequest(context){
 const {request,env}=context;
 const incoming=new URL(request.url);
 const gymManifest=/^\/g\/([a-zA-Z0-9][a-zA-Z0-9_-]{0,159})\/manifest\.webmanifest$/.exec(incoming.pathname);
 const provider=['/provider-app.webmanifest','/_provider/manifest.webmanifest'].includes(incoming.pathname);
 if(incoming.pathname==='/gym-app.webmanifest'||gymManifest||provider){
  const headers={'Content-Type':'application/manifest+json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
  if(!['GET','HEAD'].includes(request.method))return new Response(null,{status:405,headers:{...headers,Allow:'GET, HEAD'}});
  const id=gymManifest?gymManifest[1]:incoming.searchParams.get('gym'),key=incoming.searchParams.get('key');
  const valid=value=>typeof value==='string'&&/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,159}$/.test(value);
  if(!provider&&(!valid(id)||!valid(key)))return new Response(null,{status:400,headers});
  if(gymManifest&&incoming.searchParams.has('gym')&&incoming.searchParams.get('gym')!==id)return new Response(null,{status:400,headers});
  const name=(incoming.searchParams.get('name')||'Gym').replace(/[\u0000-\u001f\u007f]/g,'').trim().slice(0,100)||'Gym';
  // Public branding only. Every launch still resolves the live gym and uses normal authentication.
  const scope=provider?'/_provider/':'/g/'+encodeURIComponent(id)+'/';
  const manifest={id:scope,name:provider?'Iron Vault Admin':name,short_name:provider?'Vault Admin':name.slice(0,24),
   start_url:provider?scope+'index':scope+'login?key='+encodeURIComponent(key),scope,display:'standalone',
   background_color:'#090d16',theme_color:'#10b981',lang:'en',
   icons:[192,512].map(size=>({src:'/assets/app-icons/gym-'+size+'.png',sizes:size+'x'+size,type:'image/png',purpose:'any maskable'}))};
  const image=incoming.searchParams.get('image');
  if(!provider&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(image||'')){
   const base='https://uarvhalocgyrikjbrloh.supabase.co/storage/v1/object/public/iv-gym-images/'+image+'/';
   manifest.icons=[192,512].map(size=>({src:base+'icon-'+size+'.png',sizes:size+'x'+size,type:'image/png',purpose:'any'}));
   manifest.icons.push({src:base+'maskable-512.png',sizes:'512x512',type:'image/png',purpose:'maskable'});
  }
  if(provider)manifest.icons=[192,512].map(size=>({src:'/assets/app-icons/provider-'+size+'.png',sizes:size+'x'+size,type:'image/png',purpose:'any maskable'}));
  return new Response(request.method==='HEAD'?null:JSON.stringify(manifest),{headers});
 }
 // Distinct path scopes prevent Android Chrome from treating every gym as one installed app.
 const gymApp=/^\/g\/([a-zA-Z0-9][a-zA-Z0-9_-]{0,159})\/(login|admin|profile|memberlogin|memberprofile|reports|privacy|terms|export-viewer)(?:\.html)?$/.exec(incoming.pathname);
 const providerApp=/^\/_provider\/(index|reports|export-viewer)(?:\.html)?$/.exec(incoming.pathname);
 if(gymApp||providerApp){
  if(!['GET','HEAD'].includes(request.method))return new Response(null,{status:405,headers:{Allow:'GET, HEAD'}});
  const scope=providerApp?'/_provider/':'/g/'+gymApp[1]+'/';
  const asset=new URL(incoming);asset.pathname='/gym/'+(providerApp?providerApp[1]:gymApp[2]);
  const source=await env.ASSETS.fetch(new Request(asset,{method:'GET',headers:request.headers}));
  if(!source.ok)return source;
  const html=(await source.text()).replaceAll('../assets/','/assets/').replace(/<head(?:\s[^>]*)?>/i,head=>head+'<base href="'+scope+'">');
  const headers=new Headers(source.headers);for(const name of ['Content-Length','Content-Encoding','ETag'])headers.delete(name);
  headers.set('Cache-Control','no-store');
  return new Response(request.method==='HEAD'?null:html,{status:source.status,headers});
 }
 // Unknown app paths never fall back to the provider login or a different gym.
 if(/^\/g\/[^/]+\//.test(incoming.pathname)||incoming.pathname.startsWith('/_provider/'))return new Response('Page not found',{status:404});
 const response=await env.ASSETS.fetch(request);
 if(response.status!==404||!['GET','HEAD'].includes(request.method))return response;
 const url=new URL(request.url);
 if(!/^\/[a-z0-9]+(?:-[a-z0-9]+)*\/?$/.test(url.pathname))return response;
 // Pages canonicalizes .html URLs. Fetch the canonical asset internally to keep the gym slug visible.
 url.pathname='/gym/login';
 return env.ASSETS.fetch(new Request(url,request));
}
