const {test}=require('node:test');const assert=require('node:assert/strict');
require('../assets/auth-session.js');const {render}=require('../assets/staff-report-permissions.js');
function fixture(role='owner'){
 let enabled=false;const calls=[],containers=new Map();
 function element(){let text='';const e={children:[],disabled:false,appendChild(child){this.children.push(child)}};
  Object.defineProperty(e,'textContent',{get:()=>text,set:value=>{text=value;e.children=[]}});return e;}
 const document={getElementById:id=>{if(!containers.has(id))containers.set(id,element());return containers.get(id)},createElement:()=>element()};
 const client={auth:{getUser:async()=>({data:{user:{id:'administrator'}}})},from:()=>({select(){return this},eq:async()=>({data:[{user_id:'administrator',tenant_id:'gym-a',role}],error:null})}),
 rpc:async(name,args)=>{calls.push({name,args});if(name==='iv_list_staff_financial_report_access')return{data:[{user_id:'staff-id',email:'<b>untrusted label</b>',financial_reports_read:enabled}],error:null};enabled=args.p_enabled;return{data:null,error:null}}};
 return {client,document,calls,container:()=>document.getElementById('permissions')};
}
test('administrator widget renders labels as text and grants/revokes through verified scoped RPCs',async()=>{
 const f=fixture();await render(f.client,'gym-a','permissions',f.document);
 let row=f.container().children[0];assert.equal(row.children[0].textContent,'<b>untrusted label</b> — staff-id');
 await row.children[1].onclick();assert.equal(f.calls[1].name,'iv_set_staff_financial_report_access');
 assert.equal(f.calls[1].args.p_tenant,'gym-a');assert.equal(f.calls[1].args.p_enabled,true);
 row=f.container().children[0];assert.equal(row.children[1].textContent,'Revoke reports');
 await row.children[1].onclick();assert.equal(f.calls[3].args.p_enabled,false);
});
test('ordinary staff cannot use the administrator permission widget even with a forged local UI state',async()=>{
 const f=fixture('staff');await render(f.client,'gym-a','permissions',f.document);
 assert.equal(f.calls.length,0);assert.equal(f.container().children.length,0);
});
test('missing permission backend never invents grants or enables a fallback control',async()=>{
 const f=fixture();f.client.rpc=async()=>({data:null,error:{code:'PGRST202'}});
 await render(f.client,'gym-a','permissions',f.document);assert.equal(f.container().children.length,0);
 assert.match(f.container().textContent,/unavailable/);
});
