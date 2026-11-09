const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function setup(){
 const nodes=new Map();const node=id=>{if(!nodes.has(id))nodes.set(id,{style:{},focus(){},showModal(){this.open=true;},close(){this.open=false;this.onclose?.();}});return nodes.get(id);};
 let callback,delay;const root={document:{getElementById:node},setTimeout:(cb,ms)=>{callback=cb;delay=ms;return 1;},clearTimeout(){}};
 vm.runInNewContext(fs.readFileSync('assets/member-feedback.js','utf8'),root);
 const app={selectPlan:async()=>{}};root.IronVaultMemberFeedback.install(app);
 return {app,node,expire:()=>callback(),delay:()=>delay};
}
test('warnings are red, safely render text, and close after two seconds',()=>{
 const {app,node,expire,delay}=setup();app.showAlert('<b>Invalid action</b>',false);
 assert.equal(node('member-feedback-dialog').open,true);assert.equal(node('member-feedback-dialog').style.borderColor,'#f43f5e');
 assert.equal(node('member-feedback-message').textContent,'<b>Invalid action</b>');assert.equal(delay(),2000);expire();assert.equal(node('member-feedback-dialog').open,false);
});
test('purchase confirmation requires confirmation and cancellation resolves false',async()=>{
 const {app,node,delay}=setup();const cancel=app.confirmAction('Buy pass?');assert.equal(delay(),undefined);node('member-feedback-cancel').onclick();assert.equal(await cancel,false);
 const accept=app.confirmAction('Buy pass?');node('member-feedback-confirm').onclick();assert.equal(await accept,true);
 const escape=app.confirmAction('Buy pass?');node('member-feedback-dialog').oncancel({preventDefault(){}});assert.equal(await escape,false);
});

test('confirmation and success retain green rather than inheriting a gym preset',async()=>{const {app,node,expire}=setup();const result=app.confirmAction('Buy pass?');assert.equal(node('member-feedback-dialog').style.borderColor,'#10b981');assert.equal(node('member-feedback-confirm').style.background,'#10b981');node('member-feedback-cancel').onclick();assert.equal(await result,false);app.showAlert('Saved',true);assert.equal(node('member-feedback-dialog').style.borderColor,'#10b981');expire();assert.equal(node('member-feedback-dialog').open,false);});
