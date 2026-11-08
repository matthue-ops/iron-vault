/* Owner/staff management. Database RPCs enforce tenant and owner authority independently. */
(function(root){
 'use strict';
 function localTime(value){
  const date=new Date(value);if(Number.isNaN(date.getTime()))throw Error('Choose valid start and end times.');
  const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(date),get=key=>parts.find(part=>part.type===key).value;
  return get('year')+'-'+get('month')+'-'+get('day')+'T'+get('hour')+':'+get('minute');
 }
 function instant(value){
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value||''))throw Error('Choose valid start and end times.');
  const date=new Date(value+':00+08:00');if(Number.isNaN(date.getTime())||localTime(date)!==value)throw Error('Choose valid start and end times.');return date.toISOString();
 }
 function schedule(notice,now){if(notice.archived_at)return 'Removed';if(Date.parse(notice.starts_at)>Date.parse(now))return 'Scheduled';return Date.parse(notice.ends_at)<=Date.parse(now)?'Expired':'Active schedule';}
 function install(app,client){
  const node=id=>root.document.getElementById(id),panel=node('announcements-panel');if(!panel)return;
  const fields=['announcement-audience','announcement-title','announcement-body','announcement-start','announcement-end','announcement-pinned'];
  let audienceRequest=0,audienceRecipients=[],selectedRecipients=new Set();
  let generation=0,request=0,visible=false,busy=false,canManage=false,actor=null,tenant=null,items=[],page=0,total=0,serverNow=null,draft=null;
  function message(text,error=false){const box=node('announcements-message');box.textContent=text;box.className=error?'text-sm text-rose-300':'text-sm text-emerald-300';}
  function editorVisibility(show){node('announcement-editor').hidden=!show;node('announcement-preview').hidden=true;}
  function clear(){generation++;request++;audienceRequest++;audienceRecipients=[];selectedRecipients.clear();recipientSearch.value='';recipientSearch.hidden=true;node('announcement-recipients').textContent='';node('announcement-recipient-count').textContent='';visible=false;canManage=false;actor=null;tenant=null;items=[];draft=null;page=0;total=0;panel.hidden=true;panel.classList.add('hidden');node('announcements-list').textContent='';for(const id of ['announcements-access','announcements-page','announcements-asof'])node(id).textContent='';node('announcement-preview-title').textContent='';node('announcement-preview-body').textContent='';message('');for(const id of fields)if(node(id))node(id).value='';node('announcement-pinned').checked=false;editorVisibility(false);node('announcement-new').hidden=true;node('announcements-archived-option').hidden=true;}
  function changed(text){const error=Error(text);error.code='ACTOR_CHANGED';return error;}
  async function verify(write=false){
   const selected=app.currentTenantId;if(!selected)throw changed('Open a specific gym first.');
   const role=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:selected});
   if(app.currentTenantId!==selected||(tenant&&selected!==tenant)||(actor&&(role.user_id!==actor.user_id||role.role!==actor.role)))throw changed('The signed-in account, role or selected gym changed. Reopen Announcements.');
   if(app.authenticatedRole&&app.authenticatedRole.user_id!==role.user_id)throw changed('The signed-in account changed.');
   if(write){const {data,error}=await client.rpc('iv_staff_access',{p_tenant:selected,p_action:'mine'});if(error||data?.state!=='active'||data.permissions?.announcements_manage!==true)throw Error('Announcement management required.');}
   return role;
  }
  function explain(error){if(['PGRST202','42P01','42883'].includes(error?.code))return 'Announcements storage is not installed yet. Run the stage-one SQL before using this panel.';return error?.message||'Announcement request failed. Refresh and try again.';}
  function failed(error,prefix=''){
   const text=prefix+explain(error);
   if(['AUTH_REQUIRED','ACCESS_DENIED','ROLE_LOOKUP_FAILED','ACTOR_CHANGED'].includes(error?.code)||/access denied|owner access required/i.test(text)){clear();node('btn-announcements').classList.add('hidden');root.alert('Announcements: '+text);}else message(text,true);
  }
  function controls(){recipientSearch.disabled=busy||!canManage;for(const id of fields)if(node(id))node(id).disabled=busy||!canManage;node('announcement-save').disabled=busy||!canManage;node('announcement-new').disabled=busy;node('announcements-refresh').disabled=busy;node('announcements-filter').disabled=busy;node('announcements-prev').disabled=busy||page===0;node('announcements-next').disabled=busy||(page+1)*20>=total;}
  function textElement(tag,text,className){const el=root.document.createElement(tag);el.textContent=text;if(className)el.className=className;return el;}
  function render(){
   const list=node('announcements-list');list.textContent='';
   if(!items.length)list.appendChild(textElement('p','No announcements in this view.','text-sm text-slate-400 py-4'));
   for(const notice of items){
    const card=root.document.createElement('article');card.className='rounded-2xl border border-slate-700 bg-slate-900/70 p-4 space-y-3';
    card.appendChild(textElement('h3',notice.title,'font-bold text-white break-words'));
    card.appendChild(textElement('p',(notice.pinned?'Pinned · ':'')+schedule(notice,serverNow),'text-xs text-amber-300'));
    card.appendChild(textElement('p',notice.body,'text-sm text-slate-200 whitespace-pre-wrap break-words'));
    card.appendChild(textElement('p',localTime(notice.starts_at).replace('T',' ')+' → '+localTime(notice.ends_at).replace('T',' ')+' · Manila time','text-xs text-slate-400'));
    if(canManage&&!notice.archived_at){const actions=root.document.createElement('div');actions.className='flex flex-wrap gap-2';
     for(const [label,handler] of [['Edit',()=>app.editAnnouncement(notice.id)],[notice.pinned?'Unpin':'Pin',()=>app.pinAnnouncement(notice.id)],['Remove',()=>app.removeAnnouncement(notice.id)]]){const button=textElement('button',label,'px-3 py-2 min-h-11 rounded-xl border border-slate-600 text-xs text-white');button.type='button';button.disabled=busy;button.onclick=handler;actions.appendChild(button);}card.appendChild(actions);}
    list.appendChild(card);
   }
   node('announcements-page').textContent=total?'Showing '+(page*20+1)+'–'+Math.min((page+1)*20,total)+' of '+total:'0 announcements';
   node('announcements-asof').textContent=serverNow?'Schedule status as of '+localTime(serverNow).replace('T',' ')+' · Manila time':'';controls();
  }
  async function load(){
   const stamp=generation,ticket=++request;try{const before=await verify();if(!visible||stamp!==generation||ticket!==request)return;
   const selected=app.currentTenantId;const {data,error}=await client.rpc('iv_list_announcements',{p_tenant:selected,p_state:node('announcements-filter').value||'all',p_page:page});
   if(!visible||stamp!==generation||ticket!==request)return;if(error)throw error;
   const after=await verify();if(!visible||stamp!==generation||ticket!==request)return;
   if(after.user_id!==before.user_id||after.role!==before.role)throw changed('The signed-in account or role changed.');
   if(!data||!Array.isArray(data.items)||!Number.isSafeInteger(data.total)||data.total<0||!Number.isFinite(Date.parse(data.server_now))||data.items.some(row=>row.tenant_id!==selected||typeof row.title!=='string'||typeof row.body!=='string'||!Number.isInteger(row.version)||row.version<1||!Number.isFinite(Date.parse(row.starts_at))||!Number.isFinite(Date.parse(row.ends_at))))throw Error('Announcements returned an invalid response. Refresh and try again.');
   actor=after;tenant=selected;canManage=data.can_manage===true;items=data.items;total=data.total;serverNow=data.server_now;
   const last=Math.max(0,Math.ceil(total/20)-1);if(page>last){page=last;return load();}
   node('announcement-new').hidden=!canManage;node('announcements-archived-option').hidden=!canManage;if(!canManage)editorVisibility(false);
   node('announcements-access').textContent=canManage?'Authorized controls: create, target, schedule, pin and remove.':'Staff view: announcement management is restricted to the gym owner.';
   render();return true;
   }catch(error){if(visible&&stamp===generation&&ticket===request)throw error;return false;}
  }
  app.openAnnouncements=async function(){
   if(busy)return;clear();visible=true;panel.hidden=false;panel.classList.remove('hidden');node('announcements-filter').value='all';message('Loading announcements…');const stamp=generation;
   try{if(await load()&&visible&&stamp===generation)message('');}catch(error){if(visible&&stamp===generation)failed(error);}node('announcements-close').focus?.();
  };
  app.closeAnnouncements=function(){clear();node('btn-announcements').focus?.();};
  app.reloadAnnouncements=async function(reset=false){if(busy||!visible)return;if(reset)page=0;message('Loading announcements…');const stamp=generation;try{if(await load()&&visible&&stamp===generation)message('');}catch(error){if(visible&&stamp===generation)failed(error);}};
  app.announcementsPage=async function(direction){if(busy||!visible)return;page=Math.max(0,page+direction);return app.reloadAnnouncements();};
  function fill(notice){
   draft=notice?{id:notice.id,version:notice.version}:{id:root.crypto.randomUUID(),version:null};
   node('announcement-title').value=notice?.title||'';node('announcement-body').value=notice?.body||'';
   const now=new Date(serverNow||Date.now());node('announcement-start').value=localTime(notice?.starts_at||now);node('announcement-end').value=localTime(notice?.ends_at||new Date(now.getTime()+86400000));node('announcement-pinned').checked=notice?.pinned||false;
   node('announcement-editor-title').textContent=notice?'Edit announcement':'New announcement';editorVisibility(true);controls();node('announcement-title').focus?.();audience.value=notice?.audience||'everyone';selectedRecipients=new Set(notice?.audience_selection||[]);void loadAudience();
  }
  app.newAnnouncement=async function(){if(busy||!visible||!canManage)return;const stamp=generation;try{await verify(true);if(visible&&stamp===generation)fill(null);}catch(error){if(visible&&stamp===generation)failed(error);}};
  app.editAnnouncement=async function(id){if(busy||!visible||!canManage)return;const stamp=generation;try{await verify(true);if(!visible||stamp!==generation)return;const notice=items.find(row=>row.id===id&&!row.archived_at);if(!notice)throw Error('Reload the announcement list.');if(visible)fill(notice);}catch(error){if(visible&&stamp===generation)failed(error);}};
  app.cancelAnnouncement=function(){editorVisibility(false);draft=null;};
  app.previewAnnouncement=function(){node('announcement-preview-title').textContent=node('announcement-title').value.trim()||'Announcement title';node('announcement-preview-body').textContent=node('announcement-body').value.trim()||'Your message';node('announcement-preview').hidden=false;};
  function payload(notice){return {p_tenant:tenant,p_id:notice.id,p_title:notice.title,p_body:notice.body,p_starts_at:notice.starts_at,p_ends_at:notice.ends_at,p_pinned:notice.pinned,p_expected_version:notice.version};}
  async function write(name,args,success){
   if(busy||!visible||!canManage)return;busy=true;message('Saving change…');controls();render();const stamp=generation;let committed=false;
   try{await verify(true);if(!visible||stamp!==generation)return;
    const {data,error}=await client.rpc(name,args);if(error)throw error;committed=true;
    if(!visible||stamp!==generation)return;await verify(true);if(!visible||stamp!==generation)return;
    if(!data||data.id!==args.p_id||data.tenant_id!==tenant)throw Error('Server returned an unexpected result. Refresh the list.');
    editorVisibility(false);draft=null;await load();if(visible&&stamp===generation)message(success);
   }catch(error){if(visible&&stamp===generation)failed(error,committed?'The server confirmed the change; refresh to verify. ':'');}
   finally{busy=false;if(visible){controls();render();}}
  }
  const audience=node('announcement-audience'),recipientBox=node('announcement-recipients'),audienceCount=node('announcement-recipient-count');
  const recipientSearch=root.document.createElement('input');recipientSearch.type='search';recipientSearch.placeholder='Search recipient name or ID';recipientSearch.setAttribute('aria-label','Search announcement recipients');recipientSearch.hidden=true;recipientBox.before(recipientSearch);
  function renderRecipients(){recipientBox.textContent='';recipientSearch.hidden=audience.value!=='selected';if(audience.value!=='selected')return;const q=recipientSearch.value.trim().toLowerCase(),matches=audienceRecipients.filter(r=>r.kind!=='owner'&&[r.name,r.key,r.display_code].some(v=>String(v||'').toLowerCase().includes(q)));for(const recipient of matches){const label=root.document.createElement('label'),input=root.document.createElement('input');input.type='checkbox';input.disabled=busy||!canManage;input.checked=selectedRecipients.has(recipient.key);input.onchange=()=>{input.checked?selectedRecipients.add(recipient.key):selectedRecipients.delete(recipient.key);renderRecipients();};label.append(input,root.document.createTextNode(' '+recipient.name+' · '+recipient.kind));recipientBox.appendChild(label);}if(!matches.length)recipientBox.appendChild(textElement('p','No matching recipients.'));audienceCount.textContent=selectedRecipients.size+' selected recipients';const selected=root.document.createElement('details');selected.appendChild(textElement('summary','Review selected recipients ('+selectedRecipients.size+')'));for(const key of selectedRecipients){const recipient=audienceRecipients.find(r=>r.key===key),button=textElement('button','Remove '+(recipient?.name||key));button.type='button';button.onclick=()=>{selectedRecipients.delete(key);renderRecipients();};selected.appendChild(button);}recipientBox.appendChild(selected);}
  recipientSearch.oninput=renderRecipients;
  async function loadAudience(){const ticket=++audienceRequest;recipientSearch.value='';recipientBox.textContent='';audienceCount.textContent='Loading recipients…';try{await verify(true);const {data,error}=await client.rpc('iv_announcement_audience',{p_tenant:app.currentTenantId,p_audience:audience.value==='selected'?'everyone':audience.value});if(error)throw error;if(ticket!==audienceRequest||!visible)return;audienceRecipients=data.recipients||[];renderRecipients();if(audience.value!=='selected')audienceCount.textContent=data.count+' recipients';}catch(error){if(ticket===audienceRequest)audienceCount.textContent='Recipient preview unavailable: '+error.message;}}
  audience.onchange=()=>{selectedRecipients.clear();void loadAudience();};
  app.saveAnnouncement=async function(event){event.preventDefault();if(!draft||busy||!visible||!canManage)return;
   try{const title=node('announcement-title').value.trim(),body=node('announcement-body').value.trim(),start=instant(node('announcement-start').value),end=instant(node('announcement-end').value);
    if(!title||title.length>160||!body||body.length>4000)throw Error('Title and message are required (160 and 4000 characters maximum).');if(Date.parse(end)<=Date.parse(start))throw Error('End time must be after start time.');
    const selection=audience.value==='selected'?[...selectedRecipients]:[];const {data:count,error}=await client.rpc('iv_announcement_audience',{p_tenant:tenant,p_audience:audience.value,p_selected:selection});if(error)throw error;if(!count?.count)throw Error('Choose at least one eligible recipient.');if(!root.confirm('Publish this announcement to '+count.count+' recipient(s) in this gym?'))return;
    await write('iv_save_targeted_announcement',{...payload({...draft,title,body,starts_at:start,ends_at:end,pinned:node('announcement-pinned').checked}),p_audience:audience.value,p_selected:selection},'Announcement saved.');
   }catch(error){failed(error);}
  };
  app.pinAnnouncement=async function(id){const notice=items.find(row=>row.id===id&&!row.archived_at);if(!notice)return;await write('iv_pin_targeted_announcement',{p_tenant:tenant,p_id:id,p_expected_version:notice.version,p_pinned:!notice.pinned},'Pin updated.');};
  app.removeAnnouncement=async function(id){if(!visible||!canManage||busy)return;const notice=items.find(row=>row.id===id&&!row.archived_at);if(!notice||!root.confirm('Remove “'+notice.title+'”? It will be retained in the Removed section.'))return;await write('iv_archive_announcement',{p_tenant:tenant,p_id:id,p_expected_version:notice.version},'Announcement removed.');};
  const original=app.applyUIRoleVisibility;app.applyUIRoleVisibility=function(role){original.call(this,role);const button=node('btn-announcements');button.classList.toggle('hidden',!['admin','owner','staff'].includes(role));};
  client.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'||(actor&&session?.user?.id&&actor.user_id!==session.user.id)){clear();node('btn-announcements').classList.add('hidden');}});
  root.addEventListener('keydown',event=>{if(event.key==='Escape'&&visible)app.closeAnnouncements();});
  root.addEventListener('focus',()=>{if(visible){const stamp=generation;verify().catch(error=>{if(visible&&stamp===generation)failed(error);});}});
  clear();
 }
 const api=Object.freeze({install,localTime,instant,schedule});root.IronVaultAnnouncements=api;if(typeof module==='object'&&module.exports)module.exports=api;
})(globalThis);
