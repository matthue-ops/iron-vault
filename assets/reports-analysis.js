(function(root){
 'use strict';
 const kinds={topup:'Wallet top-up',plan_cash:'Pass paid in cash',plan_wallet:'Pass paid from wallet',refund_cash:'Cash refund',refund_wallet:'Refund to wallet',wallet_correction:'Wallet correction out',wallet_correction_in:'Wallet correction in'};
 function cents(value){const match=/^(-?)(\d+)(?:\.(\d{1,2}))?$/.exec(String(value??0));if(!match)return null;return (match[1]?-1n:1n)*(BigInt(match[2])*100n+BigInt((match[3]||'').padEnd(2,'0')));}
 function money(value){if(value===null)return 'Unavailable';const n=typeof value==='bigint'?value:cents(value);if(n===null)return 'Unavailable';const absolute=n<0n?-n:n;return (n<0n?'-':'')+'₱'+(absolute/100n).toLocaleString('en-PH')+'.'+String(absolute%100n).padStart(2,'0');}
 function walletAfter(row){const value=row?.wallet_after;if(value===null||value===undefined||!['number','string'].includes(typeof value))return 'Unavailable';const amount=cents(value);return amount===null||amount<0n?'Unavailable':money(amount);}
 function date(value){const d=new Date(value);if(Number.isNaN(d.getTime()))return '';const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(d);const get=k=>parts.find(p=>p.type===k).value;return get('year')+'-'+get('month')+'-'+get('day');}
 function validDate(value){if(!/^\d{4}-\d{2}-\d{2}$/.test(value||''))return false;const d=new Date(value+'T00:00:00Z');return !Number.isNaN(d.getTime())&&d.toISOString().slice(0,10)===value;}
 function validPass(member,today=date(new Date())){const expiry=member.expiration_date??member.expirationDate;return member.status==='ACTIVE'&&['1-Day Pass','1-Week Pass','1-Month Unlimited'].includes(member.plan)&&validDate(expiry)&&expiry>=today;}
 function expiryLabel(member,today=date(new Date())){
  if(!member)return 'Profile unavailable';
  if(!member.plan||member.plan==='Not Selected')return 'No pass';
  const expiry=member.expiration_date??member.expirationDate;
  if(!validDate(expiry))return 'Expiry unavailable';
  const label=new Intl.DateTimeFormat('en-GB',{timeZone:'UTC',day:'numeric',month:'short',year:'numeric'}).format(new Date(expiry+'T00:00:00Z'));
  const days=Math.round((new Date(expiry+'T00:00:00Z')-new Date(today+'T00:00:00Z'))/86400000);
  return days<0?'Expired '+label:days===0?'Expires today ('+label+')':'Expires '+label+' · '+days+' day'+(days===1?'':'s')+' left';
 }
 // Historical attendance must never borrow entitlement fields from the current roster.
 function attendanceDetails(row){
  const snapshot=row?.membership_snapshot;
  if(!snapshot||snapshot.version!==1)return {plan:'History unavailable',expiry:'History unavailable',status:'History unavailable'};
  const day=snapshot.business_day,expiry=snapshot.expiration_date;
  const base={plan:snapshot.plan||'History unavailable',status:snapshot.status||'History unavailable'};
  if(!validDate(day)||!validDate(expiry)||day!==date(row.created_at))return {...base,expiry:'History unavailable'};
  const label=value=>new Intl.DateTimeFormat('en-GB',{timeZone:'UTC',day:'numeric',month:'short',year:'numeric'}).format(new Date(value+'T00:00:00Z'));
  if(snapshot.plan==='1-Day Pass')return {...base,expiry:'Valid on '+label(day)};
  const days=Math.round((new Date(expiry+'T00:00:00Z')-new Date(day+'T00:00:00Z'))/86400000);
  if(days<0||!Number.isInteger(snapshot.days_remaining)||snapshot.days_remaining!==days)return {...base,expiry:'History unavailable'};
  return {...base,expiry:'Valid through '+label(expiry)+' · '+days+' day'+(days===1?'':'s')+' left'};
 }
 function auditSnapshot(row,tenant){const data=row?.audit_data;return data?.version===1&&data.tenant_id===tenant?data:null;}
 function auditActor(row,tenant){
  const actor=auditSnapshot(row,tenant)?.actor;if(!actor||typeof actor.name!=='string'||!actor.name.trim())return null;
  const roles={owner:'Gym Admin',staff:'Staff',member:'Member',super_admin:'Super Admin',unknown:'Unknown role'};
  return actor.name+' — '+(roles[actor.role]||'Unknown role');
 }
 function refundActivity(row,tenant){
  const refund=auditSnapshot(row,tenant)?.refund;if(!refund)return null;
  const operation=String(row.event||'').split(' ').at(-1),action={cash:'Cash refund',wallet:'Wallet refund',correct_credit:'Wallet credit correction'}[refund.action]||'Refund';
  const title=operation==='request'?'Refund requested':operation==='approve'?(refund.action==='correct_credit'?'Wallet credit corrected':action+' approved'):operation==='reject'?'Refund rejected':operation==='cancel'?'Refund cancelled':action;
  const member=refund.member||{},lines=['Member: '+(member.name||'Member unavailable')+(member.display_code?' · '+member.display_code:''),'Amount: '+money(refund.amount),'Reason: '+(refund.reason||'Not recorded'),'Reference: '+(refund.reference||refund.id)];
  if(operation==='request')lines.push('Pending approval—no balance change yet.');
  if(operation==='approve'&&refund.wallet_before!=null&&refund.wallet_after!=null)lines.push('Wallet: '+money(refund.wallet_before)+' → '+money(refund.wallet_after));
  if(refund.target?.id){lines.push('Corrected recipient: '+(refund.target.name||refund.target.id)+(refund.target.display_code?' · '+refund.target.display_code:''));if(operation==='approve'&&refund.target_wallet_before!=null)lines.push('Recipient wallet: '+money(refund.target_wallet_before)+' → '+money(refund.target_wallet_after));}
  if(refund.payout_reference)lines.push('Cash payout receipt: '+refund.payout_reference);
  lines.push('Technical details: Request '+refund.id+' · Original transaction '+refund.source_key);
  return {title,details:lines.join('\n')};
 }
 function analyze(snapshot,start,end,today=date(new Date())){
  if(!validDate(start)||!validDate(end)||end<start)throw Error('Choose a valid start and end date.');
  const within=row=>{const day=date(row.created_at);return day&&day>=start&&day<=end;};
  const financial=(snapshot.financial||[]).filter(within),attendance=(snapshot.attendance||[]).filter(within),purchases=(snapshot.purchases||[]).filter(within),members=snapshot.members||[];
  const totals={topup:0n,plan_cash:0n,plan_wallet:0n,refund_cash:0n,refund_wallet:0n,wallet_correction:0n,wallet_correction_in:0n};let invalid=0,other=0;const daily=new Map();
  const dayFor=day=>{if(!daily.has(day))daily.set(day,{day,cash:0n,sales:0n,visits:0});return daily.get(day);};
  for(const row of financial){const amount=cents(row.amount);if(amount===null||amount<0n){invalid++;continue;}
   if(!Object.hasOwn(totals,row.kind)){other++;continue;}totals[row.kind]+=amount;const day=dayFor(date(row.created_at));
   if(row.kind==='topup'||row.kind==='plan_cash')day.cash+=amount;
   if(row.kind==='refund_cash')day.cash-=amount;
   if(row.kind==='plan_cash'||row.kind==='plan_wallet')day.sales+=amount;
  }
  const hours=Array(24).fill(0);let qr=0,manual=0;
  for(const row of attendance){dayFor(date(row.created_at)).visits++;const hour=Number(new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Manila',hour:'2-digit',hourCycle:'h23'}).format(new Date(row.created_at)));hours[hour]++;if(row.method==='qr')qr++;if(row.method==='manual')manual++;}
  let wallet=0n;for(const member of members){const amount=cents(member.wallet_balance??member.walletBalance);if(amount===null||amount<0n)invalid++;else wallet+=amount;}
  const future=new Date(today+'T00:00:00Z');future.setUTCDate(future.getUTCDate()+7);const nextWeek=future.toISOString().slice(0,10);
  const valid=m=>validPass(m,today);
  const currentPasses=members.filter(valid),expiring=currentPasses.filter(m=>(m.expiration_date??m.expirationDate)<=nextWeek);
  const peak=Math.max(...hours);return{financial,attendance,purchases,members,totals,cashIn:totals.topup+totals.plan_cash-totals.refund_cash,
   grossSales:totals.plan_cash+totals.plan_wallet,wallet,invalid,other,purchaseCount:purchases.length,renewals:purchases.filter(p=>p.renewal===true).length,
   newMembers:members.filter(within).length,pending:members.filter(m=>m.status==='PENDING').length,activeMembers:members.filter(m=>m.status==='ACTIVE').length,
   currentPasses:currentPasses.length,expiring,visits:attendance.length,uniqueVisitors:new Set(attendance.map(a=>a.member_id)).size,qr,manual,
   otherAdmissions:attendance.length-qr-manual,peakHours:peak?hours.flatMap((n,h)=>n===peak?[h]:[]):[],peakVisits:peak,daily:[...daily.values()].sort((a,b)=>a.day.localeCompare(b.day))};
 }
 function csv(rows){return '\uFEFF'+rows.map(row=>row.map(value=>{let text=String(value??'');if(/^[\t\r\n]|^\s*[=+\-@]/.test(text))text="'"+text;return '"'+text.replace(/"/g,'""')+'"';}).join(',')).join('\r\n');}
 const api=Object.freeze({cents,money,date,validDate,validPass,analyze,expiryLabel,attendanceDetails,auditSnapshot,auditActor,refundActivity,csv,kinds,walletAfter});root.IronVaultReports=api;if(typeof module==='object'&&module.exports)module.exports=api;
})(globalThis);
