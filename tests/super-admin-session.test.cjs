const {test}=require('node:test');
const assert=require('node:assert/strict');
require('../assets/auth-session.js');
const {install}=require('../assets/super-admin-session.js');
function fixture(role='super_admin',hub=false){
    const state={user:{id:'actor'},roles:[role],loads:0,renders:0,signouts:0,alerts:[],listener:null};
    const nodes=new Map();
    const node=id=>{if(!nodes.has(id)){const classes=new Set(['hidden']);nodes.set(id,{value:'',textContent:'',classList:{add:k=>classes.add(k),remove:k=>classes.delete(k),contains:k=>classes.has(k)}})}return nodes.get(id)};
    function storage(){const m=new Map();return {getItem:k=>m.get(k)||null,setItem:(k,v)=>m.set(k,v),removeItem:k=>m.delete(k)}}
    const session=storage(),cache=storage();
    const client={auth:{getUser:async()=>({data:{user:state.user}}),signInWithPassword:async()=>({error:null}),signOut:async()=>{state.signouts++;return {error:null}},onAuthStateChange:fn=>{state.listener=fn}},
      from:()=>({select(){return this},eq:async()=>({data:state.roles.map(role=>({user_id:'actor',tenant_id:role==='super_admin'?null:'gym-a',role})),error:null})})};
    const app={owners:[],members:[],loadData:async function(){state.loads++;this.owners=['private']},renderDashboard(){state.renders++}};
    install(app,client,{hub,document:{getElementById:node},sessionStorage:session,localStorage:cache,notify:s=>state.alerts.push(s)});
    return {state,app,node,session,cache,client};
}
for(const hub of [false,true]){
 test(`master entry (${hub?'launchpad':'gym dashboard'}) rejects forged browser state before loading private data`,async()=>{
    const f=fixture('member',hub);f.session.setItem('ironvault_super_session','true');
    await f.app.init();await f.app.showDashboardView();
    assert.equal(f.state.loads,0);assert.equal(f.state.renders,0);assert.ok(f.node('super-dashboard').classList.contains('hidden'));
 });
 test(`master entry (${hub?'launchpad':'gym dashboard'}) preserves authorized dashboard access`,async()=>{
    const f=fixture('super_admin',hub);await f.app.init();
    assert.equal(f.state.loads,1);assert.equal(f.state.renders,1);assert.equal(f.node('super-dashboard').classList.contains('hidden'),false);
 });
}
test('root login must obtain Supabase authentication and a Super Admin role',async()=>{
    const f=fixture('member',true);let signins=0;f.client.auth.signInWithPassword=async()=>{signins++;return {error:null}};
    f.node('super-email').value='operator@example.invalid';f.node('super-password').value='synthetic-input';
    await f.app.handleLogin({preventDefault(){}});
    assert.equal(signins,1);assert.equal(f.state.loads,0);assert.equal(f.state.signouts,1);assert.equal(f.state.alerts.length,1);
});
test('role removal is checked again before subsequent protected reads',async()=>{
    const f=fixture();await f.app.init();f.state.roles=[];await f.app.showDashboardView();
    assert.equal(f.state.loads,1);assert.equal(f.app.owners.length,0);assert.equal(f.node('super-dashboard').classList.contains('hidden'),true);
});
test('a role revoked while private data loads prevents rendering and clears the result',async()=>{
    const f=fixture();
    // Change the role at the second Auth verification inside the guarded load.
    let reads=0;f.client.auth.getUser=async()=>{if(++reads===2)f.state.roles=[];return {data:{user:f.state.user}}};
    await f.app.init();assert.equal(f.state.renders,0);assert.equal(f.app.owners.length,0);
});
test('logout and a Supabase SIGNED_OUT event clear private state',async()=>{
    const f=fixture();await f.app.init();await f.app.logout();
    assert.equal(f.state.signouts,1);assert.equal(f.app.owners.length,0);
    f.app.owners=['private'];f.state.listener('SIGNED_OUT');assert.equal(f.app.owners.length,0);
});
test('same-user SIGNED_IN refresh events do not hide an authorized dashboard',async()=>{
    const f=fixture();await f.app.init();f.state.listener('SIGNED_IN',{user:{id:'actor'}});
    assert.equal(f.node('super-dashboard').classList.contains('hidden'),false);assert.equal(f.app.owners.length,1);
});
test('a different Auth identity event clears the previous user private view',async()=>{
    const f=fixture();await f.app.init();f.state.listener('SIGNED_IN',{user:{id:'different-user'}});
    assert.equal(f.node('super-dashboard').classList.contains('hidden'),true);assert.equal(f.app.owners.length,0);
});
