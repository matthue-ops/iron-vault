/* Camera presentation/lifecycle only. Existing pass redemption stays untouched. */
(function(root){
 'use strict';
 function install(app){
  const d=root.document,modal=d.getElementById('scanner-modal');if(!modal?.querySelector||app.ivScannerScreen)return;app.ivScannerScreen=true;
  const video=d.getElementById('qr-video'),placeholder=d.getElementById('camera-placeholder'),torch=d.getElementById('scanner-torch'),swap=d.getElementById('scanner-switch'),message=d.getElementById('scanner-camera-message');
  let generation=0,opened=false,previousFocus,overflow='',facing='environment',light=false,changing=false;
  const say=value=>{message.textContent=value;};
  const original={open:app.openScannerModal,resume:app.resumeScanner,close:app.closeScannerModal,pause:app.pauseScannerAfterSuccess,result:app.showScanResult};
  app.stopCamera=function(){
   generation++;if(this.scanTimer){clearInterval(this.scanTimer);this.scanTimer=null;}
   this.cameraStream?.getTracks().forEach(track=>track.stop());this.cameraStream=null;video.srcObject=null;video.classList.add('hidden');
   light=false;torch.hidden=true;swap.hidden=true;torch.setAttribute('aria-pressed','false');placeholder.classList.remove('hidden');placeholder.textContent='Initializing camera stream…';
  };
  app.startCamera=async function(){
   this.stopCamera();if(!opened)return;const ticket=generation;this.scanPaused=false;say('');
   try{
    const stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:facing}},audio:false});
    if(ticket!==generation||!opened){stream.getTracks().forEach(track=>track.stop());return;}
    this.cameraStream=stream;video.srcObject=stream;await video.play();
    if(ticket!==generation||!opened)return;
    video.classList.remove('hidden');placeholder.classList.add('hidden');
    this.scanTimer=setInterval(()=>this.tickCameraScan(),250);
    const track=stream.getVideoTracks()[0];try{torch.hidden=!track?.getCapabilities?.().torch;}catch(_){torch.hidden=true;}
    try{const devices=await navigator.mediaDevices.enumerateDevices();if(ticket===generation&&opened)swap.hidden=devices.filter(x=>x.kind==='videoinput').length<2;}catch(_){}
   }catch(error){
    if(ticket!==generation||!opened)return;
    this.stopCamera();placeholder.textContent='Camera unavailable. Allow camera access in your browser settings, then tap Retry camera, or use Upload QR image.';
    d.getElementById('scan-next-button').textContent='Retry camera';d.getElementById('scan-next-button').classList.remove('hidden');
   }
  };
  app.openScannerModal=function(){
   if(this.isProcessingScan&&!this.scanPaused)return;
   if(opened)return;opened=true;previousFocus=d.activeElement;overflow=d.body.style.overflow;d.body.style.overflow='hidden';
   this.lastScannedCodePayload=null;d.getElementById('scan-next-button').textContent='Scan Next Member';
   original.open.call(this);modal.querySelector('button').focus();
  };
  app.closeScannerModal=function(){opened=false;original.close.call(this);d.body.style.overflow=overflow;previousFocus?.focus?.();say('');};
  app.resumeScanner=function(){if(!opened||this.isProcessingScan&&!this.scanPaused)return;d.getElementById('scan-next-button').textContent='Scan Next Member';return original.resume.call(this);};
  app.pauseScannerAfterSuccess=function(){this.stopCamera();original.pause.call(this);};
  app.showScanResult=function(success,title,description){
   // Both outcomes wait for an explicit next scan; never keep retrying a denied QR.
   this.scanPaused=true;this.stopCamera();original.result.call(this,success,title,description);
   d.getElementById('scan-result-container').dataset.success=String(!!success);
   placeholder.textContent=success?'Entry recorded.':'Scan paused.';d.getElementById('scan-next-button').classList.remove('hidden');
  };
  torch.onclick=async()=>{if(changing||!app.cameraStream)return;changing=true;torch.disabled=true;const track=app.cameraStream.getVideoTracks()[0];try{await track.applyConstraints({advanced:[{torch:!light}]});if(app.cameraStream?.getVideoTracks()[0]!==track)return;light=!light;torch.setAttribute('aria-pressed',String(light));say('');}catch(_){say('Flashlight is unavailable on this camera.');}finally{changing=false;torch.disabled=false;}};
  swap.onclick=async()=>{if(changing||app.isProcessingScan||app.scanPaused)return;changing=true;swap.disabled=true;facing=facing==='environment'?'user':'environment';try{await app.startCamera();}finally{changing=false;swap.disabled=false;}};
  modal.addEventListener('keydown',event=>{
   if(event.key==='Escape'){event.preventDefault();app.closeScannerModal();}
   if(event.key!=='Tab')return;const buttons=[...modal.querySelectorAll('button,input')].filter(n=>!n.disabled&&n.getClientRects().length);
   if(!buttons.length)return;const first=buttons[0],last=buttons.at(-1);if(event.shiftKey&&d.activeElement===first){event.preventDefault();last.focus();}else if(!event.shiftKey&&d.activeElement===last){event.preventDefault();first.focus();}
  });
  const suspend=()=>{if(!opened)return;app.scanPaused=true;app.stopCamera();placeholder.textContent='Camera paused. Tap Scan Next Member to continue.';d.getElementById('scan-next-button').classList.remove('hidden');};
  root.addEventListener('pagehide',suspend);d.addEventListener('visibilitychange',()=>{if(d.hidden)suspend();});
 }
 root.IronVaultScannerScreen={install};
})(globalThis);
