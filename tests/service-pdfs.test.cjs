const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{stripTypeScriptTypes}=require('node:module');
test('037 remains an exact historical installer; 038 denies retired PDF APIs and viewing',()=>{
 const old=fs.readFileSync('supabase/manual/pdf_service_documents.sql','utf8'),next=fs.readFileSync('supabase/manual/tenant_service_pages.sql','utf8');assert.equal(old,fs.readFileSync('supabase/migrations/202611050037_pdf_service_documents.sql','utf8'));
 assert.match(next,/REVOKE EXECUTE ON FUNCTION public.iv_service_pdf_settings/);assert.match(next,/REVOKE EXECUTE ON FUNCTION public.iv_service_pdf_register/);assert.match(next,/SELECT false/);
 for(const page of ['gym/index.html','gym/admin.html'])assert.doesNotMatch(fs.readFileSync(page,'utf8'),/service-pdfs.js/);
});
test('retired deployed upload entry cannot parse or store any files',async()=>{let handler;const context={Error,serve:fn=>handler=fn};vm.runInNewContext(stripTypeScriptTypes(fs.readFileSync('supabase/functions/iv-service-pdf/index.ts','utf8')).replace(/^import.*;$/gm,''),context);await assert.rejects(handler(),/Invalid request/);});
