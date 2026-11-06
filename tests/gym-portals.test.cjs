const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const portals=require('../assets/gym-portals.js'),data=require('../assets/application-data.js');
test('readable portal paths accept one safe slug and reject reserved, malformed or nested paths',()=>{
 for(const path of ['/fitness-gym','/fitness-gym/','/wild-card-2'])assert.ok(portals.slugFromPath(path));
 for(const path of ['/gym','/assets','/api','/gym/login.html','/Fitness-Gym','/bad--name','/a/b','/%ZZ','/a%2Fb','/a%3Fb','/','/gym-','/-gym','/'+('a'.repeat(97))])assert.equal(portals.slugFromPath(path),null,path);
});
test('both master entry points construct origin-rooted friendly URLs and retain encoded legacy links',()=>{
 for(const path of ['/index.html','/gym/index.html']){
  const location={href:'https://example.invalid'+path};assert.equal(portals.url({portalSlug:'fitness-gym',token:'old'},location),'https://example.invalid/fitness-gym');
  assert.equal(portals.url({token:'a&b/#'},location),'https://example.invalid/gym/login.html?key=a%26b%2F%23');
  assert.match(portals.url({portalSlug:'../admin',token:'valid'},location),/login.html\?key=valid$/);
 }
});
test('displayed links use assigned names, never guessed gym names',()=>{
 assert.equal(portals.label({gymName:'Renamed Gym',portalSlug:'original-gym'}),'/original-gym');
 assert.match(portals.label({gymName:'Fitness Gym',token:'oldtoken'}),/login.html\?key=oldtoken/);
 assert.equal(portals.page('profile.html'),'/gym/profile.html');assert.equal(portals.page('admin.html?key=abc'),'/gym/admin.html?key=abc');assert.throws(()=>portals.page('../admin.html'));
});
test('master loader carries the saved slug while profile writes cannot rename URLs',async()=>{
 const loaded=await data.loadMaster({from:table=>({select:async()=>({data:table==='owners'?[{id:'gym-a',gym_name:'Renamed',token:'old',portal_slug:'fitness-gym'}]:[]})})});
 assert.equal(loaded.owners[0].portalSlug,'fitness-gym');assert.equal('portal_slug' in data.gym(loaded.owners[0]),false);
});
test('routing preserves existing files before matching only single-segment gym names',()=>{
 const config=JSON.parse(fs.readFileSync('vercel.json'));assert.deepEqual(config.routes[0],{handle:'filesystem'});
 const route=config.routes[1],re=new RegExp(route.src);assert.equal(route.dest,'/gym/login.html');assert.ok(re.test('/fitness-gym/'));assert.ok(!re.test('/assets/auth-session.js'));assert.ok(!re.test('/gym/admin.html'));assert.ok(!re.test('/unrelated/path'));
});
test('SQL is additive and private, preserves safe projection and grants no direct mapping access',()=>{
 const sql=fs.readFileSync('supabase/manual/gym_portal_urls.sql','utf8');assert.equal(sql,fs.readFileSync('supabase/migrations/202611030026_gym_portal_urls.sql','utf8'));
 for(const re of [/REFERENCES public.owners\(id\) ON DELETE CASCADE/,/slug text NOT NULL UNIQUE/,/ENABLE ROW LEVEL SECURITY/,/REVOKE ALL ON public.iv_gym_portal_links FROM PUBLIC,anon,authenticated,service_role/,/SELECT visible\.\*,g.display_code,links.slug AS portal_slug/,/FROM public.iv_visible_gyms\(\) visible/,/AFTER INSERT ON public.owners/,/ON CONFLICT DO NOTHING/,/IF FOUND THEN RETURN existing/,/ORDER BY id/,/suffix>100000/])assert.match(sql,re);
 assert.doesNotMatch(sql,/UPDATE public\.(owners|members)|DELETE FROM|DROP TABLE|ALTER TABLE public\.(owners|members)|GRANT.*iv_gym_portal_links/i);
 const reserved=sql.match(/base_name=ANY\(ARRAY\[([^\]]+)/)[1].match(/'([^']+)'/g).map(x=>x.slice(1,-1));for(const value of reserved)assert.equal(portals.valid(value),false,value);
});
test('login and both dashboards load a shared URL helper; recovery remains gym scoped',()=>{
 const login=fs.readFileSync('gym/login.html','utf8');assert.match(login,/src="\/assets\/gym-portals.js"/);assert.match(login,/portalSlug\?query.eq\('portal_slug',portalSlug\)/);assert.match(login,/recoverySlug\?'portal_slug':'token'/);assert.match(login,/role.tenant_id!==gyms\[0\].id/);
 for(const file of ['gym/index.html']){const html=fs.readFileSync(file,'utf8');assert.match(html,/IronVaultGymPortals.url\(owner, window.location\)/);assert.match(html,/href="\$\{IronVaultData.escape\(memberPortalUrl\)\}"/);assert.match(html,/openQrModal\(decodeURIComponent\('\$\{IronVaultData.argument\(memberPortalUrl\)\}/);}
});
