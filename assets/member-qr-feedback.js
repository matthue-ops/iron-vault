(function(root){
 'use strict';
 function install(app){
  const render=app.renderProfile;let previous=null,timer,baseline=true;const seen=new Set();
  const today=value=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(value));
  function hide(){const popup=root.document.getElementById('qr-accepted-window');if(timer!==undefined)root.clearTimeout(timer);if(popup){popup.hidden=true;popup.style.display='none';}}
  function reconnect(){baseline=true;hide();}
  root.addEventListener?.('offline',reconnect);root.addEventListener?.('online',reconnect);root.addEventListener?.('pagehide',reconnect);root.addEventListener?.('pageshow',reconnect);
  root.document.addEventListener?.('visibilitychange',()=>{baseline=true;if(root.document.hidden)hide();});
  app.renderProfile=function(){
   const result=render.apply(this,arguments),m=this.currentMember;if(!m){previous=null;baseline=true;hide();return result;}
   const entry=m.lastEntry||m.last_entry,clock=Number.isFinite(Date.parse(entry?.server_now))?Date.parse(entry.server_now):Date.now();
   const accepted=String(m.lastScannedDate||'').slice(0,10)===today(clock);
   const confirmed=entry&&typeof entry.id==='string'&&Number.isFinite(Date.parse(entry.created_at))&&today(entry.created_at)===today(clock);
   const method=confirmed?entry.method:null,qrUsed=method==='qr';
   const d=root.document,qr=d.getElementById('qr-wrapper'),button=d.getElementById('btn-generate-qr'),popup=d.getElementById('qr-accepted-window'),banner=d.getElementById('qr-scan-success-banner');
   if(accepted){qr?.classList.add('hidden');qr?.classList.remove('flex');}button?.classList.toggle('hidden',accepted);
   const time=confirmed?new Intl.DateTimeFormat('en-PH',{timeZone:'Asia/Manila',hour:'numeric',minute:'2-digit'}).format(new Date(entry.created_at)):'';
   const detail=qrUsed?'QR check-in':method==='manual'?'Checked in by gym staff':'Entry recorded';
   if(banner){banner.classList.toggle('hidden',!accepted);const text=banner.querySelector?.('span');if(text)text.textContent=qrUsed?'QR ACCEPTED • SCAN SUCCESSFUL':'✓ ENTRY GRANTED'+(time?' · '+detail+' · '+time:'');}
   const same=previous&&previous.id===m.id&&previous.tenant===(m.tenantId||m.tenant_id),key=confirmed?(m.tenantId||m.tenant_id)+'|'+m.id+'|'+entry.id:null;
   const online=!d.hidden&&root.navigator?.onLine!==false;
   if(accepted&&confirmed&&same&&!baseline&&online&&previous.entry!==entry.id&&!seen.has(key)&&Math.abs(clock-Date.parse(entry.created_at))<90000&&popup){
    seen.add(key);const title=d.getElementById('entry-success-title'),description=d.getElementById('entry-success-detail');if(title)title.textContent=qrUsed?'QR ACCEPTED':'Entry Granted';if(description)description.textContent=qrUsed?'Your entry has been recorded.':detail+(time?' · '+time:'');
    hide();popup.hidden=false;popup.style.display='grid';timer=root.setTimeout(hide,2500);
   }else if(!same||!accepted||!online)hide();
   if(key)seen.add(key);previous={id:m.id,tenant:m.tenantId||m.tenant_id,entry:confirmed?entry.id:null};baseline=false;return result;
  };
 }
 root.IronVaultMemberQrFeedback={install};
})(typeof window!=='undefined'?window:globalThis);
