const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const accent=require('../assets/gym-accent.js');
test('accent validates CSS input and picks readable text for light and dark accents',()=>{
 assert.equal(accent.color('red;display:none'),'#10b981');assert.equal(accent.color('#AbCdEf'),'#abcdef');
 assert.equal(accent.ink('#ffffff'),'#000000');assert.equal(accent.ink('#000000'),'#ffffff');
});
function fixture(){
 const nodes=new Map(),vars={};
 const get=id=>{if(!nodes.has(id))nodes.set(id,{value:'',textContent:'',style:{},disabled:false,classList:{contains:()=>false}});return nodes.get(id);};
 const root={document:{getElementById:get,documentElement:{style:{setProperty:(k,v)=>vars[k]=v}}},calls:[]};
 root.IronVaultData={call:async(c,name,args)=>{root.calls.push({name,args});return args.p_color.toLowerCase();}};
 vm.runInNewContext(fs.readFileSync('assets/gym-accent.js','utf8'),root);
 const app={owners:[{id:'a',accentColor:'#123456'},{id:'b',accentColor:'#abcdef'}],openEditModal(){},liveUpdates:{hold:()=>()=>{}}};
 root.IronVaultGymAccent.installMaster(app,{});return{root,app,get,vars};
}
test('master preview is local, reset requires save, and saving scopes the exact tenant',async()=>{
 const {root,app,get}=fixture();app.openEditModal('a');assert.equal(get('gym-accent-picker').value,'#123456');
 get('gym-accent-picker').value='#ffffff';get('gym-accent-picker').oninput();assert.equal(root.calls.length,0);assert.equal(get('gym-accent-preview').style.color,'#000000');
 app.openEditModal('a');assert.equal(get('gym-accent-picker').value,'#ffffff'); // live refresh preserves draft
 get('gym-accent-reset').onclick();assert.equal(root.calls.length,0);assert.equal(get('gym-accent-picker').value,'#10b981');
 await get('gym-accent-save').onclick();assert.equal(root.calls[0].name,'iv_set_gym_accent');assert.equal(root.calls[0].args.p_tenant,'a');assert.equal(app.owners[1].accentColor,'#abcdef');
 app.openEditModal('b');assert.equal(get('gym-accent-picker').value,'#abcdef');
 root.IronVaultData.call=async()=>{throw Error('Access denied');};await get('gym-accent-save').onclick();assert.match(get('gym-accent-status').textContent,/not saved.*Access denied/);assert.equal(get('gym-accent-save').disabled,false);
});
test('admin applies stored color and disables asynchronous logo overrides',()=>{
 const {root,vars}=fixture();let calls=0;const app={applyBranding(){calls++;}};
 root.IronVaultGymAccent.installAdmin(app);app.applyBranding({accentColor:'#000000'});root.applyDynamicThemeFromLogo('logo');
 assert.equal(calls,1);assert.equal(vars['--brand-primary'],'#000000');assert.equal(vars['--brand-ink'],'#ffffff');
 app.applyBranding({});assert.equal(vars['--brand-primary'],'#10b981');
});
test('migration limits writes to enabled global Super Admin and preserves existing visibility',()=>{
 const sql=fs.readFileSync('supabase/migrations/202611040028_gym_accent_colors.sql','utf8');
 assert.equal(sql,fs.readFileSync('supabase/manual/gym_accent_colors.sql','utf8'));
 for(const part of ["r.user_id=auth.uid()","r.role='super_admin'","r.tenant_id IS NULL","r.enabled AND r.disabled_at IS NULL","SET search_path=''","FROM public.iv_visible_gyms() visible","WHERE id=p_tenant","FROM PUBLIC,anon,authenticated,service_role"])assert.ok(sql.includes(part),part);
 assert.equal(/DELETE FROM|TRUNCATE|DROP TABLE/i.test(sql),false);
});
