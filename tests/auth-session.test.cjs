const {test} = require('node:test');
const assert = require('node:assert/strict');
const auth = require('../assets/auth-session.js');

function client(bindings = [], user = {id:'actor'}) {
    const state = {bindings, user, reads:0, signouts:0};
    const api = {
        auth: {
            getUser: async () => ({data:{user:state.user},error:null}),
            signOut: async options => {state.signouts++;assert.equal(options.scope,'local');return {error:null};}
        },
        from(table) {
            state.reads++;
            assert.equal(table,'iv_user_roles');
            return {select() {return this;},eq(column,value) {
                assert.equal(column,'user_id');assert.equal(value,state.user.id);
                return Promise.resolve({data:state.bindings,error:null});
            }};
        }
    };
    return {api,state};
}
function row(role,tenant='gym-a',member=null,user='actor') {
    return {user_id:user,tenant_id:tenant,member_id:member,role};
}
function storage(entries={}) {
    const data=new Map(Object.entries(entries));
    return {getItem:k=>data.get(k)||null,setItem:(k,v)=>data.set(k,String(v)),removeItem:k=>data.delete(k)};
}
test('anonymous users cannot read roles or obtain a portal grant',async()=>{
    const c=client([],null);
    await assert.rejects(auth.requireRole(c.api,{roles:['owner']}),{code:'AUTH_REQUIRED'});
    assert.equal(c.state.reads,0);
});
for(const [role,tenant,member] of [['super_admin',null,null],['owner','gym-a',null],['staff','gym-a',null],['member','gym-a','member-a']]) {
    test(`${role} is accepted only from its authenticated role binding`,async()=>{
        const c=client([row(role,tenant,member)]);
        const grant=await auth.requireRole(c.api,{roles:[role],tenantId:tenant});
        assert.equal(grant.role,role);assert.ok(Object.isFrozen(grant));
    });
}
test('another user binding, absent role and wrong role never authorize',async()=>{
    for(const rows of [[],[row('owner','gym-a',null,'someone-else')],[row('member','gym-a','member-a')]]) {
        await assert.rejects(auth.requireRole(client(rows).api,{roles:['owner']}),{code:'ACCESS_DENIED'});
    }
});
test('branch bindings cannot authorize another gym or another member',async()=>{
    const c=client([row('member','gym-a','member-a')]);
    await assert.rejects(auth.requireRole(c.api,{roles:['member'],tenantId:'gym-b'}),{code:'ACCESS_DENIED'});
    await assert.rejects(auth.requireRole(c.api,{roles:['member'],tenantId:'gym-a',memberId:'member-b'}),{code:'ACCESS_DENIED'});
});
test('global Super Admin access is opt-in and cannot substitute for a member role',async()=>{
    const c=client([row('super_admin',null)]);
    await assert.rejects(auth.requireRole(c.api,{roles:['owner'],tenantId:'gym-a',allowGlobalSuperAdmin:true}),{code:'ACCESS_DENIED'});
    await assert.rejects(auth.requireRole(c.api,{roles:['super_admin'],tenantId:'gym-a'}),{code:'ACCESS_DENIED'});
    assert.equal((await auth.requireRole(c.api,{roles:['super_admin'],tenantId:'gym-a',allowGlobalSuperAdmin:true})).role,'super_admin');
});
test('unscoped branch roles and missing member links fail closed',async()=>{
    for(const binding of [row('owner',null),row('staff',null),row('member','gym-a')]) {
        await assert.rejects(auth.requireRole(client([binding]).api,{roles:[binding.role]}),{code:'ACCESS_DENIED'});
    }
});
test('multiple branch roles require a selected tenant rather than the first result',async()=>{
    const c=client([row('staff','gym-a'),row('staff','gym-b')]);
    await assert.rejects(auth.requireRole(c.api,{roles:['staff']}),{code:'TENANT_REQUIRED'});
    assert.equal((await auth.requireRole(c.api,{roles:['staff'],tenantId:'gym-b'})).tenant_id,'gym-b');
});
test('owner and staff roles in one gym resolve without a single-row lookup',async()=>{
    const c=client([row('staff'),row('owner')]);
    assert.equal((await auth.requireRole(c.api,{roles:['owner','staff']})).role,'owner');
});
test('ambiguous member links are rejected',async()=>{
    const c=client([row('member','gym-a','one'),row('member','gym-a','two')]);
    await assert.rejects(auth.requireRole(c.api,{roles:['member']}),{code:'AMBIGUOUS_MEMBER'});
});
test('a fresh role lookup observes revocation on the next operation',async()=>{
    const c=client([row('staff')]);
    await auth.requireRole(c.api,{roles:['staff']});c.state.bindings=[];
    await assert.rejects(auth.requireRole(c.api,{roles:['staff']}),{code:'ACCESS_DENIED'});
    assert.equal(c.state.reads,2);
});
test('role service errors never become an administrator fallback',async()=>{
    const c=client();c.api.from=()=>({select(){return this},eq:async()=>({data:null,error:{message:'denied'}})});
    await assert.rejects(auth.requireRole(c.api,{roles:['owner']}),{code:'ROLE_LOOKUP_FAILED'});
});
test('logout clears private cache and application identity but preserves unrelated storage',async()=>{
    const c=client();const session=storage({'ironvault_active_role':'admin','ironvault_active_member':'member-a',unrelated:'keep'});
    const cache=storage({'ironvault_members_db':'private','ironvault_owners_db':'private',unrelated:'keep'});
    await auth.signOut(c.api,session,cache);
    assert.equal(c.state.signouts,1);assert.equal(session.getItem('ironvault_active_role'),null);
    assert.equal(session.getItem('ironvault_active_member'),null);assert.equal(cache.getItem('ironvault_members_db'),null);
    assert.equal(session.getItem('unrelated'),'keep');assert.equal(cache.getItem('unrelated'),'keep');
});
test('failed logout is reported and does not leave the private application cache',async()=>{
    const c=client();c.api.auth.signOut=async()=>({error:{message:'network'}});
    const session=storage({'ironvault_super_session':'true'});const cache=storage({'ironvault_members_db':'private'});
    await assert.rejects(auth.signOut(c.api,session,cache),{code:'SIGNOUT_FAILED'});
    assert.equal(session.getItem('ironvault_super_session'),null);assert.equal(cache.getItem('ironvault_members_db'),null);
});
module.exports={client,row,storage};
