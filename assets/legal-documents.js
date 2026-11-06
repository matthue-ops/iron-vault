/* Legal content is plain text. Published bodies and version IDs come from the server. */
(function(root){
 'use strict';
 const gymFields=[['effective_date','Effective date','date'],['notice_version','Privacy notice version'],['name','Gym legal / business name'],['address','Gym address'],['public_email','Gym support email','email'],['phone','Gym phone (optional)'],['privacy_name','Privacy contact name or role'],['privacy_email','Privacy contact email','email'],['notification_method','How members will be notified of changes'],['retention_profile','Member profile / account retention'],['retention_attendance','Attendance history retention'],['retention_financial','Financial record retention'],['retention_security','Security / support record retention'],['retention_backups','Backup / export deletion cycle'],['refund_policy','Cancellation / refund policy (optional)','textarea'],['age_policy','Minimum age / guardian policy (optional)','textarea']];
 const retentionSuggestions={retention_profile:'Suggested: review member profiles 12 months after membership ends or last activity, whichever is later. Keep only what remains necessary for legal obligations or unresolved matters. Deletion requires review; it is not automatic.',retention_attendance:'Suggested: use the same review period as member profiles unless attendance records remain necessary for a documented purpose.',retention_financial:'Suggested: retain financial records for the applicable Philippine accounting, tax and legal requirements. Confirm the required period with your accountant before publishing.',retention_security:'Suggested: review security and support records after 12 months; retain longer only where justified by an incident, dispute or legal requirement.',retention_backups:'Suggested: manage gym exports securely and delete copies when no longer needed. Confirm actual backup retention and deletion arrangements with the Service Provider; deletion is not automatic.'};
 const platformFields=[['name','Iron Vault legal operator name'],['address','Operator address'],['public_email','Support email','email'],['phone','Support phone (optional)'],['privacy_email','Privacy email','email'],['providers','Service providers and hosting locations','textarea'],['overseas_info','Overseas-processing details or contact route','textarea']];
 const fields=Array.from(new Map([...gymFields,...platformFields].map(f=>[f[0],f])).values());
 async function call(client,name,args){const {data,error}=await client.rpc(name,args);if(error)throw Error(error.message||'Legal documents unavailable.');return data;}
 function url(kind,token,bundle){
  const params=new URLSearchParams({key:token});if(bundle?.platform?.id)params.set('platform',bundle.platform.id);if(bundle?.gym?.id)params.set('gym',bundle.gym.id);
  return '/gym/'+kind+'.html?'+params;
 }
 function inline(parent,value){
  const tokens=String(value).split(/(\*\*[^*]+\*\*|\[[^\]]+\]\(https?:\/\/[^)\s]+\)|https?:\/\/[^\s<>]+)/g);
  for(const token of tokens){
   if(token.startsWith('**')&&token.endsWith('**')){const strong=root.document.createElement('strong');strong.textContent=token.slice(2,-2);parent.appendChild(strong);continue;}
   const link=/^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/.exec(token);
   if(link||/^https?:\/\//.test(token)){const a=root.document.createElement('a');a.href=link?link[2]:token;a.textContent=link?link[1]:token;a.target='_blank';a.rel='noopener';parent.appendChild(a);}else parent.appendChild(root.document.createTextNode(token));
  }
 }
 function documentBody(container,source){
  for(const block of String(source||'').split(/\n\s*\n/)){
   const lines=block.split('\n');let element;
   if(/^#{1,3} /.test(block)){element=root.document.createElement('h2');inline(element,block.replace(/^#{1,3} /,''));}
   else if(lines.every(line=>line.startsWith('- '))){element=root.document.createElement('ul');for(const line of lines){const li=root.document.createElement('li');inline(li,line.slice(2));element.appendChild(li);}}
   else if(lines.length>1&&lines.every(line=>line.startsWith('|'))){element=root.document.createElement('table');for(const line of lines){if(/^\|[-| ]+\|$/.test(line))continue;const row=root.document.createElement('tr');for(const cell of line.split('|').slice(1,-1)){const td=root.document.createElement('td');inline(td,cell.trim());row.appendChild(td);}element.appendChild(row);}}
   else{element=root.document.createElement('p');inline(element,block);}
   container.appendChild(element);
  }
 }
 function display(container,versions,kind){
  container.textContent='';
  for(const version of versions.filter(Boolean)){
   const article=root.document.createElement('article'),meta=root.document.createElement('p'),text=root.document.createElement('div');
   article.className='legal-document';meta.className='legal-version';meta.textContent=version.id?'Published '+new Date(version.published_at).toLocaleString('en-PH',{timeZone:'Asia/Manila'})+' (Manila)':'Document preview';
   text.className='legal-body';documentBody(text,version[kind==='privacy'?'privacy_text':'terms_text']);article.append(meta,text);container.appendChild(article);
  }
 }
 function editorMarkup(){return '<form method="dialog" class="legal-editor-heading"><h2 id="legal-editor-title">Document details</h2><button type="submit" aria-label="Close legal details">Close</button></form><p class="legal-help">Fill in the rows below. Your full Terms of Service and Privacy Notice will be generated automatically.</p><div id="legal-editor-fields"></div><div class="legal-actions"><button id="legal-editor-save" type="button">Save draft</button><button id="legal-editor-preview" type="button">Preview documents</button></div><p id="legal-editor-status" role="status"></p><section id="legal-editor-preview-panel" hidden><h3>Document preview</h3><div class="legal-actions"><button id="legal-preview-terms" type="button">Terms of Service</button><button id="legal-preview-privacy" type="button">Privacy Notice</button></div><div id="legal-editor-document"></div><label id="legal-editor-review-row" class="legal-review"><input id="legal-editor-reviewed" type="checkbox"> I have reviewed these documents and confirmed that all suggested policies match our actual practices.</label><button id="legal-editor-publish" type="button">Publish documents</button></section><details class="legal-advanced"><summary>Version history and acceptance records</summary><select id="legal-editor-history" aria-label="Published version"></select><button id="legal-editor-history-preview" type="button">View selected version</button><p id="legal-editor-current"></p><button id="legal-editor-receipts" type="button">Load acceptance records</button><pre id="legal-editor-receipt-list"></pre></details>';}
 function installEditor(app,client,kind){
  let dialog,state,generation=0,busy=false,view='terms',previewVersions=[],previewPayload=null,expectedActor=null;
  const node=id=>root.document.getElementById('legal-editor-'+id);
  function ensure(){
   if(dialog)return;dialog=root.document.createElement('dialog');dialog.id='legal-editor';dialog.className='legal-editor';dialog.setAttribute('aria-labelledby','legal-editor-title');dialog.innerHTML=editorMarkup();root.document.body.appendChild(dialog);
   dialog.addEventListener('close',()=>{if(dialog.open)return;generation++;state=null;expectedActor=null;previewPayload=null;previewVersions=[];node('document').textContent='';node('receipt-list').textContent='';node('history').textContent='';node('current').textContent='';for(const [key] of fields)root.document.getElementById('legal-field-'+key).value='';});
   const group=node('fields');for(const [key,label,type] of fields){const wrap=root.document.createElement('label'),caption=root.document.createElement('span'),input=root.document.createElement(type==='textarea'?'textarea':'input');caption.textContent=label;wrap.appendChild(caption);wrap.dataset.field=key;input.id='legal-field-'+key;input.maxLength=['name','public_email','phone','privacy_email'].includes(key)?254:8000;if(type&&type!=='textarea')input.type=type;wrap.appendChild(input);group.appendChild(wrap);input.addEventListener('input',()=>{node('reviewed').checked=false;previewPayload=null;node('status').textContent='Unsaved changes — preview before publishing.';});}
  }
  function groupRetention(tenant){
   let section=node('retention');if(!section){section=root.document.createElement('section');section.id='legal-editor-retention';section.className='legal-retention';const title=root.document.createElement('h3');title.textContent='Member record policies';const help=root.document.createElement('p');help.textContent='Suggested wording is a starting point, not a verified policy. Keep or edit it to match your gym. You may save an incomplete draft. Review every policy before publishing; these fields do not schedule automatic deletion.';const exceptions=root.document.createElement('details');exceptions.id='legal-retention-exceptions';const summary=root.document.createElement('summary');summary.textContent='Attendance and security exceptions';exceptions.appendChild(summary);section.append(title,help,exceptions);node('fields').appendChild(section);}
   section.hidden=!tenant;
   for(const key of Object.keys(retentionSuggestions)){const input=root.document.getElementById('legal-field-'+key),wrap=input.closest('label');(key==='retention_attendance'||key==='retention_security'?root.document.getElementById('legal-retention-exceptions'):section).appendChild(wrap);wrap.hidden=!tenant;if(tenant&&!input.value.trim())input.value=retentionSuggestions[key];}
   root.document.getElementById('legal-field-retention_profile').previousElementSibling.textContent='Default operational retention · suggested';
   root.document.getElementById('legal-field-retention_backups').previousElementSibling.textContent='Backup and export handling · separate policy';
  }
  function values(){return {...state.draft,...Object.fromEntries((state.tenant?gymFields:platformFields).map(([key])=>[key,root.document.getElementById('legal-field-'+key).value.trim()]))};}
  function history(data){
   state.versions=data.versions||[];const select=node('history');select.textContent='';for(const version of state.versions){const option=root.document.createElement('option');option.value=version.id;option.textContent=new Date(version.published_at).toLocaleString('en-PH',{timeZone:'Asia/Manila'})+' · '+version.id;select.appendChild(option);}node('current').textContent=data.current_version?'Current version: '+data.current_version:'No published version. Member self-registration needs both platform and gym documents.';
  }
  async function action(name){
   if(busy||!state)return;
   if(name==='publish'&&!node('reviewed').checked){node('status').textContent='Preview and confirm review before publishing.';return;}
   const submitted=values();if(name==='publish'&&previewPayload!==JSON.stringify(submitted)){node('status').textContent='Preview the current details before publishing.';return;}
   const current=state,stamp=generation;busy=true;dialog.querySelectorAll('.legal-actions button').forEach(b=>b.disabled=true);
   try{
    const data=await call(client,'iv_legal_manage',{p_action:name,p_tenant:current.tenant,p_data:submitted});
    if(stamp!==generation||state!==current)return;
    if(name==='preview'){node('preview-panel').hidden=false;node('review-row').hidden=false;node('publish').hidden=false;previewPayload=JSON.stringify(submitted);previewVersions=[data.preview];display(node('document'),previewVersions,view);node('preview-panel').scrollIntoView({block:'start',behavior:'smooth'});node('status').textContent='Full document preview. Blank optional policies are omitted.';}
    else{history(data);node('status').textContent=name==='save'?'Draft saved. Published documents are unchanged.':'New version published. Prior versions and acceptances are preserved.';if(name==='publish'){previewVersions=[state.versions[0]];display(node('document'),previewVersions,view);node('reviewed').checked=false;}}
   }catch(error){if(stamp===generation)node('status').textContent=error.message;}
   finally{busy=false;dialog.querySelectorAll('.legal-actions button').forEach(b=>b.disabled=false);}
  }
  app.openLegalSettings=async function(tenant=null){
   ensure();if(busy)return;const stamp=++generation;state=null;node('status').textContent='Loading legal details…';node('document').textContent='';node('receipt-list').textContent='';node('reviewed').checked=false;node('title').textContent=tenant?'Gym details for Terms & Privacy':'Iron Vault provider details';previewVersions=[];previewPayload=null;node('preview-panel').hidden=true;node('history').textContent='';node('current').textContent='';node('receipts').disabled=true;node('history-preview').disabled=true;for(const [key] of fields)root.document.getElementById('legal-field-'+key).value='';if(!dialog.open)dialog.showModal();
   try{
    if(client.auth?.getUser){const {data,error}=await client.auth.getUser();if(error||!data?.user)throw Error('Sign in required.');if(stamp!==generation)return;expectedActor=data.user.id;}
    const data=await call(client,'iv_legal_manage',{p_action:'get',p_tenant:tenant});if(stamp!==generation||!dialog.open)return;
    state={tenant,versions:[],draft:data.draft||{}};for(const wrap of node('fields').children){const definition=(tenant?gymFields:platformFields).find(f=>f[0]===wrap.dataset.field);wrap.hidden=!definition;if(definition)wrap.firstElementChild.textContent=definition[1];}const gym=kind==='admin'?app.matchedOwnerRecord:app.owners?.find(g=>g.id===tenant);
    for(const [key] of fields)root.document.getElementById('legal-field-'+key).value=data.draft?.[key]||(key==='name'?(gym?.gymName||''):key==='notice_version'?'1.0':'');
    groupRetention(tenant);
    history(data);node('history-preview').disabled=false;node('status').textContent='Drafts stay private until published.';
    for(const name of ['preview','save','publish'])node(name).onclick=()=>action(name);
    node('history-preview').onclick=()=>{node('preview-panel').hidden=false;node('review-row').hidden=true;node('publish').hidden=true;previewPayload=null;node('reviewed').checked=false;previewVersions=state.versions.filter(v=>v.id===node('history').value);display(node('document'),previewVersions,view);};
    node('receipts').disabled=!tenant;node('receipts').onclick=async()=>{const current=state,stamp=generation;try{const rows=await call(client,'iv_legal_receipts',{p_tenant:tenant});if(current===state&&stamp===generation)node('receipt-list').textContent=rows.length?rows.map(r=>r.member_id+' · '+r.accepted_at+'\nPlatform '+r.platform_version+'\nGym '+r.gym_version).join('\n\n'):'No recorded self-registration acceptances. Older and staff-created accounts have no inferred acceptance.';}catch(error){if(stamp===generation)node('status').textContent=error.message;}};
    for(const type of ['terms','privacy'])root.document.getElementById('legal-preview-'+type).onclick=()=>{view=type;display(node('document'),previewVersions,view);};
   }catch(error){if(stamp===generation)node('status').textContent=error.message;}
  };
  client.auth?.onAuthStateChange?.((event,session)=>{if(event==='SIGNED_OUT'||(expectedActor&&session?.user?.id&&session.user.id!==expectedActor)){generation++;state=null;if(dialog?.open)dialog.close();}});
  if(kind==='admin'){
   const original=app.applyUIRoleVisibility;app.applyUIRoleVisibility=function(role){const result=original.apply(this,arguments);root.document.getElementById('btn-gym-legal').classList.toggle('hidden',role!=='admin');return result;};
  }
 }
 function installSignup(app,client){
  let bundle=null,token=null,requestVersion=0;
  const checkbox=()=>root.document.getElementById('signup-legal-accepted');
  app.loadLegalDocuments=async function(){
   const stamp=++requestVersion;bundle=null;checkbox().checked=false;checkbox().disabled=true;root.document.getElementById('btn-submit-signup').disabled=true;const gym=this.matchedOwnerRecord;token=gym?.token;const requestedToken=token;
   for(const kind of ['terms','privacy'])root.document.getElementById('signup-'+kind+'-link').href=token?url(kind,token):'#';
   if(!token)return;
   const status=root.document.getElementById('signup-legal-status');status.textContent='Loading Terms and Privacy Notice…';
   try{const loaded=await call(client,'iv_legal_public',{p_token:requestedToken});if(stamp!==requestVersion||this.matchedOwnerRecord?.token!==requestedToken)return;bundle=loaded;
    if(!bundle?.platform||!bundle?.gym)throw Error('Member registration is unavailable until the gym and platform publish their Terms and Privacy Notice.');
    for(const kind of ['terms','privacy'])root.document.getElementById('signup-'+kind+'-link').href=url(kind,token,bundle);
    checkbox().disabled=false;root.document.getElementById('btn-submit-signup').disabled=false;status.textContent='';
   }catch(error){if(stamp===requestVersion){bundle=null;status.textContent=error.message;}}
  };
  app.requireLegalAcceptance=function(){if(!bundle?.platform||!bundle?.gym)throw Error('Published Terms and Privacy Notice are unavailable. Ask your gym for assistance.');if(!checkbox().checked)throw Error('Read the Terms and Privacy Notice and tick the agreement before registering.');return {accepted:true,platform_version:bundle.platform.id,gym_version:bundle.gym.id};};
  const init=app.init;app.init=async function(){const result=await init.apply(this,arguments);await this.loadLegalDocuments();return result;};
 }
 root.IronVaultLegal={fields,gymFields,platformFields,documentBody,call,url,display,installEditor,installSignup};
})(globalThis);
