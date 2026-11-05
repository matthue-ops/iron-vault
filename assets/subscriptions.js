/* Subscription authority and dates come from scoped server RPCs, never browser storage. */
(function(root){
  'use strict';
  const money=n=>'₱'+Number(n||0).toLocaleString('en-PH',{
    minimumFractionDigits:2,maximumFractionDigits:2
  }
  );
  const dateTime=value=>new Intl.DateTimeFormat('en-PH',{
    timeZone:'Asia/Manila',dateStyle:'medium',timeStyle:'short'
  }
  ).format(new Date(value))+' · Philippine time';
  const planName=p=>p==='portal'?'Dashboard + Member Portal':'Dashboard Only';
  const statusText=s=>({
    setup:'Setup — awaiting pilot activation',pilot:'Free pilot',paid:'Paid subscription',grace:'Overdue — dashboard-only grace',suspended:'Operational access suspended'
  }
  [s]||'Subscription status unavailable');
  const helpText={
    name:'Enter the actual individual or business responsible for these documents. Do not claim registration that is not completed.',address:'Enter a real business/service address. Resolve home-address privacy concerns before publishing; do not invent an address.',public_email:'Use an inbox monitored for support and confirm you control it.',privacy_email:'Use a monitored privacy and incident-reporting inbox.',effective_date:'The date this new publication becomes effective; previously accepted versions remain available.',providers:'List actual hosting, database and email delivery services, their processing locations, and other recipients. An email address is not a provider.',overseas_info:'Explain actual overseas processing and safeguards, or how individuals can obtain the details.',phone:'Public contact number; omit if optional. Do not enter passwords or secrets.',privacy_name:'Person or office responsible for privacy requests.',notification_method:'Describe the actual channel for notifying members of changes.',notice_version:'Use a clear version label; the app also records immutable publication IDs.',refund_policy:'Describe cancellation, incorrect payments and applicable remedies; do not remove non-waivable rights.',age_policy:'State any minimum age and lawful parent/guardian process. Optional policy must match gym practice.'
  }
  ;
  function element(tag,text,cls){
    const n=root.document.createElement(tag);
    if(text!=null)n.textContent=String(text);
    if(cls)n.className=cls;
    return n;
  }
  function button(label,fn,cls){
    const b=element('button',label,cls);
    b.type='button';
    b.addEventListener('click',async event=>{
      try{
        await fn(event);
      }
      catch(error){
        root.alert?.(error.message);
      }
    }
    );
    return b;
  }
  let tipSequence=0,helpRoot=null;
  function help(parent,text){
    if(parent.querySelector?.('.iv-field-help'))return;
    const wrap=element('span',null,'iv-field-help'),b=button('ⓘ',e=>{
      e.preventDefault();
      e.stopPropagation();
      tip.hidden=false;
    }
    ),tip=element('span',text);
    tip.id='iv-field-tip-'+(++tipSequence);
    tip.role='tooltip';
    tip.setAttribute('role','tooltip');
    tip.hidden=true;
    b.setAttribute('aria-label','Field guidance');
    b.setAttribute('aria-describedby',tip.id);
    wrap.append(b,tip);
    parent.appendChild(wrap);
    wrap.addEventListener('mouseenter',()=>{
      tip.hidden=false;
    }
    );
    wrap.addEventListener('mouseleave',()=>{
      if(root.document.activeElement!==b)tip.hidden=true;
    }
    );
    b.addEventListener('focus',()=>{
      tip.hidden=false;
    }
    );
    b.addEventListener('blur',()=>{
      tip.hidden=true;
    }
    );
    wrap.addEventListener('keydown',e=>{
      if(e.key==='Escape'){
        tip.hidden=true;
        b.focus();
      }
    }
    );
    if(helpRoot!==root.document){
      helpRoot=root.document;
      root.document.addEventListener('click',e=>{
        for(const h of root.document.querySelectorAll('.iv-field-help'))if(!h.contains(e.target))h.querySelector('[role=tooltip]').hidden=true;
      }
      );
    }
  }
  function decorateLegal(){
    const editor=root.document.getElementById('legal-editor');
    if(!editor)return;
    for(const row of editor.querySelectorAll('[data-field]')){
      const key=row.dataset.field;
      help(row.firstElementChild,helpText[key]||(key.startsWith('retention_')?'State the actual retention period, reasons for keeping records, and deletion/backup handling. Do not promise a cycle the service cannot perform.':'Explain the actual practice and give enough detail for the published document. Required fields must be complete before publication.'));
    }
  }
  function install(app,client,kind){
    const d=root.document;
    if(!d?.addEventListener||!d.querySelectorAll)return;
    const shownWelcome=new Set();
    let viewSerial=0,epoch=0,busy=false,timer=null,access=null,record=null,selected=null,dialog=null,actor=null,documentsState=null,lastQuote=null;
    const main=d.querySelector('main')||d.getElementById('super-dashboard')||d.body;
    const panel=element('section',null,'iv-sub-panel');
    panel.id='subscription-main-panel';
    panel.hidden=true;
    main.prepend(panel);
    let bell;
    if(kind==='admin'){
      bell=button('🔔 Billing',()=>openBilling(app.currentTenantId));
      bell.id='owner-billing-bell';
      bell.hidden=true;
      bell.className='iv-sub-select';
      d.querySelector('.admin-header-actions')?.prepend(bell);
    }
    function scope(){
      return app.authenticatedRole?.user_id||actor;
    }
    async function call(name,args){
      const stamp=epoch,who=scope(),auth=await client.auth.getUser();
      if(!auth.data?.user||auth.error||(who&&auth.data.user.id!==who))throw Error('Account changed. Sign in again.');
      actor=auth.data.user.id;
      const {
        data,error
      }
      =await client.rpc(name,args);
      if(stamp!==epoch)throw Error('Account changed.');
      if(error)throw Error(error.message||'Subscription request failed.');
      if(data==null)throw Error('Subscription service unavailable. Ask the owner to complete deployment.');
      return data;
    }
    async function run(fn){
      if(busy)return;
      busy=true;
      try{
        await fn();
      }
      catch(error){
        showError(error.message);
      }
      finally{
        busy=false;
      }
    }
    function showError(text){
      const n=dialog?.querySelector('.iv-sub-error')||panel.querySelector('.iv-sub-error');
      if(n)n.textContent=text;
      else root.alert?.(text);
    }
    function modal(title){
      if(dialog?.open)dialog.close();
      dialog=element('dialog',null,'iv-sub-dialog');
      const head=element('header'),h=element('h2',title);
      head.append(h,button('Close',event=>event.currentTarget.closest('dialog').close()));
      dialog.append(head,element('p','','iv-sub-error'));
      const current=dialog;
      d.body.appendChild(current);
      current.addEventListener('close',()=>{
        if(dialog===current){
          lastQuote=null;
          dialog=null;
        }
        current.remove();
      }
      );
      current.showModal();
      return current;
    }
    function check(label){
      const wrap=element('label',null,'iv-sub-check'),input=element('input');
      input.type='checkbox';
      wrap.append(input,element('span',label));
      return{
        wrap,input
      }
      ;
    }
    function summary(target,data){
      const state=data.state||data;
      target.appendChild(element('p',statusText(state.status),'iv-sub-banner'));
      target.appendChild(element('p',[state.plan?planName(state.plan):'Complete setup before pilot activation',state.start_date?'Counted period: '+state.start_date+' through '+state.end_date+' · Philippine time':'',state.status==='pilot'?state.days_remaining+' counted days remaining':'',state.status==='grace'?'Grace ends '+state.grace_end:'',state.retention_review_date?'Retention review date: '+state.retention_review_date:''].filter(Boolean).join('\n'),'iv-sub-summary'));
    }
    function gate(value){
      access=value;
      d.body.dataset.subscriptionOperations=String(!!value.operations);
      d.body.dataset.subscriptionPortal=String(!!value.portal);
      panel.hidden=!!value.operations;
      panel.textContent='';
      summary(panel,value);
      if(value.is_owner){
        panel.appendChild(element('p','Complete and publish gym documents, accept the service documents, then await Super Admin activation.'));
        const actions=element('div',null,'iv-sub-actions');
        actions.append(button('Subscription & Billing',()=>openBilling(app.currentTenantId),'primary'),button('Gym Terms & Privacy',()=>app.openLegalSettings(app.currentTenantId)));
        if(value.read)actions.append(button('Read-only reports / exports',()=>app.openReportsPage()));
        panel.appendChild(actions);
      }
      else panel.appendChild(element('p','Please contact your gym owner about subscription access.'));
      panel.appendChild(element('p','','iv-sub-error'));
      if(bell)bell.hidden=!value.is_owner;
    }
    async function refresh(){
      if(kind!=='admin'||!app.currentTenantId||!app.authenticatedRole)return;
      try{
        const value=await call('iv_subscription_access',{
          p_tenant:app.currentTenantId
        }
        );
        gate(value);
        if(value.is_owner){
          const data=await call('iv_subscription_portal',{
            p_tenant:app.currentTenantId,p_action:'get'
          }
          );
          record=data;
          const count=data.notifications.filter(n=>!n.read_at).length;
          bell.textContent='🔔 Billing'+(count?' ('+count+')':'');
          bell.setAttribute('aria-label','Billing notifications'+(count?', '+count+' unread':''));
          const welcome=data.notifications.find(n=>!n.read_at&&n.notice_key.endsWith(':welcome')&&!shownWelcome.has(n.notice_key));
          if(welcome&&!dialog?.open){
            shownWelcome.add(welcome.notice_key);
            const window=modal(welcome.title);
            window.append(element('p',welcome.message,'iv-sub-summary'),button('Continue to dashboard',()=>run(async()=>{
              await call('iv_subscription_portal',{
                p_tenant:data.tenant_id,p_action:'read_notice',p_data:{
                  key:welcome.notice_key
                }
              }
              );
              window.close();
              await refresh();
            }
            ),'primary'));
          }
          if(value.operations){
            panel.hidden=false;
            panel.textContent='';
            summary(panel,data);
            panel.appendChild(button('Subscription & Billing',()=>openBilling(app.currentTenantId)));
          }
        }
      }
      catch(e){
        gate({
          status:'unavailable',operations:false,is_owner:app.authenticatedRole?.role==='owner'
        }
        );
        showError(e.message);
      }
    }
    function renderDocs(target,data){
      const section=element('section');
      section.appendChild(element('h3','Service agreements and acceptance history','iv-sub-heading'));
      const select=element('select',null,'iv-sub-select');
      for(const v of data.documents){
        const option=element('option',v.effective_date+' · '+v.id);
        option.value=v.id;
        select.appendChild(option);
      }
      if(data.current_version)select.value=data.current_version;
      section.appendChild(select);
      const tabs=element('div',null,'iv-sub-actions'),body=element('article','','iv-sub-document');
      let type='terms_text';
      const render=()=>{
        const v=data.documents.find(v=>v.id===select.value);
        body.textContent=v?.[type]||'Service documents have not been published.';
      }
      ;
      for(const [key,label] of [['terms_text','Service Agreement'],['privacy_text','Privacy Notice'],['dpa_text','Data Processing Agreement']])tabs.appendChild(button(label,()=>{
        type=key;
        render();
      }
      ));
      select.addEventListener('change',render);
      section.append(tabs,body);
      render();
      if(data.is_owner){
        const agree=check('I am authorised to represent this gym. I agree to the selected Service Agreement and Data Processing Agreement and acknowledge its Privacy Notice.');
        const acceptButton=button('Accept selected version',()=>run(async()=>{
          if(!agree.input.checked)throw Error('Tick the agreement after reviewing all three documents.');
          await call('iv_subscription_portal',{
            p_tenant:selected,p_action:'accept',p_data:{
              version_id:select.value,accepted:true
            }
          }
          );
          await openBilling(selected);
        }
        ),'primary');
        acceptButton.disabled=!data.gym_documents_ready||!data.documents.length;
        section.append(agree.wrap,acceptButton);
        if(!data.gym_documents_ready)section.appendChild(element('p','Publish your gym legal details first so the gym identity can be recorded with acceptance.'));
      }
      section.appendChild(element('p',data.acceptances.map(a=>'Accepted '+a.version_id+' · '+new Intl.DateTimeFormat('en-PH',{
        timeZone:'Asia/Manila',dateStyle:'medium',timeStyle:'short'
      }
      ).format(new Date(a.accepted_at))+' · Gym '+(a.gym_snapshot?.name||data.tenant_id)+' · Owner '+(a.owner_snapshot?.name||a.owner_id)).join('\n')||'No acceptance recorded.','iv-sub-summary'));
      target.appendChild(section);
    }
    function planControls(target,data){
      if(!data.is_owner)return;
      const section=element('section');
      section.appendChild(element('h3','Choose a paid plan / request a change','iv-sub-heading'));
      section.appendChild(element('p','Payment is manual. No automatic charge. Review the exact dates and amount before confirming. Contact the billing details in the published agreement for payment instructions.'));
      const current=data.documents.find(v=>v.id===data.current_version);
      section.appendChild(element('p',current?'Billing contact: '+current.data.billing_contact+' — '+(current.data.billing_instructions||'Contact the provider for payment instructions.'):'Payment instructions are available after service documents are published.'));
      const actions=element('select',null,'iv-sub-select'),plans=element('select',null,'iv-sub-select');
      for(const [value,label] of [['payment','New period / renewal'],['upgrade','Upgrade current period'],['downgrade','Schedule downgrade']]){
        const o=element('option',label);
        o.value=value;
        actions.appendChild(o);
      }
      for(const [value,label] of [['dashboard','Dashboard Only'],['portal','Dashboard + Member Portal']]){
        const o=element('option',label);
        o.value=value;
        plans.appendChild(o);
      }
      if(data.next_plan)plans.value=data.next_plan;
      const quoteView=element('p','','iv-sub-summary'),confirm=check('I confirm this exact plan, amount, period, and the applicable renewal/cancellation policies.');
      const approve=button('Confirm quoted plan',()=>run(async()=>{
        if(!lastQuote||!confirm.input.checked)throw Error('Review a quote and tick confirmation first.');
        const key='ironvault_subscription_plan:'+scope()+':'+selected+':'+JSON.stringify(lastQuote);
        let request_id=root.sessionStorage.getItem(key);
        if(!request_id){
          request_id=root.crypto.randomUUID();
          root.sessionStorage.setItem(key,request_id);
        }
        await call('iv_subscription_portal',{
          p_tenant:selected,p_action:'confirm_plan',p_data:{
            request_id,confirmed:true,quote:lastQuote
          }
        }
        );
        await openBilling(selected);
        root.sessionStorage.removeItem(key);
      }
      ),'primary');
      approve.disabled=true;
      const invalidate=()=>{
        lastQuote=null;
        confirm.input.checked=false;
        approve.disabled=true;
        quoteView.textContent='Selection changed. Get a new quote.';
      }
      ;
      actions.addEventListener('change',invalidate);
      plans.addEventListener('change',invalidate);
      section.append(actions,plans,button('Get exact quote',()=>run(async()=>{
        lastQuote=await call('iv_subscription_portal',{
          p_tenant:selected,p_action:'quote',p_data:{
            kind:actions.value,plan:plans.value
          }
        }
        );
        confirm.input.checked=false;
        approve.disabled=false;
        quoteView.textContent=planName(lastQuote.plan)+' · '+money(lastQuote.amount)+'\nCounted dates: '+lastQuote.start_date+' – '+lastQuote.end_date+'\nAccess begins: '+lastQuote.access_from+'\nAgreement version: '+lastQuote.version_id+'\nAccept this version above before confirming.';
      }
      )),quoteView,confirm.wrap,approve);
      target.appendChild(section);
    }
    async function adminAction(action,payload){
      const key='ironvault_subscription_request:'+scope()+':'+selected+':'+action+':'+JSON.stringify(payload);
      if(!payload.request_id){
        let id=root.sessionStorage.getItem(key);
        if(!id){
          id=root.crypto.randomUUID();
          root.sessionStorage.setItem(key,id);
        }
        payload={
          ...payload,request_id:id
        }
        ;
      }
      const result=await call('iv_subscription_portal',{
        p_tenant:selected,p_action:action,p_data:payload
      }
      );
      await openBilling(selected);
      root.sessionStorage.removeItem(key);
      return result;
    }
    function masterControls(target,data){
      if(kind!=='master')return;
      const section=element('section');
      section.appendChild(element('h3','Super Admin approvals','iv-sub-heading'));
      const activation=check('I verified this gym business is eligible for its first pilot and reviewed the setup requirements.');
      const activate=button('Activate free pilot',()=>run(async()=>{
        if(!activation.input.checked)throw Error('Review pilot eligibility first.');
        if(!root.confirm('Activate full pilot access now? Counted days start tomorrow.'))return;
        await adminAction('activate_pilot',{
          reviewed_business:true
        }
        );
      }
      ),'primary');
      activate.disabled=data.pilot_used||!data.accepted||!data.gym_documents_ready||!data.platform_documents_ready;
      section.append(activation.wrap,activate);
      for(const r of data.requests){
        const card=element('article',null,'iv-sub-notice');
        card.appendChild(element('p',r.kind+' · '+planName(r.quote.plan)+' · '+money(r.quote.amount)+' · '+r.quote.start_date+' through '+r.quote.end_date+'\nOwner confirmation: '+dateTime(r.confirmed_at)+'\n'+(r.approved_at?'Approved '+dateTime(r.approved_at):'Awaiting approval'),'iv-sub-summary'));
        if(!r.approved_at){
          const label=element('label',null,'iv-sub-field'),input=element('input');
          label.append(element('span','Payment reference / receipt'),input);
          card.append(label,button(r.kind==='downgrade'?'Approve scheduled downgrade':'Approve verified payment',()=>run(async()=>{
            if(!root.confirm('Approve this exact request? Confirm that the payment is verified before proceeding.'))return;
            await adminAction(r.kind==='downgrade'?'approve_downgrade':'approve_payment',{
              request_id:r.id,reference:input.value.trim()
            }
            );
          }
          ),'primary'));
        }
        section.appendChild(card);
      }
      const days=element('input'),reason=element('textarea');
      days.type='number';
      days.min='1';
      days.max='365';
      days.placeholder='Extension days';
      reason.placeholder='Required reason for extension';
      section.append(element('h3','Documented extension','iv-sub-heading'),days,reason,button('Approve extension',()=>run(async()=>{
        if(!root.confirm('Extend the current final period and record this reason?'))return;
        await adminAction('extend',{
          days:Number(days.value),reason:reason.value.trim()
        }
        );
      }
      )));
      target.appendChild(section);
    }
    function history(target,data){
      if(data.is_owner)for(const r of data.requests)target.appendChild(element('p',(r.approved_at?'Approved request':'Awaiting Super Admin approval')+' · '+r.kind+' · '+planName(r.quote.plan)+' · '+money(r.quote.amount)+' · '+r.quote.start_date+' through '+r.quote.end_date,'iv-sub-notice'));
      target.appendChild(element('h3','Periods and approvals','iv-sub-heading'));
      for(const p of data.periods)target.appendChild(element('p',p.kind+' · '+planName(p.plan)+' · '+p.start_date+' – '+p.end_date+' · '+money(p.amount)+'\nReference: '+(p.reference||'Not applicable')+' · Approved '+dateTime(p.approved_at),'iv-sub-notice'));
      for(const e of data.events)target.appendChild(element('p',e.action+' · '+dateTime(e.created_at)+' · '+(e.data.reason||e.data.reference||'Recorded approval')+' · Actor '+e.actor_id,'iv-sub-summary'));
    }
    async function openBilling(tenant){
      const serial=++viewSerial;
      const data=await call('iv_subscription_portal',{
        p_tenant:tenant,p_action:'get'
      }
      );
      if(serial!==viewSerial)return;
      selected=tenant;
      record=data;
      const target=modal('Subscription & Billing');
      summary(target,data);
      if(data.next_plan)target.appendChild(element('p','Selected next plan: '+planName(data.next_plan)+' — renewal payment approval is required.'));
      target.appendChild(element('p','Setup: '+(data.gym_documents_ready?'gym documents published':'publish gym documents')+' · '+(data.platform_documents_ready?'platform member documents published':'platform member documents missing')+' · '+(data.accepted?'owner service acceptance recorded':'owner must accept current service documents'),'iv-sub-summary'));
      if(kind==='admin')target.appendChild(button('Open gym Terms & Privacy settings',()=>{
        dialog.close();
        app.openLegalSettings(tenant);
      }
      ));
      if(data.is_owner){
        target.appendChild(element('h3','Owner notifications','iv-sub-heading'));
        for(const n of data.notifications){
          const card=element('article',null,'iv-sub-notice');
          card.dataset.unread=String(!n.read_at);
          card.append(element('h4',n.title),element('p',n.message,'iv-sub-summary'),element('small',new Intl.DateTimeFormat('en-PH',{
            timeZone:'Asia/Manila',dateStyle:'medium',timeStyle:'short'
          }
          ).format(new Date(n.available_at))));
          if(!n.read_at)card.appendChild(button('Mark read',()=>run(async()=>{
            await call('iv_subscription_portal',{
              p_tenant:tenant,p_action:'read_notice',p_data:{
                key:n.notice_key
              }
            }
            );
            card.dataset.unread='false';
            await refresh();
          }
          )));
          target.appendChild(card);
        }
      }
      renderDocs(target,data);
      planControls(target,data);
      masterControls(target,data);
      history(target,data);
      if(data.is_owner)target.appendChild(button('Download subscription and agreement records',()=>{
        const url=root.URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{
          type:'application/json'
        }
        ));
        const a=element('a');
        a.href=url;
        a.download='IronVault-subscription-'+data.tenant_id+'.json';
        a.click();
        root.setTimeout(()=>root.URL.revokeObjectURL(url),1000);
      }
      ));
    }
    async function directory(){
      const rows=await call('iv_subscription_directory',{
      }
      );
      const target=modal('Gym subscriptions');
      target.appendChild(element('p','Existing gyms remain setup-only until owner requirements and Super Admin activation are complete.'));
      const table=element('table',null,'iv-sub-directory'),head=element('tr');
      for(const title of ['Gym','Status','Requirements','Action'])head.appendChild(element('th',title));
      const thead=element('thead');
      thead.appendChild(head);
      table.appendChild(thead);
      const tbody=element('tbody');
      for(const row of rows){
        const tr=element('tr');
        tr.append(element('td',row.gym_name+'\n'+row.owner_name),element('td',statusText(row.state.status)),element('td',(row.accepted?'Owner agreed':'Owner agreement missing')+' · '+(row.gym_documents_ready?'Gym docs published':'Gym docs missing')));
        const action=element('td');
        action.appendChild(button('Review / manage',()=>run(()=>openBilling(row.tenant_id))));
        tr.appendChild(action);
        tbody.appendChild(tr);
      }
      table.appendChild(tbody);
      target.appendChild(table);
    }
    async function serviceEditor(){
      const state=await call('iv_service_documents',{
        p_action:'get'
      }
      );
      documentsState=state;
      const target=modal('Iron Vault Service Agreement Settings'),form=element('div',null,'iv-sub-grid'),values=new Map();
      const advanced=element('details'),advancedHead=element('summary','Advanced document templates');
      advanced.appendChild(advancedHead);
      target.append(form,advanced);
      let previewed=null;
      const reviewed=check('I reviewed all three documents, provider identity, actual infrastructure and policies; the publication matches current practices.');
      const preview=element('article','','iv-sub-document'),publishDate=element('input');
      publishDate.type='date';
      publishDate.value=new Intl.DateTimeFormat('en-CA',{
        timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'
      }
      ).format(new Date());
      const dateWrap=element('label',null,'iv-sub-field');
      dateWrap.append(element('span','Effective date'),publishDate);
      help(dateWrap.firstChild,'Initial publication may take effect today. Later price changes require at least the notice period. Already approved periods keep their recorded policies.');
      for(const field of root.IronVaultServicePolicy.fields){
        const wrap=element('label',null,'iv-sub-field'),label=element('span',field.label+(field.required?' *':'')),input=element(field.type==='textarea'?'textarea':'input');
        if(field.type!=='textarea')input.type=field.type;
        if(field.type==='number')input.step=['dashboard_price','portal_price'].includes(field.key)?'.01':'1';
        input.value=state.draft[field.key]??field.default;
        input.dataset.policyField=field.key;
        help(label,field.help+(field.required?' Required before publication.':' Optional.'));
        wrap.append(label,input);
        (field.key.startsWith('_')?advanced:form).appendChild(wrap);
        values.set(field.key,input);
        input.addEventListener('input',()=>{
          previewed=null;
          reviewed.input.checked=false;
        }
        );
      }
      const collect=()=>Object.fromEntries([...values].map(([k,input])=>[k,input.type==='number'?Number(input.value):input.value.trim()]));
      const viewButtons=element('div',null,'iv-sub-actions');
      let previewData=null;
      for(const [key,label] of [['terms_text','Service Agreement'],['privacy_text','Privacy Notice'],['dpa_text','Data Processing Agreement']])viewButtons.appendChild(button(label,()=>{
        preview.textContent=previewData?.[key]||'Preview the draft first.';
      }
      ));
      const actions=element('div',null,'iv-sub-actions');
      actions.append(button('Save draft',()=>run(async()=>{
        await call('iv_service_documents',{
          p_action:'save',p_data:collect()
        }
        );
        preview.textContent='Draft saved. Published documents have not changed.';
      }
      )),button('Preview all documents',()=>run(async()=>{
        const data=collect(),result=await call('iv_service_documents',{
          p_action:'preview',p_data:data
        }
        );
        previewed=JSON.stringify(data);
        previewData=result.preview;
        preview.textContent=previewData.terms_text;
      }
      )),button('Publish new version',()=>run(async()=>{
        const data=collect();
        if(!reviewed.input.checked||previewed!==JSON.stringify(data))throw Error('Preview this exact draft and confirm review before publication.');
        if(!root.confirm('Publish these service documents with effective date '+publishDate.value+'? Existing acceptances will be preserved.'))return;
        await call('iv_service_documents',{
          p_action:'publish',p_data:data,p_effective:publishDate.value
        }
        );
        await serviceEditor();
      }
      ),'primary'));
      target.append(actions,dateWrap,reviewed.wrap,viewButtons,preview,element('h3','Published version history','iv-sub-heading'));
      for(const v of state.versions)target.appendChild(button(v.effective_date+' · '+v.id,()=>{
        previewData=v;
        preview.textContent=v.terms_text;
      }
      ));
    }
    if(kind==='master'){
      const old=app.showDashboard;
       // Buttons are visible only inside the authenticated dashboard.
      const group=element('div',null,'iv-sub-actions');
      group.append(button('Gym subscriptions',()=>run(directory)),button('Service Agreement Settings',()=>run(serviceEditor)));
      d.getElementById('super-dashboard')?.prepend(group);
    }
    else{
      const original=app.init;
      app.init=async function(...args){
        const result=await original.apply(this,args);
        await refresh();
        if(timer)root.clearTimeout(timer);
        const tick=async()=>{
          if(!d.hidden)await refresh();
          timer=root.setTimeout(tick,60000);
        }
        ;
        timer=root.setTimeout(tick,60000);
        return result;
      }
      ;
      const ops=['openAddMemberModal','handleAdminAddMember','openManualCheckInModal','admitMemberDirectly','finalizeDeskCheckIn','confirmPlanSelection','addModalCredits','openScannerModal','startScanner','resumeScanner','processScannedCode','openStaffSignupModal','handleStaffSignup','handleSaveMemberDetails','quickApproveMember','approvePendingMember','handleSavePricing','openAnnouncements'];
      for(const name of ops){
        const original=app[name];
        if(typeof original!=='function')continue;
        app[name]=async function(...args){
          try{
            const value=await call('iv_subscription_access',{
              p_tenant:this.currentTenantId
            }
            );
            gate(value);
            if(['openScannerModal','startScanner','resumeScanner','processScannedCode'].includes(name)&&!value.portal&&!value.super)throw Error('Member QR scanning is not included in the current subscription. Use manual desk check-in.');
            if(!value.operations&&!value.super)throw Error('Gym operations are unavailable under the current subscription.');
            return await original.apply(this,args);
          }
          catch(e){
            this.notifyAdmin?this.notifyAdmin(e.message,false):root.alert(e.message);
          }
        }
        ;
      }
    }
    if(typeof app.openLegalSettings==='function'){
      const original=app.openLegalSettings;
      app.openLegalSettings=async function(...args){
        const result=await original.apply(this,args);
        decorateLegal();
        return result;
      }
      ;
    }
    client.auth.onAuthStateChange((event,session)=>{
      if(event==='SIGNED_OUT'||(actor&&session?.user?.id&&session.user.id!==actor)){
        epoch++;
        shownWelcome.clear();
        record=access=null;
        actor=null;
        if(timer)root.clearTimeout(timer);
        if(dialog?.open)dialog.close();
        panel.textContent='';
        panel.hidden=true;
        if(bell)bell.hidden=true;
        delete d.body.dataset.subscriptionOperations;
        delete d.body.dataset.subscriptionPortal;
      }
      else if(session?.user?.id)actor=session.user.id;
    }
    );
    app.openSubscriptionBilling=tenant=>run(()=>openBilling(tenant||app.currentTenantId));
  }
  root.IronVaultSubscriptions={
    install,help,money,planName,statusText
  }
  ;
  if(typeof module==='object'&&module.exports)module.exports=root.IronVaultSubscriptions;
}
)(globalThis);
