const test=require('node:test'),assert=require('node:assert/strict'),review=require('../assets/service-review.js'),policy=require('../assets/service-policy.js');
test('settings copy includes all non-template fields, exact prices and provider-protection review instructions',()=>{
 const values=Object.fromEntries(policy.fields.map(f=>[f.key,f.default]));values.dashboard_price=1234;values.portal_price=2345;values.refund_policy='Owner-approved credit only';
 const text=review.settingsCopy(policy.fields,values);for(const field of policy.fields.filter(f=>!f.key.startsWith('_')))assert.ok(text.includes(field.label+':'));
 assert.match(text,/1234/);assert.match(text,/2345/);assert.match(text,/Owner-approved credit only/);assert.match(text,/mandatory customer or privacy rights/);assert.match(text,/Do not invent infrastructure/);assert.doesNotMatch(text,/26\. LAW, CONTACTS/);
 assert.match(review.keySettings(values),/PHP 1234/);assert.match(review.keySettings(values),/PHP 2345 total/);assert.match(review.keySettings(values),/does not change these operational settings/);
});
test('full-text copy uses the complete supplied text instead of a visible excerpt',async()=>{
 const old=Object.getOwnPropertyDescriptor(global,'navigator');let copied;Object.defineProperty(global,'navigator',{configurable:true,value:{clipboard:{writeText:async text=>{copied=text}}}});
 try{const text='First line\n'+'Body '.repeat(10000)+'\nFinal clause';assert.equal(await review.copyText(text),true);assert.equal(copied,text);}finally{if(old)Object.defineProperty(global,'navigator',old);else delete global.navigator;}
});
test('clipboard failure offers complete selectable text without reporting copy success',async()=>{
 const oldNavigator=Object.getOwnPropertyDescriptor(global,'navigator'),oldDocument=global.document,created=[];
 Object.defineProperty(global,'navigator',{configurable:true,value:{clipboard:{writeText:async()=>{throw Error('Denied')}}}});
 global.document={body:{appendChild(){}},execCommand:()=>false,createElement:tag=>{const n={tag,style:{},children:[],append(...nodes){this.children.push(...nodes)},setAttribute(){},addEventListener(){},focus(){},select(){this.selected=true},remove(){this.removed=true},showModal(){this.open=true}};created.push(n);return n;}};
 try{const text='Complete document\nFinal clause';assert.equal(await review.copyText(text),false);assert.equal(created[0].removed,true);const dialog=created.find(n=>n.tag==='dialog');assert.equal(dialog.open,true);assert.equal(dialog.children.find(n=>n.tag==='textarea').value,text);assert.equal(dialog.children.find(n=>n.tag==='textarea').selected,true);}finally{global.document=oldDocument;if(oldNavigator)Object.defineProperty(global,'navigator',oldNavigator);else delete global.navigator;}
});
