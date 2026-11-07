/* Local Chromium regression checks. Actual UI code; no live database or email. */
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');

async function refunds(browser,width){
 const page=await browser.newPage({viewport:{width,height:800}});
 await page.route('https://app.test/**',r=>r.fulfill({contentType:'text/html',body:'<body><button id="btn-membership-pricing"></button>'}));
 await page.goto('https://app.test/');
 await page.addStyleTag({path:'assets/refunds.css'});
 await page.addScriptTag({path:'assets/refunds.js'});
 await page.evaluate(async()=>{
  window.calls=[];window.auth=[];window.saved=null;window.loseResponse=true;window.failList=false;
  window.IronVaultAuth={requireRole:async()=>({user_id:'owner'})};
  window.app={currentTenantId:'gym',authenticatedRole:{user_id:'owner'}};
  window.client={auth:{onAuthStateChange:fn=>auth.push(fn)},rpc:async(_,args)=>{
   calls.push(args);
   if(args.p_action==='list'){
    if(failList)throw Error('List unavailable');
    return {data:{can_request:true,can_approve:true,members:[
     {id:'a',display_code:'MEM-001',name:'Alice',wallet:100,status:'ACTIVE'},
     {id:'b',display_code:'MEM-002',name:'Bob',wallet:0,status:'ACTIVE'}
    ],sources:[{key:'source-a',member_id:'a',kind:'topup',amount:100}],cases:[
     {id:'existing',member_id:'a',source_key:'source-a',status:'pending',action:'cash',amount:20,reference:'EXIST2'},
     ...(saved?[saved]:[])
    ]}};
   }
   if(args.p_action==='reserve_reference')return {data:{reference:'ABC234'}};
   if(args.p_action==='preview'){
    if(Number(args.p_payload.amount)>100)return {error:{code:'P0001',message:'Amount exceeds the remaining eligible amount'}};
    return {data:{...args.p_payload,wallet_before:100,wallet_after:100-Number(args.p_payload.amount),remaining_eligible:100,cash_payout:Number(args.p_payload.amount),review_hash:'review'}};
   }
   if(args.p_action==='request'){
    if(saved)assertSame();else saved={id:args.p_id,payload:args.p_payload,...args.p_payload,status:'pending'};
    if(loseResponse){loseResponse=false;throw Error('Network response lost');}
    return {data:saved};
    function assertSame(){if(saved.id!==args.p_id||JSON.stringify(saved.payload)!==JSON.stringify(args.p_payload))throw Error('Duplicate request identity');}
   }
   return {data:{}};
  }};
  IronVaultRefunds.install(app,client);await app.openRefunds();
 });
 const search=()=>page.getByLabel('Search member',{exact:true});
 const member=()=>page.getByLabel('Member',{exact:true});
 const results=()=>page.getByRole('group',{name:'Member search results',exact:true});
 await search().fill('ali');
 await results().getByRole('button',{name:/Alice/}).click();
 assert.equal(await member().inputValue(),'a');
 await search().fill('missing');
 assert.match(await results().textContent(),/No matching member/);
 assert.equal(await member().inputValue(),'a');
 await search().fill('MEM-002');
 await results().getByRole('button',{name:/Bob/}).click();
 assert.equal(await member().inputValue(),'b');
 await search().fill('ALICE');await results().getByRole('button',{name:/Alice/}).click();
 await page.getByLabel('Original transaction',{exact:true}).selectOption('source-a');
 assert.match(await page.locator('form [role=status]').textContent(),/1 other pending request/);
 await page.getByLabel('Amount',{exact:true}).fill('101');
 await page.getByRole('button',{name:'Review request',exact:true}).click();
 const definite=page.getByRole('dialog',{name:'Refund needs attention',exact:true});
 await definite.waitFor();assert.match(await definite.textContent(),/Amount exceeds/);
 assert.equal(await definite.evaluate(n=>n.getBoundingClientRect().top>=0),true);
 await page.getByRole('button',{name:'Back to refund',exact:true}).click();
 assert.equal(await page.getByLabel('Amount',{exact:true}).inputValue(),'101');
 await page.getByLabel('Amount',{exact:true}).fill('20');
 await page.getByRole('button',{name:'Review request',exact:true}).click();
 assert.match(await page.locator('.iv-refund-review').textContent(),/1 other pending request/);
 await page.getByRole('button',{name:'Confirm refund request',exact:true}).click();
 const uncertain=page.getByRole('dialog',{name:'Refund outcome not confirmed',exact:true});
 await uncertain.waitFor();assert.match(await uncertain.textContent(),/may already be recorded/);
 await page.getByRole('button',{name:'Back to refund',exact:true}).click();
 await page.getByRole('button',{name:'Confirm refund request',exact:true}).click();
 await page.waitForFunction(()=>calls.filter(c=>c.p_action==='request').length===2&&!document.querySelector('.iv-refund-review'));
 const ids=await page.evaluate(()=>calls.filter(c=>c.p_action==='request').map(c=>c.p_id));assert.equal(new Set(ids).size,1);
 // Initial-load errors also appear visibly, and sign-out removes every dialog.
 await page.evaluate(()=>{failList=true;return app.openRefunds();});
 await page.getByRole('dialog',{name:'Refund needs attention',exact:true}).waitFor();
 await page.evaluate(()=>auth[0]('SIGNED_OUT'));
 assert.equal(await page.locator('.iv-refunds').count(),0);
 await page.close();
 console.log('Visible search, retained selection, pending warning, error dialogs, committed-request retry and sign-out cleanup:',width);
}

