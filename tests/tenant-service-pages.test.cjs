const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{stripTypeScriptTypes}=require('node:module');
const read=p=>fs.readFileSync(p,'utf8'),sql=read('supabase/manual/tenant_service_pages.sql'),cleanup=read('supabase/manual/remove_test_service_pdfs.sql');
test('038/039 manual SQL equals migrations and cleanup preserves approved numeric policy, amount and dates',()=>{
 assert.equal(sql,read('supabase/migrations/202611050038_tenant_service_pages.sql'));assert.equal(cleanup,read('supabase/migrations/202611050039_remove_test_service_pdfs.sql'));
 assert.match(cleanup,/storage.objects WHERE bucket_id='iv-service-documents'/);assert.doesNotMatch(cleanup,/DELETE FROM storage\.|DELETE FROM public\.|TRUNCATE|DROP TABLE/);
 assert.match(cleanup,/subscription_periods p SET version_id=m.new_id/);assert.doesNotMatch(cleanup,/SET amount|SET start_date|SET end_date|SET policy/);
 assert.match(cleanup,/DELETE FROM ironvault_private.service_acceptances WHERE version_id IN/);assert.match(cleanup,/document_format='pdf'/);assert.match(cleanup,/true FROM iv_test_pdf_replacements/);
});
test('personalized acceptance binds exact review hash, registered owner and immutable tenant snapshots',()=>{
 assert.match(sql,/p_data->>'review_hash' IS DISTINCT FROM doc->>'review_hash'/);assert.match(sql,/FOR UPDATE;\n   PERFORM 1 FROM ironvault_private.legal_settings/);
 assert.match(sql,/accepted_documents=doc.*accepted_documents IS NULL/);assert.match(sql,/a.tenant_id=p_tenant AND a.owner_id=s.owner_id AND a.version_id=v.id/);
 assert.match(sql,/owner_id=auth.uid\(\) OR provider/);assert.match(sql,/REVOKE ALL ON FUNCTION ironvault_private.subscription_portal_038_base.*authenticated/);
 assert.match(sql,/WHERE NOT v.retired AND v.document_format='text'/);
});
test('renewals resolve covered old reminders while announcements and other tenants are excluded',()=>{
 assert.match(sql,/IF r.kind='payment' THEN/);assert.match(sql,/n.tenant_id=p_tenant AND n.notice_key LIKE old.id\|\|':%'/);assert.match(sql,/old.id<>new.id AND old.end_date<new.end_date/);
 assert.match(sql,/n.notice_key ~ ':\(reminder:\|expiry\|suspend\|lastgrace\|retention\)'/);assert.match(sql,/subscription_portal_038_base\(p_tenant,p_action,p_data\)/);
});
test('future gyms default Live; current gyms are Test without changing access rules',()=>{
 assert.match(sql,/is_test boolean NOT NULL DEFAULT false/);assert.match(sql,/UPDATE ironvault_private.gym_subscriptions SET is_test=true/);
 assert.doesNotMatch(sql,/CREATE OR REPLACE FUNCTION ironvault_private.subscription_(state|require)/);
 assert.match(sql,/WHERE NOT s.is_test AND p.kind='paid'/);assert.match(sql,/subscription_events.*tenant_tag/);
});
test('announcements require global Provider, freeze recipients and never return recipient lists to owners',()=>{
 const consoleSQL=sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION public.iv_provider_console'),sql.indexOf('CREATE OR REPLACE FUNCTION public.iv_service_documents'));
 assert.match(consoleSQL,/IF NOT ironvault_private.subscription_super\(\)/);assert.match(consoleSQL,/selection='live'.*WHERE NOT is_test AND owner_id IS NOT NULL/);
 assert.match(consoleSQL,/requested_targets=coalesce\(p_data->'tenants'/);assert.match(consoleSQL,/INSERT INTO ironvault_private.provider_announcement_targets VALUES\(ann,r.tenant_id,r.owner_id\)/);
 assert.match(consoleSQL,/n.owner_id=t.owner_id/);const ownerSQL=sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION public.iv_subscription_portal'),sql.indexOf('CREATE OR REPLACE FUNCTION public.iv_provider_console'));assert.doesNotMatch(ownerSQL,/provider_announcement_targets/);
});
test('document publication protects stale drafts, retries, explicit review and notice periods',()=>{
 assert.match(sql,/s.revision IS DISTINCT FROM \(p_data->>'__revision'\)::uuid/);assert.match(sql,/p_data->>'__reviewed' IS DISTINCT FROM 'true'/);
 assert.match(sql,/publication_request=request_uuid AND source_draft=source_uuid/);assert.match(sql,/effective_date=effective AND data=\(p_data-/);
 assert.match(sql,/greatest\(30,coalesce\(max\(\(policy->>'price_notice_days'/);assert.match(sql,/documents-effective:/);
});
function edge(overrides={}){let handler;const context={Error,RegExp,String,console,Deno:{env:{get:()=>''}},serve:fn=>handler=fn,actor:async()=>({id:'provider'}),role:async()=>({role:'super_admin',tenant_id:null}),limit:async()=>{},createScopedClient:()=>({rpc:async()=>({data:{allowed:true}})}),...overrides};vm.runInNewContext(stripTypeScriptTypes(read('supabase/functions/iv-cleanup-test-pdfs/index.ts')).replace(/^import.*;$/gm,'').replace(/^export /gm,''),context);return(...args)=>context.cleanupTestPDFs(...args);}
test('test PDF cleanup refuses non-Provider callers and missing explicit confirmation before touching storage',async()=>{
 const request={headers:{get:()=> 'Bearer test'}};let writes=0;const admin={storage:{from:()=>{writes++;throw Error('must not reach storage');}}};
 await assert.rejects(edge({admin,role:async()=>({role:'owner',tenant_id:'gym'})})(request,{confirmation:'DELETE TEST SERVICE PDFS'}),/Not authorized/);
 await assert.rejects(edge({admin})(request,{}),/Type DELETE/);assert.equal(writes,0);
 await assert.rejects(edge({admin,createScopedClient:()=>({rpc:async()=>({error:{message:'not permitted'}})})})(request,{confirmation:'DELETE TEST SERVICE PDFS'}),/unavailable/);assert.equal(writes,0);
});
test('cleanup deletes only the dedicated bucket through Storage API in resumable bounded batches',async()=>{
 let files=Array.from({length:105},(_,i)=>({id:'object-'+i,name:'00000000-0000-4000-8000-'+String(i).padStart(12,'0')+'.pdf'})),deleted=0,bucketDeleted=false;const paths=[];
 const admin={storage:{from:name=>{assert.equal(name,'iv-service-documents');return{list:async(prefix,{limit})=>({data:prefix==='documents'?files.slice(0,limit):[]}),remove:async names=>{paths.push(...names);deleted+=names.length;files=files.slice(names.length);return{error:null};}};},deleteBucket:async name=>{assert.equal(name,'iv-service-documents');bucketDeleted=true;return{error:null};}}};
 const invoke=edge({admin}),request={headers:{get:()=> 'Bearer test'}},body={confirmation:'DELETE TEST SERVICE PDFS'};
 const first=await invoke(request,body);assert.equal(first.complete,false);assert.equal(deleted,100);assert.equal(bucketDeleted,false);
 const second=await invoke(request,body);assert.equal(second.complete,true);assert.equal(deleted,105);assert.equal(bucketDeleted,true);assert(paths.every(p=>p.startsWith('documents/')));
});
test('cleanup refuses unexpected stored objects rather than deleting unrelated files',async()=>{
 let removed=false;const admin={storage:{from:()=>({list:async()=>({data:[{id:'a',name:'unexpected.txt'}]}),remove:async()=>{removed=true;}})}};
 await assert.rejects(edge({admin})({headers:{get:()=>''}},{confirmation:'DELETE TEST SERVICE PDFS'}),/Unexpected bucket/);assert.equal(removed,false);
});
test('quote patch excludes retired PDFs and changes only agreement selection, preserving original dates and pricing',()=>{
 const historical=read('supabase/manual/gym_subscriptions.sql');const extract=s=>{const start=s.indexOf('CREATE OR REPLACE FUNCTION ironvault_private.subscription_quote(');return s.slice(start,s.indexOf('END $fn$;',start)+10);};
 let expected=extract(historical).replace("version_id:=tail.version_id;","version_id:=CASE WHEN EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE id=tail.version_id AND NOT retired AND document_format='text') THEN tail.version_id ELSE ironvault_private.service_current() END;\n  IF version_id IS NULL THEN RAISE EXCEPTION 'Service documents must be published first';END IF;").replace('WHERE effective_date<=startday ORDER BY',"WHERE NOT retired AND document_format='text' AND effective_date<=startday ORDER BY");
 assert.equal(extract(sql),expected);
});
test('periodic notification refresh returns only count/setup metadata rather than full document pages',()=>{
 const ownerBadge=sql.slice(sql.indexOf("IF p_action IN ('notifications','badge')"),sql.indexOf(" IF p_action='submit_reference'"));
 assert.match(ownerBadge,/'state',ironvault_private.subscription_state\(p_tenant\)/);assert.match(ownerBadge,/'current_version',ironvault_private.service_current\(\)/);assert.match(ownerBadge,/'unread_count'/);assert.doesNotMatch(ownerBadge,/tenant_service_documents|terms_text|provider_announcement_targets/);
 const providerBadge=sql.slice(sql.indexOf("IF p_action='badge' THEN"),sql.indexOf(" IF p_action='tag' THEN"));assert.match(providerBadge,/'unread'/);assert.doesNotMatch(providerBadge,/terms_text|provider_announcement_targets/);
});
