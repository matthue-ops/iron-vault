/* Actual frontend against a capability-aware mocked refund API; no SQL execution. */
const {chromium}=require('playwright'),assert=require('node:assert/strict');
(async()=>{const b=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});try{for(const width of [320,375,1280]){
 const p=await b.newPage({viewport:{width,height:850}});
 await p.route('https://app.test/**',r=>r.fulfill({contentType:'text/html',body:'<body><button id="btn-membership-pricing"></button>'}));await p.goto('https://app.test/');
 await p.addStyleTag({path:'assets/refunds.css'});await p.addScriptTag({path:'assets/refunds.js'});
 await p.evaluate(async()=>{
  window.calls=[];window.lost=true;window.auth=[];window.cases=[{id:'cash',member_id:'a',source_key:'source-a',action:'cash',amount:50,status:'pending',reason:'Pilot refund',reference:'REQ234',payload:{member_id:'a',source_key:'source-a',action:'cash',amount:50,reason:'Pilot refund',reference:'REQ234'}},{id:'reject',member_id:'a',source_key:'source-a',action:'wallet',amount:20,status:'pending',reference:'REQ567',payload:{member_id:'a',source_key:'source-a',action:'wallet',amount:20}}];
  window.IronVaultAuth={requireRole:async()=>({user_id:'owner'})};window.app={currentTenantId:'gym',authenticatedRole:{user_id:'owner'}};
  window.client={auth:{onAuthStateChange:fn=>auth.push(fn)},rpc:async(_,args)=>{
   calls.push(args);if(args.p_action==='list')return {data:{features:{generated_payout_reference:true,member_rejection_notice:true},can_request:true,can_approve:true,members:[{id:'a',name:'Alice',display_code:'MEM-001',wallet:100,status:'ACTIVE'}],sources:[{key:'source-a',member_id:'a',amount:100,kind:'topup'}],cases:JSON.parse(JSON.stringify(cases))}};
   if(args.p_action==='preview')return {data:{...args.p_payload,wallet_before:100,wallet_after:50,remaining_eligible:100,review_hash:'review'}};
   const c=cases.find(c=>c.id===args.p_id);
   if(args.p_action==='approve'){
    if('payout_reference' in args.p_payload)throw Error('Client must not supply a generated payout reference');
    if(!args.p_payload.cash_returned)return {error:{code:'P0001',message:'Confirm cash was returned'}};
    c.status='approved';c.payout_reference='PAY234';c.approved_at='2026-11-08T00:00:00Z';c.wallet_before=100;c.wallet_after=50;
    if(lost){lost=false;throw Error('Approval response lost');}return {data:c};
   }
   if(args.p_action==='reject'){c.status='rejected';c.decision_reason=args.p_payload.reason;c.member_decision_reason=args.p_payload.member_reason;return {data:c};}
   return {data:{}};
  }};IronVaultRefunds.install(app,client);await app.openRefunds(undefined,'pending');
 });
 const cash=p.locator('article').filter({hasText:'REQ234'});
 await cash.getByRole('button',{name:'Review approval',exact:true}).click();
 assert.equal(await p.getByLabel('Cash payout receipt / reference').count(),0);
 assert.match(await p.locator('.iv-refund-review').textContent(),/generated on successful approval/);
 await p.getByRole('button',{name:'Confirm approval',exact:true}).click();
 await p.getByRole('dialog',{name:'Refund needs attention',exact:true}).waitFor();
 await p.getByRole('button',{name:'Back to refund',exact:true}).click();
 await p.getByLabel('I confirm this cash was returned outside the wallet').check();
 await p.getByRole('button',{name:'Confirm approval',exact:true}).click();
 await p.getByRole('dialog',{name:'Refund outcome not confirmed',exact:true}).waitFor();
 await p.getByRole('button',{name:'Back to refund',exact:true}).click();
 await p.getByRole('button',{name:'Confirm approval',exact:true}).click();
 await p.getByText('Approved cash payout reference: PAY234',{exact:true}).waitFor();
 assert.equal(await p.evaluate(()=>new Set(calls.filter(c=>c.p_action==='approve').map(c=>c.p_id)).size),1);
 await p.getByRole('button',{name:'History',exact:true}).click();
 assert.match(await p.locator('article').textContent(),/REQ234/);assert.match(await p.locator('article').textContent(),/PAY234/);
 await p.getByRole('button',{name:'Pending review',exact:true}).click();
 const rejected=p.locator('article').filter({hasText:'REQ567'});
 await rejected.getByLabel('Decision reason (internal)').fill('Internal-only pilot note');
 await rejected.getByLabel('Reason shown to member').fill('Your request was cancelled as agreed.');
 await rejected.getByRole('button',{name:'Reject request',exact:true}).click();
 await p.waitForFunction(()=>cases.find(c=>c.id==='reject').status==='rejected');
 assert.deepEqual(await p.evaluate(()=>calls.find(c=>c.p_action==='reject').p_payload),{reason:'Internal-only pilot note',member_reason:'Your request was cancelled as agreed.'});
 await p.getByRole('button',{name:'History',exact:true}).click();await p.getByText('Cash payout receipt: PAY234',{exact:true}).waitFor();
 assert.equal(await p.locator('.iv-refunds').evaluate(n=>n.scrollWidth<=n.clientWidth+1),true);
 await p.close();console.log('045 capability, cash-handover check, generated payout/retry/history and separated rejection reasons:',width);
 }}finally{await b.close();}})().catch(e=>{console.error(e);process.exit(1);});
