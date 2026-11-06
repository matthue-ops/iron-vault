/* Phone-only presentation; calculations, authorization and exports stay in ReportsUI. */
(function(root){
 'use strict';
 const node=id=>root.document.getElementById(id),make=(tag,text,cls)=>{const n=root.document.createElement(tag);if(text)n.textContent=text;if(cls)n.className=cls;return n;};
 function prepare(){
  if(!root.matchMedia)return;
  const d=root.document,media=root.matchMedia('(max-width:639px)');
  const filter=node('report-date-controls'),range=make('details',null,'phone-date-range'),summary=make('summary','Choose dates'),choices=make('div',null,'phone-date-choices');range.id='phone-date-range';summary.id='phone-date-summary';filter.before(range);range.append(summary,filter);filter.classList.add('phone-date-panel');
  const custom=make('details',null,'phone-custom-dates');custom.id='phone-custom-dates';custom.appendChild(make('summary','Custom range'));const fields=filter.firstElementChild;custom.appendChild(fields);filter.appendChild(custom);
  for(const [id,label] of [['filter-date-start','Start date'],['filter-date-end','End date']]){const input=node(id),wrap=make('label',label);wrap.htmlFor=id;wrap.appendChild(input);choices.appendChild(wrap);}fields.textContent='';fields.appendChild(choices);
  const apply=make('button','Apply dates');apply.id='phone-date-apply';apply.type='button';fields.appendChild(apply);
  const timezone=make('p','Philippine time','phone-report-timezone');range.after(timezone);
  const metadata=node('report-metadata'),mobileHeader=make('div',null,'phone-report-heading');mobileHeader.append(make('h2','Overview'),make('p','Choose dates · Philippine time'));mobileHeader.id='phone-report-heading';node('section-overview').before(mobileHeader);
  const generated=metadata.firstElementChild.lastElementChild;generated.classList.add('report-generated-detail');
  const notes=make('details',null,'phone-generated-notes');notes.appendChild(make('summary','Report details'));const generatedMarker=d.createComment('Report generation details');generated.before(generatedMarker);generated.before(notes);notes.appendChild(generated);
  for(const [tab,label] of [['financial','Transaction records'],['attendance','Attendance records'],['audit','Activity records']]){
   const panel=node('section-'+tab+'-table'),records=make('details',null,'phone-report-records'),heading=make('summary',label);records.id='phone-records-'+tab;heading.dataset.label=label;records.appendChild(heading);
   const table=panel.querySelector('.overflow-x-auto'),title=panel.querySelector('h3');table.before(records);if(title)records.appendChild(title);records.appendChild(table);panel.dataset.report=tab;
   const about=make('details',null,'phone-report-about');about.appendChild(make('summary','About these figures'));
   for(const child of [...panel.children])if(child.tagName==='P')about.appendChild(child);
   if(about.children.length>1)panel.insertBefore(about,records);
   if(tab==='audit'){const kind=node('report-activity-kind');records.insertBefore(kind.closest('label'),table);}
  }
  const overview=node('section-overview'),explanation=overview.querySelector(':scope>p.no-print');if(explanation)overview.querySelector('details').appendChild(explanation);
  const exportButton=node('report-export-excel'),actions=make('details',null,'phone-report-export no-print');actions.appendChild(make('summary','Export options'));exportButton.before(actions);actions.appendChild(exportButton);
  function mode(){range.open=!media.matches;custom.open=!media.matches;actions.open=!media.matches;notes.open=!media.matches;if(media.matches){mobileHeader.appendChild(notes);filter.appendChild(custom);}else{generatedMarker.after(notes);filter.prepend(custom);}for(const detail of d.querySelectorAll('.phone-report-records'))detail.open=!media.matches;}
  mode();media.addEventListener('change',mode);
  let printState=[];root.addEventListener('beforeprint',()=>{printState=[...d.querySelectorAll('.phone-report-records,.phone-generated-notes')].map(n=>[n,n.open]);generatedMarker.after(notes);for(const [n] of printState)n.open=true;});root.addEventListener('afterprint',()=>{for(const [n,open] of printState)n.open=open;if(media.matches)mobileHeader.appendChild(notes);});
 }
 function install(app){
  if(!root.matchMedia)return;
  const d=root.document,media=root.matchMedia('(max-width:639px)'),R=root.IronVaultReports;let applying=false,period=null;
  const names={overview:'Overview',financial:'Money',attendance:'Attendance',audit:'Activity'};
  const short=value=>new Intl.DateTimeFormat('en-PH',{timeZone:'UTC',month:'short',day:'numeric',year:'numeric'}).format(new Date(value+'T00:00:00Z'));
  function update(){
   const start=period?.start,end=period?.end,label=start&&end?(start==='1900-01-01'?'All Time':start===end?short(start):short(start)+' – '+short(end)):'Choose dates';
   node('phone-date-summary').textContent=label+' ▾';const h=node('phone-report-heading');h.firstElementChild.textContent=names[app.currentTab];h.children[1].textContent=label+' · Philippine time';
   for(const [tab,body] of [['financial','financial-tbody'],['attendance','attendance-tbody'],['audit','audit-tbody']]){
    const detail=node('phone-records-'+tab),summary=detail.firstElementChild,active=app.currentTab===tab;
    if(active)summary.textContent=summary.dataset.label+' · '+(node('report-page').textContent.match(/of (\d+)/)?.[1]||'0');
   }
  }
  app.phoneReportChanged=update;
  const render=app.ivRender;app.ivRender=async function(start,end){const result=await render.apply(this,arguments);if(!d.body.classList.contains('iv-auth-pending')||this.ivFinance){period={start,end};update();if(media.matches)node('phone-date-range').open=false;}return result;};
  const change=app.onDateFilterChange;app.onDateFilterChange=function(){if(media.matches&&!applying)return;return change.apply(this,arguments);};
  node('phone-date-apply').onclick=async()=>{applying=true;try{await app.onDateFilterChange();}finally{applying=false;}};
  const quick=app.setQuickRange;app.setQuickRange=async function(){applying=true;try{return await quick.apply(this,arguments);}finally{applying=false;}};
  const switchTab=app.switchTab;app.switchTab=function(){const result=switchTab.apply(this,arguments);update();return result;};
  const expanded=new Set();
  function decorate(){for(const body of ['financial-tbody','attendance-tbody','audit-tbody'])for(const row of node(body).rows){if(row.querySelector('.phone-row-toggle')||row.cells.length<2)continue;const key=body+':'+[...row.cells].map(c=>c.textContent).join('|');const button=make('button','Details','phone-row-toggle');button.type='button';function state(){const open=expanded.has(key);row.classList.toggle('phone-row-expanded',open);button.setAttribute('aria-expanded',String(open));button.textContent=open?'Less':'Details';}button.onclick=()=>{expanded.has(key)?expanded.delete(key):expanded.add(key);state();};row.cells[1].appendChild(button);state();}}
  const observer=new root.MutationObserver(decorate);for(const body of ['financial-tbody','attendance-tbody','audit-tbody'])observer.observe(node(body),{childList:true});decorate();
  const clear=app.ivClear;app.ivClear=function(){expanded.clear();period=null;const result=clear.apply(this,arguments);update();return result;};
  media.addEventListener('change',()=>app.switchTab(app.currentTab));update();
 }
 root.IronVaultPhoneReports={prepare,install};
})(globalThis);
