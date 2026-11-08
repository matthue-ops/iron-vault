/* Preserve file-first routing and readable single-segment gym URLs on Pages. */
export async function onRequest(context){
 const {request,env}=context;
 const incoming=new URL(request.url);
 if(incoming.pathname==='/gym-app.webmanifest'){
  const headers={'Content-Type':'application/manifest+json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
  if(!['GET','HEAD'].includes(request.method))return new Response(null,{status:405,headers:{...headers,Allow:'GET, HEAD'}});
  const id=incoming.searchParams.get('gym'),key=incoming.searchParams.get('key');
  const valid=value=>typeof value==='string'&&/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,159}$/.test(value);
  if(!valid(id)||!valid(key))return new Response(null,{status:400,headers});
  const name=(incoming.searchParams.get('name')||'Gym').replace(/[\u0000-\u001f\u007f]/g,'').trim().slice(0,100)||'Gym';
  // Public branding only. Every launch still resolves the live gym and uses normal authentication.
  const manifest={id:'/gym/app?gym='+encodeURIComponent(id),name,short_name:name.slice(0,24),
   start_url:'/gym/login?key='+encodeURIComponent(key),scope:'/gym/',display:'standalone',
   background_color:'#090d16',theme_color:'#10b981',lang:'en',
   icons:[192,512].map(size=>({src:'/assets/app-icons/gym-'+size+'.png',sizes:size+'x'+size,type:'image/png',purpose:'any maskable'}))};
  const image=incoming.searchParams.get('image');
  if(/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(image||'')){
   const base='https://uarvhalocgyrikjbrloh.supabase.co/storage/v1/object/public/iv-gym-images/'+image+'/';
   manifest.icons=[192,512].map(size=>({src:base+'icon-'+size+'.png',sizes:size+'x'+size,type:'image/png',purpose:'any'}));
   manifest.icons.push({src:base+'maskable-512.png',sizes:'512x512',type:'image/png',purpose:'maskable'});
  }
  return new Response(request.method==='HEAD'?null:JSON.stringify(manifest),{headers});
 }
 const response=await env.ASSETS.fetch(request);
 if(response.status!==404||!['GET','HEAD'].includes(request.method))return response;
 const url=new URL(request.url);
 if(!/^\/[a-z0-9]+(?:-[a-z0-9]+)*\/?$/.test(url.pathname))return response;
 // Pages canonicalizes .html URLs. Fetch the canonical asset internally to keep the gym slug visible.
 url.pathname='/gym/login';
 return env.ASSETS.fetch(new Request(url,request));
}
