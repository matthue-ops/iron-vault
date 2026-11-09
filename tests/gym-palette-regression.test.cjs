const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
test('member background refresh reads and reapplies the saved accent rather than defaulting to Emerald',async()=>{
 let adapter,chosen;const selections=[];
 const member={id:'m',tenant_id:'g',status:'ACTIVE',name:'Member',plan:'Not Selected'};
 const gym={id:'g',status:'ACTIVE',gym_name:'Gym',accent_color:'#fbbf24',pricing:{}};
 const nodes=new Map();const node=id=>{if(!nodes.has(id))nodes.set(id,{hidden:false,innerText:'',classList:{contains:()=>false,add(){},remove(){}},removeAttribute(){}});return nodes.get(id);};
 const doc={addEventListener(){},createElement:()=>({setAttribute(){}}),querySelector:()=>({prepend(){}}),getElementById:node,querySelectorAll:()=>[],body:{classList:{contains:()=>false}},activeElement:null};
 const root={document:doc,Intl,Date,Map,Set,navigator:{onLine:true},addEventListener(){},IronVaultGymAccent:{apply:c=>chosen=c},IronVaultAuth:{},IronVaultLiveUpdates:{create:options=>{adapter=options;return {};}}};
 vm.runInNewContext(fs.readFileSync('assets/dashboard-live.js','utf8'),root);
 const client={auth:{onAuthStateChange(){}},from(table){let columns;const q={select(c){columns=c;selections.push([table,c]);return q;},eq(){return q;},then(resolve){const row=table==='owners'?gym:member;const projected=columns==='*'?row:Object.fromEntries(columns.split(',').map(k=>[k,row[k]]));return Promise.resolve({data:[projected]}).then(resolve);}};return q;}};
 const app={currentMember:{id:'m'},renderProfile(){}};root.IronVaultDashboardLive.install(app,client,'member');
 const snapshot=await adapter.read({member:'m',tenant:'g'});adapter.apply(snapshot);
 assert.equal(chosen,'#fbbf24');assert.ok(selections.find(([table,columns])=>table==='owners'&&columns.includes('accent_color')));
});
test('Reports reads the same saved accent, and theme stylesheet is loaded on all gym workspaces',()=>{
 for(const page of ['admin','profile','reports'])assert.match(fs.readFileSync('gym/'+page+'.html','utf8'),/gym-palette\.css/);
 const report=fs.readFileSync('gym/reports.html','utf8');assert.match(report,/select\('id,gym_name,token,logo,status,accent_color'\)/);assert.match(report,/IronVaultGymAccent.apply\(gym.accent_color\)/);
});
