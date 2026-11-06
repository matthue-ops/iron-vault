/* Subscription authority and dates come from scoped server RPCs, never browser storage. */
(function(root){
  'use strict';
  const ownerAcknowledgment='I confirm that I am authorized to represent this Gym, have reviewed the documents listed above, and agree to the applicable Terms of Use, Data Processing Agreement, and Free Pilot Conditions. I acknowledge receipt of the Privacy Notice.';
  const pilotHeading=/^(?:#{1,6}\s*)?(?:\d+[.)]\s*)?FREE\s+PILOT(?:\s+CONDITIONS)?\b/i;
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
  function documentPreview(target,text){
    target.textContent='';target.classList.add('iv-sub-readable');
    const paragraphs=String(text||'Preview the draft first.').split(/\n\s*\n/);
    for(const part of paragraphs){const value=part.trim();if(!value)continue;
      const title=/^#{1,3}\s+/.test(value),heading=/^\d+\. [A-Z][A-Z ,/&–—()-]+$/.test(value);
      target.appendChild(element(title?'h3':heading?'h4':'p',value.replace(/^#{1,3}\s+/,'')));
    }
  }
  function tabs(target,items,initial){
    const nav=element('div',null,'iv-sub-tabs');nav.setAttribute('role','tablist');const sections=new Map(),buttons=new Map();
    function show(key){for(const [id,section] of sections){section.hidden=id!==key;buttons.get(id).setAttribute('aria-selected',String(id===key));buttons.get(id).tabIndex=id===key?0:-1;}}
    target.appendChild(nav);
    items.forEach(([key,label],index)=>{const section=element('section',null,'iv-sub-tab-panel'),tab=button(label,()=>show(key));tab.setAttribute('role','tab');tab.id='subscription-tab-'+key;section.id='subscription-section-'+key;tab.setAttribute('aria-controls',section.id);section.setAttribute('role','tabpanel');section.setAttribute('aria-labelledby',tab.id);tab.addEventListener('keydown',event=>{if(['ArrowRight','ArrowLeft','Home','End'].includes(event.key)){event.preventDefault();const at=event.key==='Home'?0:event.key==='End'?items.length-1:(index+(event.key==='ArrowRight'?1:-1)+items.length)%items.length;show(items[at][0]);buttons.get(items[at][0]).focus();}});sections.set(key,section);buttons.set(key,tab);nav.appendChild(tab);target.appendChild(section);});
    show(sections.has(initial)?initial:items[0][0]);return{sections,show};
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
  function pilotRemaining(state){
    // Display only: the server supplies the remaining access days; approval day is uncounted.
    const start=Date.parse(state.start_date+'T00:00:00Z'),end=Date.parse(state.end_date+'T00:00:00Z');
    const accessDays=Number(state.days_remaining);
    if(![start,end,accessDays].every(Number.isFinite)||end<start)return '';
    const total=Math.round((end-start)/86400000)+1,remaining=Math.min(total,Math.max(0,accessDays));
    return (accessDays>total?'Approval-day access is available now. Counted days start '+state.start_date+'. ':'')+remaining+' counted '+(remaining===1?'day':'days')+' remaining';
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
      bell=button('',()=>run(openOwnerNotifications));
      const icon=element('i');icon.className='fa-solid fa-bell';icon.setAttribute('aria-hidden','true');
      const label=element('span','Notifications','owner-notification-label'),badge=element('span','','owner-notification-count');badge.id='owner-notification-count';badge.hidden=true;
      bell.append(icon,label,badge);bell.title='Notifications';
      bell.id='owner-billing-bell';
      bell.hidden=true;
      bell.className='iv-sub-select';
      d.querySelector('.admin-header-actions')?.prepend(bell);
      const plan=button('My Plan & Subscription',()=>openBilling(app.currentTenantId));plan.id='owner-subscription-menu';plan.hidden=true;
      d.querySelector('.admin-menu-panel')?.prepend(plan);
    }
    function scope(){
      return app.authenticatedRole?.user_id||actor;
    }
    async function call(name,args){
      const stamp=epoch,who=scope(),auth=await client.auth.getUser();
      if(!auth.data?.user||auth.error||(who&&auth.data.user.id!==who))throw Error('Account changed. Sign in again.');
      actor=auth.data.user.id;
      if(name==='iv_service_documents'&&['save','publish'].includes(args.p_action)){
        args={...args,p_data:{...args.p_data,__revision:documentsState?.revision,__reviewed:args.p_action==='publish'}};
        if(args.p_action==='publish'){
          const key='iv_service_publish:'+actor+':'+documentsState?.revision+':'+args.p_effective;
          let id=root.sessionStorage.getItem(key);if(!id){id=root.crypto.randomUUID();root.sessionStorage.setItem(key,id);}args.p_data.__request_id=id;
        }
      }
      const {data,error}=await client.rpc(name,args);
      if(stamp!==epoch)throw Error('Account changed.');
      if(error)throw Error(error.message||'Subscription request failed.');
      if(data==null)throw Error('Subscription service unavailable. Ask the owner to complete deployment.');
      if(name==='iv_service_documents'&&data.revision&&documentsState)documentsState.revision=data.revision;
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
      target.appendChild(element('p',[state.plan?planName(state.plan):'Complete setup before pilot activation',state.start_date?'Counted period: '+state.start_date+' through '+state.end_date+' · Philippine time':'',state.status==='pilot'?pilotRemaining(state):'',state.status==='grace'?'Grace ends '+state.grace_end:'',['suspended','inactive'].includes(state.status)&&state.retention_review_date?'Retention review date: '+state.retention_review_date:''].filter(Boolean).join('\n'),'iv-sub-summary'));
    }
    function gate(value){
      access=value;
      let testBadge=d.getElementById('gym-test-badge');if(!testBadge){testBadge=element('span','TEST','tenant-test-badge');testBadge.id='gym-test-badge';d.getElementById('header-gym-title')?.parentElement.appendChild(testBadge);}testBadge.hidden=!value.is_test;
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
      const plan=d.getElementById('owner-subscription-menu');if(plan)plan.hidden=!value.is_owner;
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
            p_tenant:app.currentTenantId,p_action:'badge'
          }
          );
          record=data;
          if(value.status==='setup'){panel.textContent='';panel.appendChild(element('h2','Get your gym ready'));setupChecklist(panel,data,()=>openBilling(data.tenant_id,'documents'));panel.appendChild(element('p','','iv-sub-error'));}
          const count=data.unread_count??data.notifications.filter(n=>!n.read_at&&!n.resolved_at&&!n.superseded_at).length;
          const badge=d.getElementById('owner-notification-count');badge.textContent=String(count);badge.hidden=!count;bell.dataset.unread=String(count>0);
          bell.setAttribute('aria-label','Notifications'+(count?', '+count+' unread':''));
          if(value.operations&&value.status==='grace'){
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
    function setupChecklist(target,data,review){
      const steps=[
        ['1. Gym Terms & Privacy',data.gym_documents_ready,'Complete and publish your gym details.',()=>{dialog?.close();app.openLegalSettings(data.tenant_id);}],
        ['2. Service Agreement',data.accepted,!data.current_version?'Awaiting Iron Vault publication.':!data.gym_documents_ready?'Review the documents; complete step 1 before accepting.':'Review the Terms of Use, Privacy Notice, Data Processing Agreement and Free Pilot Conditions.',data.current_version?review:null],
        ['3. Pilot approval',data.state.status!=='setup',!data.accepted||!data.gym_documents_ready||!data.platform_documents_ready?'Complete the requirements above.':'Awaiting Service Provider approval. Your pilot has not started.',null]
      ];
      const list=element('div',null,'iv-sub-steps');for(const [title,done,description,action] of steps){const card=element('article',null,'iv-sub-step');card.dataset.complete=String(!!done);card.append(element('h3',(done?'✓ ':'')+title),element('p',done?'Complete':description));if(!done&&action&&data.is_owner)card.appendChild(button(title.startsWith('1.')?'Complete gym details':'Review Service Agreement',action,'primary'));list.appendChild(card);}target.appendChild(list);
      if(data.accepted&&data.state.status==='setup'){const pending=element('p','Your agreement acceptance is recorded. Pilot activation still requires manual approval by the Iron Vault Service Provider.','iv-sub-notice');pending.setAttribute('role','status');target.appendChild(pending);}
      if(!data.platform_documents_ready)target.appendChild(element('p','Iron Vault must also publish its platform member documents before activation.','iv-sub-muted'));
    }
    function renderDocs(target,data){
      const section=element('section');
      if(!data.documents.length){section.append(element('h3','Awaiting Iron Vault publication'),element('p','Your service documents will appear here once Iron Vault publishes them. No action is needed from you yet.'));target.appendChild(section);return;}
      section.appendChild(element('h3','Service Agreement','iv-sub-heading'));
      section.appendChild(element('p','Review the documents below. Free Pilot Conditions are incorporated into the Terms of Use. Accepting does not activate the pilot, authorize payment or enroll you in optional paid features.','iv-sub-muted'));
      const select=element('select',null,'iv-sub-select');
      for(const v of data.documents){
        const option=element('option',(v.version_label?'Version '+v.version_label+' · ':'')+'Effective '+v.effective_date+(v.id===data.current_version?' · current':''));
        option.value=v.id;
        select.appendChild(option);
      }
      if(data.current_version)select.value=data.current_version;
      select.setAttribute('aria-label','Document version');section.appendChild(select);
      const tabs=element('div',null,'iv-sub-actions'),body=element('article','','iv-sub-document');
      let type='terms_text';
      const pilotHelp=element('p','','iv-sub-muted');pilotHelp.hidden=true;
      function pilotSection(){return Array.from(body.querySelectorAll('h3,h4,p')).find(n=>pilotHeading.test(n.textContent.trim()));}
      const render=()=>{
        const v=data.documents.find(v=>v.id===select.value);
        documentPreview(body,v?.[type]);pilotHelp.hidden=true;
        if(type==='terms_text'){const pilot=pilotSection();if(pilot){pilot.id='service-pilot-conditions';pilot.tabIndex=-1;}}
      }
      ;
      for(const [key,label] of [['terms_text','Terms of Use'],['privacy_text','Privacy Notice'],['dpa_text','Data Processing Agreement']])tabs.appendChild(button(label,()=>{
        type=key;
        render();
      }
      ));
      const pilotLink=element('a','Free Pilot Conditions','iv-agreement-document-link');pilotLink.href='#service-pilot-conditions';pilotLink.addEventListener('click',event=>{event.preventDefault();type='terms_text';render();const pilot=pilotSection();if(pilot){pilot.focus({preventScroll:true});pilot.scrollIntoView({block:'nearest'});}else{pilotHelp.textContent='The Free Pilot section could not be located in this version. Contact the Service Provider before accepting.';pilotHelp.hidden=false;}});tabs.appendChild(pilotLink);
      select.addEventListener('change',render);
      section.append(tabs,body,pilotHelp);
      render();
      if(data.is_owner){
        const agree=check(ownerAcknowledgment);agree.input.required=true;
        const acceptButton=button('Accept and Continue',()=>run(async()=>{
          if(!agree.input.checked)throw Error('Review the listed documents and check the acknowledgment before continuing.');
          await call('iv_subscription_portal',{
            p_tenant:selected,p_action:'accept',p_data:{
              version_id:select.value,accepted:true,acknowledgment_text:ownerAcknowledgment,review_hash:data.documents.find(v=>v.id===select.value)?.review_hash
            }
          }
          );
          await openBilling(selected);await refresh();
        }
        ),'primary');
        acceptButton.disabled=true;agree.input.addEventListener('change',()=>{acceptButton.disabled=!agree.input.checked||!data.gym_documents_ready||!hasPilot();});
        const hasPilot=()=>String(data.documents.find(v=>v.id===select.value)?.terms_text||'').split(/\r?\n/).some(line=>pilotHeading.test(line.trim()));
        const already=()=>data.acceptances.some(a=>a.version_id===select.value);const acceptanceState=()=>{const done=already();agree.wrap.hidden=done||!data.gym_documents_ready;acceptButton.hidden=done||!data.gym_documents_ready;agree.input.checked=false;agree.input.disabled=!hasPilot();acceptButton.disabled=true;if(!done&&!hasPilot()){pilotHelp.textContent='The Provider must identify the Free Pilot Conditions in these Terms before you can accept.';pilotHelp.hidden=false;}};select.addEventListener('change',acceptanceState);acceptanceState();
        section.append(agree.wrap,acceptButton);
        if(!data.gym_documents_ready)section.appendChild(element('p','Publish your gym legal details first so the gym identity can be recorded with acceptance.'));
      }
      section.appendChild(element('p',data.acceptances.map(a=>'Accepted documents effective '+(data.documents.find(v=>v.id===a.version_id)?.effective_date||'recorded version')+' · '+new Intl.DateTimeFormat('en-PH',{
        timeZone:'Asia/Manila',dateStyle:'medium',timeStyle:'short'
      }
      ).format(new Date(a.accepted_at))+' · Gym '+(a.gym_snapshot?.name||data.tenant_id)+' · Owner '+(a.owner_snapshot?.name||a.owner_id)).join('\n')||'No acceptance recorded.','iv-sub-summary'));
      target.appendChild(section);
    }
    function planControls(target,data,reviewAgreement){
      const current=data.documents.find(v=>v.id===data.current_version),pending=data.requests.find(r=>!r.approved_at&&!r.cancelled_at);
      const section=element('section');target.appendChild(section);
      const contacts=()=>{
        section.append(element('h3','Payment instructions','iv-sub-heading'),element('p',current?.data.billing_instructions||'Contact the Service Provider for verified payment instructions.','iv-sub-summary'));
        const email=current?.data.support_email;if(email&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)){const a=element('a','Contact Provider','iv-sub-contact');a.href='mailto:'+email;section.appendChild(a);}
        if(current?.data.billing_contact)section.appendChild(element('p','Billing contact: '+current.data.billing_contact));
      };
      if(pending){
        section.append(element('h3',pending.reference_submitted_at?'Awaiting Provider payment approval':'Request confirmed — arrange payment','iv-sub-heading'),element('p',planName(pending.quote.plan)+' · '+money(pending.quote.amount)+' · '+pending.quote.start_date+' – '+pending.quote.end_date,'iv-sub-summary'));
        if(pending.kind==='downgrade'){section.appendChild(element('p','The plan change awaits approval. Renewal payment will still be required.'));return;}
        contacts();
        if(pending.payment_reference)section.appendChild(element('p','Submitted reference: '+pending.payment_reference));
        else {const wrap=element('label',null,'iv-sub-field'),input=element('input');input.maxLength=180;wrap.append(element('span','Payment reference / cash receipt'),input);section.append(wrap,button('Submit payment reference',()=>run(async()=>{await call('iv_subscription_portal',{p_tenant:selected,p_action:'submit_reference',p_data:{request_id:pending.id,reference:input.value.trim()}});await openBilling(selected);}), 'primary'),button('Cancel unpaid request',()=>run(async()=>{if(!root.confirm('Cancel this unpaid request? Do not cancel if payment has already been made.'))return;await call('iv_subscription_portal',{p_tenant:selected,p_action:'cancel_request',p_data:{request_id:pending.id}});await openBilling(selected);})) );}
        return;
      }
      if(!current){section.appendChild(element('p','The Provider must publish service documents first.'));return;}
      section.append(element('h3',data.state.status==='pilot'?'Choose your paid plan':'Renew or change your plan','iv-sub-heading'),element('p','Manual payment only. Prices below are current; the review step confirms the price and dates for your subscription start. No automatic charges.','iv-sub-muted'));
      const cards=element('div',null,'iv-plan-cards'),quoteView=element('p','','iv-sub-summary');
      const confirmation=check('I confirm the quoted plan, amount, dates and applicable policies.');confirmation.wrap.hidden=true;
      let quote=null;
      const reviewQuoted=button('Review quoted agreement',()=>reviewAgreement(quote?.version_id));reviewQuoted.hidden=true;
      const confirm=button('Confirm request',()=>run(async()=>{
        if(!quote||!confirmation.input.checked)throw Error('Review the quote and tick confirmation.');
        const key='ironvault_subscription_plan:'+scope()+':'+selected+':'+JSON.stringify(quote);let id=root.sessionStorage.getItem(key);if(!id){id=root.crypto.randomUUID();root.sessionStorage.setItem(key,id);}
        await call('iv_subscription_portal',{p_tenant:selected,p_action:'confirm_plan',p_data:{request_id:id,confirmed:true,quote}});root.sessionStorage.removeItem(key);await openBilling(selected);
      }),'primary');confirm.hidden=true;confirm.disabled=true;confirmation.input.addEventListener('change',()=>{confirm.disabled=!confirmation.input.checked;});
      for(const [plan,label,key,description] of [['dashboard','Dashboard Only','dashboard_price','Staff-assisted registration, check-in, member records, transactions and reports.'],['portal','Dashboard + Member Portal','portal_price','Dashboard features plus member login, QR passes and supported self-service.']]){
        const card=element('article',null,'iv-sub-step');card.append(element('h3',label),element('p','Current price: '+money(current.data[key])+' total / '+current.data.paid_days+' counted days'),element('p',description));
        const actions=element('div',null,'iv-sub-actions');
        const options=[['payment',data.state.status==='pilot'||data.state.status==='setup'?'Choose plan':'Review renewal']];
        if(data.state.status==='paid'&&data.state.plan==='dashboard'&&plan==='portal')options.push(['upgrade','Upgrade remaining days']);
        if(data.state.status==='paid'&&data.state.plan==='portal'&&plan==='dashboard')options.push(['downgrade','Change at next renewal']);
        for(const [kind,label] of options)actions.appendChild(button(label,()=>run(async()=>{quote=null;reviewQuoted.hidden=true;confirmation.wrap.hidden=true;confirm.hidden=true;quote=await call('iv_subscription_portal',{p_tenant:selected,p_action:'quote',p_data:{kind,plan}});quoteView.textContent=planName(quote.plan)+' · '+money(quote.amount)+'\nCounted dates: '+quote.start_date+' – '+quote.end_date+'\nAccess begins: '+quote.access_from+(kind==='downgrade'?'\nThis schedules a plan change; renewal payment is still required.':'');confirmation.input.checked=false;const accepted=data.acceptances.some(a=>a.version_id===quote.version_id);confirmation.wrap.hidden=!accepted;confirm.hidden=!accepted;reviewQuoted.hidden=accepted;confirm.disabled=true;if(!accepted)quoteView.textContent+='\nReview and accept the quoted agreement before confirming.';})));
        card.appendChild(actions);cards.appendChild(card);
      }
      section.append(cards,quoteView,reviewQuoted,confirmation.wrap,confirm);
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
      if(kind==='master')await app.refreshProviderConsole?.();
      await openBilling(selected);
      root.sessionStorage.removeItem(key);
      return result;
    }
    function masterControls(target,data){
      if(kind!=='master')return;
      const section=element('section');
      section.appendChild(element('h3','Provider approvals','iv-sub-heading'));
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
        card.appendChild(element('p',r.kind+' · '+planName(r.quote.plan)+' · '+money(r.quote.amount)+' · '+r.quote.start_date+' through '+r.quote.end_date+'\nOwner confirmation: '+dateTime(r.confirmed_at)+'\n'+(r.cancelled_at?'Cancelled':r.approved_at?'Approved '+dateTime(r.approved_at):'Awaiting approval'),'iv-sub-summary'));
        if(!r.approved_at&&!r.cancelled_at){
          const label=element('label',null,'iv-sub-field'),input=element('input');
          label.append(element('span','Verified payment reference / receipt'),input);input.value=r.payment_reference||'';
          card.append(label,button(r.kind==='downgrade'?'Approve scheduled downgrade':'Approve verified payment',()=>run(async()=>{
            if(!root.confirm('Approve this exact request? Confirm that the payment is verified before proceeding.'))return;
            await adminAction(r.kind==='downgrade'?'approve_downgrade':'approve_payment',{
              request_id:r.id,reference:input.value.trim()
            }
            );
          }
          ),'primary'));
        }
        if(!r.approved_at&&!r.cancelled_at){const reason=element('input');reason.placeholder='Reason for returning request';reason.setAttribute('aria-label','Reason for returning request');card.append(reason,button('Return for review',()=>run(async()=>{if(!root.confirm('Return this request for a fresh owner quote? Payment records remain; resolve any money received separately.'))return;await adminAction('cancel_request',{request_id:r.id,reason:reason.value.trim()});})));}
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
      for(const r of data.requests)target.appendChild(element('p',(r.cancelled_at?'Cancelled request':r.approved_at?'Approved request':'Awaiting Service Provider approval')+' · '+r.kind+' · '+planName(r.quote.plan)+' · '+money(r.quote.amount)+' · '+r.quote.start_date+' through '+r.quote.end_date,'iv-sub-notice'));
      if(data.is_owner)for(const n of data.notifications.filter(n=>n.destination!=='announcement'&&(n.read_at||n.resolved_at||n.superseded_at)))target.appendChild(element('p',n.title+' · '+(n.resolved_at?'Resolved / renewed':n.read_at?'Read':'Superseded')+' · '+dateTime(n.available_at)+'\n'+n.message,'iv-sub-notice'));
      target.appendChild(element('h3','Periods and approvals','iv-sub-heading'));
      for(const p of data.periods)target.appendChild(element('p',p.kind+' · '+planName(p.plan)+' · '+p.start_date+' – '+p.end_date+' · '+money(p.amount)+'\nReference: '+(p.reference||'Not applicable')+' · Approved '+dateTime(p.approved_at),'iv-sub-notice'));
      for(const e of data.events)target.appendChild(element('p',({activate_pilot:'Pilot activated',approve_payment:'Payment approved',approve_downgrade:'Downgrade scheduled',extend:'Extension approved'}[e.action]||'Subscription updated')+' · '+dateTime(e.created_at)+' · '+(e.data.reason||e.data.reference||'Recorded by platform administrator'),'iv-sub-summary'));
    }
    async function openOwnerNotifications(){
      const data=await call('iv_subscription_portal',{p_tenant:app.currentTenantId,p_action:'notifications'});
      if(!data.is_owner)throw Error('Registered owner required.');
      const target=modal('Notifications'),active=data.notifications.filter(n=>!n.read_at&&!n.resolved_at&&!n.superseded_at);
      if(!active.length)target.appendChild(element('p','You’re all caught up.'));
      for(const n of active){
        const row=element('article',null,'iv-sub-notice'),open=button(n.title,()=>run(async()=>{
          await call('iv_subscription_portal',{p_tenant:data.tenant_id,p_action:'read_notice',p_data:{key:n.notice_key}});
          documentPreview(body,n.message);body.hidden=false;row.dataset.read='true';open.disabled=true;await refresh();
        }));const body=element('p',n.message,'iv-sub-summary');body.hidden=true;
        row.append(open,element('small',dateTime(n.available_at)),body);
        if(n.destination!=='announcement')row.appendChild(button(n.notice_key.startsWith('documents')?'Review agreements':'View subscription',()=>run(async()=>{await call('iv_subscription_portal',{p_tenant:data.tenant_id,p_action:'read_notice',p_data:{key:n.notice_key}});await refresh();await openBilling(data.tenant_id,n.notice_key.startsWith('documents')?'documents':'overview');})));
        target.appendChild(row);
      }
      const readAnnouncements=data.notifications.filter(n=>n.destination==='announcement'&&n.read_at);if(readAnnouncements.length){const archive=element('details');archive.appendChild(element('summary','Read announcements'));for(const n of readAnnouncements){const row=element('article',null,'iv-sub-notice');row.append(element('h3',n.title),element('p',n.message),element('small',dateTime(n.available_at)));archive.appendChild(row);}target.appendChild(archive);}
    }
    async function openBilling(tenant,initial='overview'){
      const serial=++viewSerial;
      const data=await call('iv_subscription_portal',{p_tenant:tenant,p_action:'get'});if(serial!==viewSerial)return;
      selected=tenant;record=data;const target=modal(kind==='master'?'Gym subscription review':data.state.status==='setup'&&!data.accepted&&initial==='documents'?'Service Agreement':'My Plan & Subscription');
      const view=tabs(target,[['overview','My Plan'],['documents','Agreements'],['history','History']],initial);
      target.querySelector('[role=tablist]').classList.add('iv-plan-tabs');
      const overview=view.sections.get('overview'),current=element('section',null,'iv-sub-current-plan');overview.appendChild(current);summary(current,data);
      if(data.state.status==='setup')setupChecklist(overview,data,()=>view.show('documents'));
      else if(data.is_owner){
        if(data.next_plan)overview.appendChild(element('p','Next plan: '+planName(data.next_plan)+' — payment approval is required.'));
        if(!data.accepted)overview.appendChild(button('Review service documents',()=>view.show('documents'),'primary'));
        else if(data.current_version)planControls(overview,data,version=>{view.show('documents');const select=view.sections.get('documents').querySelector('select');if(select){select.value=version;select.dispatchEvent(new Event('change'));}});
      }
      masterControls(overview,data);
      renderDocs(view.sections.get('documents'),data);
      for(const period of data.periods.filter(p=>p.start_date>data.today))overview.appendChild(element('p','Scheduled: '+planName(period.plan)+' · '+period.start_date+' – '+period.end_date+' · '+money(period.amount),'iv-sub-notice'));
      if(kind==='master')overview.appendChild(button('Change Test / Live tag',()=>app.setTenantTag(tenant)));
      const archive=view.sections.get('history');history(archive,data);
      if(!data.periods.length&&!data.requests.length&&!data.events.length)archive.appendChild(element('p','Your subscription history will appear after activation.'));
      if(data.is_owner)archive.appendChild(button('Download records',()=>{const url=root.URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));const a=element('a');a.href=url;a.download='IronVault-subscription-'+data.tenant_id+'.json';a.click();root.setTimeout(()=>root.URL.revokeObjectURL(url),1000);}));
    }
    async function serviceEditor(){
      const state=await call('iv_service_documents',{
        p_action:'get'
      }
      );
      documentsState=state;
      const target=modal('Service Agreement Settings'),values=new Map();const wizard=tabs(target,[['provider','1. Provider details'],['plans','2. Plans & pilot'],['policies','3. Policies'],['publish','4. Preview & publish']],'provider');const groups=new Map();for(const key of ['provider','plans','policies']){const grid=element('div',null,'iv-sub-grid');wizard.sections.get(key).appendChild(grid);groups.set(key,grid);}const publication=wizard.sections.get('publish');target.appendChild(element('p','Changes remain drafts until you preview and publish.','iv-sub-muted'));
      const advanced=element('details'),advancedHead=element('summary','Advanced document templates');
      const policies=element('details');policies.appendChild(element('summary','Advanced policies — prefilled from the reviewed drafts'));wizard.sections.get('policies').appendChild(policies);
      advanced.appendChild(advancedHead);
      publication.appendChild(advanced);
      let previewed=null;
      const reviewed=check('I reviewed all three documents, provider identity, actual infrastructure and policies; the publication matches current practices.');
      const preview=element('article','','iv-sub-document'),publishDate=element('input');
      publishDate.type='date';publishDate.addEventListener('input',()=>{reviewed.input.checked=false;publish.disabled=true;});
      publishDate.min=state.minimum_effective_date||'';
      publishDate.value=state.minimum_effective_date||new Intl.DateTimeFormat('en-CA',{
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
        const provider=['provider_name','brand','address','support_email','billing_contact','privacy_contact','privacy_email','support_hours','support_days','tax_policy','billing_instructions'];const plans=['dashboard_price','portal_price','pilot_days','paid_days','grace_days','price_notice_days','export_days','retention_days'];(field.key.startsWith('_')?advanced:(provider.includes(field.key)?groups.get('provider'):plans.includes(field.key)?groups.get('plans'):['providers','database_region','email_provider','overseas_processing','backup_policy','deletion_process','document_version'].includes(field.key)?groups.get('policies'):policies)).appendChild(wrap);
        values.set(field.key,input);
        input.addEventListener('input',()=>{
          previewed=null;
          reviewed.input.checked=false;reviewed.input.disabled=true;publish.disabled=true;
        }
        );
      }
      const collect=()=>Object.fromEntries([...values].map(([k,input])=>[k,input.type==='number'?Number(input.value):input.value.trim()]));
      const review=root.IronVaultServiceReview;
      const viewButtons=element('div',null,'iv-sub-actions');
      let previewData=null,activeDocument='terms_text',pendingChoice=false;
      const editedPlain=new Set();
      const defaults=Object.fromEntries(root.IronVaultServicePolicy.fields.filter(f=>f.key.startsWith('_')).map(f=>[f.key,f.default]));
      const custom=()=>Object.keys(defaults).some(k=>values.get(k).value.trim()!==defaults[k].trim());
      const status=element('p','','iv-sub-muted');status.setAttribute('role','status');target.insertBefore(status,target.children[1]);
      const settingsSummary=element('p','','iv-sub-summary iv-sub-key-settings');
      const changed=element('section',null,'iv-sub-notice');changed.hidden=true;
      changed.append(element('p','Your settings changed. Keep your edited documents for comparison, or regenerate all three documents from the standard templates? Regenerating replaces edited wording.'));
      const editor=element('textarea',null,'iv-sub-draft-editor');editor.hidden=true;editor.maxLength=50000;editor.setAttribute('aria-label','Edit full document draft');
      const currentLabel=element('h3','Terms of Use','iv-sub-heading');
      function invalidate(clear=true){previewed=null;reviewed.input.checked=false;reviewed.input.disabled=true;publish.disabled=true;if(clear){previewData=null;editor.hidden=true;preview.hidden=false;}copy.disabled=!previewData;edit.disabled=!previewData;settingsSummary.textContent=review.keySettings(collect());}
      function validateEdits(){if(pendingChoice)throw Error('Choose Keep edited documents or Regenerate before saving or publishing.');for(const key of editedPlain)if(values.get(key).value.includes('{{'))throw Error('Resolve template placeholders in your edited document before saving.');}
      function showDocument(){editor.hidden=true;preview.hidden=false;currentLabel.textContent=review.documents.find(d=>d[0]===activeDocument)[2];documentPreview(preview,previewData?.[activeDocument]);copy.disabled=!previewData;edit.disabled=!previewData;}
      for(const [key,,label] of review.documents)viewButtons.appendChild(button(label,()=>{activeDocument=key;showDocument();}));
      const copy=button('Copy full document',()=>run(async()=>{if(!previewData)throw Error('Generate a current preview first.');const copied=await review.copyText(previewData[activeDocument]);status.textContent=copied?currentLabel.textContent+' copied in full.':'Select and copy the full text in the manual-copy window.';}));
      const edit=button('Edit draft',()=>{if(!previewData)return;editor.value=previewData[activeDocument]||'';editor.hidden=false;preview.hidden=true;editor.focus();status.textContent='Edit the full text, or select all and paste a replacement. Save draft to preserve it.';});
      copy.disabled=edit.disabled=true;
      editor.addEventListener('input',()=>{const key=review.documents.find(d=>d[0]===activeDocument)[1];values.get(key).value=editor.value;editedPlain.add(key);previewData[activeDocument]=editor.value;invalidate(false);status.textContent='Edited draft not saved. Preview the final text again before publishing.';});
      changed.append(button('Keep edited documents',()=>{pendingChoice=false;changed.hidden=true;status.textContent='Edited wording kept. Compare it with your updated settings before publishing.';}),button('Regenerate documents',()=>{for(const [key,value] of Object.entries(defaults))values.get(key).value=value;editedPlain.clear();pendingChoice=false;changed.hidden=true;invalidate();documentPreview(preview,'Generate a preview to review the regenerated documents.');status.textContent='Standard templates restored. Your form details are unchanged.';}));
      for(const [key,input] of values)input.addEventListener('input',()=>{if(!key.startsWith('_')&&custom()){pendingChoice=true;changed.hidden=false;}invalidate();status.textContent='Settings changed. Generate a fresh preview before copying or publishing.';});
      const reviewActions=element('div',null,'iv-sub-actions');reviewActions.append(copy,edit);
      const copySettings=button('Copy settings for review',()=>run(async()=>{const copied=await review.copyText(review.settingsCopy(root.IronVaultServicePolicy.fields,collect())+'\nPlanned effective date: '+publishDate.value);status.textContent=copied?'All settings from steps 1–3 copied for comparison.':'Select and copy the settings in the manual-copy window.';}));
      settingsSummary.textContent=review.keySettings(collect());
      const actions=element('div',null,'iv-sub-actions');
      actions.append(button('Save draft',()=>run(async()=>{
        await call('iv_service_documents',{
          p_action:'save',p_data:(validateEdits(),collect())
        }
        );
        status.textContent='Draft saved, including edited documents. Published documents have not changed.';
      }
      )),button('Preview all documents',()=>run(async()=>{
        validateEdits();const data=collect(),result=await call('iv_service_documents',{
          p_action:'preview',p_data:data
        }
        );
        if(JSON.stringify(collect())!==JSON.stringify(data)){status.textContent='Settings changed while the preview was loading. Generate a fresh preview.';return;}
        previewed=JSON.stringify(data);
        previewData=result.preview;
        showDocument();reviewed.input.disabled=false;publish.disabled=true;status.textContent='Current draft preview generated. Review all three documents against the settings.';
      }
      )),button('Publish new version',()=>run(async()=>{
        validateEdits();const data=collect();
        if(!reviewed.input.checked||previewed!==JSON.stringify(data))throw Error('Preview this exact draft and confirm review before publication.');
        if(!root.confirm('Publish these service documents with effective date '+publishDate.value+'? Existing acceptances will be preserved.'))return;
        await call('iv_service_documents',{
          p_action:'publish',p_data:data,p_effective:publishDate.value
        }
        );
        await serviceEditor();
      }
      ),'primary'));
      const publish=actions.lastElementChild;publish.disabled=true;reviewed.input.disabled=true;reviewed.input.addEventListener('change',()=>{publish.disabled=!reviewed.input.checked||previewed!==JSON.stringify(collect());});
      const save=actions.firstElementChild;const footer=element('div',null,'iv-sub-actions iv-sub-footer');const keys=['provider','plans','policies','publish'];const back=button('Back',()=>move(-1)),next=button('Next step',()=>move(1));const update=()=>{const at=keys.findIndex(key=>!wizard.sections.get(key).hidden);back.disabled=at===0;next.disabled=at===3;};function move(delta){const at=keys.findIndex(key=>!wizard.sections.get(key).hidden);wizard.show(keys[Math.max(0,Math.min(3,at+delta))]);update();target.scrollTop=0;}footer.append(save,back,next);target.appendChild(footer);target.addEventListener('click',update);target.addEventListener('keydown',update);update();publication.append(copySettings,element('h3','Compare with your settings','iv-sub-heading'),settingsSummary,changed,dateWrap,viewButtons,currentLabel,reviewActions,preview,editor,reviewed.wrap,actions,element('h3','Published version history','iv-sub-heading'));documentPreview(preview,'Choose Preview all documents to review your current draft.');
      for(const v of state.versions)publication.appendChild(button('Published version effective '+v.effective_date,()=>{
        previewData=null;editor.hidden=true;preview.hidden=false;copy.disabled=true;edit.disabled=true;documentPreview(preview,v.terms_text);status.textContent='Viewing a published version. Generate a current draft preview to edit or copy.';
      }
      ));
      publication.appendChild(advanced);
    }
    if(kind==='master'){
      root.IronVaultProviderConsole.install(app,client,{call,run,modal,element,button,openBilling,serviceEditor});
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
    install,help,money,planName,statusText,documentPreview,pilotRemaining,ownerAcknowledgment
  }
  ;
  if(typeof module==='object'&&module.exports)module.exports=root.IronVaultSubscriptions;
}
)(globalThis);
