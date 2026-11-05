const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function fixture(){const nodes=new Map(),get=id=>{if(!nodes.has(id))nodes.set(id,{dataset:{},style:{},children:[],append(...children){this.children.push(...children);},appendChild(child){this.children.push(child);},focus(){},showModal(){this.open=true;},close(){this.open=false;this.onclose?.();}});return nodes.get(id);};let expire,delay;const root={document:{getElementById:get,createElement:()=>({textContent:'',append(...children){this.children=children;}})},setTimeout:(cb,ms)=>{expire=cb;delay=ms;return 1;},clearTimeout(){}};vm.runInNewContext(fs.readFileSync('assets/admin-feedback.js','utf8'),root);const app={authenticatedRole:{user_id:'owner'},currentTenantId:'gym'};root.IronVaultAdminFeedback.install(app);return{app,get,expire:()=>expire(),delay:()=>delay};}
test('desk confirmation requires an explicit decision, keeps money rows separate and cancels on identity change',async()=>{
 const {app,get}=fixture();const result=app.confirmAdmin({title:'Purchase',rows:[['Total','₱700'],['Wallet','₱100'],['Cash to collect','₱600']]});assert.equal(get('admin-feedback-rows').children.length,3);get('admin-feedback-cancel').onclick();assert.equal(await result,false);
 const accepted=app.confirmAdmin({title:'Entry'});get('admin-feedback-confirm').onclick();assert.equal(await accepted,true);
 const changed=app.confirmAdmin({title:'Purchase'});app.currentTenantId='other';get('admin-feedback-confirm').onclick();assert.equal(await changed,false);
});
test('admin success and warning dialogs close after two seconds without browser alerts',()=>{
 const f=fixture();f.app.notifyAdmin('Check-in recorded',true);assert.equal(f.get('admin-feedback-dialog').dataset.mode,'success');assert.equal(f.delay(),2000);f.expire();assert.equal(f.get('admin-feedback-dialog').open,false);
 f.app.notifyAdmin('<img src=x> Invalid amount',false);assert.equal(f.get('admin-feedback-dialog').dataset.mode,'warning');assert.equal(f.get('admin-feedback-message').textContent,'<img src=x> Invalid amount');f.expire();assert.equal(f.get('admin-feedback-dialog').open,false);
});
