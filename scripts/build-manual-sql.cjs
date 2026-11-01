/* Build a reviewable atomic SQL Editor artifact. Never executes SQL. */
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),directory=path.join(root,'supabase/migrations');
const files=fs.readdirSync(directory).filter(n=>/^2026110100\d{2}_.*\.sql$/.test(n)).sort();
if(files.length!==17)throw Error('Expected exactly the reviewed 001-017 migration package; review generator for new versions.');
const included=files.filter(n=>!n.startsWith('202611010004_'));
const snapshot=`SELECT jsonb_build_object(
 'auth', (SELECT md5(coalesce(string_agg(jsonb_build_array(id,email,email_confirmed_at)::text,'|' ORDER BY id),'')) FROM auth.users),
 'roles', (SELECT md5(coalesce(string_agg(jsonb_build_array(user_id,tenant_id,role,member_id)::text,'|' ORDER BY user_id),'')) FROM public.iv_user_roles),
 'members', (SELECT md5(coalesce(string_agg(jsonb_build_array(id,tenant_id,wallet_balance,amount,plan,expiration_date,scans_used,last_scanned_date,status)::text,'|' ORDER BY id),'')) FROM public.members),
 'gyms', (SELECT md5(coalesce(string_agg(jsonb_build_array(id,email,token,status,pricing)::text,'|' ORDER BY id),'')) FROM public.owners),
 'ledger', (SELECT md5(coalesce(string_agg(to_jsonb(x)::text,'|' ORDER BY id),'')) FROM public.iv_financial_transactions x),
 'attendance', (SELECT md5(coalesce(string_agg(to_jsonb(x)::text,'|' ORDER BY id),'')) FROM public.iv_attendance_logs x),
 'activity', (SELECT md5(coalesce(string_agg(to_jsonb(x)::text,'|' ORDER BY id),'')) FROM public.iv_activity_logs x),
 'sessions', (SELECT md5(coalesce(string_agg(to_jsonb(x)::text,'|' ORDER BY id),'')) FROM public.iv_staff_sessions x)
) AS snapshot`;
let sql=`-- IRON VAULT PHASE 1 — MANUAL SQL EDITOR INSTALL, GENERATED FILE.
-- No SQL has been executed by the agent. Review docs/security/phase1-cutover.md.
-- Intended for the inspected schema with NO earlier Phase 1 files applied.
-- If any migrations were already applied, use the remaining individual files;
-- do NOT bypass guards or rerun this complete package blindly.
-- ONE ATOMIC TRANSACTION: failure rolls back this entire package. If SQL Editor
-- reports an error, issue ROLLBACK before another command and return the error.
-- Existing Auth IDs/emails, balances, entitlements, role links and histories are
-- fingerprinted before/after; any difference aborts. Fingerprints are data-drift
-- checks only, not cryptographic authorization. No password hashes are selected.
-- No resets, existing-table/column deletion or account recreation.
-- OPTIONAL 004 is deliberately EXCLUDED: never escalate supabase_admin rights.
-- Its separate file remains available for approved creator-default hardening.
-- This file configures DATABASE objects only, not Edge Function deployment or
-- SMTP secrets. Publish the matching functions/app only after separate approval.
-- Generated deterministically: node scripts/build-manual-sql.cjs
BEGIN;
SET LOCAL search_path=pg_catalog;
CREATE TEMP TABLE iv_phase1_preservation ON COMMIT DROP AS
${snapshot};
`;
for(const name of included){
 const source=fs.readFileSync(path.join(directory,name),'utf8');
 if((source.match(/^BEGIN;\s*$/gm)||[]).length!==1||(source.match(/^COMMIT;\s*$/gm)||[]).length!==1)throw Error('Unexpected transaction formatting: '+name);
 const hash=crypto.createHash('sha256').update(source).digest('hex');
 const body=source.replace(/^BEGIN;\s*$/gm,'').replace(/^COMMIT;\s*$/gm,'');
 sql+=`\n-- ===== SOURCE ${name} SHA256 ${hash} =====\n${body}\n`;
}
sql+=`\n-- Preserve every pre-existing identity/financial/audit row through schema cutover.
DO $preservation$
DECLARE actual jsonb;
BEGIN
 ${snapshot.replace(' AS snapshot','')} INTO actual;
 IF actual IS DISTINCT FROM (SELECT snapshot FROM pg_temp.iv_phase1_preservation) THEN
  RAISE EXCEPTION 'Preservation check failed: entire installation rolled back; do not reset data';
 END IF;
END
$preservation$;
COMMIT;
-- The temporary preservation object is removed on commit; no existing table is dropped.
-- Read-only final acceptance. No business RPC is invoked.
`+fs.readFileSync(path.join(root,'supabase/verification/phase1_acceptance.sql'),'utf8');
const output=path.join(root,'supabase/manual/phase1_security_install.sql');
if(process.argv.includes('--check')){
 if(!fs.existsSync(output)||fs.readFileSync(output,'utf8')!==sql)throw Error('Manual SQL is stale; regenerate it.');
 process.stdout.write('Manual SQL matches all reviewed migration sources.\n');
}else{fs.writeFileSync(output,sql);process.stdout.write('Generated '+path.relative(root,output)+' ('+Buffer.byteLength(sql)+' bytes); no SQL executed.\n');}
