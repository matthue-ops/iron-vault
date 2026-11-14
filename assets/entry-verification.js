/* Stage 1: verify first, admit only through the scoped atomic approval API. */
(function(root){
 'use strict';
 const labels={READY:'Ready for approval',ALREADY_ENTERED:'Already entered today',MEMBER_INACTIVE:'Member is not active',NO_ACTIVE_PASS:'No active pass',EXPIRED_PASS:'Expired pass',AGREEMENT_REQUIRED:'Member must review Terms & Privacy',CARD_REVOKED:'Card no longer valid',INVALID_CARD_FOR_GYM:'Invalid card for this gym',INVALID_QR:'Invalid QR for this gym',QR_EXPIRED:'Daily QR expired',PERMANENT_CARD_REQUIRED:'Scan the permanent member card for lookup'};
 const make=(tag,text)=>{const n=root.document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
 function shell(title){const d=make('dialog');d.className='iv-entry-dialog';const h=make('h2',title);h.id='iv-entry-title-'+Math.random().toString(36).slice(2);d.setAttribute('aria-labelledby',h.id);d.append(h);root.document.body.append(d);return d;}
 function photoReference(value){return /^(iv-photo:[0-9a-f-]{36}|data:image\/(jpeg|png|webp);base64,|https:\/\/)/i.test(value||'');}
 function installCard(app,client,kind){
  if(!root.document.querySelector)return;
  const d=shell('Member QR'),text=make('p'),qr=make('div'),status=make('p'),close=make('button','Close');qr.className='iv-member-qr';close.type='button';d.append(text,qr,status,close);let serial=0;
  function clear(){serial++;qr.replaceChildren();text.textContent='';status.textContent='';}
  close.onclick=()=>d.close();d.addEventListener('close',clear);
  app.openPermanentMemberQR=async function(){
   const m=kind==='member'?this.currentMember:this.members.find(x=>x.id===this.activeModalMemberId);if(!m)return;
   const tenant=m.tenantId||this.currentTenantId,ticket=++serial;qr.replaceChildren();text.textContent='';status.textContent='Loading member QR…';if(!d.open)d.showModal();
   if(kind==='member'){const menu=root.document.getElementById('member-account-menu');if(menu)menu.open=false;}
   try{const data=await root.IronVaultData.call(client,'iv_member_card',{p_member:m.id,p_tenant:tenant});
    const current=kind==='member'?this.currentMember?.id:this.activeModalMemberId;
    if(ticket!==serial||current!==m.id||!d.open)return;
    text.textContent=m.name+' · '+(m.displayCode||m.id);
    new root.QRCode(qr,{text:data.payload,width:224,height:224,colorDark:'#000000',colorLight:'#ffffff',correctLevel:root.QRCode.CorrectLevel.H});
    status.textContent='Permanent member QR. Entry requires staff approval and a valid pass. This is not the public gym portal QR.';
   }catch(error){if(ticket===serial)status.textContent=error.message;}
  };
  const holder=root.document.querySelector(kind==='member'?'.member-menu-panel':'#member-profile-modal .min-w-0');
  if(holder){const b=make('button','Member QR');b.type='button';b.className='iv-card-open';b.onclick=()=>app.openPermanentMemberQR();holder.append(b);}
  client.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT'||event==='SIGNED_IN'){clear();if(d.open)d.close();}});
 }
 function install(app,client){
  if(!root.document.querySelector)return;
  if(app.ivEntryVerification)return;app.ivEntryVerification=true;installCard(app,client,'admin');
  const d=shell('Verify member entry'),image=make('img'),fallback=make('p','No photo on file — verify another ID'),name=make('h3'),code=make('p'),plan=make('p'),badge=make('p'),help=make('p','Compare the member with their photo. Request another ID when needed.'),actions=make('div'),approve=make('button','Approve Entry'),close=make('button','Deny / Close'),profile=make('button','View Profile');
  image.alt='Member photo';image.className='iv-entry-photo';fallback.className='iv-entry-no-photo';badge.setAttribute('role','status');badge.className='iv-entry-status';actions.className='iv-entry-actions';approve.type=close.type=profile.type='button';approve.className='iv-entry-approve';actions.append(approve,close,profile);d.append(image,fallback,name,code,plan,badge,help,actions);
  const scanner=root.document.getElementById('scanner-modal'),next=root.document.getElementById('scan-next-button'),notice=root.document.getElementById('scanner-presentation-notice'),heading=root.document.getElementById('scanner-title');
  if(notice)notice.textContent='Scan a member card or current daily QR. Verify identity before approving entry.';
  const subtitle=scanner.querySelector('.scanner-header p');if(subtitle)subtitle.textContent='Card and daily QR entry require staff approval.';
  let serial=0,pending=null,busy=false,lookup=false,resumeTimer=null,closed=false,processing=false,cooldownUntil=0;
  const originalOpen=app.openScannerModal,originalClose=app.closeScannerModal,originalResume=app.resumeScanner,originalTick=app.tickCameraScan;
  const sound=make('button','Scan sounds: Off');sound.type='button';sound.setAttribute('aria-pressed','false');let sounds=false,audio;
  scanner.querySelector('.scanner-tools').append(sound);
  sound.onclick=()=>{sounds=!sounds;sound.textContent='Scan sounds: '+(sounds?'On':'Off');sound.setAttribute('aria-pressed',String(sounds));if(sounds)tone('ready');};
  function tone(kind){if(!sounds)return;try{const A=root.AudioContext||root.webkitAudioContext;audio=audio||new A();audio.resume().catch(()=>{});const o=audio.createOscillator(),g=audio.createGain();o.type=kind==='error'?'square':kind==='warning'?'triangle':'sine';o.frequency.value=kind==='success'?880:kind==='ready'?600:kind==='warning'?260:120;g.gain.setValueAtTime(.05,audio.currentTime);g.gain.exponentialRampToValueAtTime(.001,audio.currentTime+.18);o.connect(g);g.connect(audio.destination);o.start();o.stop(audio.currentTime+.19);}catch(_){}}
  function clearPhoto(){delete image.dataset.ivPhotoRef;delete image.dataset.ivPhotoUrl;image.removeAttribute('src');image.hidden=true;}
  function reset(){serial++;pending=null;processing=false;clearTimeout(resumeTimer);if(d.open)d.close();clearPhoto();image.hidden=true;fallback.hidden=false;name.textContent=code.textContent=plan.textContent=badge.textContent='';approve.disabled=true;}
  function pause(){app.scanPaused=true;app.stopCamera();next.classList.add('hidden');}
  function resume(delay=1500){cooldownUntil=Date.now()+delay;clearTimeout(resumeTimer);resumeTimer=setTimeout(()=>{if(!closed&&!d.open&&!busy){app.isProcessingScan=false;originalResume.call(app);}},delay);}
  app.openScannerModal=function(){lookup=false;closed=false;if(heading)heading.textContent='Door Access QR Scanner';return originalOpen.apply(this,arguments);};
  app.openMemberCardLookup=async function(){await this.openScannerModal();if(scanner.classList.contains('hidden'))return;lookup=true;if(heading)heading.textContent='Find Member — No Entry Recorded';};
  app.closeScannerModal=function(){if(busy)return;closed=true;reset();app.isProcessingScan=false;return originalClose.apply(this,arguments);};
  app.resumeScanner=function(){if(busy||d.open)return;if(Date.now()<cooldownUntil){resume(cooldownUntil-Date.now());return;}reset();app.isProcessingScan=false;return originalResume.apply(this,arguments);};
  app.tickCameraScan=function(){if(d.open||busy||processing||Date.now()<cooldownUntil)return;return originalTick.apply(this,arguments);};
  async function request(api,args,ticket){
   const tenant=app.currentTenantId;const before=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:tenant});
   const data=await root.IronVaultData.call(client,api,args);
   const after=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:tenant});
   if(ticket!==serial||closed||tenant!==app.currentTenantId||before.user_id!==after.user_id)throw Error('Session changed. Scan again.');return data;
  }
  app.processScannedCode=async function(payload){
   if(busy||processing||d.open||Date.now()<cooldownUntil)return;processing=true;pause();const ticket=++serial;badge.textContent='Checking…';
   const msg=root.document.getElementById('scanner-camera-message');msg.textContent='Checking…';
   try{
    const result=await request('iv_verify_entry_qr',{p_payload:String(payload),p_tenant:this.currentTenantId,p_lookup:lookup},ticket);
    if(ticket!==serial)return;
    msg.textContent='';
    if(!result.valid){tone('error');this.isProcessingScan=false;this.showScanResult(false,'SCAN NOT ACCEPTED',labels[result.reason]||'QR unavailable.');return;}
    if(lookup){this.isProcessingScan=false;this.closeScannerModal();this.openProfileModal(result.member.id);return;}
    pending={payload:String(payload),memberId:result.member.id,tenant:this.currentTenantId,ticket};
    const m=result.member;name.textContent=m.name;code.textContent=m.display_code||m.id;plan.textContent=(m.plan||'No pass')+(m.expiration_date?' · Expires '+m.expiration_date:'');
    badge.textContent=labels[result.reason]||'Entry unavailable';
    if(result.entered_at)badge.textContent+=' at '+new Intl.DateTimeFormat('en-PH',{timeZone:'Asia/Manila',hour:'numeric',minute:'2-digit'}).format(new Date(result.entered_at));
    badge.dataset.eligible=String(result.eligible===true);close.classList.toggle('iv-entry-deny-primary',result.eligible!==true);approve.disabled=result.eligible!==true;profile.disabled=false;close.disabled=false;
    clearPhoto();fallback.hidden=false;
    image.onload=()=>{image.hidden=false;fallback.hidden=true;};image.onerror=()=>{image.hidden=true;fallback.hidden=false;};
    if(photoReference(m.avatar))image.src=m.avatar;
    d.showModal();tone(result.eligible?'ready':'warning');(result.eligible?approve:close).focus();
   }catch(error){if(ticket===serial&&!closed){this.isProcessingScan=false;msg.textContent='';this.showScanResult(false,'NOT CONFIRMED',error.message);}}
   finally{if(ticket===serial)processing=false;}
  };
  close.onclick=()=>{if(!busy)d.close();};
  d.addEventListener('cancel',event=>{if(busy)event.preventDefault();});
  d.addEventListener('close',()=>{pending=null;clearPhoto();fallback.hidden=false;if(!busy&&!closed){serial++;app.isProcessingScan=false;resume();}});
  profile.onclick=()=>{if(busy||!pending)return;const id=pending.memberId;app.closeScannerModal();app.openProfileModal(id);};
  approve.onclick=async()=>{
   if(busy||!pending||approve.disabled)return;busy=true;approve.disabled=close.disabled=profile.disabled=true;const current=pending,release=app.liveUpdates?.hold?.()||(()=>{});badge.textContent='Recording entry…';
   try{
    await request('iv_approve_entry_qr',{p_payload:current.payload,p_tenant:current.tenant},current.ticket);
    if(current.ticket!==serial)return;
    pending=null;d.close();app.showScanResult(true,'ENTRY RECORDED','Member admitted.');tone('success');
    release();try{if(app.liveUpdates?.check)await app.liveUpdates.check(true);else await app.loadMembers();}catch(_){root.document.getElementById('scanner-camera-message').textContent='Entry recorded. Refresh the roster to see updated details.';}
   }catch(error){if(current.ticket===serial&&!closed){pending=null;d.close();app.showScanResult(false,'ENTRY NOT CONFIRMED',error.message+' Scan again to check status before retrying.');tone('error');}}
   finally{release();busy=false;app.isProcessingScan=false;if(!closed&&current.ticket===serial)resume();}
  };
  const search=root.document.getElementById('roster-search');if(search){const b=make('button','Scan Member Card');b.type='button';b.className='iv-card-open';b.onclick=()=>app.openMemberCardLookup();search.parentElement.after(b);}
  client.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT'||event==='SIGNED_IN'){closed=true;reset();busy=false;app.isProcessingScan=false;originalClose.call(app);}});
  root.addEventListener('pagehide',()=>{closed=true;reset();audio?.close?.();audio=null;});
 }
 root.IronVaultEntryVerification={install,installCard};
})(globalThis);
