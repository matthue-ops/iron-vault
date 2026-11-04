/* Preserve file-first routing and readable single-segment gym URLs on Pages. */
export async function onRequest(context){
 const {request,env}=context;
 const response=await env.ASSETS.fetch(request);
 if(response.status!==404||!['GET','HEAD'].includes(request.method))return response;
 const url=new URL(request.url);
 if(!/^\/[a-z0-9]+(?:-[a-z0-9]+)*\/?$/.test(url.pathname))return response;
 // Pages canonicalizes .html URLs. Fetch the canonical asset internally to keep the gym slug visible.
 url.pathname='/gym/login';
 return env.ASSETS.fetch(new Request(url,request));
}
