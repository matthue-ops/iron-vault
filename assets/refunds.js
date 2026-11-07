/* Reviewed adjustments use server references, scoped permissions and immutable request identities. */
(function(root){
 'use strict';
 const labels={cash:'Cash refund',wallet:'Refund to wallet',correct_credit:'Correct wallet credit'};
 const sourceLabels={topup:'Wallet top-up',plan_cash:'Pass paid in cash',plan_wallet:'Pass paid from wallet',refund_credit:'Wallet credit'};
 function install(app,client){
  const d=root.document;if(!d?.querySelector)return;
  const make=(tag,value)=>{const n=d.createElement(tag);if(value!==undefined)n.textContent=value;return n;};
  const money=n=>'₱'+Number(n||0).toLocaleString('en-PH',{minimumFractionDigits:2,maximumFractionDigits:2});
  const date=value=>Number.isFinite(Date.parse(value))?new Intl.DateTimeFormat('en-PH',{timeZone:'Asia/Manila',dateStyle:'medium',timeStyle:'short'}).format(new Date(value)):'Date unavailable';
  let box=null,reviewDialog=null,errorDialog=null,epoch=0,serial=0,identity=null,draft=null;const drafts=new Map();
  const role=()=>app.authenticatedRole;
  async function rpc(action,args={}){
   const stamp=epoch,tenant=app.currentTenantId,user=role()?.user_id;if(!tenant||!user)throw Error('Sign in required.');
   const before=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:tenant});if(before.user_id!==user)throw Error('Account changed.');
   try{
    const {data,error}=await client.rpc('iv_refunds',{p_tenant:tenant,p_action:action,...args});if(error)throw Object.assign(Error(error.message||'Refund service unavailable.'),{code:error.code});
    const after=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:tenant});if(epoch!==stamp||after.user_id!==user||app.currentTenantId!==tenant||role()?.user_id!==user)throw Error('Account changed.');return data;
   }catch(error){
    if(['request','approve','reject','cancel'].includes(action)&&!/^(P0001|22\w{3}|23\w{3}|IV002|IV003|42501)$/.test(error.code||''))error.uncertain=true;
    throw error;
   }
  }
  const menu=make('button');menu.id='btn-refunds';menu.type='button';menu.hidden=true;const icon=make('i');icon.className='fa-solid fa-money-bill-transfer';icon.setAttribute('aria-hidden','true');menu.append(icon,make('span','Refunds'));d.getElementById('btn-membership-pricing')?.after(menu);
  function closeError(){errorDialog?.close();errorDialog?.remove();errorDialog=null;}
  function showError(error){
   closeError();const dialog=make('dialog'),title=make('h2',error.uncertain?'Refund outcome not confirmed':'Refund needs attention'),button=make('button','Back to refund');errorDialog=dialog;dialog.className='iv-refunds iv-refund-error';dialog.setAttribute('aria-label',title.textContent);dialog.append(title,make('p',error.message||'Refund service unavailable.'));
   if(error.uncertain)dialog.append(make('p','This action may already be recorded. Check Pending review and History before retrying. Do not create a replacement request or pay cash again.'));
   button.type='button';button.onclick=closeError;dialog.append(button);dialog.oncancel=e=>{e.preventDefault();closeError();};d.body.append(dialog);dialog.showModal();
  }
  function closeReview(){closeError();reviewDialog?.close();reviewDialog?.remove();reviewDialog=null;}
  function close(){serial++;closeReview();box?.close();box?.remove();box=null;}
  function field(parent,label,input){const wrap=make('label');input.setAttribute('aria-label',label);wrap.append(make('span',label),input);parent.append(wrap);return wrap;}
  function option(parent,value,label){const n=make('option',label);n.value=value;parent.append(n);}
  function chooser(parent,label,rows,placeholder){
   const search=make('input'),select=make('select'),results=make('div');search.type='search';search.placeholder='Search name or Member ID';field(parent,'Search '+label.toLowerCase(),search);results.className='iv-refund-search-results';results.setAttribute('role','group');results.setAttribute('aria-label',label+' search results');parent.append(results);field(parent,label,select);
   const text=m=>m.name+' · '+(m.display_code||m.id)+(m.wallet!==undefined?' · '+money(m.wallet):'');
   function render(){const selected=select.value,q=search.value.trim().toLowerCase(),matches=rows.filter(m=>[m.name,m.display_code,m.id].some(v=>String(v||'').toLowerCase().includes(q)));select.textContent='';option(select,'',placeholder);for(const m of rows)if(m.id===selected||matches.includes(m))option(select,m.id,text(m));select.value=selected;results.textContent='';results.hidden=!q;
    if(q){if(!matches.length)results.append(make('p','No matching '+label.toLowerCase()+'.'));for(const m of matches){const b=make('button',text(m));b.type='button';b.onclick=()=>{select.value=m.id;search.value='';render();select.dispatchEvent(new root.Event('input',{bubbles:true}));select.dispatchEvent(new root.Event('change',{bubbles:true}));};results.append(b);}}
   }
   search.oninput=render;render();return {search,select,render};
  }
  async function open(memberId,initial='new'){
   close();const ticket=serial,who=role()?.user_id+'|'+app.currentTenantId;if(identity!==who){draft=null;drafts.clear();identity=who;}
   box=make('dialog');box.className='iv-refunds';const current=box,header=make('header'),done=make('button','Close'),status=make('p','Loading…');status.setAttribute('role','status');done.type='button';done.onclick=close;header.append(make('h2','Refunds & Corrections'),done);box.append(header,status);d.body.append(box);box.showModal();
   try{
    const data=await rpc('list');if(ticket!==serial||box!==current)return;
    function selectDraft(id=''){const key=who+'|'+id;let value=drafts.get(key);if(!value){value={key,member_id:id,source_key:'',action:'cash',amount:'',reason_category:'Incorrect account selected',reason:'',target_member_id:'',id:null,reference:null,storageKey:'iv_refund_draft:'+who+':'+id};drafts.set(key,value);}draft=value;}
    for(const id of ['',...data.members.map(m=>m.id)]){const key='iv_refund_draft:'+who+':'+id,saved=JSON.parse(root.sessionStorage.getItem(key)||'null');if(saved&&data.cases.some(c=>c.id===saved.id)){root.sessionStorage.removeItem(key);const completed=drafts.get(who+'|'+id);drafts.delete(who+'|'+id);if(draft===completed)draft=null;}}
    if(memberId!==undefined)selectDraft(memberId);status.textContent='';const nav=make('nav'),content=make('section');box.append(nav,content);
    function action(parent,label,fn,feedback=status){const b=make('button',label);b.type='button';b.onclick=async()=>{if(b.disabled)return;b.disabled=true;feedback.textContent='Processing…';try{await fn();if(b.isConnected)feedback.textContent='Completed.';}catch(error){if(b.isConnected){feedback.textContent=error.message;showError(error);}}finally{if(b.isConnected)b.disabled=false;}};parent.append(b);return b;}
    const memberName=id=>{const m=data.members.find(m=>m.id===id);return m?m.name+' · '+(m.display_code||m.id):id;};
    const sorted=[...(data.sources||[])].sort((a,b)=>(Date.parse(b.created_at)||0)-(Date.parse(a.created_at)||0)||String(a.key).localeCompare(String(b.key)));
    const remaining=s=>Number(s.amount)-(data.cases||[]).filter(c=>c.status==='approved'&&c.source_key===s.key).reduce((sum,c)=>sum+Number(c.amount),0);
    const sourceText=s=>date(s.created_at)+' · '+(sourceLabels[s.kind]||s.kind)+' · '+money(remaining(s))+' remaining'+(s.reference?' · '+s.reference:'');
    function pendingText(source,id){const count=data.cases.filter(c=>c.status==='pending'&&c.source_key===source&&c.id!==id).length;return count?count+' other pending request(s) use this transaction. Pending requests do not reserve funds. Check Pending review before creating another; approval will recheck eligibility.':'';}
    function review(result,kind,onConfirm){
     closeReview();const dialog=make('dialog');reviewDialog=dialog;dialog.className='iv-refunds iv-refund-review';dialog.setAttribute('aria-label',kind==='new'?'Review refund request':'Review refund approval');const feedback=make('p');feedback.setAttribute('role','status');dialog.append(make('h2',kind==='new'?'Confirm refund request':'Confirm approval'),feedback);
     for(const [label,value] of [['Member',memberName(result.member_id)],['Action',labels[result.action]],['Amount',money(result.amount)],['Refund request reference',result.reference],['Remaining eligible',money(result.remaining_eligible)],['Wallet',money(result.wallet_before)+' → '+money(result.wallet_after)],['Cash payout',money(result.cash_payout)],['Reason',result.reason]])dialog.append(make('p',label+': '+(value||'Unavailable')));
     const pendingWarning=pendingText(result.source_key,kind==='new'?draft?.id:result.id);if(pendingWarning){const warning=make('p',pendingWarning);warning.setAttribute('role','status');dialog.append(warning);}
     if(result.target_member_id)dialog.append(make('p','Corrected recipient: '+memberName(result.target_member_id)+' · '+money(result.target_wallet_before)+' → '+money(result.target_wallet_after)));
     dialog.append(make('p','No external payment is transferred by this app. Pass validity is unchanged; review membership separately.'));
     const technical=make('details');technical.append(make('summary','Technical details'),make('p','Original transaction: '+result.source_key));dialog.append(technical);
     const controls=make('div');action(controls,kind==='new'?'Edit':'Back',()=>closeReview(),feedback);onConfirm(dialog,controls,feedback,action);dialog.append(controls);
     dialog.oncancel=e=>{e.preventDefault();closeReview();};d.body.append(dialog);dialog.showModal();
    }
    function newCase(){
     content.textContent='';content.append(make('p','Choose a member or recent transaction. Review the destination and balances before confirming.'));
     if(!draft)selectDraft(memberId||'');
     const recent=make('details');recent.append(make('summary','Recent transactions · latest 10'));for(const s of sorted.slice(0,10))action(recent,memberName(s.member_id)+' · '+sourceText(s),()=>{save();selectDraft(s.member_id);draft.source_key=s.key;newCase();});content.append(recent);
     const form=make('form');content.append(form);const member=chooser(form,'Member',data.members,'Select member'),source=make('select'),type=make('select'),amount=make('input'),category=make('select'),reason=make('textarea'),targetWrap=make('div');
     member.select.value=draft.member_id;member.select.required=true;source.required=true;field(form,'Original transaction',source);for(const [key,label] of Object.entries(labels))option(type,key,key==='correct_credit'?'Correct incorrect wallet credit':label);field(form,'Action',type);type.value=draft.action;amount.type='number';amount.required=true;amount.step='.01';amount.min='.01';field(form,'Amount',amount);amount.value=draft.amount;
     for(const value of ['Incorrect account selected','Incorrect amount entered','Duplicate payment','Membership cancellation','Remaining balance before member removal','Other'])option(category,value,value);field(form,'Reason preset',category);category.value=draft.reason_category;reason.maxLength=1000;reason.value=draft.reason;const reasonWrap=field(form,'Specify reason',reason);
     form.append(targetWrap);const target=chooser(targetWrap,'Corrected recipient',data.members.filter(m=>m.status==='ACTIVE'&&m.id!==member.select.value),'No transfer to another member');target.select.value=draft.target_member_id;
     const warning=make('p');warning.setAttribute('role','status');form.append(warning);
     function save(){Object.assign(draft,{source_key:source.value,action:type.value,amount:amount.value,reason_category:category.value,reason:reason.value,target_member_id:target.select.value});}
     function syncSources(){source.textContent='';option(source,'','Select original transaction');for(const s of sorted)if(s.member_id===member.select.value)option(source,s.key,sourceText(s));source.value=draft.source_key;}
     function conditional(){const correction=type.value==='correct_credit',wrong=correction&&category.value==='Incorrect account selected';targetWrap.hidden=!correction;reasonWrap.hidden=category.value!=='Other';reason.required=category.value==='Other';target.select.required=wrong;amount.readOnly=wrong;warning.textContent=pendingText(source.value,draft.id);
      if(!correction){target.select.value='';draft.target_member_id='';}
      if(wrong){const s=sorted.find(s=>s.key===source.value);amount.value=s?String(remaining(s)):'';if(s&&(remaining(s)!==Number(s.amount)||Number(data.members.find(m=>m.id===member.select.value)?.wallet)<remaining(s)))warning.textContent+=' This credit was spent or previously adjusted. Owner resolution is required; a smaller transfer will not be made automatically.';}
     }
     member.select.onchange=()=>{save();selectDraft(member.select.value);newCase();};source.onchange=()=>{conditional();save();};type.onchange=()=>{conditional();save();};category.onchange=()=>{conditional();save();};form.addEventListener('input',save);syncSources();conditional();
     action(form,'Review request',async()=>{
      save();if(!form.reportValidity())return;const reviewedDraft=draft;if(draft.reason_category==='Other'&&draft.reason.trim().length<3)throw Error('Specify a reason of at least three characters.');
      if(!draft.id){let saved=JSON.parse(root.sessionStorage.getItem(draft.storageKey)||'null');draft.id=saved?.id||root.crypto.randomUUID();root.sessionStorage.setItem(draft.storageKey,JSON.stringify({id:draft.id}));}
      if(!draft.reference){const allocated=await rpc('reserve_reference',{p_id:draft.id});reviewedDraft.reference=allocated.reference;if(ticket!==serial||draft!==reviewedDraft)return;}
      const payload={member_id:draft.member_id,source_key:draft.source_key,action:draft.action,amount:draft.amount,reason_category:draft.reason_category,reason:draft.reason_category==='Other'?draft.reason.trim():draft.reason_category,target_member_id:draft.action==='correct_credit'?draft.target_member_id:'',reference:draft.reference};
      const result=await rpc('preview',{p_id:reviewedDraft.id,p_payload:payload});if(ticket!==serial||draft!==reviewedDraft)return;
      review(result,'new',(dialog,controls,feedback,add)=>add(controls,'Confirm refund request',async()=>{
       await rpc('request',{p_id:reviewedDraft.id,p_payload:payload,p_review:result.review_hash});root.sessionStorage.removeItem(reviewedDraft.storageKey);drafts.delete(reviewedDraft.key);drafts.delete(who+'|');if(draft===reviewedDraft)draft=null;closeReview();await open(undefined,'pending');
      },feedback));
     });form.onsubmit=e=>e.preventDefault();
    }
    function pending(){content.textContent='';for(const c of data.cases.filter(c=>c.status==='pending')){
     const article=make('article');article.append(make('h3',labels[c.action]+' · '+money(c.amount)),make('p',memberName(c.member_id)),make('p',c.reason),make('p','Reference: '+(c.reference||c.id)));content.append(article);
     if(data.can_approve)action(article,'Review approval',async()=>{const result=await rpc('preview',{p_id:c.id,p_payload:c.payload});if(ticket!==serial)return;review({...result,id:c.id},'approval',(dialog,controls,feedback,add)=>{
      const paid=make('input'),receipt=make('input'),generated=data.features?.generated_payout_reference===true;paid.type='checkbox';if(c.action==='cash'){field(dialog,'I confirm this cash was returned outside the wallet',paid);if(generated)dialog.append(make('p','A permanent cash payout reference will be generated on successful approval. It identifies the recorded payout; confirm actual cash handover separately.'));else field(dialog,'Cash payout receipt / reference',receipt);}
      add(controls,'Confirm approval',async()=>{const approved=await rpc('approve',{p_id:c.id,p_review:result.review_hash,p_payload:{cash_returned:paid.checked,...(!generated?{payout_reference:receipt.value.trim()}:{})}});closeReview();await open(undefined,'pending');if(approved?.payout_reference&&box)box.append(make('p','Approved cash payout reference: '+approved.payout_reference));},feedback);
     });});
     const reason=make('input'),memberReason=make('input');field(article,'Decision reason (internal)',reason);if(data.can_approve&&data.features?.member_rejection_notice===true){memberReason.maxLength=500;memberReason.placeholder='Optional. Otherwise the member is asked to contact the gym.';field(article,'Reason shown to member',memberReason);}action(article,data.can_approve?'Reject request':'Cancel my request',async()=>{await rpc(data.can_approve?'reject':'cancel',{p_id:c.id,p_payload:{reason:reason.value.trim(),...(data.features?.member_rejection_notice===true?{member_reason:memberReason.value.trim()}:{})}});await open(undefined,'pending');});
    }if(!content.children.length)content.append(make('p','No pending refunds.'));}
    function history(){content.textContent='';const search=make('input'),list=make('section');search.placeholder='Search member, reference or reason';search.setAttribute('aria-label','Search refund history');content.append(search,list);const render=()=>{list.textContent='';for(const c of data.cases.filter(c=>c.status!=='pending'&&(JSON.stringify(c)+' '+memberName(c.member_id)).toLowerCase().includes(search.value.toLowerCase()))){const row=make('article');row.append(make('h3',labels[c.action]+' · '+money(c.amount)+' · '+c.status),make('p','Member: '+memberName(c.member_id)),make('p','Reference: '+(c.reference||c.id)),make('p','Reason: '+c.reason),make('p','Requested: '+date(c.created_at)+' · '+(c.requested_actor?.name||c.requested_by)));if(c.approved_at)row.append(make('p','Approved: '+date(c.approved_at)+' · '+(c.approved_actor?.name||c.approved_by)),make('p','Wallet: '+money(c.wallet_before)+' → '+money(c.wallet_after)));if(c.target_member_id)row.append(make('p','Corrected recipient: '+memberName(c.target_member_id)+' · '+money(c.target_wallet_before)+' → '+money(c.target_wallet_after)));if(c.payout_reference)row.append(make('p','Cash payout receipt: '+c.payout_reference));if(c.decision_reason)row.append(make('p',c.decision_reason));const technical=make('details');technical.append(make('summary','Technical details'),make('p','Request: '+c.id+'\nSource: '+c.source_key));row.append(technical);list.append(row);}};search.oninput=render;render();}
    for(const [label,fn] of [...(data.can_request?[['New',newCase]]:[]),['Pending review',pending],['History',history]])action(nav,label,()=>{closeReview();fn();});if(initial==='pending'||!data.can_request)pending();else newCase();
   }catch(error){if(box===current){status.textContent=error.message;showError(error);}}
  }
  menu.onclick=()=>open();app.openRefunds=open;
  const originalDelete=app.deleteMember;if(typeof originalDelete==='function')app.deleteMember=async function(id){const member=(this.members||[]).find(m=>m.id===id);if(member&&Number(member.walletBalance??member.wallet_balance)>0){await open(id);return;}return originalDelete.apply(this,arguments);};
  client.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'||identity&&session?.user?.id&&identity.split('|')[0]!==session.user.id){epoch++;draft=null;drafts.clear();identity=null;close();menu.hidden=true;}});
 }
 root.IronVaultRefunds={install};
})(globalThis);
