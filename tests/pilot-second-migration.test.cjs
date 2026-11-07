/* SQL artifact invariants only. These checks do not execute or validate a live migration. */
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const sql=fs.readFileSync('supabase/migrations/202611080045_pilot_refund_references_notices.sql','utf8');
test('manual 045 copy matches the numbered review migration',()=>{assert.equal(fs.readFileSync('supabase/manual/pilot_refund_references_notices.sql','utf8'),sql);});
test('045 preserves the prior refund engine and cannot directly mutate balances or the ledger',()=>{
 assert.match(sql,/RENAME TO refunds_045_base/);assert.match(sql,/result:=ironvault_private.refunds_045_base\(p_tenant,p_action,p_id,p_payload,p_review\)/);
 assert.doesNotMatch(sql,/(?:UPDATE|DELETE FROM|INSERT INTO)\s+(?:public\.)?(?:members|iv_financial_transactions|iv_activity_logs)\b/i);
 assert.match(sql,/REVOKE ALL ON FUNCTION.*refunds_045_base/s);assert.match(sql,/045 already installed; do not reapply/);
});
test('generated payouts retain authority, lock order, identity and legacy reference collision protection',()=>{
 const wrapper=sql.split('CREATE FUNCTION public.iv_refunds')[1];
 assert(wrapper.indexOf("staff_require(p_tenant,'refund_approve')")<wrapper.indexOf('SELECT * INTO r'));
 assert(wrapper.indexOf("pg_advisory_xact_lock")<wrapper.indexOf('SELECT * INTO r'));
 assert.match(wrapper,/r\.tenant_id<>p_tenant/);assert.match(wrapper,/IF r.status='pending' THEN/);assert.match(wrapper,/transaction_reference\(p_tenant,'payout',r.id\)/);
 assert.match(sql,/c.tenant_id=p_tenant AND c.payout_reference=ref/);
});
test('notices only follow transitions and public rejection text never borrows the internal decision reason',()=>{
 const trigger=sql.split('CREATE FUNCTION ironvault_private.refund_member_notice_045()')[1].split('CREATE TRIGGER')[0];
 assert.match(trigger,/OLD.status<>'pending' OR NEW.status=OLD.status/);assert.match(trigger,/'refund:'\|\|NEW.id/);assert.match(trigger,/'refund-rejected:'\|\|NEW.id/);
 assert.match(trigger,/Cash payout reference: '\|\|NEW.payout_reference/);assert.match(trigger,/NEW.member_decision_reason/);assert.doesNotMatch(trigger,/NEW.decision_reason\b/);
 assert.match(sql,/AFTER UPDATE OF status/);assert.match(sql,/member_decision_reason IS NULL OR length\(member_decision_reason\)<=500/);
});
