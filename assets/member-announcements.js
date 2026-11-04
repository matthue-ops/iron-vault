/* Active gym notices only; read receipts persist when members open the bell. */
(function(root){
 'use strict';
 function install(app,client){
  const el=id=>root.document.getElementById(id),bell=el('member-notices-bell'),panel=el('member-notices-dialog');if(!bell)return;
  let epoch=0,serial=0,items=[],identity=null,offset=0,visible=false,busy=false,timer=null,lastFocus=null;
  const now=()=>Date.now()+offset;
  const active=row=>Date.parse(row.starts_at)<=now()&&Date.parse(row.ends_at)>now();
  function clear(){epoch++;serial++;busy=false;items=[];identity=null;visible=false;bell.hidden=true;bell.setAttribute('data-unread','false');panel.hidden=true;el('member-notices-list').textContent='';el('member-notices-count').textContent='';if(timer)root.clearTimeout(timer);timer=null;}
  function text(tag,value,cls){const n=root.document.createElement(tag);n.textContent=value;n.className=cls||'';return n;}
  function cards(target,rows){target.textContent='';if(!rows.length)target.appendChild(text('p','No active announcements.','text-slate-400'));
   for(const row of rows){const card=text('article','','rounded-xl border border-slate-700 bg-slate-900 p-4 space-y-2');card.appendChild(text('h3',row.title,'font-bold text-white break-words'));card.appendChild(text('p',row.body,'whitespace-pre-wrap break-words text-slate-200 text-sm'));card.appendChild(text('p',(row.pinned?'Pinned · ':'')+'Until '+new Intl.DateTimeFormat('en-PH',{timeZone:'Asia/Manila',dateStyle:'medium',timeStyle:'short'}).format(new Date(row.ends_at))+' · Manila time','text-xs text-slate-400'));target.appendChild(card);}
  }
  function render(){items=items.filter(active);const unread=items.filter(r=>r.unread).length;el('member-notices-count').textContent=unread?String(unread):'';bell.setAttribute('data-unread',String(unread>0));bell.setAttribute('aria-label','Announcements'+(unread?', '+unread+' unread':''));
   app.renderLegalNotice?.(unread);
   if(visible)cards(el('member-notices-list'),items);
   if(timer)root.clearTimeout(timer);const next=items.length?Math.min(...items.map(r=>Date.parse(r.ends_at)))-now():60000;timer=root.setTimeout(()=>{render();refresh();},Math.min(Math.max(next+30,100),60000));
  }
  async function verify(){const expected=app.authenticatedRole;if(!expected||!app.currentMember)throw Error('Sign in required.');const role=await root.IronVaultAuth.requireRole(client,{roles:['member'],tenantId:expected.tenant_id,memberId:expected.member_id});
   if(role.user_id!==expected.user_id||role.member_id!==expected.member_id||role.tenant_id!==expected.tenant_id||(identity&&identity!==role.user_id+'|'+role.tenant_id+'|'+role.member_id))throw Error('The signed-in membership changed.');return role;
  }
  async function fetchFeed(mode,read=[]){const stamp=epoch,ticket=++serial,role=await verify();if(stamp!==epoch)return null;
   const {data,error}=await client.rpc('iv_member_announcements',{p_tenant:role.tenant_id,p_mode:mode,p_read:read});if(stamp!==epoch||ticket!==serial)return null;if(error)throw error;
   const checked=await verify();if(stamp!==epoch||ticket!==serial)return null;if(checked.user_id!==role.user_id||checked.tenant_id!==role.tenant_id||checked.member_id!==role.member_id)throw Error('The signed-in account changed.');
   if(!data||!Array.isArray(data.items)||!Number.isFinite(Date.parse(data.server_now))||data.items.some(r=>r.tenant_id!==role.tenant_id||typeof r.id!=='string'||typeof r.revision!=='string'||typeof r.title!=='string'||typeof r.body!=='string'||typeof r.unread!=='boolean'||typeof r.popup!=='boolean'||!Number.isFinite(Date.parse(r.starts_at))||!Number.isFinite(Date.parse(r.ends_at))))throw Error('Invalid announcement response.');
   el('member-notices-status').textContent='';identity=role.user_id+'|'+role.tenant_id+'|'+role.member_id;offset=Date.parse(data.server_now)-Date.now();items=data.items.filter(active);bell.hidden=false;render();return items;
  }
  function show(rows){lastFocus=root.document.activeElement;visible=true;panel.hidden=false;cards(el('member-notices-list'),rows);el('member-notices-close').focus();}
  async function refresh(){if(busy)return;busy=true;const stamp=epoch;try{await fetchFeed('list');
   }catch(error){if(stamp===epoch){clear();bell.hidden=false;bell.setAttribute('aria-label','Announcements unavailable');el('member-notices-status').textContent='Announcements are unavailable. Please try again.';app.renderLegalNotice?.(0);}}
   finally{if(stamp===epoch)busy=false;}
  }
  app.openMemberAnnouncements=async function(){if(busy)return;busy=true;const stamp=epoch;el('member-notices-status').textContent='';try{const rows=await fetchFeed('list');if(!rows||stamp!==epoch)return;show(rows);const read=rows.map(r=>({id:r.id,revision:r.revision}));await fetchFeed('read',read);}catch(error){if(stamp===epoch){clear();bell.hidden=false;el('member-notices-status').textContent='Announcements are unavailable. Please try again.';if(app.hasLegalNotice?.()){show([]);app.renderLegalNotice?.(0);}}}finally{if(stamp===epoch)busy=false;}};
  app.closeMemberAnnouncements=function(){visible=false;panel.hidden=true;lastFocus?.focus?.();};
  const init=app.init;app.init=async function(...args){clear();await init.apply(this,args);if(this.currentMember)await refresh();};
  client.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'||(identity&&session?.user?.id&&identity.split('|')[0]!==session.user.id))clear();});
  root.addEventListener('focus',()=>refresh());
  root.addEventListener('keydown',e=>{if(!visible)return;if(e.key==='Escape')app.closeMemberAnnouncements();if(e.key==='Tab'){const nodes=panel.querySelectorAll('button:not([disabled]),[href],input,select,textarea,[tabindex="0"]');const first=nodes[0],last=nodes[nodes.length-1];if(e.shiftKey&&root.document.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&root.document.activeElement===last){e.preventDefault();first.focus();}}});clear();
 }
 root.IronVaultMemberAnnouncements=Object.freeze({install});if(typeof module==='object'&&module.exports)module.exports=root.IronVaultMemberAnnouncements;
})(globalThis);
