/* Phone presentation only. Reuses the existing roster, filters and profile actions. */
(function(root){
 'use strict';
 function install(app,client){
  if(!root.matchMedia)return;
  const d=root.document,media=root.matchMedia('(max-width:639px)'),card=d.getElementById('member-roster-card');if(!card)return;
  const marker=d.createComment('Desktop member roster');card.before(marker);
  const view=d.createElement('section');view.id='phone-members-view';view.hidden=true;view.setAttribute('role','dialog');view.setAttribute('aria-modal','true');view.setAttribute('aria-labelledby','phone-members-title');
  const header=d.createElement('header'),title=d.createElement('h2'),close=d.createElement('button'),content=d.createElement('div');title.id='phone-members-title';title.textContent='Members';close.type='button';close.textContent='Close';close.setAttribute('aria-label','Close members');header.append(title,close);content.className='phone-members-content';view.append(header,content);d.body.appendChild(view);
  let opener=null,overflow='';
  app.openPhoneMembers=function(){if(!media.matches)return;opener=d.activeElement;overflow=d.body.style.overflow;content.appendChild(card);view.hidden=false;d.body.style.overflow='hidden';d.getElementById('roster-search').focus({preventScroll:true});};
  function shut(){if(view.hidden)return;view.hidden=true;view.inert=false;d.body.style.overflow=overflow;opener?.focus({preventScroll:true});}
  close.onclick=shut;
  view.addEventListener('keydown',event=>{if(event.key==='Escape'){event.preventDefault();shut();}if(event.key==='Tab'){const items=[...view.querySelectorAll('button,input,select,a[href],summary')].filter(n=>!n.disabled&&n.getClientRects().length);if(!items.length)return;const first=items[0],last=items.at(-1);if(event.shiftKey&&d.activeElement===first){event.preventDefault();last.focus();}else if(!event.shiftKey&&d.activeElement===last){event.preventDefault();first.focus();}}});
  const stats=app.updateStats;app.updateStats=function(){const result=stats.apply(this,arguments);d.getElementById('phone-members-count').textContent='('+this.members.filter(m=>m.status==='ACTIVE').length+')';return result;};
  function resize(){if(!media.matches){shut();marker.after(card);}else if(view.hidden)content.appendChild(card);}
  media.addEventListener('change',resize);resize();
  client?.auth?.onAuthStateChange?.(event=>{if(event==='SIGNED_OUT'){shut();d.getElementById('roster-search').value='';d.getElementById('mobile-roster-list').textContent='';}});
  // Keep list page, search, scroll and selected member when returning from a profile.
  const open=app.openProfileModal,closeProfile=app.closeProfileModal;let scroll=0,memberId=null;
  app.openProfileModal=function(id){if(!view.hidden){scroll=content.scrollTop;memberId=id;}const result=open.apply(this,arguments);if(!view.hidden){view.inert=true;const profile=d.getElementById('member-profile-modal');profile.setAttribute('role','dialog');profile.setAttribute('aria-modal','true');profile.setAttribute('aria-labelledby','modal-member-name');profile.querySelector('button')?.focus({preventScroll:true});}return result;};
  app.closeProfileModal=function(){const result=closeProfile.apply(this,arguments);view.inert=false;if(!view.hidden){content.scrollTop=scroll;[...card.querySelectorAll('[data-member-id]')].find(n=>n.dataset.memberId===memberId)?.focus({preventScroll:true});}return result;};
 }
 root.IronVaultPhoneMembers={install};
})(globalThis);
