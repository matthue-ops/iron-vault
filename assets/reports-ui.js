(function(root){
 'use strict';
 function install(app,client){
  const R=root.IronVaultReports,node=id=>root.document.getElementById(id);let page=0,model=null,period=null;
  const oldRender=app.ivRender,oldClear=app.ivClear;
  const stamp=value=>new Date(value).toLocaleString('en-PH',{timeZone:'Asia/Manila'});
  const code=(m,fallback)=>m?.display_code||m?.displayCode||m?.id||fallback||'—';
  function clear(){model=null;period=null;node('report-overview').textContent='';node('report-insights').textContent='';node('report-daily').textContent='';node('report-expiring').textContent='';node('overview-period').textContent='';node('report-expiring-count').textContent='';}
  app.ivClear=function(){oldClear.call(this);clear();};
  function tableRows(){
   if(!model)return[];const members=new Map(model.members.map(m=>[m.id,m]));
   if(app.currentTab==='attendance')return model.attendance.map(a=>[code(members.get(a.member_id),a.member_id),members.get(a.member_id)?.name||'—',members.get(a.member_id)?.plan||'—',stamp(a.created_at),a.method==='qr'?'QR scan':a.method==='manual'?'Manual desk entry':a.method,'—',members.get(a.member_id)?.status||'—']);
   if(app.currentTab==='audit'){
    const rows=app.ivMode==='sessions'?(app.ivSessions||[]).map(s=>({...s,event:'Staff '+s.event,details:s.event})):app.ivMode==='activity'?app.ivActivity||[]:model.financial.map(t=>({...t,event:R.kinds[t.kind]||t.kind,details:code(members.get(t.member_id),t.member_id)+' '+R.money(t.amount)}));
    return rows.map(a=>[stamp(a.created_at),a.actor_id||'System',a.event,a.details||'']);
   }
   return model.financial.map(t=>[code(members.get(t.member_id),t.member_id),members.get(t.member_id)?.name||'—',members.get(t.member_id)?.classification||'—',R.kinds[t.kind]||t.kind,R.money(t.amount),R.money(members.has(t.member_id)?members.get(t.member_id).wallet_balance??members.get(t.member_id).walletBalance:null),stamp(t.created_at),t.description||'—']);
  }
  function matches(){const query=node('report-search').value.trim().toLowerCase();return tableRows().filter(row=>!query||row.some(cell=>String(cell).toLowerCase().includes(query)));}
  function rowsInto(id,rows){const body=node(id);body.textContent='';for(const cells of rows){const row=root.document.createElement('tr');for(const value of cells){const cell=root.document.createElement('td');cell.className='p-3';cell.textContent=value;row.appendChild(cell);}body.appendChild(row);}}
  function renderDetails(){if(!model)return;const rows=matches();page=Math.min(page,Math.max(0,Math.ceil(rows.length/100)-1));const kind=app.currentTab==='attendance'?'attendance':app.currentTab==='audit'?'audit':'financial';
   rowsInto(kind+'-tbody',rows.slice(page*100,(page+1)*100));node('report-page').textContent=rows.length?'Showing '+(page*100+1)+'–'+Math.min((page+1)*100,rows.length)+' of '+rows.length+' matching rows':'No matching records';
   node('report-prev').disabled=page===0;node('report-next').disabled=(page+1)*100>=rows.length;
  }
  function card(label,value,note){const box=root.document.createElement('div');box.className='bg-slate-900/70 rounded-xl p-4 border border-slate-700';const heading=root.document.createElement('p');heading.className='text-xs text-slate-300';heading.textContent=label;
   const number=root.document.createElement('p');number.className='text-xl font-bold text-emerald-300 mt-2';number.textContent=value;const detail=root.document.createElement('p');detail.className='text-xs text-slate-400 mt-2';detail.textContent=note;box.appendChild(heading);box.appendChild(number);box.appendChild(detail);return box;}
  function overview(){
   const box=node('report-overview');box.textContent='';node('overview-period').textContent='Selected period: '+period.start+' to '+period.end+' · Asia/Manila';
   for(const [label,value,note] of [
    ['Net cash collected',R.money(model.cashIn),'Selected period: top-ups + cash pass payments − cash refunds.'],
    ['Gross membership sales',R.money(model.grossSales),'Selected period: cash + wallet pass spending. Top-ups excluded.'],
    ['Wallet top-ups',R.money(model.totals.topup),'Selected period: cash received as prepaid member credit.'],
    ['Wallet used for passes',R.money(model.totals.plan_wallet),'Selected period: previously collected credit spent on passes.'],
    ['Cash refunds',R.money(model.totals.refund_cash),'Selected period: recorded cash refunds only.'],
    ['Outstanding wallet credit now',R.money(model.wallet),'Current snapshot across all member statuses; not a historical closing balance.'],
    ['Recorded pass purchases',String(model.purchaseCount),'One per purchase receipt, including split payments. Older sales without receipts are excluded.'],
    ['Recorded repeat purchases',String(model.renewals),'Receipts with an earlier recorded pass purchase for the same member.'],
    ['New registrations',String(model.newMembers),'Created during this period; based on account creation time, not last renewal date.'],
    ['Current valid passes',String(model.currentPasses),'Active members with an unexpired, recognized pass today.'],
    ['Pending approvals now',String(model.pending),'Current waiting list, regardless of selected report dates.'],
    ['Visits / unique visitors',model.visits+' / '+model.uniqueVisitors,'Selected period. Repeat visits count once each; visitors count once per member.']])box.appendChild(card(label,value,note));
   node('report-insights').textContent='Roster now: '+model.activeMembers+' active · '+model.pending+' pending · '+model.members.length+' total (including inactive). Attendance: '+model.qr+' QR scans · '+model.manual+' manual entries · '+model.otherAdmissions+' other entries. '+(model.peakHours.length?'Busiest recorded hour'+(model.peakHours.length>1?'s':'')+': '+model.peakHours.map(h=>String(h).padStart(2,'0')+':00–'+String(h).padStart(2,'0')+':59').join(', ')+' ('+model.peakVisits+' visits each).':'No attendance recorded in this period.')+
    (model.invalid?' Warning: '+model.invalid+' invalid money values were excluded from totals.':'')+(model.other?' '+model.other+' unclassified financial entries appear in the detail log and are excluded from the summary.':'');
   rowsInto('report-daily',model.daily.map(d=>[d.day,R.money(d.cash),R.money(d.sales),String(d.visits)]));
   rowsInto('report-expiring',model.expiring.map(m=>[code(m),m.name,m.plan,m.expiration_date??m.expirationDate]));
   node('report-expiring-count').textContent=model.expiring.length+' current passes expire within the next 7 days (including today).';
  }
  app.ivRender=async function(start,end){
   await oldRender.call(this,start,end);if(!this.ivFinance)return;
   model=R.analyze({financial:this.ivFinance,attendance:this.ivAttendance,purchases:this.ivPurchases||[],members:this.branchMembers},start,end);period={start,end};
   node('report-range-subtitle').textContent='Report period: '+start+' to '+end;node('report-generated-timestamp').textContent=stamp(new Date());
   node('metric-revenue').textContent=R.money(model.cashIn);node('metric-credits').textContent=R.money(model.wallet);node('metric-registrations').textContent=model.purchaseCount;node('metric-subscriptions').textContent=model.currentPasses;
   overview();renderDetails();
  };
  const oldSwitch=app.switchTab;app.switchTab=function(tab){oldSwitch.call(this,tab);page=0;renderDetails();};
  app.exportReportCsv=async function(){try{
   await this.ivRequireReport();if(!model||!period)throw Error('Load a report first.');
   const kind=this.currentTab==='attendance'?'attendance':this.currentTab==='audit'?'audit':'financial';
   const headings=kind==='attendance'?['Member code','Name','Current plan','Check-in (Asia/Manila)','Method','Unused','Current status']:kind==='audit'?['Time (Asia/Manila)','Actor ID','Action','Details']:['Member code','Name','Classification','Entry type','Amount','Current wallet credit','Time (Asia/Manila)','Description'];
   const text=R.csv([['Gym',this.currentTenant.gymName],['Period',period.start,period.end],['Timezone','Asia/Manila'],['Note','Balances, plans, classifications and statuses reflect the current snapshot. CSV includes all matching detail rows.'],headings,...matches()]);
   const url=root.URL.createObjectURL(new root.Blob([text],{type:'text/csv;charset=utf-8'}));const link=root.document.createElement('a');link.href=url;link.download='IronVault_'+kind+'_'+period.start+'_'+period.end+'.csv';link.click();root.setTimeout(()=>root.URL.revokeObjectURL(url),1000);
  }catch(error){this.ivDeny(error);}};
  node('report-search').addEventListener('input',()=>{page=0;renderDetails();});node('report-prev').addEventListener('click',()=>{page--;renderDetails();});node('report-next').addEventListener('click',()=>{page++;renderDetails();});
  const change=app.onDateFilterChange;app.onDateFilterChange=function(){const start=node('filter-date-start').value,end=node('filter-date-end').value;node('report-validation').textContent='';if(!R.validDate(start)||!R.validDate(end)||end<start){node('report-validation').textContent='Choose a valid start date and an end date on or after it. The last valid report remains displayed.';return;}return change.call(this);};
  app.setQuickRange=function(type){const today=R.date(new Date());let start=today;
   if(type==='week'){const first=new Date(today+'T00:00:00Z');first.setUTCDate(first.getUTCDate()-6);start=first.toISOString().slice(0,10);}
   else if(type==='month')start=today.slice(0,7)+'-01';else if(type==='all')start='1900-01-01';
   node('filter-date-start').value=start;node('filter-date-end').value=today;return this.onDateFilterChange();
  };
 }
 root.IronVaultReportsUI=Object.freeze({install});
})(globalThis);
