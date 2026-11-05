const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
test('roster previews three members, expands all matches, preserves live expansion and resets search',()=>{
 const nodes=new Map(),node=id=>{if(!nodes.has(id))nodes.set(id,{value:'',innerHTML:'',textContent:'',attributes:{},setAttribute(k,v){this.attributes[k]=v;},querySelectorAll:()=>[],contains:()=>true});return nodes.get(id);};
 const root={Intl,Date,document:{getElementById:node},IronVaultData:{escape:require('../assets/application-data.js').escape}};
 vm.runInNewContext(fs.readFileSync('assets/mobile-roster.js','utf8'),root);
 let original=0,opened,desktopCount;const app={currentTenantId:'gym',rosterActiveFilter:'all',renderRoster(list){original++;desktopCount=(this.rosterExpanded?list:list.slice(0,3)).length;},calculateDaysLeft:()=> '6 days left',openProfileModal:id=>{opened=id;},filterRoster(){this.renderRoster(current);}};
 let current=Array.from({length:23},(_,i)=>({id:'id-'+i,displayCode:'MEM-'+i,name:i===0?'<img src=x>':'Member '+i,plan:'1-Week Pass',status:'ACTIVE'}));current.push({id:'pending',status:'PENDING'});
 root.IronVaultMobileRoster.install(app);
 app.renderRoster(current);assert.equal(original,1);assert.equal(desktopCount,3);assert.equal((node('mobile-roster-list').innerHTML.match(/data-member-id=/g)||[]).length,3);assert.match(node('mobile-roster-list').innerHTML,/&lt;img src=x&gt;/);assert.doesNotMatch(node('mobile-roster-list').innerHTML,/<img|pending/);
 const expand=node('roster-expansion');assert.equal(expand.hidden,false);assert.equal(expand.attributes['aria-expanded'],'false');expand.onclick();assert.equal(expand.textContent,'Show fewer');assert.equal((node('mobile-roster-list').innerHTML.match(/data-member-id=/g)||[]).length,23);
 app.renderRoster(current);assert.equal(app.rosterExpanded,true);expand.onclick();assert.equal(desktopCount,3);
 expand.onclick();node('roster-search').value='Member 20';current=[current[20]];app.renderRoster(current);assert.equal(app.rosterExpanded,false);assert.equal(expand.hidden,true);assert.match(node('mobile-roster-list').innerHTML,/Member 20/);
 node('mobile-roster-list').onclick({target:{closest:()=>({dataset:{memberId:'id-20'}})}});assert.equal(opened,'id-20');assert.equal(node('mobile-roster-remove').hidden,true);app.authenticatedRole={role:'owner'};node('account-recovery').open=true;app.openProfileModal('id-20');assert.equal(node('account-recovery').open,false);assert.equal(node('mobile-roster-remove').hidden,false);app.authenticatedRole={role:'staff'};app.openProfileModal('id-20');assert.equal(node('mobile-roster-remove').hidden,true);
 app.renderRoster([]);assert.match(node('mobile-roster-list').innerHTML,/No matching active/);assert.equal(expand.hidden,true);
});
