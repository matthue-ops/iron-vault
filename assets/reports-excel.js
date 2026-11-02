/* Small write-only XLSX exporter. Text cells are explicit strings, never formulas. */
(function(root){
 'use strict';
 const ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main';
 function xml(value){return String(value).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/g,'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));}
 function column(index){let text='';for(let n=index+1;n;n=Math.floor((n-1)/26))text=String.fromCharCode(65+(n-1)%26)+text;return text;}
 function filename(gym,start,end){
  const name=Array.from(String(gym||'').normalize('NFKC').replace(/[<>:"/\\|?*\u0000-\u001f]/g,'_').replace(/\s+/g,'_').replace(/^[._]+|[._]+$/g,'')).slice(0,100).join('')||'GYM';
  if(!/^\d{4}-\d{2}-\d{2}$/.test(start)||!/^\d{4}-\d{2}-\d{2}$/.test(end))throw Error('A valid report period is required.');
  return name+'_REPORTS_'+start+'_'+end+'.xlsx';
 }
 function cell(value,reference,header){
  let money=false;if(value&&typeof value==='object'&&value.format==='money'){money=true;value=value.value;}
  if(value===null||value===undefined)return '';
  const style=header?1:money?2:0;
  if(typeof value==='number'){
   if(!Number.isFinite(value))throw Error('A report contains an invalid numeric value.');
   return '<c r="'+reference+'" s="'+style+'"><v>'+value+'</v></c>';
  }
  if(typeof value!=='string')throw Error('Unsupported Excel cell value.');
  if(value.length>32767)throw Error('A report cell exceeds Excel’s text limit. Export a narrower report or use CSV.');
  return '<c r="'+reference+'" s="'+style+'" t="inlineStr"><is><t xml:space="preserve">'+xml(value)+'</t></is></c>';
 }
 function worksheet(sheet){
  if(!Array.isArray(sheet.rows)||!sheet.rows.length||sheet.rows.length>1048576)throw Error('The report exceeds Excel’s row limit. Select a shorter period.');
  const count=sheet.rows.reduce((max,row)=>Math.max(max,row.length),1);if(count>16384)throw Error('The report exceeds Excel’s column limit.');
  if(!Number.isInteger(sheet.headerRow)||sheet.headerRow<1||sheet.headerRow>sheet.rows.length)throw Error('Invalid Excel header row.');
  const last=column(Math.max(0,count-1))+sheet.rows.length;
  const rows=sheet.rows.map((row,r)=>'<row r="'+(r+1)+'">'+row.map((value,c)=>cell(value,column(c)+(r+1),r+1===sheet.headerRow)).join('')+'</row>').join('');
  const widths=(sheet.widths||[]).map((width,c)=>'<col min="'+(c+1)+'" max="'+(c+1)+'" width="'+Math.max(8,Math.min(100,width))+'" customWidth="1"/>').join('');
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="'+ns+'"><dimension ref="A1:'+last+'"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="'+sheet.headerRow+'" topLeftCell="A'+(sheet.headerRow+1)+'" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'+(widths?'<cols>'+widths+'</cols>':'')+'<sheetData>'+rows+'</sheetData>'+(sheet.filter?'<autoFilter ref="A'+sheet.headerRow+':'+last+'"/>':'')+'<pageMargins left="0.3" right="0.3" top="0.5" bottom="0.5" header="0.2" footer="0.2"/></worksheet>';
 }
 const styles='<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="'+ns+'"><numFmts count="1"><numFmt numFmtId="164" formatCode="&quot;₱&quot;#,##0.00;[Red]-&quot;₱&quot;#,##0.00"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0F172A"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFill="1" applyFont="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right" vertical="top" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';
 let zipLoading=null;
 async function loadZip(document=root.document){
  if(typeof root.JSZip==='function')return root.JSZip;
  if(!document?.head||!document.createElement)throw Error('The Excel export library could not load. Refresh and try again.');
  if(!zipLoading){
   zipLoading=new Promise((resolve,reject)=>{
    const script=document.createElement('script');script.src='https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js';script.async=true;
    const timer=root.setTimeout(()=>finish(false),20000);
    function finish(ok){root.clearTimeout(timer);script.onload=null;script.onerror=null;script.remove?.();if(ok&&typeof root.JSZip==='function')resolve(root.JSZip);else reject(Error('The Excel export library could not load. Refresh and try again.'));}
    script.onload=()=>finish(true);script.onerror=()=>finish(false);document.head.appendChild(script);
   });
  }
  try{return await zipLoading;}catch(error){zipLoading=null;throw error;}
 }
 async function create(sheets,Zip=root.JSZip){
  if(typeof Zip!=='function')throw Error('The Excel export library could not load. Refresh and try again.');
  if(!Array.isArray(sheets)||sheets.length!==4)throw Error('Four report sheets are required.');
  const seen=new Set();for(const sheet of sheets){if(!sheet.name||sheet.name.length>31||/[\\/?*\[\]:]/.test(sheet.name)||seen.has(sheet.name.toLowerCase()))throw Error('Invalid Excel sheet name.');seen.add(sheet.name.toLowerCase());}
  const zip=new Zip();const sheetTypes=[],relations=[],entries=[];
  sheets.forEach((sheet,i)=>{const number=i+1;zip.file('xl/worksheets/sheet'+number+'.xml',worksheet(sheet));sheetTypes.push('<Override PartName="/xl/worksheets/sheet'+number+'.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');relations.push('<Relationship Id="rId'+number+'" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet'+number+'.xml"/>');entries.push('<sheet name="'+xml(sheet.name)+'" sheetId="'+number+'" r:id="rId'+number+'"/>');});
  zip.file('[Content_Types].xml','<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'+sheetTypes.join('')+'</Types>');
  zip.file('_rels/.rels','<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
  zip.file('xl/workbook.xml','<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="'+ns+'" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView/></bookViews><sheets>'+entries.join('')+'</sheets></workbook>');
  zip.file('xl/_rels/workbook.xml.rels','<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+relations.join('')+'<Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>');
  zip.file('xl/styles.xml',styles);
  return zip.generateAsync({type:'uint8array',compression:'DEFLATE',compressionOptions:{level:6}});
 }
 const api=Object.freeze({create,filename,loadZip});root.IronVaultReportsExcel=api;if(typeof module==='object'&&module.exports)module.exports=api;
})(globalThis);
