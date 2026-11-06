const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const sql=fs.readFileSync('supabase/manual/owner_agreement_acknowledgment.sql','utf8'),ui=require('../assets/subscriptions.js');
test('040 is an additive manual migration, reusing acceptance identity/snapshots and keeping historical wording honest',()=>{
 assert.equal(sql,fs.readFileSync('supabase/migrations/202611060040_owner_agreement_acknowledgment.sql','utf8'));
 assert.doesNotMatch(sql,/DELETE FROM|TRUNCATE|DROP TABLE|UPDATE ironvault_private.subscription_periods|INSERT INTO ironvault_private.subscription_periods/);
 for(const column of ['agreement_type','document_versions','acceptance_method','acknowledgment_text'])assert.match(sql,new RegExp('ADD COLUMN '+column));
 const backfill=sql.slice(sql.indexOf('UPDATE ironvault_private.service_acceptances a'),sql.indexOf('CREATE FUNCTION ironvault_private.owner_agreement_valid'));
 assert.match(backfill,/legacy_recorded_owner_acceptance/);assert.doesNotMatch(backfill,/accepted_at=|acknowledgment_text=/);
});
test('new receipt text matches the exact required client acknowledgment and records server-defined evidence',()=>{
 const expected='I confirm that I am authorized to represent this Gym, have reviewed the documents listed above, and agree to the applicable Terms of Use, Data Processing Agreement, and Free Pilot Conditions. I acknowledge receipt of the Privacy Notice.';
 assert.equal(ui.ownerAcknowledgment,expected);assert.match(sql,/p_data->>'acknowledgment_text' IS DISTINCT FROM acknowledgment/);assert.ok(sql.includes("acknowledgment constant text:='"+expected+"'"));
 assert.match(sql,/acceptance_method='dashboard_checkbox',acknowledgment_text=acknowledgment/);
 for(const key of ['terms_of_use','privacy_notice','data_processing_agreement','free_pilot_conditions'])assert.ok(sql.includes("'"+key+"'"));
 assert.match(sql,/'incorporated_into','terms_of_use'/);
});
test('staff and Provider cannot accept as an owner, and private legacy routes cannot bypass the public gate',()=>{
 assert.match(sql,/owner:=ironvault_private.subscription_owner\(p_tenant\)/);assert.match(sql,/IF NOT owner THEN RAISE EXCEPTION 'Only the registered owner account/);
 assert.match(sql,/REVOKE ALL ON FUNCTION ironvault_private.subscription_portal_040_base.*authenticated,service_role/);
 assert.match(sql,/GRANT EXECUTE ON FUNCTION public.iv_subscription_portal.*TO authenticated/);
 assert.match(sql,/WHERE tenant_id=p_tenant AND owner_id=auth.uid\(\) AND version_id=bundle.id/);
});
test('repeat acceptance preserves the original receipt and does not reactivate or duplicate pilot access',()=>{
 const branch=sql.slice(sql.indexOf('  IF FOUND THEN'),sql.indexOf("  IF p_data->>'accepted'"));assert.match(branch,/owner_agreement_valid/);assert.match(branch,/RETURN ironvault_private.subscription_portal_040_base\(p_tenant,'get','\{\}'\)/);assert.doesNotMatch(branch,/UPDATE |INSERT /);
 const acceptance=sql.slice(sql.indexOf(" IF p_action='accept' THEN"),sql.indexOf(" ELSIF p_action='activate_pilot'"));assert.doesNotMatch(acceptance,/activate_pilot|subscription_periods|SET pilot_used/);assert.match(acceptance,/subscription_portal_040_base\(p_tenant,'accept',p_data\)/);
});
test('manual activation requires Provider authority and valid current owner evidence, preserving completed retries',()=>{
 const activation=sql.slice(sql.indexOf(" ELSIF p_action='activate_pilot'"));assert.match(activation,/IF NOT provider THEN/);assert.match(activation,/owner_agreement_valid\(p_tenant,subscription.owner_id,ironvault_private.service_current\(\)\)/);assert.match(activation,/kind='pilot'/);
 const base=fs.readFileSync('supabase/manual/gym_subscriptions.sql','utf8');assert.match(base,/reviewed_business/);assert.match(base,/Registered owner must accept current service documents first/);assert.match(base,/Publish gym and platform member documents first/);
});
test('receipt validity binds immutable snapshots and all document references; optional payments stay separate',()=>{
 assert.match(sql,/a.accepted_documents->>'id'=v.id::text/);assert.match(sql,/a.document_versions=ironvault_private.owner_agreement_document_refs\(v.id\)/);assert.match(sql,/a.tenant_id=p_tenant AND a.owner_id=p_owner AND a.version_id=p_version/);
 const base=fs.readFileSync('supabase/manual/gym_subscriptions.sql','utf8');assert.match(base,/p_action='confirm_plan'.*Registered owner must explicitly confirm the plan/s);
 assert.doesNotMatch(sql,/CREATE.*subscription_state|CREATE.*subscription_quote|UPDATE public\.|ALTER TABLE public\./);
});
