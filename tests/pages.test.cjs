const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const files=['index.html',...fs.readdirSync('gym').filter(f=>f.endsWith('.html')).map(f=>'gym/'+f)];
test('every inline script parses and every local script reference exists',()=>{
    let count=0;
    for(const file of files){
        const html=fs.readFileSync(file,'utf8');
        for(const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)){
            const src=match[1].match(/src="([^"]+)"/);
            if(src){if(!src[1].startsWith('http'))assert.ok(fs.existsSync(path.resolve(path.dirname(file),src[1])));}
            else if(match[2].trim()){new vm.Script(match[2],{filename:file});count++;}
        }
    }
    assert.ok(count>=19);
});
test('both master entry points use the same adapter and no embedded-credential comparison',()=>{
    for(const file of ['index.html','gym/index.html']){
        const html=fs.readFileSync(file,'utf8');
        assert.match(html,/IronVaultSuperAdmin\.install\(indexApp,supabaseClient/);
        assert.doesNotMatch(html,/if\s*\(email\s*===\s*['"]/);
        assert.doesNotMatch(html,/id="super-password"[^>]*\bvalue=/);
    }
});
test('admin portal derives UI permissions from verified roles, not a default admin flag',()=>{
    const html=fs.readFileSync('gym/admin.html','utf8');
    assert.doesNotMatch(html,/getItem\(ACTIVE_ROLE_KEY\)\s*\|\|\s*'admin'/);
    assert.match(html,/checkExistingSession: async function/);
});
