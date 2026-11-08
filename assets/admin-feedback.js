/* Scoped admin dialogs; never override browser alert/confirm globally. */
(function(root){
 'use strict';
 function install(app,client){
  const d=root.document,node=id=>d.getElementById('admin-feedback-'+id);let timer,resolvePending;
  function finish(value){if(timer!==undefined)root.clearTimeout(timer);timer=undefined;const resolve=resolvePending;resolvePending=null;node('dialog').close();resolve?.(value);}
  function open(options,mode){
   if(node('dialog').open&&node('dialog').dataset.persistent==='true')return false;
   if(resolvePending)finish(false);if(timer!==undefined)root.clearTimeout(timer);
   const dialog=node('dialog'),confirm=mode==='confirm';dialog.dataset.mode=mode;dialog.dataset.persistent=String(!confirm&&options.timeoutMs===0);
   node('title').textContent=options.title||(confirm?'Please confirm':mode==='success'?'Success':'Please check');node('message').textContent=options.message||'';
   node('icon').className='fa-solid '+(confirm?'fa-circle-question':mode==='success'?'fa-circle-check':'fa-circle-exclamation');
   node('rows').textContent='';for(const [label,value] of options.rows||[]){const row=d.createElement('div'),term=d.createElement('dt'),definition=d.createElement('dd');term.textContent=label;definition.textContent=String(value);row.append(term,definition);node('rows').appendChild(row);}
   node('cancel').hidden=!confirm;node('confirm').textContent=confirm?(options.confirmLabel||'Confirm'):'Close';node('cancel').onclick=()=>finish(false);node('confirm').onclick=()=>finish(confirm);
   dialog.oncancel=e=>{e.preventDefault();finish(false);};dialog.onclose=()=>{if(!dialog.open){if(timer!==undefined)root.clearTimeout(timer);timer=undefined;const resolve=resolvePending;resolvePending=null;resolve?.(false);}};
   if(!dialog.open)dialog.showModal();(confirm?node('cancel'):node('confirm')).focus();if(!confirm&&options.timeoutMs!==0)timer=root.setTimeout(()=>finish(false),options.timeoutMs??2000);return true;
  }
  app.confirmAdmin=function(options){const actor=app.authenticatedRole?.user_id,tenant=app.currentTenantId;if(open(options,'confirm')===false)return Promise.resolve(false);return new Promise(resolve=>{resolvePending=value=>resolve(value&&actor===app.authenticatedRole?.user_id&&tenant===app.currentTenantId);});};
  app.notifyAdmin=function(message,success=true,options={}){open({...options,message},success?'success':'warning');};
  app.notifyFinancialError=function(error,label='Payment not confirmed'){const uncertain=error.uncertain===true;this.notifyAdmin(label+': '+error.message+(uncertain?'\nThis payment may already be recorded. Check transaction history before retrying; do not collect cash again.':''),false,{timeoutMs:uncertain?0:error.code==='IV004'?6000:2000});};
  client?.auth?.onAuthStateChange?.((event,session)=>{if(event==='SIGNED_OUT'||(app.authenticatedRole?.user_id&&session?.user?.id&&session.user.id!==app.authenticatedRole.user_id)){if(node('dialog').open)finish(false);node('message').textContent='';node('rows').textContent='';}});
  const menu=d.getElementById('admin-account-menu');d.addEventListener?.('click',event=>{if(menu.open&&(!menu.contains(event.target)||event.target.closest('.admin-menu-panel button')))menu.open=false;});d.addEventListener?.('keydown',event=>{if(event.key==='Escape')menu.open=false;});
 }
 root.IronVaultAdminFeedback={install};
})(globalThis);
