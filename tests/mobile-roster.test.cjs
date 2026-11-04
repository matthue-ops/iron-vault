const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
test('mobile roster paginates filtered active members, preserves live page, resets search and opens existing profile',()=>{
 const nodes=new Map(),node=id=>{if(!nodes.has(id))nodes.set(id,{value:'',innerHTML:'',textContent:'',querySelectorAll:()=>[],contains:()=>true});return nodes.get(id);};
 const root={Intl,Date,document:{getElementById:node},IronVaultData:{escape:require('../assets/application-data.js').escape}};
 vm.runInNewContext(fs.readFileSync('assets/mobile-roster.js','utf8'),root);
 let original=0,opened;const app={currentTenantId:'gym',rosterActiveFilter:'all',renderRoster(){original++;},calculateDaysLeft:()=> '6 days left',openProfileModal:id=>{opened=id;}};
 root.IronVaultMobileRoster.install(app);
 const list=Array.from({length:23},(_,i)=>({id:'id-'+i,displayCode:'MEM-'+i,name:i===0?'<img src=x>':'Member '+i,plan:'1-Week Pass',status:'ACTIVE'}));list.push({id:'pending',status:'PENDING'});
 app.renderRoster(list);assert.equal(original,1);assert.equal(node('mobile-roster-page').textContent,'1–10 of 23');assert.match(node('mobile-roster-list').innerHTML,/&lt;img src=x&gt;/);assert.doesNotMatch(node('mobile-roster-list').innerHTML,/<img|pending/);
 node('mobile-roster-next').onclick();assert.equal(node('mobile-roster-page').textContent,'11–20 of 23');
 app.renderRoster(list);assert.equal(node('mobile-roster-page').textContent,'11–20 of 23');
 node('mobile-roster-next').onclick();assert.equal(node('mobile-roster-page').textContent,'21–23 of 23');assert.equal(node('mobile-roster-next').disabled,true);
 app.renderRoster(list.slice(0,3));assert.equal(node('mobile-roster-page').textContent,'1–3 of 3');
 node('roster-search').value='Member 2';app.renderRoster([list[2]]);assert.equal(node('mobile-roster-page').textContent,'1–1 of 1');
 node('mobile-roster-list').onclick({target:{closest:()=>({dataset:{memberId:'id-2'}})}});assert.equal(opened,'id-2');assert.equal(node('mobile-roster-remove').hidden,true);app.authenticatedRole={role:'owner'};app.openProfileModal('id-2');assert.equal(node('mobile-roster-remove').hidden,false);app.authenticatedRole={role:'staff'};app.openProfileModal('id-2');assert.equal(node('mobile-roster-remove').hidden,true);
 app.renderRoster([]);assert.match(node('mobile-roster-list').innerHTML,/No matching active/);assert.equal(node('mobile-roster-next').disabled,true);assert.equal(node('mobile-roster-prev').disabled,true);
});
