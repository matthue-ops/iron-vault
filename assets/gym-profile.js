/* Gym Profile presentation. Reuses loaded tenant data and existing authorized action handlers. */
(function(root){
 'use strict';
 const plans={portal:'Dashboard + Member Portal',dashboard:'Dashboard Only'};
 function subscriptionView(state={}){
  const labels={setup:['Setup required','Awaiting activation'],pilot:['Free Pilot','Active'],paid:['Paid Subscription','Active'],grace:['Grace Period','Dashboard only'],suspended:['Subscription Suspended','Suspended'],inactive:['Gym Inactive','Inactive']};
  const [title,status]=labels[state.status]||['Subscription details unavailable','Unavailable'];
  const date=value=>{if(!/^\d{4}-\d{2}-\d{2}$/.test(value||''))return '';const parsed=new Date(value+'T00:00:00+08:00');return Number.isFinite(parsed.getTime())?new Intl.DateTimeFormat('en-PH',{timeZone:'Asia/Manila',month:'short',day:'numeric',year:'numeric'}).format(parsed):'';};
  let remaining='';
  if(['pilot','paid'].includes(state.status)&&state.days_remaining!=null&&Number.isFinite(Number(state.days_remaining))){const start=Date.parse(state.start_date+'T00:00:00Z'),end=Date.parse(state.end_date+'T00:00:00Z'),total=Math.round((end-start)/86400000)+1;const days=Math.max(0,Number(state.days_remaining));const counted=Number.isFinite(total)&&total>0?Math.min(days,total):days;remaining=counted+' counted '+(counted===1?'day':'days')+' remaining';}
  else if(state.status==='grace')remaining=date(state.grace_end)?'Grace ends '+date(state.grace_end):'Contact the owner about renewal.';
  else if(state.status==='setup')remaining='Complete onboarding before pilot activation.';
  else if(state.status==='suspended')remaining='Review payment and renewal requirements.';
  const dates=date(state.start_date)&&date(state.end_date)?date(state.start_date)+' – '+date(state.end_date):'';
  return {title,status,plan:plans[state.plan]||'No plan selected',remaining,dates,tone:['pilot','paid'].includes(state.status)?'active':state.status==='grace'?'warning':'muted'};
 }
 function install(app,client){
  const d=root.document,node=id=>d.getElementById(id),overlay=node('branch-inspect-modal');if(!overlay||!d.createElement)return;
  const panel=overlay.firstElementChild;if(!panel)return;
  const make=(tag,text,cls)=>{const el=d.createElement(tag);if(text!==undefined)el.textContent=text;if(cls)el.className=cls;return el;};
  const action=(label,handler,cls)=>{const el=make('button',label,cls);el.type='button';el.addEventListener('click',handler);return el;};
  const identity=node('inspect-logo-container').parentElement,identityText=node('inspect-owner-info').parentElement,nameRow=node('inspect-gym-name').parentElement;
  const pricing=node('toggle-content-pricing').parentElement,roster=node('toggle-content-roster').parentElement,staff=node('toggle-content-staff').parentElement,backup=node('toggle-content-zip').parentElement;
  const stats=node('inspect-stat-members').parentElement.parentElement,reports=node('inspect-reports-btn'),footer=panel.lastElementChild;
  const close=panel.querySelector('button[onclick="indexApp.closeInspectModal()"]');close.className='gym-profile-close';close.setAttribute('aria-label','Close Gym Profile');
  panel.classList.add('gym-profile-panel');panel.setAttribute('role','dialog');panel.setAttribute('aria-modal','true');panel.setAttribute('aria-labelledby','gym-profile-title');overlay.classList.add('gym-profile-overlay');
  const heading=make('header',undefined,'gym-profile-heading');const title=make('h2','Gym Profile');title.id='gym-profile-title';heading.append(title,close);
  identity.className='gym-profile-identity gym-profile-card';const tag=make('span','Status unavailable','gym-profile-tag');tag.id='gym-profile-tag';nameRow.className='gym-profile-name-row';nameRow.appendChild(tag);identityText.classList.add('gym-profile-identity-text');identityText.insertBefore(node('inspect-tenant-id'),node('inspect-owner-info'));
  const actions=make('div',undefined,'gym-profile-actions'),portal=make('a','Open Gym Portal','gym-profile-portal');portal.target='_blank';portal.rel='noopener';portal.id='gym-profile-portal';
  const menu=make('details',undefined,'gym-profile-menu'),menuSummary=make('summary','⋯');menuSummary.setAttribute('aria-label','Gym profile actions');const menuBody=make('div',undefined,'gym-profile-menu-panel');
  const edit=action('Edit Gym Details',()=>{const id=app.currentInspectOwnerId;app.closeInspectModal();app.openEditModal(id);});
  const retag=action('Change Test / Live Status',()=>{menu.open=false;app.setTenantTag?.(app.currentInspectOwnerId);});
  const purge=action('Purge Gym',()=>{const id=app.currentInspectOwnerId;app.closeInspectModal();app.openTenantPurge(id);},'gym-profile-danger');const suspend=action('Suspend Gym',async()=>{const id=app.currentInspectOwnerId;menu.open=false;if(!root.confirm('Change operational access for this gym? Its records will be kept.'))return;await app.toggleOwnerStatus(id);render(id);});menuBody.append(edit,retag,make('hr'),suspend,purge);menu.append(menuSummary,menuBody);actions.append(portal,menu);identityText.appendChild(actions);
  const subscription=make('section',undefined,'gym-profile-card gym-profile-subscription'),eyebrow=make('p','SUBSCRIPTION','gym-profile-eyebrow'),planHeading=make('div',undefined,'gym-profile-plan-heading'),planTitle=make('h3'),status=make('span',undefined,'gym-profile-status'),plan=make('p',undefined,'gym-profile-plan'),remaining=make('p',undefined,'gym-profile-remaining'),dates=make('p',undefined,'gym-profile-dates');
  const manage=action('Manage Subscription',()=>app.openSubscriptionBilling(app.currentInspectOwnerId),'gym-profile-primary');manage.id='inspect-subscription-button';planHeading.append(planTitle,status);subscription.append(eyebrow,planHeading,plan,remaining,dates,manage);
  const top=make('div',undefined,'gym-profile-top');top.append(identity,subscription);stats.className='gym-profile-stats';
  node('inspect-stat-members').previousElementSibling.textContent='Members';node('inspect-stat-active').previousElementSibling.textContent='Active Memberships';node('inspect-stat-revenue').previousElementSibling.textContent='Gym Revenue';node('inspect-stat-revenue').parentElement.title='Revenue recorded for gym members, separate from the gym’s Iron Vault subscription.';
  function styleSection(section,label){section.classList.add('gym-profile-section');const h=section.querySelector('h4');if(h){const icon=h.querySelector('i');h.textContent='';if(icon)h.append(icon,d.createTextNode(' '));h.appendChild(d.createTextNode(label));}}
  styleSection(pricing,'Pricing & Discounts');styleSection(roster,'Members');styleSection(staff,'Staff Accounts');styleSection(backup,'Backup & Restore');
  const members=make('details',undefined,'gym-profile-section gym-profile-members'),membersTitle=make('summary','Members & Staff');members.append(membersTitle,roster,staff);
  const records=make('details',undefined,'gym-profile-section gym-profile-records'),recordsTitle=make('summary','Reports & Records'),recordsBody=make('div',undefined,'gym-profile-record-actions');reports.classList.add('gym-profile-record-link');reports.rel='noopener';recordsBody.append(reports,action('Subscription & Agreement Records',()=>app.openSubscriptionBilling(app.currentInspectOwnerId)));records.append(recordsTitle,recordsBody);
  footer.className='gym-profile-footer';footer.querySelector('button').textContent='Close Profile';
  panel.replaceChildren(heading,top,stats,members,pricing,records,backup,footer);
  let opener=null;
  function render(id){const owner=app.owners.find(g=>g.id===id);if(!owner)return;const tenant=app.providerTenants?.[id],view=subscriptionView(tenant?.state);node('inspect-gym-name').textContent=owner.gymName;
   const known=typeof tenant?.is_test==='boolean';tag.textContent=known?(tenant.is_test?'TEST':'LIVE'):'Status unavailable';tag.dataset.kind=known?(tenant.is_test?'test':'live'):'unknown';
   planTitle.textContent=view.title;status.textContent=view.status;status.dataset.tone=view.tone;plan.textContent=view.plan;remaining.textContent=view.remaining;dates.textContent=view.dates;dates.hidden=!view.dates;
   const url=root.IronVaultGymPortals?.url(owner,root.location);if(url){portal.href=url;portal.hidden=false;}else{portal.removeAttribute('href');portal.hidden=true;}
   suspend.textContent=owner.status==='ACTIVE'?'Suspend Gym':'Reactivate Gym';
   retag.hidden=typeof app.setTenantTag!=='function';manage.disabled=typeof app.openSubscriptionBilling!=='function';
  }
  const originalOpen=app.openInspectModal;
  app.openInspectModal=function(id){if(!this.owners.some(g=>g.id===id))return;opener=d.activeElement;const result=originalOpen.apply(this,arguments);menu.open=false;members.open=records.open=false;
   for(const key of ['pricing','roster','staff','zip']){node('toggle-content-'+key).classList.add('hidden');node('toggle-icon-'+key).classList.remove('rotate-180');}
   for(const detail of staff.querySelectorAll('details'))detail.open=false;
   render(id);panel.scrollTop=0;close.focus({preventScroll:true});return result;
  };
  const originalClose=app.closeInspectModal;app.closeInspectModal=function(){menu.open=false;const result=originalClose.apply(this,arguments);if(opener?.isConnected)opener.focus({preventScroll:true});opener=null;return result;};
  const originalRender=app.renderDashboard;app.renderDashboard=function(){const result=originalRender.apply(this,arguments);if(!overlay.classList.contains('hidden')&&this.currentInspectOwnerId)render(this.currentInspectOwnerId);return result;};
  overlay.addEventListener('keydown',event=>{if(event.key==='Escape'){event.preventDefault();if(menu.open)menu.open=false;else app.closeInspectModal();}if(event.key==='Tab'){const items=Array.from(panel.querySelectorAll('button,a[href],input,select,textarea,summary')).filter(el=>!el.disabled&&el.getClientRects().length);if(!items.length)return;const first=items[0],last=items[items.length-1];if(event.shiftKey&&d.activeElement===first){event.preventDefault();last.focus();}else if(!event.shiftKey&&d.activeElement===last){event.preventDefault();first.focus();}}});
  d.addEventListener('click',event=>{if(!menu.contains(event.target))menu.open=false;});
  client?.auth?.onAuthStateChange?.(event=>{if(event==='SIGNED_OUT'){app.closeInspectModal();node('inspect-gym-name').textContent='';node('inspect-owner-info').textContent='';planTitle.textContent='';remaining.textContent='';dates.textContent='';}});
 }
 root.IronVaultGymProfile={install,subscriptionView};if(typeof module==='object'&&module.exports)module.exports=root.IronVaultGymProfile;
})(globalThis);
