const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const root={Intl,Date};vm.runInNewContext(fs.readFileSync('assets/subscriptions.js','utf8'),root);
test('pilot display excludes approval-day access without changing the counted period',()=>{
 const state={status:'pilot',start_date:'2026-11-06',end_date:'2026-11-19',days_remaining:15};
 const remaining=root.IronVaultSubscriptions.pilotRemaining;
 assert.match(remaining(state),/Approval-day access.*2026-11-06.*14 counted days remaining/);
 assert.equal(remaining({...state,days_remaining:14}),'14 counted days remaining');
 assert.equal(remaining({...state,days_remaining:1}),'1 counted day remaining');
 assert.equal(remaining({...state,days_remaining:0}),'0 counted days remaining');
 assert.equal(remaining({}),'');assert.equal(state.days_remaining,15);
});
