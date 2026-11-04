const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const script=fs.readFileSync('assets/legal-documents.js','utf8');
function fixture(){const nodes=new Map(),node=id=>{if(!nodes.has(id))nodes.set(id,{value:'',checked:false,href:'',textContent:''});return nodes.get(id);};const root={URLSearchParams,document:{getElementById:node}};vm.runInNewContext(script,root);return{root,node,api:root.IronVaultLegal};}
const bundle={platform:{id:'11111111-1111-4111-8111-111111111111'},gym:{id:'22222222-2222-4222-8222-222222222222'}};
test('signup fails closed without published documents and requires unchecked explicit acceptance',async()=>{
 const {api,node}=fixture(),app={matchedOwnerRecord:{token:'gym-token'},init:async()=>{}};let current=bundle;
 api.installSignup(app,{rpc:async()=>({data:current})});await app.init();
 assert.equal(node('signup-legal-accepted').checked,false);assert.throws(()=>app.requireLegalAcceptance(),/tick the agreement/);
 node('signup-legal-accepted').checked=true;const accepted=app.requireLegalAcceptance();assert.equal(accepted.platform_version,bundle.platform.id);assert.equal(accepted.gym_version,bundle.gym.id);assert.equal(accepted.accepted,true);
 assert.match(node('signup-terms-link').href,/platform=11111111/);assert.match(node('signup-privacy-link').href,/gym=22222222/);
 current={platform:bundle.platform,gym:null};await app.loadLegalDocuments();node('signup-legal-accepted').checked=true;assert.throws(()=>app.requireLegalAcceptance(),/unavailable/);assert.match(node('signup-legal-status').textContent,/until.*publish/);
});
test('legal links pin the displayed version pair and encode gym tokens',()=>{
 const {api}=fixture(),url=new URL(api.url('terms','token&extra=x',bundle),'https://example.invalid');assert.equal(url.searchParams.get('key'),'token&extra=x');assert.equal(url.searchParams.get('platform'),bundle.platform.id);assert.equal(url.searchParams.get('gym'),bundle.gym.id);
});
test('legal SQL isolates drafts, restricts management, freezes bodies and captures acceptance atomically',()=>{
 const sql=fs.readFileSync('supabase/manual/legal_documents.sql','utf8');assert.equal(sql,fs.readFileSync('supabase/migrations/202611040030_legal_documents.sql','utf8'));
 for(const text of ["r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL","r.role='super_admin' AND r.tenant_id IS NULL","r.role='owner' AND r.tenant_id=p_tenant",'terms_text text NOT NULL','privacy_text text NOT NULL',"p_action<>'preview'",'BEFORE INSERT OR UPDATE ON ironvault_private.provision_requests',"NEW.payload->'legal'->'accepted' IS DISTINCT FROM 'true'::jsonb","USING ERRCODE='IV001'",'OLD.completed_user IS NULL AND NEW.completed_user IS NOT NULL','NEW.created_at','current_version','platform_version,gym_version,accepted_at','FROM PUBLIC,anon,authenticated,service_role'])assert.ok(sql.includes(text),text);
 const publicFn=sql.split('FUNCTION public.iv_legal_public')[1].split('END $fn$;')[0];assert.equal(publicFn.includes('draft'),false);assert.ok(publicFn.includes("scope='platform'"));assert.ok(publicFn.includes('scope=tenant'));
 assert.equal(/UPDATE ironvault_private.legal_versions|UPDATE ironvault_private.legal_acceptances|UPDATE public.members|DELETE FROM/i.test(sql),false);
});
test('login links stay inside their relevant forms and signup agreement starts unchecked',()=>{
 const html=fs.readFileSync('gym/login.html','utf8');const form=id=>html.split('id="'+id+'"')[1].split('</form>')[0];
 const member=form('auth-signin-form'),admin=form('auth-admin-form'),join=form('auth-signup-form');
 assert.ok(member.indexOf('Resend email confirmation')>member.indexOf('btn-submit-signin'));assert.ok(admin.indexOf('Forgot password?')<admin.indexOf('id="admin-login-password"'));assert.ok(admin.indexOf('Resend email confirmation')>admin.indexOf('btn-submit-admin'));assert.ok(join.indexOf('Already registered?')>join.indexOf('btn-submit-signup'));
 assert.match(join,/id="signup-legal-accepted" type="checkbox" required/);assert.doesNotMatch(join,/id="signup-legal-accepted"[^>]*checked/);assert.match(join,/target="_blank" rel="noopener"/);
});

test('late legal responses cannot replace a newly selected gym bundle',async()=>{
 const {api,node}=fixture();const pending=[];const app={matchedOwnerRecord:{token:'a'},init:async()=>{}};api.installSignup(app,{rpc:()=>new Promise(resolve=>pending.push(resolve))});
 const first=app.loadLegalDocuments();app.matchedOwnerRecord={token:'b'};const second=app.loadLegalDocuments();
 const newer={platform:bundle.platform,gym:{id:'33333333-3333-4333-8333-333333333333'}};pending[1]({data:newer});await second;pending[0]({data:bundle});await first;node('signup-legal-accepted').checked=true;assert.equal(app.requireLegalAcceptance().gym_version,newer.gym.id);assert.match(node('signup-terms-link').href,/key=b/);
});
test('only the server-confirmed rejected legal preflight clears an unprepared retry key',async()=>{
 const gateway=require('../assets/branch-auth.js'),state=new Map();const storage={getItem:k=>state.get(k)||null,setItem:(k,v)=>state.set(k,v),removeItem:k=>state.delete(k)};
 const client={auth:{getUser:async()=>({data:{user:null}})},functions:{invoke:async()=>({data:{error:'Network error'}})}};
 const body={email:'test@example.invalid',password:'test-password',gym_token:'gym',action:'signup'};
 await assert.rejects(gateway.provision(client,storage,'iv-branch-auth',body),/Network/);assert.equal(state.size,1);
 client.functions.invoke=async()=>({data:{error:'LEGAL_REVIEW_REQUIRED: refresh documents'}});await assert.rejects(gateway.provision(client,storage,'iv-branch-auth',body),/LEGAL_REVIEW_REQUIRED/);assert.equal(state.size,0);
});
