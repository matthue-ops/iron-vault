/* URL names identify branding only. Authentication and membership authority remain server verified. */
(function(root){
 'use strict';
 const reserved=new Set(['gym','assets','api','docs','supabase','tests','index','favicon','robots','sitemap','login','logout','admin','memberlogin','memberprofile','reports','health']);
 function valid(value){return typeof value==='string'&&value.length<=96&&/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value)&&!reserved.has(value);}
 function slugFromPath(path){const m=/^\/([^/]+)\/?$/.exec(path||'');if(!m)return null;let value;try{value=decodeURIComponent(m[1]);}catch(_){return null;}return valid(value)?value:null;}
 function origin(location){try{const url=new URL(location.href||location.origin);return /^https?:$/.test(url.protocol)?url.origin:'';}catch(_){return '';}}
 function url(gym,location=root.location){const base=origin(location||{});if(valid(gym.portalSlug))return base+'/'+gym.portalSlug;return base+'/gym/login.html?key='+encodeURIComponent(gym.token||'');}
 function label(gym){return valid(gym.portalSlug)?'/'+gym.portalSlug:'/gym/login.html?key='+String(gym.token||'').slice(0,10)+'…';}
 function page(name){if(!/^(profile|memberprofile|admin)\.html(?:\?key=[^#]*)?$/.test(name))throw Error('Invalid gym page');return '/gym/'+name.replace(/^memberprofile\.html/,'profile.html');}
 const api=Object.freeze({valid,slugFromPath,url,label,page});root.IronVaultGymPortals=api;if(typeof module==='object'&&module.exports)module.exports=api;
})(globalThis);
