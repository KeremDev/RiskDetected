/* Deterministic OOXML exports from a frozen wizard snapshot. No remote fonts or macros. */
(function(root){
  'use strict';
  const xml=s=>String(s==null?'':s).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&apos;');
  const enc=root.ISGWizard.utf8;
  function zip(files){
    const output=[],central=[];let offset=0;
    const le=(v,n)=>Array.from({length:n},(_,i)=>(v>>>i*8)&255);
    function crc(bytes){let c=0xffffffff;for(const byte of bytes){c^=byte;for(let j=0;j<8;j++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0;}
    for(const name of Object.keys(files).sort()){
      const n=enc(name),data=enc(files[name]),check=crc(data),size=data.length;
      const header=[...le(0x04034b50,4),20,0,0,8,0,0,0,0,33,0,...le(check,4),...le(size,4),...le(size,4),...le(n.length,2),0,0,...n];
      const dir=[...le(0x02014b50,4),20,0,20,0,0,8,0,0,0,0,33,0,...le(check,4),...le(size,4),...le(size,4),...le(n.length,2),0,0,0,0,0,0,0,0,0,0,0,0,...le(offset,4),...n];
      output.push(header,data);central.push(dir);offset+=header.length+size;
    }
    const count=central.length,size=central.reduce((n,c)=>n+c.length,0);
    return output.concat(central,[[...le(0x06054b50,4),0,0,0,0,...le(count,2),...le(count,2),...le(size,4),...le(offset,4),0,0]]).flat();
  }
  function base64(bytes){const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';let out='';for(let i=0;i<bytes.length;i+=3){const a=bytes[i],b=bytes[i+1],c=bytes[i+2];out+=alphabet[a>>2]+alphabet[((a&3)<<4)|((b||0)>>4)]+(i+1<bytes.length?alphabet[((b&15)<<2)|((c||0)>>6)]:'=')+(i+2<bytes.length?alphabet[c&63]:'=');}return out;}
  const declaration='<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  const rels=(target,type)=>declaration+'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/'+type+'" Target="'+target+'"/></Relationships>';
  const types=overrides=>declaration+'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="json" ContentType="application/json"/>'+overrides.map(([part,type])=>'<Override PartName="/'+part+'" ContentType="application/vnd.openxmlformats-officedocument.'+type+'"/>').join('')+'</Types>';
  function docx(blocks,snapshot){
    const p=(s,style)=>'<w:p><w:pPr><w:pStyle w:val="'+(style||'Normal')+'"/></w:pPr><w:r>'+String(s).split('\n').map((line,i)=>(i?'<w:br/>':'')+'<w:t xml:space="preserve">'+xml(line)+'</w:t>').join('')+'</w:r></w:p>';
    const table=rows=>{const cols=Math.max(...rows.map(x=>x.length)),width=Math.floor(9360/cols);return '<w:tbl><w:tblPr><w:tblW w:w="9360" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders>'+['top','left','bottom','right','insideH','insideV'].map(x=>'<w:'+x+' w:val="single" w:sz="4" w:color="DDDDDD"/>').join('')+'</w:tblBorders><w:tblCellMar><w:top w:w="80" w:type="dxa"/><w:left w:w="100" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>'+Array(cols).fill('<w:gridCol w:w="'+width+'"/>').join('')+'</w:tblGrid>'+rows.map((row,rowIndex)=>'<w:tr><w:trPr><w:cantSplit/>'+(cols>2&&rowIndex===0?'<w:tblHeader/>':'')+'</w:trPr>'+row.map((cell,i)=>'<w:tc><w:tcPr><w:tcW w:w="'+width+'" w:type="dxa"/>'+(i===0?'<w:shd w:fill="F2F4F5"/>':'')+'</w:tcPr>'+p(cell)+'</w:tc>').join('')+'</w:tr>').join('')+'</w:tbl>'+p('');};
    const body=blocks.map(b=>b.type==='table'?table(b.rows):p(b.text,{title:'Title',heading:'Heading1',subheading:'Heading2'}[b.type])).join('');
    const styles=declaration+'<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/><w:color w:val="000000"/><w:lang w:val="tr-TR"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="100" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'+[['Title',36],['Heading1',28],['Heading2',24]].map(([name,size])=>'<w:style w:type="paragraph" w:styleId="'+name+'"><w:name w:val="'+name+'"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="220" w:after="100"/></w:pPr><w:rPr><w:b/><w:sz w:val="'+size+'"/><w:color w:val="000000"/></w:rPr></w:style>').join('')+'</w:styles>';
    return zip({'[Content_Types].xml':types([['word/document.xml','wordprocessingml.document.main+xml'],['word/styles.xml','wordprocessingml.styles+xml']]),'_rels/.rels':rels('word/document.xml','officeDocument'),'word/_rels/document.xml.rels':rels('styles.xml','styles'),'word/styles.xml':styles,'word/document.xml':declaration+'<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'+body+'<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>','customXml/isgada-snapshot.json':root.ISGWizard.canonical(snapshot)});
  }
  function xlsx(blocks,snapshot){
    const data=[['Kimlik','Olası olay','Olası zarar','Önerilen önlemler','Önerilen rol','Mevcut durum','Faktörler ve puan','Termin','Planlanan risk','Uygulama sonrası risk'],...snapshot.rows.map(r=>[r.id,r.scenario_tr,r.consequences_tr,r.controls.map(c=>c.hierarchy_label_tr+': '+c.text_tr).join('\n'),r.suggested_owner_role_tr,'','','','',''])];
    const report=[['Bölüm','İçerik']];blocks.forEach(b=>{if(b.type==='table')b.rows.forEach(row=>report.push([row[0],row.slice(1).join(' · ')]));else report.push([b.type==='text'?'':b.text,b.type==='text'?b.text:'']);});
    const scope=[['Konu','Gerekli kapsam'],...snapshot.unresolved.map(x=>[x.id+' '+x.title,x.missing_labels.join('; ')]),['Satır sınırı dışında',''],...snapshot.omitted.map(x=>[x.id,x.title])];
    const sheets=snapshot.domain==='risk'?[['Riskler',data],['Belge',report],['Ek kapsam',scope]]:[['Acil durum planı',report]];
    const col=n=>{let out='';for(n++;n;n=Math.floor((n-1)/26))out=String.fromCharCode(65+(n-1)%26)+out;return out;};
    const files={'_rels/.rels':rels('xl/workbook.xml','officeDocument'),'customXml/isgada-snapshot.json':root.ISGWizard.canonical(snapshot)};
    files['[Content_Types].xml']=types([['xl/workbook.xml','spreadsheetml.sheet.main+xml'],['xl/styles.xml','spreadsheetml.styles+xml'],...sheets.map((s,i)=>['xl/worksheets/sheet'+(i+1)+'.xml','spreadsheetml.worksheet+xml'])]);
    files['xl/workbook.xml']=declaration+'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'+sheets.map((s,i)=>'<sheet name="'+xml(s[0])+'" sheetId="'+(i+1)+'" r:id="rId'+(i+1)+'"/>').join('')+'</sheets></workbook>';
    files['xl/_rels/workbook.xml.rels']=declaration+'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+sheets.map((s,i)=>'<Relationship Id="rId'+(i+1)+'" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet'+(i+1)+'.xml"/>').join('')+'<Relationship Id="styles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>';
    files['xl/styles.xml']=declaration+'<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';
    sheets.forEach(([name,rows],i)=>{
      const cols=Math.max(...rows.map(x=>x.length));files['xl/worksheets/sheet'+(i+1)+'.xml']=declaration+'<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>'+Array.from({length:cols},(_,c)=>'<col min="'+(c+1)+'" max="'+(c+1)+'" width="'+(cols===2?(c===0?40:110):(c===0?14:c===3?95:38))+'" customWidth="1"/>').join('')+'</cols><sheetData>'+rows.map((row,r)=>'<row r="'+(r+1)+'" ht="'+Math.min(409,Math.max(...row.map((v,c)=>String(v).split('\n').reduce((n,line)=>n+Math.max(1,Math.ceil(line.length/(cols===2?(c===0?38:108):(c===0?12:c===3?93:36)))),0)))*15+8)+'" customHeight="1">'+row.map((v,c)=>'<c r="'+col(c)+(r+1)+'" t="inlineStr"><is><t xml:space="preserve">'+xml(v)+'</t></is></c>').join('')+'</row>').join('')+'</sheetData></worksheet>';
    }); return zip(files);
  }
  root.ISGWizard.exportFile=(engine,snapshot,format)=>{
    if(!['docx','xlsx'].includes(format))throw Error('Dosya türü desteklenmiyor.');
    const bytes=(format==='docx'?docx:xlsx)(engine.blocks(snapshot),snapshot);
    return {name:(snapshot.domain==='risk'?'Risk_Analizi_':'Acil_Durum_Plani_')+snapshot.content_sha256.slice(0,10)+'.'+format,base64:base64(bytes)};
  };
})(globalThis);
