/* Optional offline warning support. No app data caching or offline writes. */
(function(root){
 'use strict';
 if(!root.navigator?.serviceWorker||!(root.location.protocol==='https:'||['localhost','127.0.0.1'].includes(root.location.hostname)))return;
 function register(){root.navigator.serviceWorker.register('/service-worker.js',{scope:'/',updateViaCache:'none'}).catch(()=>{root.console?.warn('Offline warning page could not be prepared. Normal app operation is unchanged.');});}
 if(root.document.readyState==='loading')root.document.addEventListener('DOMContentLoaded',register,{once:true});else register();
})(globalThis);
