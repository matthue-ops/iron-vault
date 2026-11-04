const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('docs/legal/member-portal-source-draft.md','utf8').replace(/\r\n/g,'\n');
const terms=fs.readFileSync('docs/legal/terms-template.md','utf8'),privacy=fs.readFileSync('docs/legal/privacy-template.md','utf8');
test('full legal templates retain every numbered section and original substantive paragraphs',()=>{
 for(const [text,title] of [[terms,'Terms of Service'],[privacy,'Privacy Notice']]){assert.equal((text.match(/^### \d+\./gm)||[]).length,12,title);for(let n=1;n<=12;n++)assert.ok(text.includes('### '+n+'.'),title+' '+n);}
 const originalTerms=source.split('## Draft Member Portal Terms of Service\n\n')[1].split('\n---')[0];
 const originalPrivacy=source.split('## Draft Member Portal Privacy Notice\n\n')[1].split('\n---')[0];
 const normalize=s=>s.replace(/\[privacy.gov.ph\]\(https:\/\/privacy.gov.ph\)/g,'privacy.gov.ph').replace(/\[[^\]]*\]|\{\{[^}]*\}\}/g,'FIELD').replace('Before publication, complete the actual schedule:','The applicable retention schedule is:').trim();
 assert.equal(normalize(terms),normalize(originalTerms));assert.equal(normalize(privacy),normalize(originalPrivacy));
});
test('new renderer stores complete templates per new version and leaves existing versions and receipts untouched',()=>{
 const sql=fs.readFileSync('supabase/manual/full_legal_documents.sql','utf8');assert.equal(sql,fs.readFileSync('supabase/migrations/202611040031_full_legal_documents.sql','utf8'));
 assert.ok(sql.includes(terms.trim()));assert.ok(sql.includes(privacy.trim()));assert.ok(sql.includes("'_template_format',2"));assert.ok(sql.includes('render_full_legal_v2'));assert.ok(sql.includes('fill_legal_tokens_v2'));
 assert.equal(/UPDATE ironvault_private.legal_versions|UPDATE ironvault_private.legal_acceptances|DELETE FROM|ALTER TABLE/i.test(sql),false);
 assert.ok(sql.includes("scope='platform'"));assert.ok(sql.includes('scope=tenant'));assert.ok(sql.includes("'documents',documents"));
});
test('gym and platform editors expose only the appropriate bracket detail rows',()=>{
 const root={URLSearchParams};vm.runInNewContext(fs.readFileSync('assets/legal-documents.js','utf8'),root);const {gymFields,platformFields}=root.IronVaultLegal;
 const gym=gymFields.map(f=>f[0]),platform=platformFields.map(f=>f[0]);
 for(const key of ['effective_date','notice_version','privacy_name','notification_method','retention_profile','retention_attendance','retention_financial','retention_security','retention_backups','refund_policy','age_policy'])assert.ok(gym.includes(key),key);
 assert.equal(gym.includes('providers'),false);assert.equal(gym.includes('terms_extra'),false);assert.equal(platform.includes('retention_attendance'),false);assert.ok(platform.includes('overseas_info'));
});
