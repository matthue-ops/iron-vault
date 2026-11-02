/* QRCode.js 1.0.0 supplies the matrix; render whole pixels with a four-module quiet zone. */
(function(root){
 'use strict';
 let png=null,filename='Gym_Access_QR.png';
 function close(){root.document.getElementById('qr-code-modal').classList.add('hidden');png=null;root.document.getElementById('qr-code-img').removeAttribute('src');}
 function open(url,gymName){
  const d=root.document,button=d.getElementById('qr-download');png=null;button.disabled=true;
  d.getElementById('qr-modal-title').textContent=String(gymName)+' Access Portal';d.getElementById('qr-modal-url-text').textContent=url;
  d.getElementById('qr-code-img').removeAttribute('src');d.getElementById('qr-download-status').textContent='';d.getElementById('qr-code-modal').classList.remove('hidden');
  try{
   const qr=new root.QRCode(d.createElement('div'),{text:url,width:256,height:256,correctLevel:root.QRCode.CorrectLevel.H}),matrix=qr._oQRCode,count=matrix.getModuleCount();
   const scale=Math.ceil(2048/(count+8)),size=(count+8)*scale,canvas=d.createElement('canvas');canvas.width=size;canvas.height=size;
   const ctx=canvas.getContext('2d');ctx.fillStyle='#ffffff';ctx.fillRect(0,0,size,size);ctx.fillStyle='#000000';
   for(let y=0;y<count;y++)for(let x=0;x<count;x++)if(matrix.isDark(y,x))ctx.fillRect((x+4)*scale,(y+4)*scale,scale,scale);
   png=canvas.toDataURL('image/png');filename=(String(gymName).normalize('NFKD').replace(/[^a-zA-Z0-9_-]+/g,'_').replace(/^_+|_+$/g,'').slice(0,100)||'Gym')+'_Access_QR.png';
   d.getElementById('qr-code-img').src=png;d.getElementById('qr-code-img').alt=String(gymName)+' branch access QR';d.getElementById('qr-download-status').textContent=size+' × '+size+' px PNG';button.disabled=false;
  }catch(error){png=null;d.getElementById('qr-download-status').textContent='Could not generate this QR code. Close and try again.';}
 }
 function download(){if(!png)return;const link=root.document.createElement('a');link.href=png;link.download=filename;root.document.body.appendChild(link);link.click();link.remove();}
 root.IronVaultBranchQR=Object.freeze({open,close,download});
})(globalThis);
