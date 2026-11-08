/* Local install UI + real Chrome manifest/service-worker checks. No Supabase calls. */
const {chromium}=require('playwright'),http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const {onRequest}=await import('data:text/javascript;base64,'+Buffer.from(fs.readFileSync('functions/[[path]].js','utf8')).toString('base64'));
 const types={'.js':'text/javascript','.css':'text/css','.png':'image/png','.html':'text/html'};
 const html=(key,hash='')=>'<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/assets/gym-install.css"><script src="/assets/gym-install.js"></script></head><body><main><h1>Gym login</h1><form><input aria-label="Email"><button type="submit">Sign in</button></form></main><script>window.fixtureGym='+JSON.stringify({id:key==='other'?'gym-b':'gym-a',token:key||'public',gymName:key==='other'?'Other Gym':'A & B Gym'})+';IronVaultGymInstall.configure(fixtureGym,{offer:true});</script><script src="/assets/offline-fallback.js"></script></body></html>';
 const server=http.createServer(async(req,res)=>{try{
  const url=new URL(req.url,'http://localhost');
  if(url.pathname==='/gym-app.webmanifest'){const response=await onRequest({request:new Request(url),env:{}});res.writeHead(response.status,Object.fromEntries(response.headers));res.end(await response.text());return;}
  const file=path.resolve('.','.'+url.pathname);
  if((url.pathname.startsWith('/assets/')||['/service-worker.js','/offline.html'].includes(url.pathname))&&file.startsWith(process.cwd()+path.sep)&&fs.existsSync(file)){res.setHeader('Content-Type',types[path.extname(file)]||'text/plain');res.end(fs.readFileSync(file));return;}
  if(url.pathname==='/missing'){res.writeHead(404);res.end('Not found');return;}
  res.setHeader('Content-Type','text/html');res.end(html(url.searchParams.get('key')));
 }catch(e){res.writeHead(500);res.end(String(e));}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin='http://127.0.0.1:'+server.address().port;
 let browser;try{
  browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
  for(const width of [320,390,1280]){
   const context=await browser.newContext({viewport:{width,height:850}}),p=await context.newPage();
   await p.goto(origin+'/gym/login?key=public');await p.getByRole('dialog').waitFor();assert.match(await p.locator('#gym-install-title').textContent(),/A & B Gym/);
   assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);assert.equal(await p.locator('#gym-install-dialog').evaluate(n=>n.scrollWidth<=n.clientWidth),true);
   await p.screenshot({path:'/tmp/gym-install-'+width+'.png'});
   await p.locator('#gym-install-continue').click();assert.equal(await p.evaluate(()=>localStorage.getItem('iv-gym-install:v1:gym-a')),'browser');await p.reload();assert.equal(await p.getByRole('dialog').count(),0);await p.locator('#gym-install-open').click();await p.locator('#gym-install-continue').click();
   // A different gym gets its own choice and app identity.
   await p.goto(origin+'/gym/login?key=other');await p.getByRole('dialog').waitFor();await p.locator('#gym-install-continue').click();
   assert.equal(await p.evaluate(()=>localStorage.getItem('iv-gym-install:v1:gym-b')),'browser');
   await p.goto(origin+'/gym/login?key=public');
   // A native prompt is used only after a user clicks; cancellation never blocks login.
   await p.evaluate(()=>{window.promptCalls=0;const e=new Event('beforeinstallprompt',{cancelable:true});e.prompt=async()=>{promptCalls++};e.userChoice=Promise.resolve({outcome:'dismissed'});dispatchEvent(e);});
   assert.equal(await p.evaluate(()=>promptCalls),0);await p.locator('#gym-install-open').click();await p.locator('#gym-install-confirm').click();await p.waitForFunction(()=>promptCalls===1&&!document.getElementById('gym-install-dialog').open);
   // Installed status synchronizes; a new native event allows reinstallation after uninstall.
   await p.evaluate(()=>dispatchEvent(new Event('appinstalled')));assert.equal(await p.locator('#gym-install-open').isVisible(),false);await p.reload();assert.equal(await p.locator('#gym-install-open').isVisible(),false);
   await p.evaluate(()=>{const e=new Event('beforeinstallprompt',{cancelable:true});e.prompt=async()=>{};e.userChoice=Promise.resolve({outcome:'accepted'});dispatchEvent(e)});assert.equal(await p.locator('#gym-install-open').isVisible(),true);
   await p.locator('#gym-install-open').click();await p.locator('#gym-install-confirm').click();await p.waitForFunction(()=>localStorage.getItem('iv-gym-install:v1:gym-a')==='requested');
   await p.evaluate(()=>dispatchEvent(new Event('appinstalled')));
   // Real manifest fetch verifies identity, launch destination and valid icon downloads.
   const cdp=await context.newCDPSession(p);const manifest=await cdp.send('Page.getAppManifest');assert(manifest.data,'Chrome fetched manifest');const data=JSON.parse(manifest.data);assert.equal(data.start_url,'/gym/login?key=public');assert.equal(data.id,'/gym/app?gym=gym-a');assert.equal(data.display,'standalone');
   const errors=await cdp.send('Page.getInstallabilityErrors');assert(!errors.installabilityErrors.some(e=>/manifest|icon|start-url/.test(e.errorId)),JSON.stringify(errors));
   for(const icon of data.icons){const response=await context.request.get(origin+icon.src);assert.equal(response.status(),200);assert.match(response.headers()['content-type'],/image\/png/);}
   // Existing public-only offline fallback retains this gym URL, with no private caches.
   await p.evaluate(()=>navigator.serviceWorker.ready);await p.waitForFunction(()=>!!navigator.serviceWorker.controller);await context.setOffline(true);await p.reload();assert.equal(await p.locator('h1').textContent(),'Connection interrupted');assert.equal(p.url(),origin+'/gym/login?key=public');await context.setOffline(false);await p.locator('#retry-page').click();await p.getByRole('heading',{name:'Gym login'}).waitFor();
   const cached=await p.evaluate(async()=>{const values=[];for(const name of await caches.keys()){for(const request of await (await caches.open(name)).keys())values.push(new URL(request.url).pathname)}return values});assert.deepEqual(cached,['/offline.html']);
   await context.close();console.log('Install choice, native prompt, manifest, icons, gym isolation and offline checks:',width);
  }
  const context=await browser.newContext(),p=await context.newPage();
  await p.goto(origin+'/friendly-gym');await p.locator('#gym-install-continue').click();
  const friendlyCDP=await context.newCDPSession(p);const friendlyManifest=await friendlyCDP.send('Page.getAppManifest');assert.equal(JSON.parse(friendlyManifest.data).start_url,'/gym/login?key=public');const friendlyErrors=await friendlyCDP.send('Page.getInstallabilityErrors');assert(!friendlyErrors.installabilityErrors.some(e=>/manifest|icon|start-url/.test(e.errorId)),JSON.stringify(friendlyErrors));
  const tab=await context.newPage();await tab.goto(origin+'/gym/login?key=public');await p.evaluate(()=>dispatchEvent(new Event('appinstalled')));await tab.waitForFunction(()=>document.getElementById('gym-install-open').hidden);await tab.close();
  await p.evaluate(()=>localStorage.clear());
  await p.goto(origin+'/gym/login?key=public#iv_recovery=secret');assert.equal(await p.getByRole('dialog').count(),0);assert.equal(await p.locator('#gym-install-open').isVisible(),true);
  await p.evaluate(()=>{history.replaceState(null,'',location.pathname+location.search);IronVaultGymInstall.configure(fixtureGym,{offer:true})});assert.equal(await p.getByRole('dialog').count(),0);
  await p.evaluate(()=>IronVaultGymInstall.configure(null,{offer:true}));assert.equal(await p.locator('link[rel=manifest]').count(),0);assert.equal(await p.locator('#gym-install-open').count(),0);
  await context.close();
  const standalone=await browser.newContext();await standalone.addInitScript(()=>{const original=window.matchMedia;window.matchMedia=function(q){return q==='(display-mode: standalone)'?{matches:true}:original.call(this,q)}});const app=await standalone.newPage();await app.goto(origin+'/gym/login?key=public');assert.equal(await app.locator('#gym-install-dialog').count(),0);assert.equal(await app.locator('#gym-install-open').count(),0);assert.equal(await app.evaluate(()=>localStorage.getItem('iv-gym-install:v1:gym-a')),'installed');await standalone.close();
  const ios=await browser.newContext({userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1'});const iphone=await ios.newPage();await iphone.goto(origin+'/gym/login?key=public');await iphone.locator('#gym-install-confirm').click();assert.match(await iphone.locator('#gym-install-guidance').textContent(),/Safari.*Share.*Add to Home Screen/);await iphone.locator('#gym-install-continue').click();await ios.close();
  const blocked=await browser.newContext();await blocked.addInitScript(()=>Object.defineProperty(window,'localStorage',{get(){throw Error('blocked')}}));const restricted=await blocked.newPage();await restricted.goto(origin+'/gym/login?key=public');await restricted.locator('#gym-install-continue').click();assert.equal(await restricted.getByRole('heading',{name:'Gym login'}).isVisible(),true);await blocked.close();
  console.log('Recovery callbacks, invalid gym, standalone, iOS instructions and blocked storage checks passed.');
 }finally{await browser?.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exit(1)});
