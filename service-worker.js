/* Network-only app navigation. Cache only the public, self-contained warning page. */
'use strict';
const CACHE_PREFIX='iron-vault-offline-',CACHE_NAME=CACHE_PREFIX+'v2',OFFLINE_URL='/offline.html';
self.addEventListener('install',event=>{
 event.waitUntil((async()=>{
  const response=await fetch(OFFLINE_URL,{cache:'reload',credentials:'omit'});
  if(!response.ok)throw Error('Offline page unavailable');
  const text=await response.text();
  if(!text.includes('data-iron-vault-offline'))throw Error('Unexpected offline page');
  const cache=await caches.open(CACHE_NAME);
  // Rebuild the response so canonical .html redirects are not replayed offline.
  await cache.put(OFFLINE_URL,new Response(text,{headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'}}));
  await self.skipWaiting();
 })());
});
self.addEventListener('activate',event=>{
 event.waitUntil((async()=>{
  for(const key of await caches.keys())if(key.startsWith(CACHE_PREFIX)&&key!==CACHE_NAME)await caches.delete(key);
  await self.clients.claim();
 })());
});
self.addEventListener('fetch',event=>{
 const request=event.request,url=new URL(request.url);
 // Never intercept API calls, form submissions, scripts or cross-origin traffic.
 if(request.method!=='GET'||request.mode!=='navigate'||url.origin!==self.location.origin)return;
 event.respondWith((async()=>{
  let timeout;
  try{
   const controller=new AbortController();timeout=setTimeout(()=>controller.abort(),10000);
   const response=await fetch(request,{signal:controller.signal});
   if(response.status<500)return response;
   const fallback=await caches.match(OFFLINE_URL,{cacheName:CACHE_NAME});
   return fallback||response;
  }catch(_){
   const fallback=await caches.match(OFFLINE_URL,{cacheName:CACHE_NAME});
   return fallback||new Response('Connection interrupted. Check your connection and retry. Do not repeat unconfirmed payments.',{status:503,headers:{'Content-Type':'text/plain; charset=utf-8'}});
  }finally{if(timeout)clearTimeout(timeout);}
 })());
});
