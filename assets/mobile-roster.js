/* Uses the existing authorized, filtered roster. No queries or writes. */
(function(root){
 'use strict';
 function install(app){
  const d=root.document,node=id=>d.getElementById('mobile-roster-'+id),escape=root.IronVaultData.escape;
  let key='',members=[],page=0;
  const previous=node('prev'),next=node('next'),counter=node('page');previous.onclick=()=>{page--;render();};next.onclick=()=>{page++;render();};
  function render(){
   const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
   const focused=d.activeElement?.dataset?.memberId;
   node('list').innerHTML=(root.matchMedia?.('(max-width:639px)').matches?members.slice(page*5,page*5+5):(app.rosterExpanded?members:members.slice(0,3))).map(m=>{
    const entered=String(m.lastScannedDate||'').slice(0,10)===today;
    return '<button type="button" class="mobile-member-row" data-member-id="'+escape(m.id)+'" aria-label="'+escape('View '+m.name+' '+(m.displayCode||m.id))+'">'+
     '<span class="mobile-member-heading"><strong>'+escape(m.name)+'</strong><span class="mobile-member-active">ACTIVE</span></span>'+
     '<span class="mobile-member-meta">'+escape(m.displayCode||m.id)+' · '+escape(m.plan||'Not Selected')+'</span>'+
     '<span class="mobile-member-bottom"><span>'+escape(app.calculateDaysLeft(m.expirationDate))+' · <span class="'+(entered?'mobile-member-entered':'mobile-member-waiting')+'">'+(entered?'Entered today':'Not entered')+'</span></span><span aria-hidden="true">›</span></span></button>';
   }).join('')||'<p class="mobile-roster-empty">No matching active members.</p>';
   page=Math.min(page,Math.max(0,Math.ceil(members.length/5)-1));previous.disabled=page===0;next.disabled=(page+1)*5>=members.length;counter.textContent=members.length?'Showing '+(page*5+1)+'–'+Math.min(page*5+5,members.length)+' of '+members.length:'No matching members';
   const expand=d.getElementById('roster-expansion');
   expand.hidden=members.length<=3;expand.textContent=app.rosterExpanded?'Show fewer':'Show all members ('+members.length+')';expand.setAttribute('aria-expanded',String(!!app.rosterExpanded));
   if(focused)Array.from(node('list').querySelectorAll('button')).find(b=>b.dataset.memberId===focused)?.focus({preventScroll:true});
  }
  const original=app.renderRoster;
  app.renderRoster=function(list){
   const nextKey=JSON.stringify([this.currentTenantId,d.getElementById('roster-search').value,this.rosterActiveFilter]);
   if(nextKey!==key){this.rosterExpanded=false;page=0;key=nextKey;}
   page=Math.min(page,Math.max(0,Math.ceil(list.filter(m=>m.status==='ACTIVE').length/5)-1));
   const result=original.apply(this,arguments);
   members=list.filter(m=>m.status==='ACTIVE');render();return result;
  };
  const openProfile=app.openProfileModal;
  app.openProfileModal=function(id){
   const result=openProfile.apply(this,arguments);
   const recovery=d.getElementById('account-recovery');if(recovery)recovery.open=false;
   node('remove').hidden=this.authenticatedRole?.role!=='owner';
   return result;
  };
  node('remove').onclick=async()=>{
   const id=app.activeModalMemberId;if(!id)return;
   await app.deleteMember(id);
   if(app.members.find(m=>m.id===id)?.status==='INACTIVE')app.closeProfileModal();
  };
  node('list').onclick=event=>{const button=event.target.closest('button[data-member-id]');if(button&&node('list').contains(button))app.openProfileModal(button.dataset.memberId);};
  d.getElementById('roster-expansion').onclick=()=>{app.rosterExpanded=!app.rosterExpanded;app.filterRoster();};
 }
 root.IronVaultMobileRoster={install};
})(globalThis);
