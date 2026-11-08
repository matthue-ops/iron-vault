const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function fixture(){const nodes=new Map(),get=id=>{if(!nodes.has(id))nodes.set(id,{dataset:{},style:{},children:[],append(...children){this.children.push(...children);},appendChild(child){this.children.push(child);},focus(){},showModal(){this.open=true;},close(){this.open=false;this.onclose?.();}});return nodes.get(id);};let clock=0,next=0,delay;const timers=new Map(),auth=[];const root={document:{getElementById:get,createElement:()=>({textContent:'',append(...children){this.children=children;}})},setTimeout:(cb,ms)=>{delay=ms;timers.set(++next,{cb,at:clock+ms});return next;},clearTimeout:id=>timers.delete(id)};vm.runInNewContext(fs.readFileSync('assets/admin-feedback.js','utf8'),root);const app={authenticatedRole:{user_id:'owner'},currentTenantId:'gym'};root.IronVaultAdminFeedback.install(app,{auth:{onAuthStateChange:fn=>auth.push(fn)}});function advance(ms){clock+=ms;for(const [id,t] of [...timers])if(t.at<=clock){timers.delete(id);t.cb();}}return{app,get,auth,advance,timers,expire:()=>advance(delay),delay:()=>delay};}
test('desk confirmation requires an explicit decision, keeps money rows separate and cancels on identity change',async()=>{
 const {app,get}=fixture();const result=app.confirmAdmin({title:'Purchase',rows:[['Total','₱700'],['Wallet','₱100'],['Cash to collect','₱600']]});assert.equal(get('admin-feedback-rows').children.length,3);get('admin-feedback-cancel').onclick();assert.equal(await result,false);
 const accepted=app.confirmAdmin({title:'Entry'});get('admin-feedback-confirm').onclick();assert.equal(await accepted,true);
 const changed=app.confirmAdmin({title:'Purchase'});app.currentTenantId='other';get('admin-feedback-confirm').onclick();assert.equal(await changed,false);
});
test('admin success and warning dialogs close after two seconds without browser alerts',()=>{
 const f=fixture();f.app.notifyAdmin('Check-in recorded',true);assert.equal(f.get('admin-feedback-dialog').dataset.mode,'success');assert.equal(f.delay(),2000);f.expire();assert.equal(f.get('admin-feedback-dialog').open,false);
 f.app.notifyAdmin('<img src=x> Invalid amount',false);assert.equal(f.get('admin-feedback-dialog').dataset.mode,'warning');assert.equal(f.get('admin-feedback-message').textContent,'<img src=x> Invalid amount');f.expire();assert.equal(f.get('admin-feedback-dialog').open,false);
});
test('outdated-review warning keeps Close available for six seconds and can be dismissed early',()=>{
 const f=fixture(),error=Object.assign(Error('Top-up review is out of date.'),{code:'IV004',uncertain:false});
 f.app.notifyFinancialError(error,'Top-up not confirmed');assert.equal(f.delay(),6000);assert.equal(f.get('admin-feedback-confirm').textContent,'Close');
 f.advance(2000);assert.equal(f.get('admin-feedback-dialog').open,true);f.advance(3999);assert.equal(f.get('admin-feedback-dialog').open,true);f.advance(1);assert.equal(f.get('admin-feedback-dialog').open,false);
 f.app.notifyFinancialError(error);f.get('admin-feedback-confirm').onclick();assert.equal(f.get('admin-feedback-dialog').open,false);assert.equal(f.timers.size,0);
});
test('unknown payment outcomes persist and cannot be overwritten by success or another confirmation',async()=>{
 const f=fixture();f.app.notifyFinancialError(Object.assign(Error('Response lost'),{uncertain:true}));
 assert.equal(f.timers.size,0);f.advance(60000);assert.equal(f.get('admin-feedback-dialog').open,true);assert.match(f.get('admin-feedback-message').textContent,/may already be recorded/);
 f.app.notifyAdmin('Other success',true);assert.match(f.get('admin-feedback-message').textContent,/Response lost/);assert.equal(await f.app.confirmAdmin({title:'Another payment'}),false);
 f.get('admin-feedback-confirm').onclick();assert.equal(f.get('admin-feedback-dialog').open,false);f.app.notifyAdmin('Now acknowledged',true);assert.equal(f.delay(),2000);
});
test('sign-out closes a persistent financial warning and clears its private contents',()=>{
 const f=fixture();f.app.notifyFinancialError(Object.assign(Error('Unknown payment'),{uncertain:true}));f.auth[0]('SIGNED_OUT');assert.equal(f.get('admin-feedback-dialog').open,false);assert.equal(f.get('admin-feedback-message').textContent,'');assert.equal(f.timers.size,0);
});
