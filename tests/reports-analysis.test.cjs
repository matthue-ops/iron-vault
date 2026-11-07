const {test}=require('node:test');const assert=require('node:assert/strict');const R=require('../assets/reports-analysis.js');
const at='2026-11-01T01:00:00Z';
test('cash collected and pass sales stay separate and split payments count as one purchase',()=>{
 const data={financial:[{kind:'topup',amount:'100.10',created_at:at},{kind:'plan_wallet',amount:'70.10',created_at:at},{kind:'plan_cash',amount:'29.90',created_at:at},{kind:'refund_cash',amount:'10',created_at:at}],
 purchases:[{request_id:'one',renewal:false,created_at:at}],members:[{wallet_balance:'30.00'}]};
 const m=R.analyze(data,'2026-11-01','2026-11-01','2026-11-01');
 assert.equal(m.cashIn,12000n);assert.equal(m.grossSales,10000n);assert.equal(m.wallet,3000n);assert.equal(m.purchaseCount,1);assert.equal(m.daily[0].cash,12000n);
 assert.equal(R.money(m.cashIn),'₱120.00');assert.equal(R.cents('0.10')+R.cents('0.20'),30n);
});
test('report periods and attendance peak hours use Manila boundaries with inclusive end dates',()=>{
 const rows=[{member_id:'m',method:'qr',created_at:'2026-10-31T16:00:00Z'},{member_id:'m',method:'manual',created_at:'2026-11-01T15:59:59Z'},{member_id:'n',method:'qr',created_at:'2026-11-01T16:00:00Z'}];
 const m=R.analyze({attendance:rows},'2026-11-01','2026-11-01','2026-11-01');
 assert.equal(m.visits,2);assert.equal(m.uniqueVisitors,1);assert.equal(m.qr,1);assert.equal(m.manual,1);assert.deepEqual(m.peakHours,[0,23]);
});
test('current valid and expiring passes reject expired, malformed, pending and unknown plans',()=>{
 const members=[{id:'valid',status:'ACTIVE',plan:'1-Week Pass',expiration_date:'2026-11-08',created_at:at},
 {status:'ACTIVE',plan:'1-Day Pass',expiration_date:'2026-10-31'},
 {status:'PENDING',plan:'1-Week Pass',expiration_date:'2026-11-08'},
 {status:'ACTIVE',plan:'Not Selected',expiration_date:'2026-11-08'},
 {status:'ACTIVE',plan:'1-Week Pass',expiration_date:'2026-02-31'}];
 const m=R.analyze({members},'2026-11-01','2026-11-01','2026-11-01');
 assert.equal(m.currentPasses,1);assert.equal(m.expiring[0].id,'valid');assert.equal(m.newMembers,1);assert.equal(m.pending,1);
 assert.throws(()=>R.analyze({},'2026-02-31','2026-03-01'),/valid/);
});
test('unsupported or invalid legacy entries are disclosed rather than silently inflating totals',()=>{
 const m=R.analyze({financial:[{kind:'topup',amount:'1.234',created_at:at},{kind:'refund_cash',amount:'-10',created_at:at},{kind:'constructor',amount:20,created_at:at}],members:[{wallet_balance:'NaN'}]},'2026-11-01','2026-11-01','2026-11-01');
 assert.equal(m.invalid,3);assert.equal(m.other,1);assert.equal(m.cashIn,0n);assert.equal(m.purchaseCount,0);
});
test('CSV protects spreadsheet formula cells, quotes commas, and keeps UTF-8 names',()=>{
 const csv=R.csv([['Name','Value'],['José, Jr.',' =HYPERLINK("bad")'],['Tab','\t=1+1']]);
 assert.ok(csv.startsWith('\uFEFF'));assert.match(csv,/"José, Jr\."/);assert.ok(csv.includes("' =HYPERLINK"));assert.ok(csv.includes("'\t=1+1"));
});
test('generated delta contains exactly the current reviewed usability migrations',()=>{
 const {spawnSync}=require('node:child_process');const result=spawnSync(process.execPath,['scripts/build-usability-sql.cjs','--check'],{encoding:'utf8'});assert.equal(result.status,0,result.stderr);
});

test('a 100-peso top-up and wallet purchase produce 100-peso sales, never 200',()=>{
 const m=R.analyze({financial:[{kind:'topup',amount:100,created_at:at},{kind:'plan_wallet',amount:100,created_at:at}]},'2026-11-01','2026-11-01','2026-11-01');
 assert.equal(m.grossSales,10000n);assert.equal(m.cashIn,10000n);
 const unused=R.analyze({financial:[{kind:'topup',amount:100,created_at:at}]},'2026-11-01','2026-11-01','2026-11-01');assert.equal(unused.grossSales,0n);
});
test('expiry labels distinguish no pass, missing date, expired, today and remaining days',()=>{
 assert.equal(R.expiryLabel({plan:'Not Selected'},'2026-11-02'),'No pass');
 assert.equal(R.expiryLabel({plan:'1-Day Pass'},'2026-11-02'),'Expiry unavailable');
 assert.match(R.expiryLabel({plan:'1-Day Pass',expiration_date:'2026-11-01'},'2026-11-02'),/^Expired/);
 assert.match(R.expiryLabel({plan:'1-Day Pass',expiration_date:'2026-11-02'},'2026-11-02'),/^Expires today/);
 assert.match(R.expiryLabel({plan:'1-Week Pass',expiration_date:'2026-11-09'},'2026-11-02'),/7 days left/);
});

test('Wallet after uses only the saved transaction value, including zero',()=>{
 for(const [value,expected] of [[100,'₱100.00'],[0,'₱0.00'],['50.25','₱50.25']])assert.equal(R.walletAfter({wallet_after:value} ),expected);
 for(const value of [null,undefined,'',true,false,{},[],NaN,Infinity,-1,'-1.00','1.234'])assert.equal(R.walletAfter({wallet_after:value}), 'Unavailable');
 assert.equal(R.walletAfter({wallet_balance:999}), 'Unavailable');
});

test('wallet refunds and credit corrections do not invent cash receipts or rewrite gross sales',()=>{const model=R.analyze({financial:[['topup',100],['plan_wallet',60],['refund_wallet',20],['wallet_correction',10],['wallet_correction_in',10],['refund_cash',5]].map(([kind,amount])=>({kind,amount,created_at:at})),members:[{wallet_balance:55}]},'2026-11-01','2026-11-01');assert.equal(model.grossSales,6000n);assert.equal(model.cashIn,9500n);assert.equal(model.totals.refund_wallet,2000n);assert.equal(model.totals.wallet_correction,1000n);assert.equal(model.totals.wallet_correction_in,1000n);assert.equal(model.other,0);});
