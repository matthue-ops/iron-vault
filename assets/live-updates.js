/* Change signals are hints only. Every displayed value is read again through scoped APIs. */
(function(root){
 'use strict';
 const identity=r=>[r.user_id,r.role,r.tenant_id||'',r.member_id||''].join('|');
 const denied=e=>['AUTH_REQUIRED','ACCESS_DENIED','ACTOR_CHANGED','42501'].includes(e?.code);
 function create(options){
  const {client,context,authorize,read,apply,status=()=>{},onDenied=()=>{},isVisible=()=>true}=options;
  const schedule=options.setTimeout||root.setTimeout.bind(root),cancel=options.clearTimeout||root.clearTimeout.bind(root);
  let epoch=0,running=false,starting=false,channel=null,scope=null,actor=null,cursor=null,day=null,holds=new Set(),mutation=0,busy=false,checking=false,full=false,queued=new Map(),timer=null,poll=null,connected=false,failures=0,baseline=null,acknowledged=new Map();
  const contextKey=()=>JSON.stringify(context());
  function valid(stamp,key){if(running&&stamp===epoch&&contextKey()!==key){stop();return false;}return running&&stamp===epoch;}
  function clearTimers(){if(timer!==null)cancel(timer);if(poll!==null)cancel(poll);timer=poll=null;}
  function stop(){epoch++;running=starting=false;busy=checking=false;mutation++;actor=null;scope=null;cursor=null;day=null;baseline=null;acknowledged.clear();full=false;queued.clear();clearTimers();connected=false;
   if(channel){const old=channel;channel=null;try{Promise.resolve(client.removeChannel(old)).catch(()=>{});}catch(_){}}
   status('stopped');
  }
  function failed(error){if(denied(error)){stop();onDenied(error);}else status(['PGRST202','42883','42P01'].includes(error?.code)?'unavailable':'reconnecting');}
  async function verify(stamp,key){const role=await authorize();if(!valid(stamp,key))return false;if(actor&&identity(role)!==actor){const e=Error('The signed-in account or role changed.');e.code='ACTOR_CHANGED';throw e;}return role;}
  const signalKey=s=>s.kind+'|'+s.entity_id;
  function revision(value){if(typeof value==='number'&&!Number.isSafeInteger(value))return null;const s=String(value??'');return /^[1-9][0-9]{0,19}$/.test(s)?s:null;}
  function remember(key,value){const old=acknowledged.get(key);if(!old||value.length>old.length||(value.length===old.length&&value>old))acknowledged.set(key,value);}
  function enqueue(hint){if(!running)return;
   if(!hint||hint.kind==='system'){full=true;queued.clear();}
   else if(!['member','gym'].includes(hint.kind)||typeof hint.entity_id!=='string'||typeof hint.tenant_id!=='string')return;
   else{
    if(scope.tenant&&hint.tenant_id!==scope.tenant)return;
    if(scope.member&&hint.kind==='member'&&hint.entity_id!==scope.member)return;
    if(!full){const item={kind:hint.kind,entity_id:hint.entity_id,tenant_id:hint.tenant_id},v=revision(hint.revision);if(v)item.revision=v;queued.set(signalKey(hint),item);}
    if(queued.size>64){full=true;queued.clear();}
   }
   if(timer===null)timer=schedule(()=>{timer=null;pump();},150);
  }
  async function pump(){
   if(!running||busy||holds.size||!isVisible()||(!full&&!queued.size))return;
   const stamp=epoch,key=JSON.stringify(scope);if(!valid(stamp,key))return;const version=mutation,snapshot=baseline?new Map(baseline):null,wanted=full?null:Array.from(queued.values());full=false;queued.clear();busy=true;
   try{
    if(!await verify(stamp,key))return;
    const data=await read(scope,wanted);if(!valid(stamp,key))return;
    if(!await verify(stamp,key))return;
    if(holds.size||version!==mutation){full=true;return;}
    await apply(data,wanted);if(wanted){for(const h of wanted)if(h.revision)remember(signalKey(h),h.revision);}else if(snapshot){acknowledged=snapshot;}failures=0;if(valid(stamp,key))status(connected?'live':'fallback');
   }catch(error){if(valid(stamp,key)){full=true;failures++;failed(error);}}
   finally{if(stamp===epoch){busy=false;if(running&&(full||queued.size)&&timer===null)timer=schedule(()=>{timer=null;pump();},Math.min(30000,1000*Math.pow(2,failures)));}}
  }
  function planPoll(delay=20000){if(poll!==null)cancel(poll);if(running)poll=schedule(()=>{poll=null;check();},delay);}
  async function check(force=false){
   if(!running||checking||!isVisible())return;const stamp=epoch,key=JSON.stringify(scope);if(!valid(stamp,key))return;checking=true;let delay=20000;
   try{
    if(!await verify(stamp,key))return;
    const {data,error}=await client.rpc('iv_live_cursor',{p_tenant:scope.tenant||null,p_member:scope.member||null,p_cursor:force?null:cursor});
    if(!valid(stamp,key))return;if(error)throw error;
    if(!data||typeof data.cursor!=='string'||!/^[a-f0-9]{32}$/.test(data.cursor))throw Error('Invalid live update checkpoint.');
    if(!await verify(stamp,key))return;
    const currentDay=Number.isFinite(Date.parse(data.server_now))?new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(data.server_now)):day;
    if(Array.isArray(data.signals)){
     const next=new Map();for(const h of data.signals){const v=revision(h.revision);if(!['member','gym','system'].includes(h.kind)||typeof h.entity_id!=='string'||!v||(scope.tenant&&h.tenant_id!==scope.tenant)||(scope.member&&h.kind==='member'&&h.entity_id!==scope.member))throw Error('Invalid signal checkpoint.');next.set(signalKey(h),v);}
     const first=baseline===null,removed=Array.from(acknowledged.keys()).some(k=>!next.has(k));baseline=next;
     if(force||first||removed||day!==currentDay)enqueue(null);else for(const h of data.signals)if(acknowledged.get(signalKey(h))!==next.get(signalKey(h)))enqueue(h);
    }else if(force||cursor!==data.cursor||day!==currentDay)enqueue(null);
    cursor=data.cursor;day=currentDay;
    status(connected?'live':'fallback');
   }catch(error){if(valid(stamp,key)){delay=60000;failed(error);}}
   finally{if(stamp===epoch){checking=false;if(valid(stamp,key))planPoll(delay);}}
  }
  async function start(){
   if(running||starting||!isVisible())return;const selected=context();if(!selected)return;
   starting=running=true;scope={...selected};const stamp=++epoch,key=contextKey();status('connecting');
   try{
    const role=await authorize();if(!valid(stamp,key))return;actor=identity(role);
    if(typeof client.channel==='function'){
     channel=client.channel('iv-live-'+role.user_id+'-'+stamp+'-'+Math.random().toString(36).slice(2));
     for(const event of ['INSERT','UPDATE']){const filter={event,schema:'public',table:'iv_live_signals'};if(scope.tenant)filter.filter='tenant_id=eq.'+scope.tenant;
      channel.on('postgres_changes',filter,payload=>{if(valid(stamp,key))enqueue(payload?.new);});}
     channel.subscribe(value=>{if(!valid(stamp,key))return;connected=value==='SUBSCRIBED';if(connected){status('live');check(true);}else if(['CHANNEL_ERROR','TIMED_OUT','CLOSED'].includes(value)){status('reconnecting');check(true);}});
    }
    await check(true);
   }catch(error){if(valid(stamp,key)){if(denied(error))failed(error);else{stop();status('reconnecting');poll=schedule(()=>{poll=null;start();},10000);}}}
   finally{if(stamp===epoch)starting=false;}
  }
  function hold(){const token={};holds.add(token);mutation++;return ()=>{if(!holds.delete(token))return;mutation++;if(running&&!holds.size)enqueue(null);};}
  return Object.freeze({start,stop,check,notify:enqueue,hold,get running(){return running;}});
 }
 root.IronVaultLiveUpdates=Object.freeze({create});if(typeof module==='object'&&module.exports)module.exports=root.IronVaultLiveUpdates;
})(globalThis);
