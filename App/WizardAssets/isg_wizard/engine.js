/* ISGADA portable offline engine. Same bytes run on JavaScriptCore and Android WebView.
 * No network, eval, DOM, storage, identity authority, inferred scores or approval state.
 * Sources: content/isg/wizard. Runtime contract and fixture tests are versioned together.
 */
(function (root) {
  'use strict';
  const VERSION = 'isgada-engine-5.0.0';
  const DOMAINS = ['sectors','areas','equipment','tasks','hazards','conditions','processes','energy','people','emergency_systems'];
  const LABELS = {sectors:'Faaliyetler',areas:'Çalışma alanları',equipment:'Ekipmanlar',tasks:'Yapılan işler',hazards:'Özel tehlikeler',conditions:'Çalışma düzeni',processes:'Özel süreçler',energy:'Enerji sistemleri',people:'Maruz kalan kişiler',emergency_systems:'Kritik acil durum sistemleri'};
  const clone = v => JSON.parse(JSON.stringify(v));
  const canonical = v => Array.isArray(v) ? '['+v.map(canonical).join(',')+']' : v && typeof v === 'object' ? '{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}' : JSON.stringify(v);
  const unique = xs => Array.from(new Set(xs)).sort();
  const intersects = (a,b) => a.some(x=>b.has(x));
  const text = (v,max) => typeof v === 'string' ? v.trim().slice(0,max || 1000) : '';
  function utf8(s) {
    const bytes=[];
    for (let ch of s) {
      let c=ch.codePointAt(0); if(c>=0xd800 && c<=0xdfff)c=0xfffd;
      if(c<128)bytes.push(c); else if(c<2048)bytes.push(192|(c>>6),128|(c&63));
      else if(c<65536)bytes.push(224|(c>>12),128|((c>>6)&63),128|(c&63));
      else bytes.push(240|(c>>18),128|((c>>12)&63),128|((c>>6)&63),128|(c&63));
    } return bytes;
  }
  function sha256(s) {
    const k=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    const h=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19], b=utf8(s), n=b.length*8;
    b.push(128); while(b.length%64!==56)b.push(0); for(let i=7;i>=0;i--)b.push(i<4 ? (n>>>i*8)&255 : 0);
    const rr=(x,n)=>(x>>>n)|(x<<(32-n));
    for(let off=0;off<b.length;off+=64){
      const w=[]; for(let i=0;i<16;i++)w[i]=(b[off+4*i]<<24)|(b[off+4*i+1]<<16)|(b[off+4*i+2]<<8)|b[off+4*i+3];
      for(let i=16;i<64;i++){const a=w[i-15],z=w[i-2];w[i]=(w[i-16]+(rr(a,7)^rr(a,18)^(a>>>3))+w[i-7]+(rr(z,17)^rr(z,19)^(z>>>10)))|0;}
      let [a,c,d,e,f,g,j,l]=h;
      for(let i=0;i<64;i++){const t=(l+(rr(f,6)^rr(f,11)^rr(f,25))+((f&g)^(~f&j))+k[i]+w[i])|0,u=((rr(a,2)^rr(a,13)^rr(a,22))+((a&c)^(a&d)^(c&d)))|0;l=j;j=g;g=f;f=(e+t)|0;e=d;d=c;c=a;a=(t+u)|0;}
      [a,c,d,e,f,g,j,l].forEach((x,i)=>h[i]=(h[i]+x)|0);
    } return h.map(x=>(x>>>0).toString(16).padStart(8,'0')).join('');
  }
  function create(bundle) {
    if(bundle.schema_version!==5)throw Error('Katalog sürümü desteklenmiyor.');
    const b=clone(bundle), risks=new Map(b.risk_catalog.map(r=>[r.id,r]));
    const choices={}; DOMAINS.forEach(k=>choices[k]=b.taxonomy[k] ? b.taxonomy[k].map(x=>({id:x.id,label:x.name_tr,aliases:x.aliases_tr || []})) : Object.keys(b.options[k]).map(id=>({id,label:b.options[k][id],aliases:[]})));
    const featureLabels={}; Object.keys(choices).forEach(k=>choices[k].forEach(x=>featureLabels[x.id]=x.label));
    b.risk_catalog.forEach(r=>{ for(const f of r.requires_any_features) if(!featureLabels[f])featureLabels[f]=r.context_tr; });
    function normalize(raw) {
      if(!raw || typeof raw!=='object' || Array.isArray(raw))throw Error('Yanıtlar geçersiz.');
      const allowed=new Set([...DOMAINS,'scope','method','preset']);
      if(Object.keys(raw).some(k=>!allowed.has(k)))throw Error('Tanımsız soru alanı.');
      const a={method:raw.method || 'fk',preset:raw.preset || 'standard'};
      if(typeof a.method!=='string' || typeof a.preset!=='string' || !Object.prototype.hasOwnProperty.call(b.methods,a.method) || !Object.prototype.hasOwnProperty.call(b.presets,a.preset))throw Error('Yöntem veya kapsam seçimi geçersiz.');
      const s=raw.scope || {};
      if(typeof s!=='object' || Array.isArray(s))throw Error('Firma bilgisi geçersiz.');
      a.scope={company_id:text(s.company_id,64)||null,workplace_id:text(s.workplace_id,64)||null,company_name:text(s.company_name,160),workplace_name:text(s.workplace_name,160)};
      if(a.scope.workplace_id && !a.scope.company_id)throw Error('İşyeri seçimi için firma gerekli.');
      if(!a.scope.company_id){a.scope.company_name='';a.scope.workplace_name='';}
      if(!a.scope.workplace_id)a.scope.workplace_name='';
      DOMAINS.forEach(k=>{
        let v=raw[k] || {state:'unknown',ids:[]}; if(Array.isArray(v))v={state:v.length?'selected':'unknown',ids:v};
        if(!['selected','none','unknown'].includes(v.state) || (v.ids!==undefined && !Array.isArray(v.ids)))throw Error('Seçim durumu geçersiz.');
        const ids=v.ids || [], allowed=new Set(choices[k].map(x=>x.id));
        if(ids.length>100 || ids.some(x=>typeof x!=='string'||!allowed.has(x)) || (v.state==='selected'&&!ids.length) || (v.state!=='selected'&&ids.length))throw Error('Seçim listesi geçersiz: '+LABELS[k]);
        a[k]={state:v.state,ids:unique(ids)};
      }); return a;
    }
    function generate(raw, domain) {
      if(!['risk','emergency'].includes(domain))throw Error('Belge türü geçersiz.');
      const a=normalize(raw), origins={}, pool={};
      const addFeature=(tag,kind,ref)=>{const item={kind,ref};origins[tag]=origins[tag]||[];if(!origins[tag].some(x=>x.kind===kind&&x.ref===ref))origins[tag].push(item);};
      const add=(id,kind,weight,ref)=>{if(!risks.has(id))throw Error('Kırık risk eşlemesi.');pool[id]=pool[id]||[];pool[id].push({kind,weight,ref});};
      DOMAINS.filter(k=>!b.taxonomy[k]).forEach(k=>a[k].ids.forEach(f=>addFeature(f,'declared_context',k)));
      b.core_risk_ids.forEach(id=>add(id,'universal_recommendation',15,'core'));
      ['sectors','equipment','tasks'].forEach(k=>a[k].ids.forEach(id=>{
        const leaf=b.taxonomy[k].find(x=>x.id===id),kind=k==='sectors'?'sector_profile':'declared_activity';
        leaf.features.forEach(f=>addFeature(f,kind,id));leaf.risk_ids.forEach(r=>add(r,kind,k==='sectors'?35:65,id));
      }));
      let changed=true;
      while(changed){const before=canonical(origins);Object.keys(origins).sort().forEach(f=>(b.feature_implications[f]||[]).forEach(g=>origins[f].slice().forEach(o=>addFeature(g,o.kind,o.ref))));changed=before!==canonical(origins);}
      const features=new Set(Object.keys(origins));
      a.areas.ids.forEach(f=>(b.area_risks[f]||[]).forEach(r=>add(r,'declared_context',45,f)));
      unique(a.conditions.ids.concat(a.people.ids)).forEach(f=>(b.condition_risks[f]||[]).forEach(r=>add(r,'declared_context',45,f)));
      unique(a.hazards.ids.concat(a.energy.ids)).forEach(f=>(b.hazard_family_risks[f]||[]).forEach(family=>b.risk_catalog.filter(r=>r.family_id===family).forEach(r=>add(r.id,'declared_hazard_group',50,f))));
      b.risk_catalog.forEach(r=>{const matched=r.requires_any_features.filter(x=>features.has(x));if(matched.length){const explicit=matched.some(f=>origins[f].some(o=>o.kind!=='sector_profile'));add(r.id,explicit?'declared_feature':'sector_profile',explicit?55:35,matched.sort().join(','));}});
      const unresolved=[],eligible=[];
      Object.keys(pool).sort().forEach(id=>{
        const r=clone(risks.get(id)),missing=[r.requires_any_features,r.family_requires_any_features].filter(c=>c.length&&!intersects(c,features));
        if(missing.length){unresolved.push({id,title:r.scenario_tr,consequences:r.consequences_tr,missing_features:missing,missing_labels:missing.map(c=>c.map(f=>featureLabels[f]||f).join(' veya '))});return;}
        r.selection_reasons=pool[id].sort((x,y)=>canonical(x).localeCompare(canonical(y),'en'));
        r.selection_relevance=Math.max(...pool[id].map(x=>x.weight)); r.score=null; r.current_state=null;
        r.existing_controls_tr=null; r.planned_residual=null; r.verified_residual=null;
        if(a.areas.ids.includes('office') && ['G24','G26'].includes(r.family_id)){r.owner_role_code='employer';r.suggested_owner_role_tr=b.roles.employer;}
        eligible.push(r);
      });
      Object.keys(b.equivalence_groups).sort().forEach(key=>{
        const ids=b.equivalence_groups[key],members=eligible.filter(r=>ids.includes(r.id)).sort((x,y)=>y.selection_relevance-x.selection_relevance||x.id.localeCompare(y.id));
        if(members.length<2)return;
        const primary=members[0];primary.catalog_alias_ids=members.slice(1).map(r=>r.id);primary.equivalence_group=key;
        const seen=new Set();primary.controls=members.flatMap(r=>r.controls).filter(c=>{if(seen.has(c.text_tr))return false;seen.add(c.text_tr);return true;}).slice(0,4);
        primary.legal_topic_ids=unique(members.flatMap(r=>r.legal_topic_ids));
        members.slice(1).forEach(r=>eligible.splice(eligible.indexOf(r),1));
      });
      function select(rows,limit,reserveCore){
        let remaining=rows.slice(),out=[],counts={};
        const take=r=>{out.push(r);counts[r.family_id]=(counts[r.family_id]||0)+1;remaining=remaining.filter(x=>x.id!==r.id);};
        if(reserveCore&&limit>0){const r=remaining.find(r=>r.id==='R-49-01')||remaining.find(r=>b.core_risk_ids.includes(r.id));if(r)take(r);}
        while(remaining.length&&out.length<limit){remaining.sort((x,y)=>y.selection_relevance/(1+(counts[y.family_id]||0))-x.selection_relevance/(1+(counts[x.family_id]||0)) || Number(y.potential_severe_harm)-Number(x.potential_severe_harm) || x.id.localeCompare(y.id));take(remaining[0]);}return out;
      }
      const preset=b.presets[a.preset],selected=select(eligible,preset.row_limit,true),summary=select(selected,preset.summary_limit,false);
      selected.sort((x,y)=>y.selection_relevance-x.selection_relevance||x.id.localeCompare(y.id));
      const cardIDs=new Set(b.cards.filter(c=>c.core||intersects(c.requires_any_features,features)).map(c=>c.id));
      changed=true;while(changed){const n=cardIDs.size;Array.from(cardIDs).forEach(id=>(b.card_dependencies[id]||[]).forEach(dep=>cardIDs.add(dep)));changed=n!==cardIDs.size;}
      const cards=b.cards.filter(c=>cardIDs.has(c.id)).map(clone);
      const conflicts=[];
      if(a.hazards.state==='none'){const f=Object.keys(b.options.hazards).filter(f=>features.has(f));if(f.length)conflicts.push('Özel tehlike yok seçimiyle faaliyet/ekipman seçimi çelişiyor: '+f.map(f=>featureLabels[f]||f).join(', ')+'. İlgili riskler korundu.');}
      const chosen=new Set(selected.map(r=>r.id)),omitted=eligible.filter(r=>!chosen.has(r.id)).map(r=>({id:r.id,title:r.scenario_tr,severe:r.potential_severe_harm}));
      const result={schema_version:5,engine_version:VERSION,catalog_version:b.catalog_version,catalog_sha256:b.catalog_sha256,method_profile_id:b.methods[a.method].id,domain,answers:a,state:'editable_draft',rows:selected,cards,summary_ids:summary.map(r=>r.id),eligible_count:eligible.length,omitted,unresolved,input_conflicts:conflicts,unanswered_domains:DOMAINS.filter(k=>a[k].state==='unknown'),method_defaulted:!raw.method,preset_defaulted:!raw.preset,document_fields:{assessment_on:null,prepared_on:null,valid_until:null,assessment_team:[],emergency_team:[],signatures:null}};
      result.content_sha256=sha256(canonical(result));return result;
    }
    function blocks(r){
      const out=[],push=(type,text)=>out.push({type,text}),table=(rows)=>out.push({type:'table',rows});
      push('title',r.domain==='risk'?'Risk Değerlendirmesi Taslağı':'Acil Durum Planı Taslağı');
      push('text','Seçilen faaliyet, ekipman, iş ve çalışma koşulları için düzenlenebilir belge. Mevcut durum, puanlar, görevli kişiler ve tarihler doldurulabilir alanlar olarak bırakılmıştır.');
      table([['Firma',r.answers.scope.company_name||'________________'],['İşyeri',r.answers.scope.workplace_name||'________________'],['Adres','________________'],['Hazırlama / değerlendirme tarihi','________________'],['Geçerlilik / yenileme tarihi','________________']]);
      push('heading','Kapsam');
      DOMAINS.forEach(k=>push('text',LABELS[k]+': '+(r.answers[k].state==='selected'?r.answers[k].ids.map(id=>choices[k].find(x=>x.id===id).label).join(', '):r.answers[k].state==='none'?'Yok olarak belirtildi':'Belirtilmedi')));
      r.input_conflicts.forEach(x=>push('text',x));
      if(r.domain==='risk'){
        push('heading','Yöntem ve öncelikli konular');
        push('text',b.options.method[r.answers.method]+(r.answers.method==='fk'?' · Olasılık × Frekans × Şiddet':' · Olasılık × Şiddet')+'. Boş puan düşük risk anlamına gelmez.');
        table([['Üst sınır dahil','Düzey','Aksiyon'],...b.methods[r.answers.method].bands.map(x=>[x.upper_inclusive===null?'400 üzeri':String(x.upper_inclusive),x.label_tr,x.action_tr])]);
        r.summary_ids.forEach(id=>{const row=r.rows.find(x=>x.id===id);push('text',id+' · '+row.scenario_tr+' — '+row.consequences_tr);});
        push('text',r.rows.length+' / '+r.eligible_count+' risk bu belgede. Satır sınırı dışında '+r.omitted.length+' risk bulunuyor.');
        for(const row of r.rows){
          push('heading',row.id+' '+row.scenario_tr);
          table([['Bağlam',row.context_tr],['Olası zarar',row.consequences_tr],['Önerilen önlemler',row.controls.map(c=>c.hierarchy_label_tr+': '+c.text_tr).join('\n')],['Önerilen sorumlu rol',row.suggested_owner_role_tr],['Mevcut durum ve uygulanan önlemler','________________'],['Faktörler ve puan','________________'],['Sorumlu kişi ve termin','________________'],['Planlanan / uygulama sonrası risk','________________ / ________________']]);
        }
        if(r.unresolved.length){push('heading','Kapsamı netleşmemiş konular');r.unresolved.forEach(x=>push('text',x.id+' · '+x.title+' — '+x.consequences+'\nGerekli kapsam bilgisi: '+x.missing_labels.join('; ')));}
        if(r.omitted.length){push('heading','Satır sınırı dışında kalan konular');r.omitted.forEach(x=>push('text',x.id+' · '+x.title+(x.severe?' · Ağır zarar olasılığı':'')));}
        push('heading','Risk değerlendirme ekibi');
        table([['Görev','Ad / unvan','İmza'],...['İşveren / işveren vekili','İş güvenliği uzmanı','İşyeri hekimi','Çalışan temsilcisi','Destek elemanı','İşi ve tehlikeleri bilen çalışan'].map(x=>[x,'________________','________________'])]);
        push('heading','Ölçüm ve periyodik kontrol referansları');
        table([['Rapor türü / numarası','Tarih','İlgili kapsam'],['________________','________________','________________']]);
      } else {
        push('heading','Organizasyon ve iletişim');
        table([['Görev','Asıl / yedek / vardiya','İletişim'],...['Koordinatör','Söndürme','Kurtarma','Koruma ve sayım','İlkyardım','Tahliye sorumlusu'].map(x=>[x,'________________','________________'])]);
        push('text','Olayı güvenli noktadan bildirin; konum, olay türü ve bilinen yaralı / tehlike bilgisini aktarın. 112 çağrısı iç bildirimin tamamlanmasını beklememelidir.');
        table([['Alarm yöntemi ve noktaları','________________'],['Açık adres ve ambulans karşılama','________________'],['Kroki ve alternatif çıkışlar','________________'],['Birincil / alternatif toplanma alanı','________________'],['Tahliye desteği ve sayım düzeni','________________']]);
        r.cards.forEach(c=>{
          push('heading',c.id+' '+c.title_tr);push('text','Tetikleyici: '+c.trigger_tr+'\nHareket: '+c.mode_label_tr);
          [['before','Önce'],['during_worker','Sırasında çalışanlar'],['during_team','Sırasında görevli ekip'],['after','Sonrasında'],['prohibited','Yapılmayacaklar']].forEach(([key,label])=>{push('subheading',label);c[key].forEach((x,i)=>push('text',(i+1)+'. '+x));});
          push('text','Geri giriş: '+c.reentry_tr);table(c.site_field_keys.map(k=>[c.site_field_labels_tr[k],'________________']));
        });
        push('heading','Eğitim tatbikat ve düzeltici faaliyet');table([['Planlanan tarih','Gerçekleşme / gözlem','Sorumlu / takip'],['________________','________________','________________']]);
        push('heading','Olay sonrası kayıt ve hizmete dönüş');push('text','Olay zamanı, yer, alarm, yapılan işlemler, dış ekibe devir ve geri giriş kararının dayanağını kaydedin. Kritik kontroller tamamlanmadan normal faaliyete dönülmez.');
      }
      push('heading','Revizyon ve imza alanları');push('text','İşyeri, süreç, ekipman, ekip veya yerleşim değiştiğinde ilgili bölümleri güncelleyin. Belge oluşturma zamanı değerlendirme tarihi yerine geçmez.');
      table([['Hazırlayan','İşveren / vekili','Tarih / imza'],['________________','________________','________________']]);
      push('heading','Konu dayanakları');
      unique((r.domain==='risk'?r.rows:r.cards).flatMap(x=>x.legal_topic_ids)).forEach(id=>push('text',b.legal_topics[id]));
      push('text','İçerik: '+r.catalog_version+' · Motor: '+r.engine_version+(r.domain==='risk'?' · Yöntem: '+r.method_profile_id:''));
      push('text','Belge kimliği: '+r.content_sha256);return out;
    }
    return {generate,blocks,choices,questions:clone(b.questions),options:clone(b.options),version:b.catalog_version};
  }
  root.ISGWizard={create,sha256,canonical,utf8,version:VERSION};
})(globalThis);
