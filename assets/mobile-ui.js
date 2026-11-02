/* Presentation only: retain existing rows, controls, handlers and permission checks. */
(function(root){
 'use strict';
 function enhance(){
  for(const table of root.document.querySelectorAll('table')){
   const headings=Array.from(table.querySelectorAll('thead th'),h=>h.textContent.trim());
   if(!headings.length)continue;table.classList.add('iv-card-table');
   for(const row of table.querySelectorAll('tbody tr')){
    if(row.dataset.mobileReady)continue;row.dataset.mobileReady='true';
    Array.from(row.children).forEach((cell,index)=>{
     if(cell.colSpan>1)return;cell.dataset.label=headings[index]||'';
     if(!/action|manage/i.test(headings[index]||''))return;
     const controls=Array.from(cell.children).filter(child=>child.matches('button,a'));
     if(controls.length<2)return;
     const menu=root.document.createElement('details');menu.className='iv-secondary-actions';
     const summary=root.document.createElement('summary');summary.textContent='⋯';summary.setAttribute('aria-label','More actions');menu.appendChild(summary);
     menu.addEventListener('click',event=>event.stopPropagation());
     for(const control of controls.slice(1))menu.appendChild(control);cell.appendChild(menu);
    });
   }
  }
 }
 if(!root.document.querySelectorAll||!root.MutationObserver)return;
 root.document.addEventListener('DOMContentLoaded',()=>{
  for(const input of root.document.querySelectorAll('input[type="password"][minlength="8"]')){
   input.addEventListener('input',()=>input.setCustomValidity(''));
   input.addEventListener('invalid',()=>{if(input.validity.tooShort)input.setCustomValidity('At least 8 characters.');});
  }
  enhance();new root.MutationObserver(enhance).observe(root.document.body,{childList:true,subtree:true});});
})(globalThis);
