(function(root){
 'use strict';
 function install(app){
  let timer,resolvePending,busy=false;
  const node=id=>root.document.getElementById('member-feedback-'+id);
  function clearTimer(){if(timer!==undefined){root.clearTimeout(timer);timer=undefined;}}
  function finish(accepted){
   clearTimer();const resolve=resolvePending;resolvePending=null;
   node('dialog').close();if(resolve)resolve(accepted);
  }
  function open(message,mode){
   clearTimer();const dialog=node('dialog');
   if(resolvePending)finish(false);
   const warning=mode==='warning',confirm=mode==='confirm';
   dialog.style.borderColor=warning?'#f43f5e':'var(--brand-primary)';
   dialog.style.boxShadow=warning?'0 0 32px rgba(244,63,94,.2)':'0 0 32px var(--brand-primary-glow)';
   node('title').textContent=warning?'Please check':confirm?'Confirm your pass':'Success';
   node('title').style.color=node('icon').style.color=warning?'#fb7185':'var(--brand-primary)';
   node('icon').className='fa-solid '+(warning?'fa-circle-exclamation':confirm?'fa-wallet':'fa-circle-check')+' text-4xl';
   node('message').textContent=String(message);
   node('confirm').style.background=warning?'#f43f5e':'var(--brand-primary)';
   node('cancel').hidden=!confirm;node('confirm').textContent=confirm?'Confirm':'Close';
   node('cancel').onclick=()=>finish(false);node('confirm').onclick=()=>finish(confirm);
   dialog.oncancel=event=>{event.preventDefault();finish(false);};
   dialog.onclose=()=>{if(!dialog.open){clearTimer();const resolve=resolvePending;resolvePending=null;if(resolve)resolve(false);}};
   if(!dialog.open)dialog.showModal();
   (confirm?node('cancel'):node('confirm')).focus();
   if(!confirm)timer=root.setTimeout(()=>finish(false),warning?2000:2500);
  }
  app.confirmAction=function(message){open(message,'confirm');return new Promise(resolve=>{resolvePending=resolve;});};
  app.showAlert=function(message,success=true){open(message,success?'success':'warning');};
  // Ignore repeat taps while a quote, confirmation, or purchase is in progress.
  const select=app.selectPlan;
  app.selectPlan=async function(){if(busy)return;busy=true;try{return await select.apply(this,arguments);}finally{busy=false;}};
 }
 root.IronVaultMemberFeedback={install};
})(typeof window!=='undefined'?window:globalThis);
