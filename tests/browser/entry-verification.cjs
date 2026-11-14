/* Real scanner lifecycle and new verification UI, synthetic RPC responses. */
const {chromium}=require('playwright'),fs=require('node:fs'),assert=require('node:assert/strict');
const source=fs.readFileSync('gym/admin.html','utf8');
const modal=source.slice(source.indexOf('    <!-- QR SCANNER MODAL -->'),source.indexOf('    <!-- MEMBER PROFILE MODAL'));
const methods=source.slice(source.indexOf('            openScannerModal: function'),source.indexOf('            toggleProfileSection: function'));
(async()=>{const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});try{
for(const viewport of [{width:390,height:844},{width:1280,height:850}]){
 const page=await browser.newPage({viewport});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('https://entry.test/**',r=>r.fulfill({contentType:'text/html',body:'<!doctype html><meta charset="utf-8"><style>body{font-family:Arial}.hidden{display:none}</style><button id="launch">Scan</button><div><input id="roster-search"></div>'+modal}));await page.goto('https://entry.test/');
 await page.addStyleTag({path:'assets/scanner-screen.css'});await page.addStyleTag({path:'assets/entry-verification.css'});
 await page.evaluate(methods=>{
  window.adminApp=Function('return ({'+methods+'})')();adminApp.currentTenantId='gym-a';adminApp.members=[];adminApp.loadMembers=async()=>{};adminApp.openProfileModal=id=>window.openedMember=id;
  window.authCallbacks=[];window.calls=[];window.nextResult={valid:true,eligible:true,reason:'READY',member:{id:'member-a',name:'Alex <script>',display_code:'MEM-0001',avatar:null,plan:'1-Month Unlimited',expiration_date:'2027-01-01'}};
  window.userId='owner-a';window.approveDelay=false;window.verifyDelay=false;window.redeemed=0;
  window.IronVaultAuth={requireRole:async()=>({user_id:userId})};window.IronVaultData={call:async(client,name,args)=>{calls.push({name,args});if(name==='iv_verify_entry_qr'){if(verifyDelay)await new Promise(r=>window.releaseVerify=r);return structuredClone(nextResult);}if(name==='iv_approve_entry_qr'){redeemed++;if(approveDelay)await new Promise(r=>window.releaseApprove=r);return {admitted_at:new Date().toISOString()};}return {payload:'IVC1|11111111-1111-4111-8111-111111111111'};}};
  window.client={auth:{onAuthStateChange:fn=>authCallbacks.push(fn)}};
  Object.defineProperty(navigator,'mediaDevices',{configurable:true,value:{getUserMedia:async()=>{const t={stop(){},getCapabilities:()=>({})};return {getTracks:()=>[t],getVideoTracks:()=>[t]};},enumerateDevices:async()=>[]}});
  Object.defineProperty(HTMLMediaElement.prototype,'srcObject',{configurable:true,get(){return this.fakeStream;},set(v){this.fakeStream=v;}});HTMLMediaElement.prototype.play=async()=>{};
  adminApp.tickCameraScan=()=>{};document.getElementById('launch').onclick=()=>adminApp.openScannerModal();
 },methods);
 await page.addScriptTag({path:'assets/scanner-screen.js'});await page.evaluate(()=>IronVaultScannerScreen.install(adminApp));await page.addScriptTag({path:'assets/entry-verification.js'});await page.evaluate(()=>IronVaultEntryVerification.install(adminApp,client));
 const dialog=page.getByRole('dialog',{name:'Verify member entry'});
 await page.locator('#launch').click();await page.evaluate(()=>adminApp.processScannedCode('IVC1|card'));await dialog.waitFor();assert.equal(await page.evaluate(()=>redeemed),0);assert.equal(await page.evaluate(()=>adminApp.scanPaused&&adminApp.cameraStream===null),true);await dialog.getByText('No photo on file — verify another ID').waitFor();await dialog.getByText('Alex <script>',{exact:true}).waitFor();assert.equal(await dialog.getByRole('button',{name:'Approve Entry'}).isEnabled(),true);
 assert.equal(await dialog.evaluate(n=>n.scrollWidth<=n.clientWidth),true);await page.screenshot({path:'/tmp/entry-verify-'+viewport.width+'.png'});
 await dialog.getByRole('button',{name:'Deny / Close'}).click();await page.waitForTimeout(1700);assert.equal(await page.evaluate(()=>redeemed),0);assert.equal(await page.evaluate(()=>!!adminApp.cameraStream),true);
 await page.evaluate(()=>{nextResult.eligible=false;nextResult.reason='ALREADY_ENTERED';nextResult.entered_at='2026-11-14T00:14:00Z';});await page.evaluate(()=>adminApp.processScannedCode('IV1|daily'));await dialog.waitFor();assert.equal(await dialog.getByRole('button',{name:'Approve Entry'}).isDisabled(),true);await dialog.getByText(/Already entered today at 8:14/).waitFor();await dialog.getByRole('button',{name:'Deny / Close'}).click();await page.waitForTimeout(1700);
 await page.evaluate(()=>nextResult={valid:false,reason:'INVALID_CARD_FOR_GYM'});await page.evaluate(()=>adminApp.processScannedCode('IVC1|foreign'));assert.equal(await dialog.isVisible(),false);await page.getByText('Invalid card for this gym',{exact:true}).waitFor();
 await page.evaluate(()=>{nextResult={valid:true,eligible:true,reason:'READY',member:{id:'member-a',name:'Alex',display_code:'MEM-0001'}};});await page.getByRole('button',{name:'Close scanner',exact:true}).click();await page.getByRole('button',{name:'Scan Member Card',exact:true}).click();await page.evaluate(()=>adminApp.processScannedCode('IVC1|card'));assert.equal(await page.evaluate(()=>openedMember),'member-a');assert.equal(await page.evaluate(()=>calls.at(-1).args.p_lookup),true);assert.equal(await page.evaluate(()=>redeemed),0);
 await page.locator('#launch').click();await page.evaluate(()=>adminApp.processScannedCode('IV1|daily'));await dialog.waitFor();await page.evaluate(()=>approveDelay=true);await dialog.getByRole('button',{name:'Approve Entry'}).click();await page.waitForFunction(()=>!!window.releaseApprove);assert.equal(await dialog.getByRole('button',{name:'Approve Entry'}).isDisabled(),true);await page.keyboard.press('Escape');assert.equal(await dialog.isVisible(),true);await page.evaluate(()=>releaseApprove());await page.getByText('ENTRY RECORDED',{exact:true}).waitFor();assert.equal(await page.evaluate(()=>redeemed),1);await page.evaluate(()=>adminApp.resumeScanner());assert.equal(await page.evaluate(()=>adminApp.cameraStream===null),true);await page.waitForTimeout(1700);assert.equal(await page.evaluate(()=>!!adminApp.cameraStream),true);
 // A late verification response after closing must not show private data.
 await page.evaluate(()=>{verifyDelay=true;adminApp.processScannedCode('IVC1|card');});await page.waitForFunction(()=>!!window.releaseVerify);await page.getByRole('button',{name:'Close scanner',exact:true}).click();await page.evaluate(()=>releaseVerify());await page.waitForTimeout(50);assert.equal(await dialog.isVisible(),false);
 // Sign-out clears an open verification window and stops scanning.
 await page.evaluate(()=>{verifyDelay=false;});await page.locator('#launch').click();await page.evaluate(()=>adminApp.processScannedCode('IVC1|card'));await dialog.waitFor();await page.evaluate(()=>authCallbacks.forEach(fn=>fn('SIGNED_OUT')));assert.equal(await dialog.isVisible(),false);assert.equal(await page.evaluate(()=>adminApp.cameraStream===null),true);
 // Basic permanent QR display uses the scoped API and is cleared when closed.
 await page.addScriptTag({path:'assets/vendor/qrcode.min.js'});
 await page.evaluate(()=>{window.memberApp={currentMember:{id:'member-a',tenantId:'gym-a',name:'Alex',displayCode:'MEM-0001'}};IronVaultEntryVerification.installCard(memberApp,client,'member');});
 await page.evaluate(()=>memberApp.openPermanentMemberQR());
 const cardView=page.getByRole('dialog',{name:'Member QR',exact:true}).last();await cardView.waitFor();assert.equal(await cardView.locator('canvas').count(),1);assert.equal(await page.evaluate(()=>calls.at(-1).name),'iv_member_card');
 await cardView.getByRole('button',{name:'Close',exact:true}).click();assert.equal(await cardView.locator('canvas').count(),0);
 assert.deepEqual(errors,[]);await page.close();console.log('PASS unified verification, approval-only writes, disabled entry, fallback photo, lookup isolation, cooldown, duplicate clicks, close/response race and sign-out:',viewport.width);
}
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