async function topups(browser,width){
 const html=fs.readFileSync('gym/admin.html','utf8');
 const selection=html.match(/selectModalTopUp: function\(amount\) \{([\s\S]*?)\r?\n\s*\},/)[1];
 const custom=html.match(/handleCustomModalTopUp: async function\(\) \{([\s\S]*?)\r?\n\s*\},/)[1];
 const writer=html.match(/adminApp.addModalCredits=async function\(amount\)\{([\s\S]*?)\r?\n\};/)[1];
 const markup=html.match(/<div id="modal-cash-topup-section"[\s\S]*?<\/div>\s*<\/div>\s*<\/div>/)[0];
 const page=await browser.newPage({viewport:{width,height:800}});
 await page.route('https://app.test/**',r=>r.fulfill({contentType:'text/html; charset=utf-8',body:'<!doctype html><meta charset="utf-8"><body>'+markup}));await page.goto('https://app.test/');
 await page.addScriptTag({path:'assets/financial-requests.js'});
 await page.evaluate(({selection,custom,writer})=>{
  const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
  window.alert=()=>{throw Error('Unexpected native alert');};
  window.calls=[];window.messages=[];window.release=null;
  window.ivRequireRole=async()=>({user_id:'owner'});window.IronVaultAuth={requireRole:ivRequireRole};window.ivMoney=n=>'₱'+n;
  window.supabaseClient={auth:{getUser:async()=>({data:{user:{id:'owner'}}})},from:()=>({select(){return this;},eq(){return this;},single:async()=>({data:{id:'a',status:'ACTIVE'}})}),rpc:async(_,args)=>{calls.push(args);return {data:{request_id:args.p_request_id,wallet_balance:args.p_amount}};}};
  window.adminApp={currentTenantId:'gym',authenticatedRole:{user_id:'owner'},activeModalMemberId:'a',members:[{id:'a',name:'Alice',status:'ACTIVE',walletBalance:0}],
   selectModalTopUp:new Function('amount',selection),handleCustomModalTopUp:new AsyncFunction(custom),addModalCredits:new AsyncFunction('amount',writer),
   confirmAdmin:async()=>new Promise(r=>release=r),notifyAdmin:m=>messages.push(m),loadMembers:async()=>{},openProfileModal(){}
  };
 },{selection,custom,writer});
 await page.getByRole('button',{name:'+₱100',exact:true}).click();
 assert.equal(await page.locator('#modal-topup-input').inputValue(),'100');
 assert.equal(await page.evaluate(()=>calls.length),0);
 await page.getByRole('button',{name:'Add Funds',exact:true}).click();
 await page.waitForFunction(()=>!!release);
 assert.equal(await page.getByRole('button',{name:'Add Funds',exact:true}).isDisabled(),true);
 await page.evaluate(async()=>{await adminApp.handleCustomModalTopUp();adminApp.selectModalTopUp(500);});
 assert.equal(await page.locator('#modal-topup-input').inputValue(),'100');
 await page.evaluate(()=>release(true));
 await page.waitForFunction(()=>!adminApp.modalTopUpBusy);
 assert.equal(await page.evaluate(()=>calls.length),1);
 assert.equal(await page.locator('#modal-topup-input').inputValue(),'');
 assert.equal(await page.evaluate(()=>adminApp.members[0].walletBalance),100);
 // Cancel preserves amount, sends nothing and releases controls.
 await page.getByRole('button',{name:'+₱500',exact:true}).click();
 await page.evaluate(()=>release=null);await page.getByRole('button',{name:'Add Funds',exact:true}).click();await page.waitForFunction(()=>!!release);await page.evaluate(()=>release(false));await page.waitForFunction(()=>!adminApp.modalTopUpBusy);
 assert.equal(await page.locator('#modal-topup-input').inputValue(),'500');assert.equal(await page.evaluate(()=>calls.length),1);
 assert.equal(await page.getByRole('button',{name:'Add Funds',exact:true}).isDisabled(),false);
 // An uncertain commit preserves amount and request ID; retry credits only once.
 await page.evaluate(()=>{window.ids=[];window.ledger=new Map();window.lose=true;supabaseClient.rpc=async(_,args)=>{ids.push(args.p_request_id);if(!ledger.has(args.p_request_id))ledger.set(args.p_request_id,args.p_amount);if(lose){lose=false;throw Error('Lost response');}return {data:{request_id:args.p_request_id,wallet_balance:600}};};release=null;});
 await page.getByRole('button',{name:'Add Funds',exact:true}).click();await page.waitForFunction(()=>!!release);await page.evaluate(()=>release(true));await page.waitForFunction(()=>!adminApp.modalTopUpBusy);
 assert.equal(await page.locator('#modal-topup-input').inputValue(),'500');
 await page.evaluate(()=>release=null);await page.getByRole('button',{name:'Add Funds',exact:true}).click();await page.waitForFunction(()=>!!release);await page.evaluate(()=>release(true));await page.waitForFunction(()=>!adminApp.modalTopUpBusy);
 assert.equal(await page.evaluate(()=>new Set(ids).size),1);assert.equal(await page.evaluate(()=>ledger.size),1);assert.equal(await page.evaluate(()=>adminApp.members[0].walletBalance),600);
 await page.close();console.log('Actual top-up controls, single confirmation, cancellation and uncertain-commit retry:',width);
}

(async()=>{const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});try{for(const width of [320,375,1280]){await refunds(browser,width);await topups(browser,width);}}finally{await browser.close();}})().catch(e=>{console.error(e);process.exit(1);});
