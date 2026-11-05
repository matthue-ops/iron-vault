const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function fixture(status='PENDING'){
 let options,redirect;const store=new Map([['ironvault_active_token','stored-token']]),cls={contains:()=>false,add(){}};
 const root={document:{body:{classList:cls,prepend(){}},addEventListener(){},getElementById:()=>null,createElement:()=>({setAttribute(){}}),querySelector:()=>null,querySelectorAll:()=>[]},
 IronVaultLiveUpdates:{create:o=>{options=o;return{stop(){},start:async()=>{}}}},IronVaultAuth:{requireRole:async()=>({user_id:'u',role:'member',tenant_id:'gym',member_id:'member'}),clearState:()=>store.clear()},sessionStorage:{getItem:k=>store.get(k)},localStorage:{},location:{replace:url=>{redirect=url}},addEventListener(){}};
 let member={id:'member',tenant_id:'gym',status,tenant_token:'member-token'};
 const client={auth:{onAuthStateChange(){}},from:table=>{const q={select(){return q},eq(){return q},then(resolve){return Promise.resolve({data:table==='members'?[member]:[{id:'gym',status:'ACTIVE',token:'gym-token'}]}).then(resolve)}};return q;}};
 const app={authenticatedRole:{user_id:'u',tenant_id:'gym',member_id:'member'},currentMember:{id:'member',tenantId:'gym',tenantToken:'member-token'},init(){}};
 vm.runInNewContext(fs.readFileSync('assets/dashboard-live.js','utf8'),root);root.IronVaultDashboardLive.install(app,client,'member');
 return{app,options:()=>options,redirect:()=>redirect,member:()=>member};
}
test('live member adapter allows pending own-profile reads and denies inactive or foreign membership',async()=>{
 const f=fixture(),scope={member:'member',tenant:'gym'};const data=await f.options().read(scope);assert.equal(data.members[0].status,'PENDING');
 f.member().status='INACTIVE';await assert.rejects(f.options().read(scope),/Membership access changed/);
 f.member().status='ACTIVE';f.member().tenant_id='other';await assert.rejects(f.options().read(scope),/Membership access changed/);
});
test('live denial captures member gym token before clearing the private profile',()=>{
 const f=fixture();f.options().onDenied();assert.equal(f.app.currentMember,null);assert.equal(f.redirect(),'login.html?key=member-token');
});
test('034 manual migration preserves action gates, uniqueness, idempotent provisioning and tenant boundaries',()=>{
 const sql=fs.readFileSync('supabase/manual/pending_access_optional_contact.sql','utf8');assert.equal(sql,fs.readFileSync('supabase/migrations/202611050034_pending_access_optional_contact.sql','utf8'));
 assert.match(sql,/PRIMARY KEY\(user_id\)/);assert.match(sql,/UNIQUE\(tenant_id,role,contact_email\)/);assert.match(sql,/CHECK\(role='member' OR contact_email IS NOT NULL\)/);
 assert.match(sql,/p_email IS NULL AND \(p_role<>'member' OR p_actor IS NULL OR p_new_gym\)/);assert.match(sql,/job.contact_email IS DISTINCT FROM p_email/);
 assert.match(sql,/m.status IN \('ACTIVE','PENDING'\)/);assert.match(sql,/r.member_id=p_member AND r.enabled AND r.disabled_at IS NULL/);
 assert.match(sql,/your profile is read-only/);assert.doesNotMatch(sql,/CREATE OR REPLACE FUNCTION (?:public.iv_financial_transaction|public.iv_issue_member_pass|ironvault_private.member_legal_current)/);
 assert.doesNotMatch(sql,/DELETE FROM|UPDATE public.members SET status|UPDATE ironvault_private.legal_acceptances/);
});
