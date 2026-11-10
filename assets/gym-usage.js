/* Isolated read-only usage adapter. Failure never gates subscriptions, entry or financial actions. */
(function(root){
 'use strict';
 function install(app,client,kind){const d=root.document;if(!d.querySelector||!root.IronVaultGymUsageView)return;let ticket=0,view=null,activeTenant=null,actor=null,disposed=false;
 function context(){const role=app.authenticatedRole;return {actor:kind==='master'?actor:role?.user_id||null,tenant:kind==='master'?app.currentInspectOwnerId:app.currentTenantId,allowed:kind==='master'?true:role?.role==='owner'};}
 function reset(){ticket++;activeTenant=null;actor=null;view?.clear();}
 async function refresh(){const ctx=context();if(!view||!ctx.allowed||!ctx.tenant||kind!=='master'&&!ctx.actor)return;const serial=++ticket;view.loading();try{const auth=await client.auth.getUser();if(serial!==ticket||disposed)return;if(auth.error||!auth.data?.user?.id||kind!=='master'&&auth.data.user.id!==ctx.actor)throw Error('Account changed');if(kind==='master')ctx.actor=auth.data.user.id;activeTenant=ctx.tenant;actor=ctx.actor;const {data,error}=await client.rpc('iv_gym_usage',{p_tenant:ctx.tenant});const now=context();if(serial!==ticket||disposed||now.actor!==ctx.actor||now.tenant!==ctx.tenant||!now.allowed)return;if(error)throw Error(error.message);view.show(data,ctx.tenant);}catch(_){const now=context();if(serial===ticket&&!disposed&&now.actor===ctx.actor&&now.tenant===ctx.tenant&&now.allowed)view.fail();}}

 if(kind==='admin'){
  const card=d.querySelector('.phone-subscription-summary');if(!card)return;card.classList.add('gym-usage-card');view=root.IronVaultGymUsageView.create(card,{onRetry:refresh});view.section.hidden=true;const label=card.querySelector('small');if(label)label.textContent='SUBSCRIPTION & USAGE';const manage=[...card.children].find(n=>n.tagName==='BUTTON');if(manage)manage.textContent='Manage subscription';const original=app.renderPhoneSubscription;
  app.renderPhoneSubscription=function(...args){const result=original?.apply(this,args),ctx=context();view.section.hidden=!ctx.allowed;if(label)label.textContent=ctx.allowed?'SUBSCRIPTION & USAGE':'SUBSCRIPTION';if(manage)manage.textContent=ctx.allowed?'Manage subscription':'View Subscription';if(!ctx.allowed||!ctx.actor||!ctx.tenant){reset();return result;}if(ctx.tenant!==activeTenant||ctx.actor!==actor)refresh();return result;};app.renderPhoneSubscription(app.phoneSubscriptionState);
  // Usage can be refreshed explicitly; subscription polling keeps its existing cadence and behavior.
  app.refreshGymUsage=refresh;
 }else if(kind==='master'){
  const card=d.querySelector('.gym-profile-subscription');if(!card)return;view=root.IronVaultGymUsageView.create(card,{onRetry:refresh});const label=card.querySelector('.gym-profile-eyebrow');if(label)label.textContent='SUBSCRIPTION & USAGE';const open=app.openInspectModal,close=app.closeInspectModal;
  app.openInspectModal=function(...args){reset();const result=open.apply(this,args);const ctx=context();view.section.hidden=!ctx.allowed;if(ctx.allowed&&ctx.tenant)refresh();return result;};
  app.closeInspectModal=function(...args){reset();return close.apply(this,args);};app.refreshGymUsage=refresh;const overlay=d.getElementById('branch-inspect-modal');if(overlay&&root.MutationObserver)new root.MutationObserver(()=>{if(overlay.classList.contains('hidden'))reset();}).observe(overlay,{attributes:true,attributeFilter:['class']});
 }
 client.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'||actor&&session?.user?.id&&session.user.id!==actor){reset();if(view)view.section.hidden=true;disposed=event==='SIGNED_OUT';}else if(event==='SIGNED_IN'){disposed=false;}});
 }
 root.IronVaultGymUsage=Object.freeze({install});
})(globalThis);
