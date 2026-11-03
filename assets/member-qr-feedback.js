(function(root){
 'use strict';
 function install(app){
  const render=app.renderProfile;
  let previous=null,timer;
  app.renderProfile=function(){
   const result=render.apply(this,arguments),m=this.currentMember;
   if(!m)return result;
   const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
   const accepted=String(m.lastScannedDate||'').slice(0,10)===today;
   const d=root.document,qr=d.getElementById('qr-wrapper'),button=d.getElementById('btn-generate-qr'),popup=d.getElementById('qr-accepted-window');
   if(accepted){qr?.classList.add('hidden');qr?.classList.remove('flex');}
   button?.classList.toggle('hidden',accepted);
   // Initial loads establish a baseline; only a newly confirmed entry opens the window.
   const sameMember=previous&&previous.id===m.id&&previous.tenantId===m.tenantId;
   if(sameMember&&!previous.accepted&&accepted&&popup){
    if(timer!==undefined)root.clearTimeout(timer);popup.hidden=false;popup.style.display='grid';
    timer=root.setTimeout(()=>{popup.hidden=true;popup.style.display='none';},2500);
   }else if((!sameMember||!accepted)&&popup){
    if(timer!==undefined)root.clearTimeout(timer);popup.hidden=true;popup.style.display='none';
   }
   previous={id:m.id,tenantId:m.tenantId,accepted};
   return result;
  };
 }
 root.IronVaultMemberQrFeedback={install};
})(typeof window!=='undefined'?window:globalThis);
