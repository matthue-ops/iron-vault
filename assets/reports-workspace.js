/* Presentation only. Uses the existing authorized report snapshot and analysis. */
(function(root){
 'use strict';
 function install(app){
  const d=root.document;if(!d.querySelector)return;const R=root.IronVaultReports,node=id=>d.getElementById(id),make=(tag,text,cls)=>{const n=d.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
  let model=null,group='overview',creditPage=0,version=0,period='',printing=false,detailView='overview',overviewRendered=false,creditsRendered=false,requestedGroup=null;
  app.ivReportsWorkspace=true;
  const button=(label,fn,parent)=>{const b=make('button',label);b.type='button';b.onclick=fn;parent.append(b);return b;};
  d.body.classList.add('reports-workspace');
  const legacy=d.querySelector('.report-tabs');legacy.classList.add('reports-legacy-tabs');
  const nav=make('nav',undefined,'reports-main-tabs no-print');nav.setAttribute('aria-label','Report views');legacy.before(nav);
  const tabs=new Map();for(const [key,label] of [['overview','Overview'],['credits','Member Credits'],['activity','Activity & Audit']])tabs.set(key,button(label,()=>show(key),nav));
  const toolbar=make('div',undefined,'reports-toolbar no-print');node('section-overview').before(toolbar);
  const dateRange=node('phone-date-range');if(dateRange){dateRange.open=false;toolbar.append(dateRange);}
  const viewLabel=make('label','View', 'reports-view-label'),viewSelect=make('select');viewSelect.setAttribute('aria-label','Report view');
  for(const [value,label] of [['overview','Summary'],['financial','Money details'],['attendance','Attendance'],['daily','Daily totals']]){const option=make('option',label);option.value=value;viewSelect.append(option);}viewLabel.append(viewSelect);toolbar.append(viewLabel);
  viewSelect.onchange=()=>{const value=viewSelect.value;app.switchTab(value==='daily'?'overview':value);detailView=value;select();};
  const actions=make('details',undefined,'reports-actions'),actionTitle=make('summary','Print & Export'),actionMenu=make('div',undefined,'reports-action-menu');actions.append(actionTitle,actionMenu);toolbar.append(actions);
  const printCurrent=button('Print overview',()=>{actions.open=false;app.printReport();},actionMenu);
  const workbook=node('report-export-excel');actionMenu.append(workbook);const csv=button('Export current table (.csv)',()=>{actions.open=false;app.exportReportCsv();},actionMenu);
  workbook.addEventListener('click',()=>{actions.open=false;});
  d.querySelector('.phone-report-export')?.remove();
  for(const b of node('report-table-tools').querySelectorAll('button[onclick]'))if(/exportReportCsv|printReport/.test(b.getAttribute('onclick')))b.remove();
  function popup(title){const dialog=make('dialog',undefined,'reports-info-dialog no-print'),head=make('div',undefined,'reports-dialog-heading');dialog.setAttribute('aria-label',title);head.append(make('h2',title));button('Close',()=>dialog.close(),head);dialog.append(head);d.body.append(dialog);return dialog;}
  const guide=popup('Report guide'),expiryDialog=popup('Passes expiring soon');
  button('ⓘ Report guide',()=>{actions.open=false;app.ivEnsureReportSection('guide');guide.showModal();},toolbar).className='reports-guide-button';
  function closeMenus(){actions.open=false;if(dateRange)dateRange.open=false;}
  d.addEventListener('click',event=>{if(!actions.contains(event.target))actions.open=false;if(dateRange&&!dateRange.contains(event.target))dateRange.open=false;if(event.target.closest('[data-report-range],#phone-date-apply'))queueMicrotask(()=>{dateRange.open=false;});});
  d.addEventListener('keydown',event=>{if(event.key==='Escape')closeMenus();});
  root.matchMedia?.('(max-width:639px)').addEventListener('change',closeMenus);
  const overview=node('section-overview'),hero=make('section',undefined,'reports-summary'),cards=make('div',undefined,'reports-summary-cards'),explain=make('p','Top-ups add prepaid credit. Spending that credit on a plan records a sale; it is not another cash receipt.','reports-explanation'),columns=make('div',undefined,'reports-columns'),trend=make('section'),breakdown=make('section'),recent=make('section'),membership=make('p');
  hero.append(cards,explain,columns,recent,membership);columns.append(trend,breakdown);node('report-overview').before(hero);node('report-overview').hidden=true;
  const credits=make('section',undefined,'reports-credits glass-card');credits.id='section-member-credits';credits.hidden=true;credits.append(make('h2','Member Credits'),make('p','Current unused wallet balances — not revenue. These balances are current, independent of the selected report dates.'));
  const creditTotal=make('p',undefined,'reports-credit-total'),controls=make('div',undefined,'reports-credit-controls no-print'),label=make('label','Search members'),search=make('input');search.type='search';search.placeholder='Name or member number';label.append(search);controls.append(label);const creditList=make('div'),pagination=make('div',undefined,'reports-credit-controls no-print'),count=make('p');button('Previous',()=>{creditPage=Math.max(0,creditPage-1);renderCredits();},pagination);button('Next',()=>{creditPage++;renderCredits();},pagination);pagination.append(count);credits.append(creditTotal,controls,creditList,pagination);overview.after(credits);search.oninput=()=>{creditPage=0;renderCredits();};
  const dailyPanel=make('section',undefined,'reports-daily-panel glass-card');dailyPanel.id='section-daily-totals';dailyPanel.hidden=true;dailyPanel.append(make('h2','Daily totals'));overview.after(dailyPanel);
  const existingDetails=[...overview.children].filter(n=>n.tagName==='DETAILS');
  for(const details of existingDetails){const title=details.querySelector('summary')?.textContent||'';const target=title.includes('How these')?guide:title.includes('Daily money')?dailyPanel:expiryDialog;for(const child of [...details.children])if(child.tagName!=='SUMMARY')target.append(child);details.remove();}
  const expiryLink=button('Passes expiring soon',()=>{app.ivEnsureReportSection('expiring');expiryDialog.showModal();},hero);expiryLink.className='reports-text-link no-print';
  function select(){
   if(model){if(group==='overview'&&detailView==='overview'&&!overviewRendered){render();overviewRendered=true;}if(group==='credits'&&!creditsRendered)renderCredits();if(group==='overview'&&detailView==='daily')app.ivEnsureReportSection('daily');if(guide.open)app.ivEnsureReportSection('guide');if(expiryDialog.open)app.ivEnsureReportSection('expiring');}
   const dateSummary=node('phone-date-summary');if(dateSummary)dateSummary.textContent=dateSummary.textContent.replace(/\s*▾$/,'');
   for(const [key,b] of tabs)b.setAttribute('aria-current',key===group?'page':'false');viewLabel.hidden=group!=='overview';viewSelect.value=detailView;
   credits.hidden=group!=='credits';dailyPanel.hidden=group!=='overview'||detailView!=='daily';
   const summary=group==='overview'&&detailView==='overview';overview.classList.toggle('hidden',!summary);overview.hidden=!summary;
   if(group==='credits'||app.currentTab==='overview')node('report-print-context').textContent=group==='credits'?'Member Credits · Current balances':(detailView==='daily'?'Daily totals':'Overview')+' · '+period;
   csv.hidden=group==='credits'||app.currentTab==='overview';printCurrent.textContent=group==='credits'?'Print member credits':detailView==='daily'&&group==='overview'?'Print daily totals':app.currentTab==='overview'?'Print overview':'Print table (current page)';
  }
  const originalSwitch=app.switchTab;app.switchTab=function(tab){closeMenus();group=requestedGroup||(tab==='audit'?'activity':'overview');detailView=tab;originalSwitch.call(this,tab);select();};
  function show(value){requestedGroup=value;try{app.switchTab(value==='activity'?'audit':'overview');}finally{requestedGroup=null;}}
  app.ivRefreshReportLayout=()=>{app.ivRefreshReportDetails();select();};
  function card(label,value,note){const box=make('article');box.append(make('h3',label),make('strong',value),make('p',note));return box;}
  function rowsTable(headings,rows){const wrap=make('div',undefined,'reports-scroll'),table=make('table'),head=make('thead'),tr=make('tr'),body=make('tbody');for(const h of headings){const th=make('th',h);th.scope='col';tr.append(th);}head.append(tr);for(const values of rows){const row=make('tr');values.forEach((v,i)=>{const td=make('td',v);td.dataset.label=headings[i];row.append(td);});body.append(row);}if(!rows.length){const row=make('tr'),td=make('td','No matching records.');td.colSpan=headings.length;row.append(td);body.append(row);}table.append(head,body);wrap.append(table);return wrap;}
  function renderCredits(all=false){creditsRendered=true;creditList.replaceChildren();if(!model){creditTotal.textContent='Load a report to view balances.';count.textContent='';return;}const q=search.value.trim().toLowerCase(),members=model.members.filter(m=>{const amount=R.cents(m.wallet_balance??m.walletBalance);return amount!==null&&amount>0n;}).filter(m=>!q||[m.name,m.display_code||m.displayCode||m.id].some(x=>String(x||'').toLowerCase().includes(q))).sort((a,b)=>String(a.name).localeCompare(String(b.name)));if(group==='credits')node('report-print-context').textContent='Member Credits · Current balances'+(q?' · Search: '+search.value:'');creditPage=Math.min(creditPage,Math.max(0,Math.ceil(members.length/100)-1));const total=members.reduce((s,m)=>s+R.cents(m.wallet_balance??m.walletBalance),0n);creditTotal.textContent=R.money(total)+' · '+members.length+' matching members';const visible=all?members:members.slice(creditPage*100,(creditPage+1)*100);creditList.append(rowsTable(['Member','Member number','Unused credit'],visible.map(m=>[m.name,m.display_code||m.displayCode||m.id,R.money(R.cents(m.wallet_balance??m.walletBalance))])));count.textContent=members.length?'Showing '+(creditPage*100+1)+'–'+Math.min((creditPage+1)*100,members.length)+' of '+members.length:'No members with unused credit';pagination.children[0].disabled=creditPage===0;pagination.children[1].disabled=(creditPage+1)*100>=members.length;}
  function render(){cards.replaceChildren();trend.replaceChildren();breakdown.replaceChildren();recent.replaceChildren();membership.textContent='';expiryLink.textContent='Passes expiring soon';if(!model)return;expiryLink.textContent=model.expiring.length+' pass'+(model.expiring.length===1?'':'es')+' expiring soon';
   explain.textContent='Top-ups add prepaid credit. Spending that credit on a plan records a sale; it is not another cash receipt.'+(model.invalid?' Warning: '+model.invalid+' invalid values were excluded; inspect Money details.':'')+(model.other?' Unclassified entries are shown in Money details but excluded from summary totals.':'');
   for(const row of [['Plan Revenue',R.money(model.grossSales),'Before refunds · selected period'],['Wallet Top-ups',R.money(model.totals.topup),'Prepaid funds added · selected period'],['Unused Credits',R.money(model.wallet),'Current balance · all members'],['Member Visits',String(model.visits),'Check-ins · selected period']])cards.append(card(...row));
   trend.append(make('h3','Revenue by day'),make('p','Last 14 days with recorded activity in the selected period.'));const days=model.daily.slice(-14),max=days.reduce((m,x)=>x.sales>m?x.sales:m,0n),bars=make('div',undefined,'reports-bars');for(const day of days){const row=make('div',undefined,'reports-bar-row'),track=make('div',undefined,'reports-bar-track'),bar=make('span');bar.style.width=(max?Number(day.sales*1000n/max)/10:0)+'%';track.append(bar);row.append(make('span',day.day.slice(5)),track,make('span',R.money(day.sales)));bars.append(row);}if(!days.length)bars.append(make('p','No activity recorded for these dates.'));trend.append(bars);
   breakdown.append(make('h3','Revenue breakdown'),rowsTable(['Source','Amount'],[['Cash plan payments',R.money(model.totals.plan_cash)],['Wallet plan payments',R.money(model.totals.plan_wallet)],['Total plan sales',R.money(model.grossSales)],['Net cash received',R.money(model.cashIn)]]),make('p','Net cash includes top-ups and cash plan payments, less cash refunds. Wallet spending is not a second cash receipt.'));
   const byId=new Map(model.members.map(m=>[m.id,m]));recent.append(make('h3','Recent attendance'));recent.append(rowsTable(['Member','Check-in (Manila)','Plan at entry','Valid until'],[...model.attendance].sort((a,b)=>new Date(b.created_at)-new Date(a.created_at)).slice(0,5).map(a=>{const details=R.attendanceDetails(a);return[byId.get(a.member_id)?.name||'Member unavailable',new Date(a.created_at).toLocaleString('en-PH',{timeZone:'Asia/Manila'}),details.plan,details.expiry];})));
   membership.textContent='Membership activity · '+model.newMembers+' new registrations · '+model.renewals+' repeat purchases · '+model.currentPasses+' currently valid passes.';
  }
  function clearOverview(){cards.replaceChildren();trend.replaceChildren();breakdown.replaceChildren();recent.replaceChildren();membership.textContent='';expiryLink.textContent='Passes expiring soon';}
  const oldRender=app.ivRender;app.ivRender=async function(start,end){
   const request=this.ivRequest;await oldRender.apply(this,arguments);const view=this.ivGetReportView();
   if(!view||view.start!==start||view.end!==end||request!==this.ivRequest)return;
   model=view.model;period=start+' to '+end;version=view.version;overviewRendered=creditsRendered=false;clearOverview();creditList.replaceChildren();creditTotal.textContent=count.textContent='';select();
  };
  const oldClear=app.ivClear;app.ivClear=function(){closeMenus();guide.close();expiryDialog.close();version++;model=null;overviewRendered=creditsRendered=false;creditPage=0;search.value='';oldClear.apply(this,arguments);clearOverview();renderCredits();};
  app.ivCredits=()=>show('credits');
  const oldPrint=app.printReport;app.printReport=async function(){if(group!=='credits'&&this.currentTab!=='overview')return oldPrint.apply(this,arguments);const stamp=version,t=this.currentTenant?.id,view=group,tab=this.currentTab,selected=detailView;try{const before=await this.ivRequireReport();await this.ivRequireExport?.();const after=await this.ivRequireReport();if(!model||stamp!==version||t!==this.currentTenant?.id||view!==group||tab!==this.currentTab||selected!==detailView||before.user_id!==after.user_id)return;if(group==='credits')renderCredits(true);printing=true;root.print();}catch(e){this.ivDeny(e);}finally{if(printing){printing=false;if(group==='credits')renderCredits();}}};
  root.addEventListener('beforeprint',()=>{if(group==='credits')renderCredits(true);});root.addEventListener('afterprint',()=>{if(group==='credits')renderCredits();});
  credits.append(make('p','Balances shown from the last loaded member snapshot. Refresh the report to retrieve updates.','reports-explanation'));
  app.openReportView=show;show('overview');
 }
 root.IronVaultReportsWorkspace=Object.freeze({install});
})(globalThis);
