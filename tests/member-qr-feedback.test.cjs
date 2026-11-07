const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
test('confirmed entry hides QR, closes feedback after 2.5 seconds, and does not replay',()=>{
 const nodes=new Map();
 for(const id of ['qr-wrapper','btn-generate-qr','qr-accepted-window']){
  const classes=new Set(id==='qr-wrapper'?['flex']:[]);
  nodes.set(id,{hidden:true,style:{},classList:{add:c=>classes.add(c),remove:c=>classes.delete(c),toggle:(c,on)=>on?classes.add(c):classes.delete(c),contains:c=>classes.has(c)}});
 }
 let callback,delay,scheduled=0;
 const context={Intl,Date,document:{getElementById:id=>nodes.get(id)},setTimeout:(cb,ms)=>{callback=cb;delay=ms;scheduled++;return scheduled;},clearTimeout:()=>{}};
 vm.runInNewContext(fs.readFileSync('assets/member-qr-feedback.js','utf8'),context);
 const app={currentMember:{id:'a',tenantId:'gym',lastScannedDate:null},renderProfile(){}};
 context.IronVaultMemberQrFeedback.install(app);
 app.renderProfile();assert.equal(scheduled,0);
 app.renderProfile();assert.equal(scheduled,0); // failed scan / unrelated update
 app.currentMember.lastScannedDate=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 app.currentMember.lastEntry={id:'entry-a',method:'qr',created_at:new Date().toISOString()};
 app.renderProfile();assert.equal(scheduled,1);assert.equal(delay,2500);
 assert.equal(nodes.get('qr-wrapper').classList.contains('hidden'),true);
 assert.equal(nodes.get('qr-wrapper').classList.contains('flex'),false);
 assert.equal(nodes.get('btn-generate-qr').classList.contains('hidden'),true);
 assert.equal(nodes.get('qr-accepted-window').hidden,false);
 callback();assert.equal(nodes.get('qr-accepted-window').hidden,true);
 app.renderProfile();assert.equal(scheduled,1);
 const fresh={currentMember:app.currentMember,renderProfile(){}};
 context.IronVaultMemberQrFeedback.install(fresh);fresh.renderProfile();assert.equal(scheduled,1);
 app.currentMember={id:'b',tenantId:'other',lastScannedDate:null};app.renderProfile();
 assert.equal(nodes.get('btn-generate-qr').classList.contains('hidden'),false);
 assert.equal(nodes.get('qr-accepted-window').hidden,true);
});
test('manual entry has its own window; initial/offline/reconnected history does not replay',()=>{
 const nodes=new Map(),events={},classes=new Set();for(const id of ['qr-wrapper','btn-generate-qr','qr-accepted-window','entry-success-title','entry-success-detail','qr-scan-success-banner'])nodes.set(id,{hidden:true,style:{},textContent:'',querySelector(){return nodes.get('entry-success-detail')},classList:{add:c=>classes.add(c),remove:c=>classes.delete(c),toggle(){}}});
 let count=0;const document={hidden:false,getElementById:id=>nodes.get(id),addEventListener:(n,f)=>events[n]=f},navigator={onLine:true};const c={document,navigator,Date,Intl,setTimeout:()=>++count,clearTimeout(){},addEventListener:(n,f)=>events[n]=f};vm.runInNewContext(fs.readFileSync('assets/member-qr-feedback.js','utf8'),c);const app={renderProfile(){},currentMember:{id:'m',tenantId:'g',lastScannedDate:null}};c.IronVaultMemberQrFeedback.install(app);app.renderProfile();const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());app.currentMember.lastScannedDate=today;app.currentMember.lastEntry={id:'manual-1',method:'manual',created_at:new Date().toISOString()};app.renderProfile();assert.equal(nodes.get('entry-success-title').textContent,'Entry Granted');assert.match(nodes.get('entry-success-detail').textContent,/Checked in by gym staff/);assert.equal(count,1);app.renderProfile();assert.equal(count,1);
 events.offline();navigator.onLine=false;app.currentMember.lastEntry={id:'manual-2',method:'manual',created_at:new Date().toISOString()};app.renderProfile();assert.equal(count,1);navigator.onLine=true;events.online();app.renderProfile();assert.equal(count,1);events.visibilitychange();app.currentMember.lastEntry={id:'qr-after-away',method:'qr',created_at:new Date().toISOString()};app.renderProfile();assert.equal(count,1);
});
