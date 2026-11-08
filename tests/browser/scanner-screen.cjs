/* Actual scanner markup/methods and presentation module. Camera-only fixtures, no backend calls. */
const {chromium}=require('playwright'),fs=require('node:fs'),assert=require('node:assert/strict');
const source=fs.readFileSync('gym/admin.html','utf8');
const modal=source.slice(source.indexOf('    <!-- QR SCANNER MODAL -->'),source.indexOf('    <!-- MEMBER PROFILE MODAL'));
const methods=source.slice(source.indexOf('            openScannerModal: function'),source.indexOf('            toggleProfileSection: function'));
(async()=>{
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
try{for(const size of [{width:320,height:740},{width:390,height:844},{width:844,height:390},{width:1280,height:850}]){
 const page=await browser.newPage({viewport:size});await page.route('https://scanner.test/**',route=>route.fulfill({contentType:'text/html',body:'<!doctype html><meta charset="utf-8"><style>body{font-family:Arial,sans-serif}.hidden{display:none}</style><button id="launch">Scan</button>'+modal}));await page.goto('https://scanner.test/');
 await page.addStyleTag({path:'assets/scanner-screen.css'});
 await page.evaluate(methods=>{
  window.adminApp=Function('return ({'+methods+'})')();window.cameraTracks=[];window.requests=[];window.delayCamera=false;window.failCamera=false;window.calls=0;
  Object.defineProperty(navigator,'mediaDevices',{configurable:true,value:{getUserMedia:async options=>{requests.push(options);if(failCamera)throw Error('denied');if(delayCamera)await new Promise(resolve=>window.releaseCamera=resolve);const track={stopped:false,stop(){this.stopped=true;},getCapabilities:()=>({torch:true}),applyConstraints:async c=>{track.constraints=c;}};cameraTracks.push(track);return {getTracks:()=>[track],getVideoTracks:()=>[track]};},enumerateDevices:async()=>[{kind:'videoinput'},{kind:'videoinput'}]}});
  Object.defineProperty(HTMLMediaElement.prototype,'srcObject',{configurable:true,get(){return this.fakeStream;},set(value){this.fakeStream=value;}});HTMLMediaElement.prototype.play=async()=>{};
  adminApp.tickCameraScan=function(){calls++;};document.getElementById('launch').onclick=()=>adminApp.openScannerModal();
 },methods);
 await page.addScriptTag({path:'assets/scanner-screen.js'});await page.evaluate(()=>IronVaultScannerScreen.install(adminApp));
 // Use the real subscription wrapper around the presentation, as on the admin page.
 await page.addScriptTag({path:'assets/subscriptions.js'});
 await page.evaluate(()=>{window.scanAllowed=false;window.denied='';adminApp.currentTenantId='gym';adminApp.notifyAdmin=m=>denied=m;IronVaultSubscriptions.install(adminApp,{auth:{getUser:async()=>({data:{user:{id:'owner'}}}),onAuthStateChange(){}},rpc:async()=>({data:{operations:true,portal:scanAllowed,is_owner:false}})},'admin');});
 await page.locator('#launch').click();await page.waitForFunction(()=>!!denied);assert.equal(await page.locator('#scanner-modal').isVisible(),false);assert.equal(await page.evaluate(()=>requests.length),0);assert.notEqual(await page.evaluate(()=>document.body.style.overflow),'hidden');await page.evaluate(()=>scanAllowed=true);
 await page.locator('#launch').click();await page.waitForFunction(()=>!!adminApp.cameraStream);
 const rect=await page.locator('#scanner-modal').boundingBox();assert.equal(rect.width,size.width);assert.equal(rect.height,size.height);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
 const panel=await page.locator('.scanner-shell').boundingBox();if(size.width<1024)assert.equal(Math.round(panel.height),size.height);else if(size.width>1000)assert(panel.width<=520);
 await page.locator('#scanner-torch').click();assert.equal(await page.locator('#scanner-torch').getAttribute('aria-pressed'),'true');
 await page.locator('#scanner-switch').click();await page.waitForFunction(()=>requests.length===2&&!!adminApp.cameraStream);assert.equal(await page.evaluate(()=>cameraTracks[0].stopped),true);
 await page.evaluate(()=>adminApp.showScanResult(false,'ACCESS DENIED','Invalid, expired or used pass.'));
 assert.equal(await page.evaluate(()=>adminApp.scanPaused&&adminApp.cameraStream===null&&adminApp.scanTimer===null),true);await page.getByText('ACCESS DENIED',{exact:true}).waitFor();
 await page.locator('#scan-next-button').click();await page.waitForFunction(()=>!!adminApp.cameraStream);
 await page.evaluate(()=>{adminApp.showScanResult(true,'ENTRY RECORDED','Welcome!');adminApp.pauseScannerAfterSuccess();});assert.equal(await page.locator('#scan-result-container').isVisible(),true);
 await page.screenshot({path:'/tmp/scanner-screen-'+size.width+'.png'});
 await page.getByRole('button',{name:'Close scanner',exact:true}).click();assert.equal(await page.evaluate(()=>cameraTracks.every(t=>t.stopped)),true);assert.equal(await page.locator('#launch').evaluate(n=>n===document.activeElement),true);
 // Closing while the permission prompt is pending must stop the late stream.
 await page.evaluate(()=>delayCamera=true);await page.locator('#launch').click();await page.waitForFunction(()=>!!window.releaseCamera);await page.keyboard.press('Escape');await page.evaluate(()=>{delayCamera=false;releaseCamera();});await page.waitForFunction(()=>cameraTracks.at(-1).stopped);assert.equal(await page.evaluate(()=>adminApp.cameraStream),null);
 await page.evaluate(()=>failCamera=true);await page.locator('#launch').click();await page.getByText(/Camera unavailable/).waitFor();assert.equal(await page.locator('#scan-next-button').textContent(),'Retry camera');await page.evaluate(()=>failCamera=false);await page.locator('#scan-next-button').click();await page.waitForFunction(()=>!!adminApp.cameraStream);
 await page.evaluate(()=>dispatchEvent(new Event('pagehide')));assert.equal(await page.evaluate(()=>adminApp.cameraStream===null&&adminApp.scanPaused),true);
 await page.keyboard.press('Escape');await page.close();console.log('Scanner viewport, controls, result pause, camera cleanup/races and permission retry passed:',size.width,'x',size.height);
}}finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
