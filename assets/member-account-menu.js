/* Menu presentation only; account edits retain their original handlers. */
(function(root){
 'use strict';
 function install(app){
  const d=root.document,menu=d.getElementById('member-account-menu');
  app.openMemberSettings=function(){menu.open=false;d.getElementById('member-settings-dialog').showModal();};
  app.openMemberTerms=function(){
   menu.open=false;const token=this.currentMember?.tenantToken;if(!token){this.showAlert('Gym details are unavailable. Please refresh.',false);return;}
   d.getElementById('member-terms-link').href='/gym/terms.html?key='+encodeURIComponent(token);
   d.getElementById('member-privacy-link').href='/gym/privacy.html?key='+encodeURIComponent(token);
   d.getElementById('member-terms-dialog').showModal();
  };
  d.addEventListener?.('click',event=>{if(menu.open&&!menu.contains(event.target))menu.open=false;});
  d.addEventListener?.('keydown',event=>{if(event.key==='Escape')menu.open=false;});
 }
 root.IronVaultMemberAccountMenu={install};
})(globalThis);
