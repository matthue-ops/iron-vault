const {test}=require('node:test'),assert=require('node:assert/strict'),JSZip=require('jszip');
const X=require('../assets/reports-excel.js');
const sheets=()=>['Overview','Money','Attendance','Activity'].map(name=>({name,headerRow:1,filter:name!=='Overview',widths:[28,22],rows:[['Name','Amount'],['José & <Gym>',{value:100.25,format:'money'}],['=HYPERLINK("bad")',0],['+cmd',null]]}));
test('XLSX contains four related worksheets, numeric PHP cells, filters and frozen headers',async()=>{
 const bytes=await X.create(sheets(),JSZip);assert.equal(bytes[0],0x50);assert.equal(bytes[1],0x4b);const zip=await JSZip.loadAsync(bytes);
 const workbook=await zip.file('xl/workbook.xml').async('string');for(const name of ['Overview','Money','Attendance','Activity'])assert.ok(workbook.includes('name="'+name+'"'));
 assert.equal((workbook.match(/<sheet /g)||[]).length,4);
 const money=await zip.file('xl/worksheets/sheet2.xml').async('string');assert.match(money,/<c r="B2" s="2"><v>100.25<\/v><\/c>/);assert.match(money,/<v>0<\/v>/);
 assert.match(money,/autoFilter ref="A1:B4"/);assert.match(money,/state="frozen"/);assert.match(money,/José &amp; &lt;Gym&gt;/);
 assert.doesNotMatch(await zip.file('xl/worksheets/sheet1.xml').async('string'),/autoFilter/);
 assert.match(await zip.file('xl/styles.xml').async('string'),/₱/);
});
test('XLSX writes formula-looking user content as strings with no executable formulas or external links',async()=>{
 const zip=await JSZip.loadAsync(await X.create(sheets(),JSZip));const xml=await zip.file('xl/worksheets/sheet2.xml').async('string');
 assert.match(xml,/t="inlineStr"><is><t xml:space="preserve">=HYPERLINK\(&quot;bad&quot;\)/);assert.match(xml,/>\+cmd<\/t>/);
 assert.doesNotMatch(xml,/<f[ >]|<hyperlink/);assert.ok(!Object.keys(zip.files).some(name=>/externalLinks/.test(name)));
});
test('Excel filename reflects the gym and period while rejecting unsafe path characters',()=>{
 assert.equal(X.filename('FITNESS GYM','2026-11-01','2026-11-30'),'FITNESS_GYM_REPORTS_2026-11-01_2026-11-30.xlsx');
 assert.equal(X.filename('.. /Gym: A?','2026-11-01','2026-11-30'),'Gym__A_REPORTS_2026-11-01_2026-11-30.xlsx');
 assert.equal(X.filename('', '2026-11-01','2026-11-30'),'GYM_REPORTS_2026-11-01_2026-11-30.xlsx');
 assert.throws(()=>X.filename('Gym','bad','date'),/valid report period/);
});
test('Excel export fails clearly for unavailable dependency and oversized cells instead of corrupting a download',async()=>{
 await assert.rejects(X.create(sheets(),null),/library could not load/);
 const large=sheets();large[0].rows.push(['x'.repeat(32768)]);await assert.rejects(X.create(large,JSZip),/text limit/);
 const bad=sheets();bad[0].rows.push([NaN]);await assert.rejects(X.create(bad,JSZip),/invalid numeric/);
});
