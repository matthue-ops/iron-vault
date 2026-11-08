(function(root){
 'use strict';
 function install(app){const d=root.document;if(!d.querySelectorAll)return;const buttons=[...d.querySelectorAll('[data-report-range]')];let applying=false;
  function select(value){for(const b of buttons)b.setAttribute('aria-pressed',String(b.dataset.reportRange===value));}
  const quick=app.setQuickRange;app.setQuickRange=async function(type){applying=true;select(type);try{return await quick.apply(this,arguments);}finally{applying=false;}};
  const custom=app.onDateFilterChange;app.onDateFilterChange=function(){if(!applying)select('');return custom.apply(this,arguments);};
  for(const id of ['filter-date-start','filter-date-end'])for(const event of ['input','change'])d.getElementById(id)?.addEventListener(event,()=>select(''));
  select('today');
 }
 root.IronVaultReportControls={install};
})(globalThis);
