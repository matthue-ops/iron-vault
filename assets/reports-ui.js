(function(root){
 'use strict';
 function install(app,client){
  const R=root.IronVaultReports,node=id=>root.document.getElementById(id);let page=0,model=null,period=null,snapshotAt=null,reportVersion=0,exporting=false;
  const oldRender=app.ivRender,oldClear=app.ivClear;
  const stamp=value=>new Date(value).toLocaleString('en-PH',{timeZone:'Asia/Manila'});
  const code=(m,fallback)=>m?.display_code||m?.displayCode||m?.id||fallback||'—';
  function clear(){reportVersion++;snapshotAt=null;node('report-export-excel').disabled=true;model=null;period=null;node('report-overview').textContent='';node('report-insights').textContent='';node('report-daily').textContent='';node('report-expiring').textContent='';node('overview-period').textContent='';node('report-expiring-count').textContent='';node('report-money-summary').textContent='';node('report-attendance-summary').textContent='';node('report-print-context').textContent='';node('report-sales-details').textContent='';}
  app.ivClear=function(){oldClear.call(this);clear();};
  const roleNames={owner:'Gym Admin',staff:'Staff',member:'Member',super_admin:'Super Admin'};
  function actorLabel(id){
   if(!id)return 'System';
   const actor=(app.ivActors||[]).find(a=>String(a.user_id).toLowerCase()===String(id).toLowerCase()&&Object.hasOwn(roleNames,a.role));
   if(!actor)return 'Account unavailable';
   const name=typeof actor.name==='string'&&actor.name.trim()?actor.name.trim():'Name unavailable';
   return name+' — '+roleNames[actor.role];
  }
  function activityDetailsFormatter(){
   const members=new Map((model?.members||[]).filter(m=>(m.tenantId??m.tenant_id)===app.currentTenant?.id).map(m=>[String(m.id).toLowerCase(),m]));
   const escape=value=>value.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
   const ids=Array.from(members.keys()).sort((a,b)=>b.length-a.length).map(escape);
   const uuid='[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}';
   const references=new RegExp('(?<![a-z0-9_-])(?:'+[...ids,uuid].join('|')+')(?![a-z0-9_-])','gi');
   return text=>String(text||'').replace(references,id=>{
    const member=members.get(id.toLowerCase());
    if(member){
     const name=typeof member.name==='string'&&member.name.trim()?member.name.trim():'Name unavailable';
     const shortCode=member.display_code||member.displayCode||member.id;
     return name+(/^MEM-\d{4,}$/i.test(shortCode)?' · '+shortCode:'');
    }
    return (app.ivActors||[]).some(a=>String(a.user_id).toLowerCase()===id.toLowerCase())?actorLabel(id):id;
   }).replace(/(Target account:\s*)([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})\b/gi,(_,prefix,id)=>prefix+actorLabel(id));
  }
  function tableRows(tab=app.currentTab,mode=app.ivMode){
   if(!model)return[];const members=new Map(model.members.map(m=>[m.id,m]));
   if(tab==='attendance')return model.attendance.map(a=>{const history=R.attendanceDetails(a);return [code(members.get(a.member_id),a.member_id),members.get(a.member_id)?.name||'—',history.plan,stamp(a.created_at),a.method==='qr'?'QR scan':a.method==='manual'?'Manual desk entry':a.method,history.expiry,history.status];});
   if(tab==='audit'){
    const within=row=>{const d=R.date(row.created_at);return d>=period.start&&d<=period.end;};
    const sessions=(app.ivSessions||[]).map(s=>{const actor=(app.ivActors||[]).find(a=>a.user_id===s.actor_id);return {...s,event:(roleNames[actor?.role]||'Account')+' '+s.event,details:s.event};});
    const rows=(mode==='sessions'?sessions:mode==='activity'?(app.ivActivity||[]):[...(app.ivActivity||[]),...sessions]).filter(within).sort((a,b)=>new Date(b.created_at)-new Date(a.created_at));
    const details=activityDetailsFormatter();
    return rows.map(a=>{const refund=R.refundActivity(a,app.currentTenant?.id);return [stamp(a.created_at),R.auditActor(a,app.currentTenant?.id)||actorLabel(a.actor_id),refund?.title||a.event,refund?.details||(R.auditSnapshot(a,app.currentTenant?.id)?String(a.details||''):details(a.details))];});
   }
   return model.financial.map(t=>[code(members.get(t.member_id),t.member_id),members.get(t.member_id)?.name||'—',members.get(t.member_id)?.classification||'—',R.kinds[t.kind]||t.kind,R.money(t.amount),R.walletAfter(t),stamp(t.created_at),t.description||'—']);
  }
  function matches(){const query=node('report-search').value.trim().toLowerCase();return tableRows().filter(row=>!query||row.some(cell=>String(cell).toLowerCase().includes(query)));}
  function rowsInto(id,rows){const body=node(id);body.textContent='';for(const cells of rows){const row=root.document.createElement('tr');for(const value of cells){const cell=root.document.createElement('td');cell.className='p-3';if(id==='audit-tbody'&&String(value).includes('Technical details: ')){const [summary,technical]=String(value).split('Technical details: ');cell.textContent=summary;cell.style.whiteSpace='pre-line';const more=root.document.createElement('details'),label=root.document.createElement('summary'),text=root.document.createElement('p');label.textContent='Technical details';text.textContent=technical;more.appendChild(label);more.appendChild(text);cell.appendChild(more);}else cell.textContent=value;row.appendChild(cell);}body.appendChild(row);}}
  const pageSize=()=>root.matchMedia?.('(max-width:639px)').matches?10:100;
  function renderDetails(){if(!model||app.currentTab==='overview')return;const rows=matches();page=Math.min(page,Math.max(0,Math.ceil(rows.length/pageSize())-1));const kind=app.currentTab==='attendance'?'attendance':app.currentTab==='audit'?'audit':'financial';
   if(kind==='audit')node('metric-audit-count').textContent=rows.length+' records';
   rowsInto(kind+'-tbody',rows.slice(page*pageSize(),(page+1)*pageSize()));node('report-page').textContent=rows.length?'Showing '+(page*pageSize()+1)+'–'+Math.min((page+1)*pageSize(),rows.length)+' of '+rows.length+' matching rows':'No matching records';
   app.phoneReportChanged?.();node('report-prev').disabled=page===0;node('report-next').disabled=(page+1)*pageSize()>=rows.length;node('report-print-context').textContent=(app.currentTab==='financial'?'Money':app.currentTab==='audit'?'Activity':'Attendance')+' · '+node('report-page').textContent+(node('report-search').value?' · Search: '+node('report-search').value:'')+(kind==='attendance'?' · Membership details are saved at check-in; days left exclude that day. Older history may be unavailable.':'');
  }
  function card(label,value,note){const box=root.document.createElement('div');box.className='bg-slate-900/70 rounded-xl p-4 border border-slate-700';const heading=root.document.createElement('p');heading.className='text-xs text-slate-300';heading.textContent=label;
   const number=root.document.createElement('p');number.className='text-xl font-bold text-emerald-300 mt-2';number.textContent=value;const detail=root.document.createElement('p');detail.className='text-xs text-slate-400 mt-2';detail.textContent=note;box.appendChild(heading);box.appendChild(number);box.appendChild(detail);return box;}
  function overview(){
   const box=node('report-overview');box.textContent='';node('overview-period').textContent='Selected period: '+period.start+' to '+period.end+' · Asia/Manila';
   for(const [label,value,note] of [
    ['Membership sales',R.money(model.grossSales),'Selected period'],
    ['Outstanding wallet credit',R.money(model.wallet),'Current'],
    ['Visits',String(model.visits),'Selected period'],
    ['Valid passes',String(model.currentPasses),'Current']])box.appendChild(card(label,value,note));
   const money=node('report-money-summary');money.textContent='';
   for(const [label,value] of [['Membership sales',model.grossSales],['Wallet top-ups',model.totals.topup],['Wallet spending',model.totals.plan_wallet],['Cash refunds',model.totals.refund_cash],['Refunds to wallet',model.totals.refund_wallet],['Credit corrections out',model.totals.wallet_correction],['Credit corrections in',model.totals.wallet_correction_in],['Net cash received',model.cashIn]])money.appendChild(card(label,R.money(value),'Selected period'));
   node('report-sales-details').textContent='Recorded pass purchases: '+model.purchaseCount+' · Repeat purchases: '+model.renewals+' · New registrations: '+model.newMembers+'. Receipts count one purchase even when payment is split; older sales without receipts are excluded from purchase counts.';
   const attendance=node('report-attendance-summary');attendance.textContent='';
   for(const [label,value,note] of [['Visits / unique visitors',model.visits+' / '+model.uniqueVisitors,'Selected period'],['Entry methods',model.qr+' QR · '+model.manual+' manual · '+model.otherAdmissions+' other','Selected period'],['Valid passes',String(model.currentPasses),'Current membership validity']])attendance.appendChild(card(label,value,note));
   node('report-insights').textContent='Roster now: '+model.activeMembers+' active · '+model.pending+' pending · '+model.members.length+' total (including inactive). Attendance: '+model.qr+' QR scans · '+model.manual+' manual entries · '+model.otherAdmissions+' other entries. '+(model.peakHours.length?'Busiest recorded hour'+(model.peakHours.length>1?'s':'')+': '+model.peakHours.map(h=>String(h).padStart(2,'0')+':00–'+String(h).padStart(2,'0')+':59').join(', ')+' ('+model.peakVisits+' visits each).':'No attendance recorded in this period.')+
    (model.invalid?' Warning: '+model.invalid+' invalid money values were excluded from totals.':'')+(model.other?' '+model.other+' unclassified financial entries appear in the detail log and are excluded from the summary.':'');
   rowsInto('report-daily',model.daily.map(d=>[d.day,R.money(d.cash),R.money(d.sales),String(d.visits)]));
   rowsInto('report-expiring',model.expiring.map(m=>[code(m),m.name,m.plan,m.expiration_date??m.expirationDate]));
   node('report-expiring-count').textContent=model.expiring.length+' current passes expire within the next 7 days (including today).';
  }
  app.ivRender=async function(start,end){
   await oldRender.call(this,start,end);if(!this.ivFinance)return;
   model=R.analyze({financial:this.ivFinance,attendance:this.ivAttendance,purchases:this.ivPurchases||[],members:this.branchMembers},start,end);period={start,end};snapshotAt=new Date();reportVersion++;node('report-export-excel').disabled=exporting;
   node('report-range-subtitle').textContent='Report period: '+start+' to '+end;node('report-generated-timestamp').textContent=stamp(snapshotAt);
   node('metric-revenue').textContent=R.money(model.grossSales);node('metric-credits').textContent=R.money(model.wallet);node('metric-registrations').textContent=model.purchaseCount;node('metric-subscriptions').textContent=model.currentPasses;
   overview();renderDetails();
  };
  const searches={},pages={};
  app.switchTab=function(tab){
   if(!['overview','financial','attendance','audit'].includes(tab))return;
   searches[this.currentTab]=node('report-search').value;pages[this.currentTab]=page;this.currentTab=tab;page=pageSize()===10?(pages[tab]||0):0;
   node('report-search').value=searches[tab]||'';
   for(const name of ['overview','financial','attendance','audit']){
    const panel=node(name==='overview'?'section-overview':'section-'+name+'-table');
    panel.hidden=name!==tab;panel.classList.toggle('hidden',name!==tab);
    const button=node('tab-btn-'+name);button.setAttribute('aria-selected',String(name===tab));button.setAttribute('aria-controls',panel.id);button.classList.toggle('report-tab-active',name===tab);
   }
   const tools=node('report-table-tools');tools.hidden=tab==='overview';
   if(tab!=='overview'){const panel=node('section-'+tab+'-table'),container=panel.querySelector?.('.phone-report-records')||panel;if(container.insertBefore)container.insertBefore(tools,container.querySelector('.overflow-x-auto'));else container.appendChild(tools);}
   node('report-search').placeholder=tab==='audit'?'Name, role, action, date…':'Member code, name, type, date…';
   renderDetails();
  };
  app.ivChoose=function(mode){this.ivMode=['sessions','activity'].includes(mode)?mode:'all';page=0;renderDetails();};
  app.printReport=async function(){try{await this.ivRequireReport();await this.ivRequireExport?.();if(!model||this.currentTab==='overview')return;renderDetails();root.print();}catch(error){this.ivDeny(error);}};
  function excelMoney(value){
   const cents=typeof value==='bigint'?value:R.cents(value);
   if(cents===null)return 'Unavailable';
   if(cents>999999999999999n||cents< -999999999999999n)return R.money(cents);
   return {value:Number(cents)/100,format:'money'};
  }
  app.exportAllReportsXlsx=async function(){
   if(exporting)return;
   const button=node('report-export-excel');exporting=true;button.disabled=true;button.textContent='Preparing Excel…';
   try{
    let actor;try{actor=await this.ivRequireReport();await this.ivRequireExport?.();}catch(error){this.ivDeny(error);return;}
    if(!model||!period||!snapshotAt)throw Error('Load a report first.');
    const loaded=model,version=reportVersion,request=this.ivRequest,tenant=this.currentTenant.id;
    const exportedAt=new Date(),gym=this.currentTenant.gymName,start=period.start,end=period.end;
    const metadata=[['Gym',gym],['Report period',start+' to '+end],['Timezone','Asia/Manila'],['Current snapshot as of',stamp(snapshotAt)],['Export generated',stamp(exportedAt)],['Scope','All selected-period records; table search, Activity type filter and pagination do not limit this workbook. Current values are not historical month-end balances.']];
    const summary=[['Metric','Value','Scope / explanation'],
     ['Membership sales',excelMoney(loaded.grossSales),'Selected period: cash and wallet pass payments.'],
     ['Outstanding wallet credit',excelMoney(loaded.wallet),'Current snapshot at the time this report loaded.'],
     ['Visits',loaded.visits,'Selected period'],['Valid passes',loaded.currentPasses,'Current snapshot at the time this report loaded.'],[],
     ['Money summary','Amount (PHP)','Selected-period totals'],
     ['Membership sales',excelMoney(loaded.grossSales),'Cash and wallet pass payments; top-ups are not additional sales.'],
     ['Wallet top-ups',excelMoney(loaded.totals.topup),'Prepaid credit collected'],
     ['Wallet spending',excelMoney(loaded.totals.plan_wallet),'Credit spent on passes'],
     ['Cash refunds',excelMoney(loaded.totals.refund_cash),'Recorded cash refunds only'],
     ['Refunds to wallet',excelMoney(loaded.totals.refund_wallet),'Wallet credit, no cash payout'],
     ['Credit corrections out',excelMoney(loaded.totals.wallet_correction),'Erroneous credit reversed, no cash payout'],
     ['Credit corrections in',excelMoney(loaded.totals.wallet_correction_in),'Incoming corrected credit, no cash receipt'],
     ['Net cash received',excelMoney(loaded.cashIn),'Top-ups + cash pass payments − cash refunds. Do not add to membership sales.'],[],
     ['Attendance summary','Count','Scope'],['Unique visitors',loaded.uniqueVisitors,'Selected period'],['QR entries',loaded.qr,'Selected period'],['Manual entries',loaded.manual,'Selected period'],['Other entries',loaded.otherAdmissions,'Selected period'],[],
     ['Other report counts','Count','Scope'],['Recorded pass purchases',loaded.purchaseCount,'Selected-period receipts; split payment counts as one purchase.'],['Repeat purchases',loaded.renewals,'Selected-period receipts with an earlier recorded purchase.'],['New registrations',loaded.newMembers,'Selected period'],['Pending approvals',loaded.pending,'Current snapshot'],[],
     ['Data notes','', 'Wallet after comes from a matching saved receipt. Unavailable history is not inferred. Attendance plan, expiry, remaining days and status use saved check-in history; unavailable history is not inferred. Remaining days exclude the check-in day. New structured activity records preserve actor names/roles and details at the event. Older activity names and other profile labels use currently available information. Older sales without receipts do not contribute to purchase counts.'],
     ['Excluded invalid money values',loaded.invalid,'Excluded from summary totals; original detail records remain included.'],['Unclassified financial entries',loaded.other,'Excluded from summary totals; original detail records remain included.'],[],
     ['Daily totals (Manila)','Net cash (PHP)','Membership sales (PHP)','Visits'],...loaded.daily.map(day=>[day.day,excelMoney(day.cash),excelMoney(day.sales),day.visits]),[],
     ['Passes expiring within 7 days','Member name','Current plan','Current expiry'],...loaded.expiring.map(member=>[code(member),member.name,member.plan,member.expiration_date??member.expirationDate])];
    const money=tableRows('financial').map((row,i)=>{const tx=loaded.financial[i];row[4]=excelMoney(tx.amount);row[5]=R.walletAfter(tx)==='Unavailable'?'Unavailable':excelMoney(tx.wallet_after);return row;});
    const sheets=[
     {name:'Overview',rows:[...metadata,...summary],headerRow:7,widths:[36,32,90,24]},
     {name:'Money',rows:[...metadata,['Member code','Name','Classification','Entry type','Transaction amount (PHP)','Wallet after (PHP)','Recorded at (Manila)','Description'],...money],headerRow:7,widths:[18,28,18,28,25,23,27,65],filter:true},
     {name:'Attendance',rows:[...metadata,['Member code','Name','Plan at check-in','Check-in (Manila)','Entry method','Expiry / days left at check-in','Status at check-in'],...tableRows('attendance')],headerRow:7,widths:[18,28,25,27,25,40,20],filter:true},
     {name:'Activity',rows:[...metadata,['Recorded at (Manila)','Name / role','Action','Details'],...tableRows('audit','all')],headerRow:7,widths:[27,36,40,85],filter:true}
    ];
    const bytes=await root.IronVaultReportsExcel.create(sheets,root.JSZip||await root.IronVaultReportsExcel.loadZip());
    let after;try{after=await this.ivRequireReport();await this.ivRequireExport?.();}catch(error){this.ivDeny(error);return;}
    if(after.user_id!==actor.user_id||this.currentTenant?.id!==tenant||model!==loaded||reportVersion!==version||this.ivRequest!==request)throw Error('The report changed during export. Load the desired period and export again.');
    const blob=new root.Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
    const url=root.URL.createObjectURL(blob),link=root.document.createElement('a');link.href=url;link.download=root.IronVaultReportsExcel.filename(gym,start,end);
    try{link.click();}finally{root.setTimeout(()=>root.URL.revokeObjectURL(url),1000);}
   }catch(error){root.alert('Excel export not completed: '+error.message);}
   finally{exporting=false;button.disabled=!model;button.textContent='Export all reports (.xlsx)';}
  };
  app.exportReportCsv=async function(){try{
   await this.ivRequireReport();await this.ivRequireExport?.();if(this.currentTab==='overview')return;if(!model||!period)throw Error('Load a report first.');
   const kind=this.currentTab==='attendance'?'attendance':this.currentTab==='audit'?'audit':'financial';
   const headings=kind==='attendance'?['Member code','Name','Plan at check-in','Check-in (Asia/Manila)','Method','Expiry / days left at check-in','Status at check-in']:kind==='audit'?['Time (Asia/Manila)','Name / role','Action','Details']:['Member code','Name','Classification','Entry type','Transaction amount','Wallet after','Time (Asia/Manila)','Description'];
   const text=R.csv([['Gym',this.currentTenant.gymName],['Period',period.start,period.end],['Timezone','Asia/Manila'],['Note',kind==='financial'?'Wallet after is the saved balance immediately after that transaction; Unavailable means the historical balance cannot be verified. Names and classifications reflect current profiles. CSV includes all matching rows.':'Attendance uses saved check-in history. New structured activity uses actor and action details saved at the event; older entries remain as recorded. Other profile labels use current information. CSV includes all matching rows.'],headings,...matches()]);
   const url=root.URL.createObjectURL(new root.Blob([text],{type:'text/csv;charset=utf-8'}));const link=root.document.createElement('a');link.href=url;link.download='IronVault_'+kind+'_'+period.start+'_'+period.end+'.csv';link.click();root.setTimeout(()=>root.URL.revokeObjectURL(url),1000);
  }catch(error){this.ivDeny(error);}};
  node('report-search').addEventListener('input',()=>{page=0;renderDetails();});node('report-prev').addEventListener('click',()=>{page--;renderDetails();});node('report-next').addEventListener('click',()=>{page++;renderDetails();});
  const change=app.onDateFilterChange;app.onDateFilterChange=function(){const start=node('filter-date-start').value,end=node('filter-date-end').value;node('report-validation').textContent='';if(!R.validDate(start)||!R.validDate(end)||end<start){node('report-validation').textContent='Choose a valid start date and an end date on or after it. The last valid report remains displayed.';return;}return change.call(this);};
  app.setQuickRange=function(type){const today=R.date(new Date());let start=today;
   if(type==='week'){const first=new Date(today+'T00:00:00Z');first.setUTCDate(first.getUTCDate()-6);start=first.toISOString().slice(0,10);}
   else if(type==='month')start=today.slice(0,7)+'-01';else if(type==='all')start='1900-01-01';
   node('filter-date-start').value=start;node('filter-date-end').value=today;return this.onDateFilterChange();
  };
  node('report-export-excel').disabled=true;app.ivMode='all';app.switchTab('overview');
 }
 root.IronVaultReportsUI=Object.freeze({install});
})(globalThis);
