/* Stage 1: filter only the existing scoped roster. No queries, writes or admissions. */
(function(root){
 'use strict';
 const dateFormat=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}),labelFormat=new Intl.DateTimeFormat('en-GB',{timeZone:'UTC',day:'numeric',month:'short',year:'numeric'});
 const plans=new Set(['1-Day Pass','1-Week Pass','1-Month Unlimited']);
 function day(value=new Date()){const parts=dateFormat.formatToParts(value);return ['year','month','day'].map(k=>parts.find(p=>p.type===k).value).join('-');}
 function validDate(value){if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value))return false;const date=new Date(value+'T00:00:00Z');return Number.isFinite(date.getTime())&&date.toISOString().slice(0,10)===value;}
 function remaining(member,today=day()){const expiry=member.expirationDate??member.expiration_date;if(!validDate(expiry)||!validDate(today))return null;return Math.round((Date.parse(expiry+'T00:00:00Z')-Date.parse(today+'T00:00:00Z'))/86400000);}
 function expiring(member,tenant,days=3,today=day()){const left=remaining(member,today);return !!tenant&&(member.tenantId??member.tenant_id)===tenant&&member.status==='ACTIVE'&&plans.has(member.plan)&&left!==null&&left>=0&&left<=days;}
 function expiryLabel(member,today=day()){const left=remaining(member,today);if(left===null)return 'Expiry unavailable';const expiry=member.expirationDate??member.expiration_date;const formatted=labelFormat.format(new Date(expiry+'T00:00:00Z'));return formatted+' · '+(left===0?'Expires today':left<0?'Expired':left+' day'+(left===1?'':'s')+' left');}
 function install(app,client){
  const d=root.document;if(!d.querySelector||app.ivMemberListTools)return;const actions=d.querySelector('.roster-filter-actions');if(!actions)return;app.ivMemberListTools=true;app.rosterExpiryDays=3;let signedOut=false;actions.closest('#member-roster-card')?.classList.add('member-tools-enabled');
  const make=(tag,text)=>{const n=d.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  const button=make('button');button.id='filter-btn-expiring';button.type='button';button.className='member-expiring-button';button.setAttribute('aria-pressed','false');button.title='Find active members whose passes expire soon';
  button.innerHTML='<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M15 4H5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h7M7 2v5m8-5v5M3 10h10"/><circle cx="17" cy="16" r="6"/><path d="M17 12v4l3 2"/></svg>';
  const caption=make('span'),count=make('span');count.id='expiring-member-count';button.append(caption,count);caption.textContent='Expiring Soon';actions.insertBefore(button,d.getElementById('pending-approvals-button'));button.onclick=()=>app.toggleRosterFilter('expiring');
  const settings=make('div'),select=make('select'),label=make('label','Expiry window');settings.className='member-expiry-settings';label.htmlFor='member-expiry-range';label.className='member-tools-sr-only';select.id='member-expiry-range';
  for(const [value,text] of [['0','Today'],['3','Within 3 days'],['7','Within 7 days'],['14','Within 14 days'],['custom','Custom days…']]){const option=make('option',text);option.value=value;select.append(option);}select.value='3';
  const custom=make('input'),customLabel=make('label','Custom days');custom.type='number';custom.id='member-expiry-custom';custom.min='0';custom.max='365';custom.step='1';custom.value='3';custom.hidden=true;customLabel.htmlFor=custom.id;customLabel.className='member-tools-sr-only';customLabel.hidden=true;custom.setAttribute('aria-describedby','member-expiry-help');
  const help=make('span');help.id='member-expiry-help';help.className='member-expiry-help';help.setAttribute('role','status');settings.append(label,select,customLabel,custom,help);actions.after(settings);
  app.rosterExpiryLabel=expiryLabel;
  function refresh(today=day()){const total=signedOut?0:(app.members||[]).filter(m=>expiring(m,app.currentTenantId,app.rosterExpiryDays,today)).length;count.textContent=' · '+total;button.setAttribute('aria-label','Expiring Soon, '+total+' members, '+(app.rosterExpiryDays===0?'today':'within '+app.rosterExpiryDays+' days'));button.setAttribute('aria-pressed',String(app.rosterActiveFilter==='expiring'));for(const [id,type] of [['filter-btn-logged','logged'],['filter-btn-not-entered','not_entered']])d.getElementById(id)?.setAttribute('aria-pressed',String(app.rosterActiveFilter===type));}
  const render=app.renderRoster;app.renderRoster=function(list){const today=day();refresh(today);const visible=signedOut?[]:this.rosterActiveFilter==='expiring'?list.filter(m=>expiring(m,this.currentTenantId,this.rosterExpiryDays,today)):list;return render.call(this,visible);};
  function apply(value){if(signedOut)return;app.rosterExpiryDays=value;help.textContent='';custom.setCustomValidity('');if(app.rosterActiveFilter!=='expiring')app.toggleRosterFilter('expiring');else app.filterRoster();}
  select.onchange=()=>{custom.hidden=customLabel.hidden=select.value!=='custom';if(select.value==='custom'){custom.value=String(app.rosterExpiryDays);custom.focus();}else apply(Number(select.value));};
  custom.oninput=()=>{const value=custom.value;if(!/^\d+$/.test(value)||Number(value)>365){const text='Enter a whole number from 0 to 365. The last valid range remains applied.';custom.setCustomValidity(text);help.textContent=text;return;}apply(Number(value));};
  client?.auth?.onAuthStateChange?.(event=>{if(event==='SIGNED_OUT'){signedOut=true;app.rosterExpiryDays=3;app.rosterActiveFilter='all';select.value='3';custom.value='3';custom.hidden=customLabel.hidden=true;custom.setCustomValidity('');help.textContent='';count.textContent=' · 0';button.setAttribute('aria-pressed','false');button.setAttribute('aria-label','Expiring Soon, 0 members, within 3 days');}});
  refresh();
 }
 const api=Object.freeze({install,day,remaining,expiring,expiryLabel});root.IronVaultMemberListTools=api;if(typeof module==='object'&&module.exports)module.exports=api;
})(globalThis);
