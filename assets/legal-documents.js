/* Legal content is plain text. Published bodies and version IDs come from the server. */
(function(root){
 'use strict';
 const fields=[['name','Legal/business name'],['address','Business/contact address'],['public_email','Public contact email'],['phone','Public phone (optional)'],['privacy_email','Privacy contact email'],['retention','Retention and deletion schedule (including backups/exports)'],['providers','Service providers and processing locations'],['membership_policy','Membership rules (optional)'],['refund_policy','Cancellation/refund policy (optional)'],['age_policy','Minimum age / guardian policy (optional)'],['terms_extra','Additional terms (optional)'],['privacy_extra','Additional privacy information (optional)']];
 async function call(client,name,args){const {data,error}=await client.rpc(name,args);if(error)throw Error(error.message||'Legal documents unavailable.');return data;}
 function url(kind,token,bundle){
  const params=new URLSearchParams({key:token});if(bundle?.platform?.id)params.set('platform',bundle.platform.id);if(bundle?.gym?.id)params.set('gym',bundle.gym.id);
  return '/gym/'+kind+'.html?'+params;
 }
 function display(container,versions,kind){
  container.textContent='';
  for(const version of versions.filter(Boolean)){
   const article=root.document.createElement('article'),meta=root.document.createElement('p'),text=root.document.createElement('div');
   article.className='legal-document';meta.className='legal-version';meta.textContent=version.id?'Published '+new Date(version.published_at).toLocaleString('en-PH',{timeZone:'Asia/Manila'})+' (Manila) · Version '+version.id:'Private draft preview — not published';
   text.className='legal-body';text.textContent=version[kind==='privacy'?'privacy_text':'terms_text'];article.append(meta,text);container.appendChild(article);
  }
 }
 function editorMarkup(){return '<form method="dialog" class="legal-editor-heading"><h2 id="legal-editor-title">Legal details</h2><button type="submit" aria-label="Close legal details">Close</button></form><p class="legal-help">Only designated public contact details are published. Login emails are not copied. Review the wording before publishing; material changes require notifying members through your actual process.</p><div id="legal-editor-fields"></div><label class="legal-review"><input id="legal-editor-reviewed" type="checkbox"> I have reviewed these details and the preview for publication.</label><div class="legal-actions"><button id="legal-editor-preview" type="button">Preview</button><button id="legal-editor-save" type="button">Save draft</button><button id="legal-editor-publish" type="button">Publish new version</button></div><p id="legal-editor-status" role="status"></p><details><summary>Published versions</summary><select id="legal-editor-history" aria-label="Published version"></select><button id="legal-editor-history-preview" type="button">View selected version</button><p id="legal-editor-current"></p></details><details><summary>Member acceptance records (gym only)</summary><button id="legal-editor-receipts" type="button">Load acceptance records</button><pre id="legal-editor-receipt-list"></pre></details><div class="legal-actions"><button id="legal-preview-terms" type="button">Terms</button><button id="legal-preview-privacy" type="button">Privacy</button></div><div id="legal-editor-document"></div>';}
 function installEditor(app,client,kind){
  let dialog,state,generation=0,busy=false,view='terms',previewVersions=[],previewPayload=null,expectedActor=null;
  const node=id=>root.document.getElementById('legal-editor-'+id);
  function ensure(){
   if(dialog)return;dialog=root.document.createElement('dialog');dialog.id='legal-editor';dialog.className='legal-editor';dialog.setAttribute('aria-labelledby','legal-editor-title');dialog.innerHTML=editorMarkup();root.document.body.appendChild(dialog);
   dialog.addEventListener('close',()=>{generation++;state=null;expectedActor=null;previewPayload=null;previewVersions=[];node('document').textContent='';node('receipt-list').textContent='';node('history').textContent='';node('current').textContent='';for(const [key] of fields)root.document.getElementById('legal-field-'+key).value='';});
   const group=node('fields');for(const [key,label] of fields){const wrap=root.document.createElement('label'),input=root.document.createElement(['name','public_email','phone','privacy_email'].includes(key)?'input':'textarea');wrap.textContent=label;input.id='legal-field-'+key;input.maxLength=['name','public_email','phone','privacy_email'].includes(key)?254:8000;if(key.includes('email'))input.type='email';wrap.appendChild(input);group.appendChild(wrap);input.addEventListener('input',()=>{node('reviewed').checked=false;previewPayload=null;node('status').textContent='Unsaved changes — preview before publishing.';});}
  }
  function values(){return Object.fromEntries(fields.map(([key])=>[key,root.document.getElementById('legal-field-'+key).value.trim()]));}
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
    if(name==='preview'){previewPayload=JSON.stringify(submitted);previewVersions=[data.preview];display(node('document'),previewVersions,view);node('status').textContent='Private preview. Optional blank policies are omitted.';}
    else{history(data);node('status').textContent=name==='save'?'Draft saved. Published documents are unchanged.':'New version published. Prior versions and acceptances are preserved.';if(name==='publish'){previewVersions=[state.versions[0]];display(node('document'),previewVersions,view);node('reviewed').checked=false;}}
   }catch(error){if(stamp===generation)node('status').textContent=error.message;}
   finally{busy=false;dialog.querySelectorAll('.legal-actions button').forEach(b=>b.disabled=false);}
  }
  app.openLegalSettings=async function(tenant=null){
   ensure();if(busy)return;const stamp=++generation;state=null;node('status').textContent='Loading legal details…';node('document').textContent='';node('receipt-list').textContent='';node('reviewed').checked=false;node('title').textContent=tenant?'Gym Terms & Privacy Details':'Iron Vault Platform Legal Details';previewVersions=[];previewPayload=null;node('history').textContent='';node('current').textContent='';node('receipts').disabled=true;node('history-preview').disabled=true;for(const [key] of fields)root.document.getElementById('legal-field-'+key).value='';if(!dialog.open)dialog.showModal();
   try{
    if(client.auth?.getUser){const {data,error}=await client.auth.getUser();if(error||!data?.user)throw Error('Sign in required.');if(stamp!==generation)return;expectedActor=data.user.id;}
    const data=await call(client,'iv_legal_manage',{p_action:'get',p_tenant:tenant});if(stamp!==generation||!dialog.open)return;
    state={tenant,versions:[]};const gym=kind==='admin'?app.matchedOwnerRecord:app.owners?.find(g=>g.id===tenant);
    for(const [key] of fields)root.document.getElementById('legal-field-'+key).value=data.draft?.[key]||(key==='name'?(gym?.gymName||''):'');
    history(data);node('history-preview').disabled=false;node('status').textContent='Drafts stay private until published.';
    for(const name of ['preview','save','publish'])node(name).onclick=()=>action(name);
    node('history-preview').onclick=()=>{previewPayload=null;node('reviewed').checked=false;previewVersions=state.versions.filter(v=>v.id===node('history').value);display(node('document'),previewVersions,view);};
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
 root.IronVaultLegal={fields,call,url,display,installEditor,installSignup};
})(globalThis);
