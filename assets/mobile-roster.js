/* Uses the existing authorized, filtered roster. No queries or writes. */
(function(root){
 'use strict';
 function install(app){
  const d=root.document,node=id=>d.getElementById('mobile-roster-'+id),escape=root.IronVaultData.escape;
  let page=0,key='',members=[];
  function render(){
   page=Math.max(0,Math.min(page,Math.ceil(members.length/10)-1));
   const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
   const focused=d.activeElement?.dataset?.memberId;
   node('list').innerHTML=members.slice(page*10,page*10+10).map(m=>{
    const entered=String(m.lastScannedDate||'').slice(0,10)===today;
    return '<button type="button" class="mobile-member-row" data-member-id="'+escape(m.id)+'" aria-label="'+escape('View '+m.name+' '+(m.displayCode||m.id))+'">'+
     '<span class="mobile-member-heading"><strong>'+escape(m.name)+'</strong><span class="mobile-member-active">ACTIVE</span></span>'+
     '<span class="mobile-member-meta">'+escape(m.displayCode||m.id)+' · '+escape(m.plan||'Not Selected')+'</span>'+
     '<span class="mobile-member-bottom"><span>'+escape(app.calculateDaysLeft(m.expirationDate))+' · <span class="'+(entered?'mobile-member-entered':'mobile-member-waiting')+'">'+(entered?'Entered today':'Not entered')+'</span></span><span aria-hidden="true">›</span></span></button>';
   }).join('')||'<p class="mobile-roster-empty">No matching active members.</p>';
   node('prev').disabled=page===0;node('next').disabled=(page+1)*10>=members.length;
   node('page').textContent=members.length?(page*10+1)+'–'+Math.min((page+1)*10,members.length)+' of '+members.length:'0 members';
   if(focused)Array.from(node('list').querySelectorAll('button')).find(b=>b.dataset.memberId===focused)?.focus({preventScroll:true});
  }
  const original=app.renderRoster;
  app.renderRoster=function(list){
   const result=original.apply(this,arguments);
   const nextKey=JSON.stringify([this.currentTenantId,d.getElementById('roster-search').value,this.rosterActiveFilter]);
   if(nextKey!==key){page=0;key=nextKey;}
   members=list.filter(m=>m.status==='ACTIVE');render();return result;
  };
  const openProfile=app.openProfileModal;
  app.openProfileModal=function(id){
   const result=openProfile.apply(this,arguments);
   node('remove').hidden=this.authenticatedRole?.role!=='owner';
   return result;
  };
  node('remove').onclick=async()=>{
   const id=app.activeModalMemberId;if(!id)return;
   await app.deleteMember(id);
   if(app.members.find(m=>m.id===id)?.status==='INACTIVE')app.closeProfileModal();
  };
  node('list').onclick=event=>{const button=event.target.closest('button[data-member-id]');if(button&&node('list').contains(button))app.openProfileModal(button.dataset.memberId);};
  node('prev').onclick=()=>{page--;render();};node('next').onclick=()=>{page++;render();};
 }
 root.IronVaultMobileRoster={install};
})(globalThis);
