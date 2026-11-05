const test=require('node:test'),assert=require('node:assert/strict');
const ui=require('../assets/subscriptions.js');
test('service document previews format headings while rendering hostile content only as text',()=>{
 const previous=global.document;global.document={createElement:tag=>({tag,textContent:'',className:''})};
 try{const target={children:[],textContent:'',classList:{add(){}},appendChild(n){this.children.push(n)}};
 ui.documentPreview(target,'# Service Agreement\n\n1. PARTIES\n\n<img src=x onerror=alert(1)>');
 assert.deepEqual(target.children.map(n=>n.tag),['h3','h4','p']);assert.equal(target.children[0].textContent,'Service Agreement');assert.equal(target.children[2].textContent,'<img src=x onerror=alert(1)>');assert.ok(target.children.every(n=>!('innerHTML' in n)));
 }finally{global.document=previous;}
});
