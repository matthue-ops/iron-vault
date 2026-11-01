/* Generate the owner-run 018-020 delta; never executes SQL. */
const fs=require('node:fs'),path=require('node:path');const root=path.resolve(__dirname,'..');
const names=['202611010018_short_display_codes.sql','202611010019_staff_without_confirmation.sql','202611010020_clear_report_snapshots.sql'];
let sql='-- MANUAL SQL EDITOR UPDATE: only for a database with migrations 001-017 applied.\n-- Installs short display codes, optional staff confirmation, and report metadata.\n-- No internal IDs, credentials, tenant links, balances or history are replaced.\n-- Select/run the ENTIRE file once. Do not rerun the initial installation package.\nBEGIN;\n';
for(const name of names)sql+='\n-- '+name+'\n'+fs.readFileSync(path.join(root,'supabase/migrations',name),'utf8').replace(/^BEGIN;\s*$/gm,'').replace(/^COMMIT;\s*$/gm,'');
sql+='\nCOMMIT;\n';const output=path.join(root,'supabase/manual/usability_update.sql');
if(process.argv.includes('--check')){if(fs.readFileSync(output,'utf8')!==sql)throw Error('Usability SQL is stale.');}else fs.writeFileSync(output,sql);
console.log('Usability SQL '+(process.argv.includes('--check')?'matches sources.':'generated; not executed.'));
