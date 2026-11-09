/* Compact lists. Only opening a full message acknowledges its exact displayed notice. */
(function(root){
 'use strict';
 function render(target,rows,options={}){
  if(target.querySelector?.('.iv-notice-detail[open]')){target.noticePending={rows,options};return;}
  target.noticePending=null;
  const {onRead,onOpen,emptyMessage}=options,version=(target.noticeVersion||0)+1;target.noticeVersion=version;
  const d=root.document,make=(tag,text)=>{const n=d.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  const status=r=>r.pinned===true||r.kind==='status'&&!r.resolved_at;
  const groups=()=>({unread:rows.filter(r=>r.unread),status:rows.filter(status),read:rows.filter(r=>!r.unread&&!status(r))});
  const selected=target.dataset.noticeView||'unread';target.dataset.noticeView=selected;target.textContent='';
  const nav=make('nav');nav.className='iv-notice-tabs';nav.setAttribute('aria-label','Notification views');const tabs=[];
  function counts(){const g=groups();for(const [b,key,label]of tabs)b.textContent=label+' ('+g[key].length+')';}
  for(const [key,label]of [['unread','Unread'],['status','Pinned / Status'],['read','Read']]){const b=make('button');b.type='button';b.setAttribute('aria-pressed',String(selected===key));b.onclick=()=>{target.dataset.noticeView=key;render(target,rows,options);};tabs.push([b,key,label]);nav.append(b);}counts();target.append(nav);
  const feedback=make('p');feedback.setAttribute('role','status');target.append(feedback);const list=make('div');target.append(list);
  const ordered=[...groups()[selected]].sort((a,b)=>Date.parse(b.starts_at||b.available_at||0)-Date.parse(a.starts_at||a.available_at||0));
  const date=value=>Number.isFinite(Date.parse(value))?new Intl.DateTimeFormat('en-PH',{timeZone:'Asia/Manila',dateStyle:'medium',timeStyle:'short'}).format(new Date(value))+' · Philippine time':'';
  if(!ordered.length){const empty=make('p',emptyMessage||(selected==='unread'?'You’re all caught up':'No notifications in this view.'));empty.className='iv-notice-empty';list.append(empty);}
  for(const row of ordered){const article=make('article');article.className='iv-notice-card iv-notice-compact';const open=make('button');open.type='button';open.className='iv-notice-row';open.setAttribute('aria-label','Open message: '+row.title);open.append(make('strong',row.title),make('small',date(row.starts_at||row.available_at)),make('small',(row.noticeSource==='subscription'?'Subscription · ':'')+(status(row)?'Pinned / current status · ':'')+(row.unread?'Unread':'Read')));article.append(open);list.append(article);
   open.onclick=async()=>{if(open.disabled)return;open.disabled=true;const detail=make('dialog');detail.className='iv-notice-detail';detail.setAttribute('aria-label',row.title);const heading=make('header'),close=make('button','✕');close.type='button';close.setAttribute('aria-label','Close message');close.onclick=()=>detail.close();heading.append(make('h2',row.title),close);detail.append(heading,make('small',date(row.starts_at||row.available_at)),make('p',row.body||row.message||''));
    if(!row.kind&&row.ends_at&&Number.isFinite(Date.parse(row.ends_at))&&!String(row.ends_at).startsWith('9999'))detail.append(make('small','Until '+date(row.ends_at)));
    const message=make('p');message.setAttribute('role','status');detail.append(message);const retry=make('button','Retry marking read');retry.type='button';retry.hidden=true;detail.append(retry);
    if(onOpen&&row.noticeSource!=='announcement'&&row.detailLabel!==false){const more=make('button',row.detailLabel||(row.noticeSource==='subscription'?'Open subscription':'View details'));more.type='button';more.onclick=async()=>{detail.close();try{await onOpen(row);}catch(_){if(target.isConnected)feedback.textContent='Details could not be opened. Please retry.';}};detail.append(more);}
    detail.addEventListener('close',()=>{const connected=detail.isConnected;detail.remove();open.disabled=false;if(connected&&target.isConnected&&target.noticeVersion===version){const pending=target.noticePending;target.noticePending=null;render(target,pending?.rows||rows,pending?.options||options);}});
    target.append(detail);
    try{detail.showModal();}catch(_){detail.remove();open.disabled=false;feedback.textContent='Message could not be opened. Please retry.';return;}
    let saving=false;async function acknowledge(){if(saving||!row.unread||!onRead)return;saving=true;retry.disabled=true;try{await onRead(row);if(detail.isConnected&&detail.open&&target.noticeVersion===version){row.unread=false;counts();retry.hidden=true;message.textContent='Read';}}catch(_){if(detail.isConnected&&detail.open){message.textContent='Read status could not be saved. Please retry.';retry.hidden=false;}}finally{saving=false;retry.disabled=false;}}
    retry.onclick=acknowledge;await acknowledge();
   };
  }
 }
 root.IronVaultNoticeViews=Object.freeze({render});
})(globalThis);
