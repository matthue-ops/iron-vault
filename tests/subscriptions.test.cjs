const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const sql=fs.readFileSync('supabase/manual/gym_subscriptions.sql','utf8');
const section=name=>{const start=sql.indexOf('FUNCTION '+name+'(');assert.ok(start>=0,name);return sql.slice(start,sql.indexOf('$fn$;',start)+6)};
test('035 manual copy is exact, requires 034 and makes no destructive business-history changes',()=>{
 assert.equal(sql,fs.readFileSync('supabase/migrations/202611050035_gym_subscriptions.sql','utf8'));assert.match(sql,/Apply migrations 033 and 034 first/);
 assert.doesNotMatch(sql,/DELETE FROM|TRUNCATE|DROP TABLE|UPDATE public\.members SET|ALTER TABLE public\.members/);
 assert.match(sql,/Existing gyms become setup-only/);assert.match(sql,/No automatic deletion is performed/);
});
test('subscription authority is fixed to registered owner and explicit global Super Admin',()=>{
 assert.match(section('ironvault_private.subscription_owner'),/s.owner_id=auth.uid\(\).*r.role='owner'/s);
 assert.match(section('ironvault_private.subscription_super'),/role='super_admin' AND tenant_id IS NULL AND enabled AND disabled_at IS NULL/);
 assert.match(section('public.iv_subscription_portal'),/Only the registered owner may accept/);
 assert.match(section('public.iv_subscription_portal'),/Registered owner must explicitly confirm/);
 assert.match(section('public.iv_subscription_portal'),/WHEN owner THEN/);
 assert.match(sql,/REVOKE ALL ON ironvault_private/);assert.match(sql,/ENABLE ROW LEVEL SECURITY/);
});
test('pilot activates only after member documents and exact current owner service acceptance',()=>{
 const f=section('public.iv_subscription_portal');assert.match(f,/version_id=current_id/);assert.match(f,/Publish gym and platform member documents first/);assert.match(f,/Review first-pilot business eligibility/);
 assert.match(f,/s.pilot_used/);assert.match(sql,/UNIQUE INDEX iv_one_pilot_per_gym/);assert.match(f,/t,t\+1,t\+\(v.data->>'pilot_days'\)::integer,0/);
});
test('paid date calculations preserve pilot and early-renewal days, distinguish grace from fresh late activation',()=>{
 const f=section('ironvault_private.subscription_quote');assert.match(f,/t<=tail.end_date THEN tail.end_date\+1/);assert.match(f,/t<=tail.end_date\+tail.grace_days THEN tail.end_date\+1 ELSE t\+1/);
 assert.match(f,/finish:=startday\+\(policy->>'paid_days'\)::integer-1/);assert.match(f,/accessday:=startday/);
 const state=section('ironvault_private.subscription_state');assert.match(state,/p.kind='paid' AND t>p.end_date AND t<=p.end_date\+p.grace_days/);assert.match(state,/'portal',t<=p.end_date AND p.plan='portal'/);
});
test('server quotes bind owner confirmation to exact amount/dates, approved requests are replay-safe',()=>{
 const f=section('public.iv_subscription_portal');assert.match(f,/quote IS DISTINCT FROM p_data->'quote'/);assert.match(f,/quote IS DISTINCT FROM req.quote/);assert.match(f,/req.approved_at IS NOT NULL THEN RETURN/);
 assert.match(f,/Quote dates or amount changed/);assert.match(f,/version_id=\(quote->>'version_id'\)::uuid/);
 assert.match(section('ironvault_private.subscription_quote'),/round\(\(\(policy->>'portal_price'\)::numeric-\(policy->>'dashboard_price'\)::numeric\)\*\(finish-t\+1\)\/\(policy->>'paid_days'\)::numeric,2\)/);
});
test('database enforcement covers member login, tickets, manual/QR entry, transactions, staff and raw member reads',()=>{
 assert.match(section('public.iv_prepare_branch_account'),/CASE WHEN p_actor IS NULL THEN 'portal' ELSE 'operations'/);
 assert.match(section('public.iv_finish_branch_account'),/CASE WHEN job.actor_id IS NULL THEN 'portal' ELSE 'operations'/);
 assert.match(section('public.iv_branch_identity'),/a.role='member'.*subscription_state.*portal/s);
 assert.match(section('public.iv_issue_member_pass'),/subscription_require\(m.tenant_id,'portal'\)/);
 for(const relation of ['public.members','public.iv_financial_transactions','public.iv_attendance_logs','public.owners','public.iv_announcements','ironvault_private.staff_report_permissions'])assert.ok(sql.includes('ON '+relation+' FOR EACH ROW EXECUTE FUNCTION ironvault_private.subscription_write_guard()'),relation);
 assert.match(sql,/AS RESTRICTIVE FOR SELECT TO authenticated/);assert.match(section('ironvault_private.subscription_write_guard'),/rowdata->>'method'='qr'/);
});
test('service publication keeps immutable versions, validates fields and enforces price notice',()=>{
 const f=section('public.iv_service_documents');assert.match(f,/Super Admin required/);assert.match(f,/Complete field before publication/);assert.match(f,/price_notice_days/);assert.match(f,/effective<ironvault_private.subscription_today\(\)\+greatest\(30/);
 assert.match(f,/Existing approved paid periods are preserved|Approved paid periods are preserved/);assert.doesNotMatch(f,/UPDATE ironvault_private.service_versions|UPDATE ironvault_private.service_acceptances/);
 const config=JSON.parse(fs.readFileSync('config/service-agreement.json','utf8'));const defaults=Object.fromEntries(config.fields.map(f=>[f.key,f.default]));
 const embedded=JSON.parse(sql.match(/\$defaults\$([\s\S]*?)\$defaults\$/)[1]);assert.deepEqual(embedded,defaults);
 assert.equal(defaults.provider_name,'Matt Hue');assert.equal(defaults.pilot_days,14);assert.equal(defaults.paid_days,30);assert.equal(defaults.grace_days,7);assert.equal(defaults.dashboard_price,999);assert.equal(defaults.portal_price,1800);
 assert.equal(defaults.address,'');assert.equal(defaults.refund_policy,'');assert.equal(defaults.providers,'');
 for(const field of config.fields)assert.ok(field.help.length>20);assert.match(defaults._terms_template,/26\. LAW/);assert.match(defaults._privacy_template,/12\. VERSIONS/);assert.match(defaults._dpa_template,/12\. CONFLICTS/);
});
test('owner notifications persist due dates with unique keys and exclude staff/private data from public status',()=>{
 assert.match(sql,/PRIMARY KEY\(tenant_id,notice_key\)/);assert.match(section('ironvault_private.subscription_notice'),/ON CONFLICT DO NOTHING/);
 assert.match(section('ironvault_private.subscription_schedule'),/ARRAY\[7,3,1\]/);assert.match(section('public.iv_subscription_portal'),/owner_id=auth.uid\(\) AND available_at<=now\(\)/);
 const pub=section('public.iv_subscription_public');assert.doesNotMatch(pub,/owner_id|amount|reference|notifications|draft/);
});

test('internal state and billing remain private and super inspection is preserved by the scoped RLS helper',()=>{
 assert.doesNotMatch(sql,/GRANT EXECUTE ON FUNCTION ironvault_private.subscription_state/);
 assert.match(sql,/USING\(ironvault_private.subscription_can_read\(tenant_id,member_id\)/);
 assert.match(section('ironvault_private.subscription_can_read'),/SELECT ironvault_private.subscription_super\(\) OR EXISTS/);
 assert.match(section('ironvault_private.subscription_require'),/p_actor IS NOT NULL AND NOT EXISTS/);
 assert.match(sql,/iv_subscription_payment_reference_unique/);assert.match(sql,/gym_snapshot jsonb NOT NULL,owner_snapshot jsonb NOT NULL/);
});

test('036 fixes SQL variable/column collisions without reinstalling subscription tables or touching records',()=>{
 const patch=fs.readFileSync('supabase/manual/fix_subscription_sql_names.sql','utf8');assert.equal(patch,fs.readFileSync('supabase/migrations/202611050036_fix_subscription_sql_names.sql','utf8'));
 assert.doesNotMatch(patch,/CREATE TABLE|ALTER TABLE|DROP |DELETE FROM|TRUNCATE|GRANT |REVOKE /);
 assert.doesNotMatch(patch,/;id uuid;/);assert.match(patch,/published_version_id uuid/);assert.match(patch,/request_id_value uuid/);
 assert.match(patch,/FROM ironvault_private.subscription_periods period_row/);assert.doesNotMatch(patch,/to_jsonb\(p\) ORDER BY start_date/);
 for(const name of ['public.iv_service_documents','public.iv_subscription_portal']){const start=patch.indexOf('FUNCTION '+name+'(');assert.ok(start>=0);assert.equal(patch.slice(start,patch.indexOf('$fn$;',start)+6),section(name));}
});
