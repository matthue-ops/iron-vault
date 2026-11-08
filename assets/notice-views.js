/* Shared phone-friendly views. Opening the panel never marks unseen items read. */
(function(root){
 'use strict';
 function render(target,rows,{onRead,onOpen}={}){
  const version=(target.noticeVersion||0)+1;target.noticeVersion=version;
  const d=root.document,make=(tag,text)=>{const n=d.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  const status=r=>r.pinned===true||r.kind==='status'&&!r.resolved_at;
  const groups={unread:rows.filter(r=>r.unread),status:rows.filter(status),read:rows.filter(r=>!r.unread&&!status(r))};
  const selected=target.dataset.noticeView||'unread';target.dataset.noticeView=selected;target.textContent='';
  const nav=make('nav');nav.className='iv-notice-tabs';nav.setAttribute('aria-label','Notification views');
  for(const [key,label] of [['unread','Unread'],['status','Pinned / Status'],['read','Read']]){const button=make('button',label+' ('+groups[key].length+')');button.type='button';button.setAttribute('aria-pressed',String(selected===key));button.onclick=()=>{target.dataset.noticeView=key;render(target,rows,{onRead,onOpen});};nav.append(button);}target.append(nav);
  const feedback=make('p');feedback.setAttribute('role','status');target.append(feedback);
  const list=make('div');target.append(list);const ordered=[...groups[selected]].sort((a,b)=>Date.parse(b.starts_at||b.available_at||0)-Date.parse(a.starts_at||a.available_at||0));
  if(!ordered.length)list.append(make('p','No notifications in this view.'));
  for(const row of ordered){const article=make('article');article.className='iv-notice-card';article.append(make('h3',row.title),make('p',row.body||row.message),make('small',(status(row)?'Pinned / current status · ':'')+(row.unread?'Unread':'Read')));
   const instant=row.starts_at||row.available_at;if(Number.isFinite(Date.parse(instant)))article.append(make('small',new Intl.DateTimeFormat('en-PH',{timeZone:'Asia/Manila',dateStyle:'medium',timeStyle:'short'}).format(new Date(instant))+' · Philippine time'));
   if(!row.kind&&row.ends_at&&Number.isFinite(Date.parse(row.ends_at))&&!String(row.ends_at).startsWith('9999'))article.append(make('small','Until '+new Intl.DateTimeFormat('en-PH',{timeZone:'Asia/Manila',dateStyle:'medium',timeStyle:'short'}).format(new Date(row.ends_at))));
   if(row.unread&&onRead){const read=make('button','Mark read');read.type='button';read.onclick=async()=>{if(read.disabled)return;read.disabled=true;try{await onRead(row);if(target.noticeVersion===version&&target.isConnected){row.unread=false;render(target,rows,{onRead,onOpen});}}catch(_){if(target.noticeVersion===version&&target.isConnected){feedback.textContent='Read status could not be saved. Please retry.';read.disabled=false;}}};article.append(read);}
   if(onOpen){const open=make('button','View details');open.type='button';open.onclick=()=>onOpen(row);article.append(open);}list.append(article);
  }
 }
 root.IronVaultNoticeViews=Object.freeze({render});
})(globalThis);
