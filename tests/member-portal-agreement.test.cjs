const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const p='11111111-1111-4111-8111-111111111111',g='22222222-2222-4222-8222-222222222222';
function fixture(agreed=false){
 const nodes=new Map(),node=id=>{if(!nodes.has(id)){const classes=new Set();nodes.set(id,{hidden:false,checked:false,textContent:'',href:'',open:false,attrs:{},classList:{contains:c=>classes.has(c),add:c=>classes.add(c),remove:c=>classes.delete(c),toggle:(c,on)=>on?classes.add(c):classes.delete(c)},setAttribute(k,v){this.attrs[k]=v;},showModal(){this.open=true;},close(){this.open=false;},contains(){return false;}});}return nodes.get(id);};
 const events={},auth=[],calls=[];let user='user',reply={user_id:user,member_id:'member',tenant_id:'gym',accepted:agreed,platform_version:p,gym_version:g,acceptance:agreed?{platform_version:p,gym_version:g,accepted_at:'2026-11-05T00:00:00Z'}:null};
 const root={Intl,Date,URLSearchParams,navigator:{onLine:true},document:{body:node('body'),getElementById:node,addEventListener(){}},setTimeout:()=>1,clearTimeout(){},addEventListener:(n,f)=>{events[n]=f;}};
 const client={auth:{getUser:async()=>({data:{user:{id:user}}}),onAuthStateChange:f=>auth.push(f)},rpc:async(name,args)=>{calls.push({name,args});if(name==='iv_member_legal_accept')reply={...reply,accepted:true,acceptance:{platform_version:p,gym_version:g,accepted_at:'2026-11-05T00:00:00Z'}};return{data:reply};}};
 let purchases=0,qr=0;const app={authenticatedRole:{user_id:'user',member_id:'member',tenant_id:'gym'},currentMember:{id:'member',tenantId:'gym',tenantToken:'token'},init:async()=>{},renderProfile(){},openMemberAnnouncements:async()=>{},selectPlan:async()=>{purchases++;},generateDailyQR:async()=>{qr++;}};
 vm.runInNewContext(fs.readFileSync('assets/member-portal-agreement.js','utf8'),root);root.IronVaultMemberPortalAgreement.install(app,client);
 return{root,node,client,app,auth,calls,setReply:value=>{reply=value;},reply:()=>reply,setUser:value=>{user=value;},purchases:()=>purchases,qr:()=>qr};
}
test('unaccepted member can view profile but purchase and QR calls stop before their original handlers',async()=>{
 const f=fixture();await f.app.init();assert.equal(f.node('btn-generate-qr').attrs['aria-disabled'],'true');assert.equal(f.node('member-qr-legal-help').hidden,false);
 await f.app.selectPlan('1-Day Pass');await f.app.generateDailyQR();assert.equal(f.purchases(),0);assert.equal(f.qr(),0);assert.equal(f.node('member-terms-dialog').open,true);assert.equal(f.node('member-legal-checkbox').checked,false);
 assert.equal(f.node('member-notices-count').textContent,'1');f.app.renderLegalNotice(2);assert.equal(f.node('member-notices-count').textContent,'3');
});
test('explicit acceptance unlocks features and keeps exact accepted documents and timestamp accessible',async()=>{
 const f=fixture();await f.app.init();await f.node('member-legal-agree').onclick();assert.equal(f.calls.some(c=>c.name==='iv_member_legal_accept'),false);
 f.node('member-legal-checkbox').checked=true;await f.node('member-legal-agree').onclick();const call=f.calls.find(c=>c.name==='iv_member_legal_accept');assert.equal(call.args.p_platform,p);assert.equal(call.args.p_gym,g);assert.equal('p_member' in call.args,false);
 assert.equal(f.node('member-notices-count').textContent,'');assert.equal(f.node('member-accepted-record').hidden,false);assert.match(f.node('member-accepted-date').textContent,/Agreed/);assert.match(f.node('member-accepted-terms').href,/platform=11111111/);
 await f.app.selectPlan('1-Day Pass');await f.app.generateDailyQR();assert.equal(f.purchases(),1);assert.equal(f.qr(),1);
});
test('current signup acceptance unlocks immediately while a new publication requires renewed acceptance',async()=>{
 const f=fixture(true);await f.app.init();assert.equal(f.node('member-current-documents').hidden,true);assert.equal(f.node('btn-generate-qr').attrs['aria-disabled'],'false');
 f.setReply({...f.reply(),accepted:false,gym_version:'33333333-3333-4333-8333-333333333333'});await f.app.refreshMemberLegal(true);assert.equal(f.node('member-legal-notice').hidden,false);assert.equal(f.node('member-legal-checkbox').checked,false);assert.match(f.node('member-accepted-privacy').href,/gym=22222222/);assert.match(f.node('member-privacy-link').href,/gym=33333333/);
});
test('RPC failures and wrong-account responses fail closed without clearing the read-only member profile',async()=>{
 const f=fixture(true);await f.app.init();f.client.rpc=async()=>({error:{message:'Offline'}});await f.app.refreshMemberLegal(true);assert.equal(f.node('btn-generate-qr').attrs['aria-disabled'],'true');assert.equal(f.app.currentMember.id,'member');
 f.client.rpc=async()=>({data:{...f.reply(),member_id:'other'}});await f.app.refreshMemberLegal(true);assert.equal(f.node('member-legal-agree').disabled,true);
});
test('signout and late status replies cannot unlock a different account',async()=>{
 const f=fixture();let release;f.client.rpc=()=>new Promise(resolve=>{release=resolve;});const request=f.app.refreshMemberLegal(true);while(!release)await Promise.resolve();f.auth[0]('SIGNED_OUT',null);f.setUser('other');release({data:{...f.reply(),accepted:true,acceptance:{platform_version:p,gym_version:g,accepted_at:'2026-11-05T00:00:00Z'}}});await request;assert.equal(f.node('btn-generate-qr').attrs['aria-disabled'],'true');assert.equal(f.node('member-accepted-record').hidden,true);
});
test('server migration scopes self-service acceptance, preserves financial replay and staff manual admission',()=>{
 const sql=fs.readFileSync('supabase/manual/member_portal_agreement.sql','utf8');assert.equal(sql,fs.readFileSync('supabase/migrations/202611050032_member_portal_agreement.sql','utf8'));
 assert.ok(sql.includes("r.user_id=auth.uid() AND r.role='member' AND r.enabled AND r.disabled_at IS NULL"));assert.ok(sql.includes('FOR UPDATE OF member_row'));assert.ok(sql.includes('p_platform IS DISTINCT FROM p OR p_gym IS DISTINCT FROM g'));assert.ok(sql.includes("USING ERRCODE='IV002'"));assert.ok(sql.includes('clock_timestamp()'));assert.ok(sql.includes('NOT public.iv_can_access(m.tenant_id)'));
 assert.ok(sql.indexOf('RETURN receipt.result;')<sql.indexOf("IF p_operation='purchase' AND ironvault_private.is_own_membership"));assert.ok(sql.includes('require_current_member_legal(ticket.member_id)'));
 assert.equal(sql.includes('CREATE OR REPLACE FUNCTION ironvault_private.record_admission'),false);assert.equal(/CREATE TABLE|DELETE FROM|UPDATE ironvault_private.legal_acceptances/i.test(sql),false);
});
test('financial writer changes only the new member agreement gate and preserves every existing money operation',()=>{
 const base=fs.readFileSync('supabase/migrations/202611010013_member_wallet_and_daily_passes.sql','utf8');
 const sql=fs.readFileSync('supabase/manual/member_portal_agreement.sql','utf8');
 const original=base.slice(base.indexOf('CREATE OR REPLACE FUNCTION public.iv_financial_transaction'),base.indexOf('CREATE TABLE ironvault_private.daily_passes')).trim();
 let updated=sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION public.iv_financial_transaction'),sql.indexOf('CREATE OR REPLACE FUNCTION public.iv_issue_member_pass')).trim();
 const gate=" -- Staff-assisted operations stay available; completed retries above remain read-only.\n IF p_operation='purchase' AND ironvault_private.is_own_membership(m.id,m.tenant_id) AND NOT public.iv_can_access(m.tenant_id) THEN\n  PERFORM ironvault_private.require_current_member_legal(m.id);\n END IF;\n";
 assert.ok(updated.includes(gate));updated=updated.replace(gate,'');assert.equal(updated,original);
});
