/* Apply the saved gym palette; owner presets and provider custom colors share this path. */
(function(root){
 'use strict';
 const DEFAULT='#10b981';
 const valid=value=>typeof value==='string'&&/^#[0-9a-f]{6}$/i.test(value);
 const color=value=>valid(value)?value.toLowerCase():DEFAULT;
 function ink(value){
  const channels=color(value).slice(1).match(/../g).map(v=>{const c=parseInt(v,16)/255;return c<=.04045?c/12.92:((c+.055)/1.055)**2.4;});
  const l=.2126*channels[0]+.7152*channels[1]+.0722*channels[2];
  return (l+.05)/.05>=1.05/(l+.05)?'#000000':'#ffffff';
 }
 function apply(value){
  const c=color(value),s=root.document.documentElement.style;
  root.document.documentElement.setAttribute?.('data-gym-palette',c);
  const meta=root.document.querySelector?.('meta[name="theme-color"]');if(meta)meta.content=c;
  s.setProperty('--brand-primary',c);s.setProperty('--brand-primary-glow',c+'33');s.setProperty('--brand-ink',ink(c));
 }
 function installAdmin(app){
  // Prevent the asynchronous logo sampler from overwriting the saved accent.
  root.applyDynamicThemeFromLogo=function(){};
  const original=app.applyBranding;
  app.applyBranding=function(owner){const result=original.apply(this,arguments);apply(owner?.accentColor);return result;};
 }
 function installMaster(app,client){
  const node=id=>root.document.getElementById('gym-accent-'+id);
  let tenant=null,generation=0,saving=false;
  function preview(){const c=color(node('picker').value);node('value').textContent=c;node('preview').style.background=c;node('preview').style.color=ink(c);node('preview-title').style.color=c;}
  const original=app.openEditModal;
  app.openEditModal=function(id){
   const modal=root.document.getElementById('edit-owner-modal');
   const preserve=tenant===id&&!modal.classList.contains('hidden');
   const result=original.apply(this,arguments),gym=this.owners.find(g=>g.id===id);if(!gym)return result;
   if(!preserve){tenant=id;generation++;node('picker').value=color(gym.accentColor);node('status').textContent='';preview();}
   node('picker').oninput=()=>{node('status').textContent='Preview only — save to apply.';preview();};
   node('reset').onclick=()=>{node('picker').value=DEFAULT;node('status').textContent='Default preview — save to apply.';preview();};
   node('save').onclick=async()=>{
    if(saving)return;
    const id=tenant,version=generation,chosen=node('picker').value;if(!valid(chosen)){node('status').textContent='Choose a valid color.';return;}
    saving=true;node('save').disabled=true;const release=app.liveUpdates?.hold();
    try{
     const saved=await root.IronVaultData.call(client,'iv_set_gym_accent',{p_tenant:id,p_color:chosen});
     const current=app.owners.find(g=>g.id===id);if(current)current.accentColor=color(saved);
     if(version===generation)node('status').textContent='Accent saved. Connected gym dashboards will update automatically.';
    }catch(error){if(version===generation)node('status').textContent='Color was not saved. '+error.message;}
    finally{saving=false;node('save').disabled=false;release?.();}
   };
   return result;
  };
 }
 root.IronVaultGymAccent={DEFAULT,valid,color,ink,apply,installAdmin,installMaster};
 if(typeof module==='object'&&module.exports)module.exports=root.IronVaultGymAccent;
})(globalThis);
