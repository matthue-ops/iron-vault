/* Publish only browser assets. Backend source, SQL, tests and docs stay out of the site. */
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),out=path.join(root,'dist');
fs.rmSync(out,{recursive:true,force:true});fs.mkdirSync(out,{recursive:true});
fs.copyFileSync(path.join(root,'index.html'),path.join(out,'index.html'));
for(const name of ['gym','assets'])fs.cpSync(path.join(root,name),path.join(out,name),{recursive:true,filter:source=>{
 const stat=fs.lstatSync(source);if(stat.isSymbolicLink())throw Error('Symbolic links are not published: '+source);
 return stat.isDirectory()||/\.(html|js|css|png|jpe?g|svg|webp|ico|woff2?|ttf|txt)$/i.test(source);
}});
fs.writeFileSync(path.join(out,'404.html'),'<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Page not found</title><body style="background:#0c111b;color:#e2e8f0;font-family:system-ui;padding:3rem"><h1>Page not found</h1><p>Check your gym link or return to <a href="/" style="color:#6ee7b7">Iron Vault</a>.</p></body></html>');
fs.writeFileSync(path.join(out,'_routes.json'),JSON.stringify({version:1,include:['/*'],exclude:['/','/index','/index.html','/gym','/gym/*','/assets/*','/404.html']},null,2)+'\n');
console.log('Cloudflare Pages site prepared in dist/');
