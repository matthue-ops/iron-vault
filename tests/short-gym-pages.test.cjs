const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const routes=require('../assets/gym-portals.js');
test('legacy login/profile aliases preserve every query and fragment token without changing origin',()=>{
 for(const [old,next] of [['memberlogin.html','login.html'],['memberprofile.html','profile.html']]){
  const html=fs.readFileSync('gym/'+old,'utf8'),scripts=Array.from(html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g));assert.equal(scripts.length,1);
  for(const suffix of ['', '?key=gym-demo&from=admin','#iv_verify=verify-demo','?key=gym%2Fdemo#iv_recovery=recovery%2Bdemo%3D','?key=gym-demo#access_token=demo-access&refresh_token=demo-refresh&type=recovery','?redirect=https%3A%2F%2Fother.invalid#next=%2Fprivate']){
   const source=new URL('https://example.invalid/gym/'+old+suffix);let replaced;const window={location:{search:source.search,hash:source.hash,replace:value=>replaced=value}};vm.runInNewContext(scripts[0][1],{window});const dest=new URL(replaced,source.href);assert.equal(dest.origin,source.origin);assert.equal(dest.pathname,'/gym/'+next);assert.equal(dest.search,source.search);assert.equal(dest.hash,source.hash);assert.ok(!dest.pathname.includes('%20'));
  }
  assert.doesNotMatch(html,/supabase|fetch\(|signOut|sessionStorage|localStorage/);
 }
});
test('canonical pages contain the original gated application and live controllers',()=>{
 const login=fs.readFileSync('gym/login.html','utf8'),profile=fs.readFileSync('gym/profile.html','utf8');assert.match(login,/const app =/);assert.match(login,/IronVaultBranchAuth.install\(app,supabaseClient\)/);assert.match(profile,/const profileApp =/);assert.match(profile,/IronVaultDashboardLive.install\(profileApp,supabaseClient,'member'\)/);assert.match(profile,/IronVaultMemberAnnouncements.install/);
 assert.equal(routes.page('profile.html'),'/gym/profile.html');assert.equal(routes.page('memberprofile.html'),'/gym/profile.html');
});
test('friendly gym routes and new links use login.html while existing callback allowlists stay supported',()=>{
 const config=JSON.parse(fs.readFileSync('vercel.json'));assert.deepEqual(config.routes[0],{handle:'filesystem'});assert.equal(config.routes[1].dest,'/gym/login.html');assert.equal(routes.url({portalSlug:'fitness-gym'},{href:'https://example.invalid/index.html'}),'https://example.invalid/fitness-gym');assert.match(routes.url({token:'gym-demo'},{href:'https://example.invalid/gym/index.html'}),/\/gym\/login.html\?key=gym-demo$/);
 const login=fs.readFileSync('gym/login.html','utf8');assert.match(login,/emailRedirectTo:new URL\('\/gym\/memberlogin.html\?key=/);assert.match(login,/redirectTo:new URL\('\/gym\/memberlogin.html\?key=/);
});
