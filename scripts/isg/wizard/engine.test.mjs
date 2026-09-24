import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
const assets=path.join(root,'App/WizardAssets/isg_wizard');
vm.runInThisContext(fs.readFileSync(path.join(assets,'engine.js'),'utf8'));
vm.runInThisContext(fs.readFileSync(path.join(assets,'export.js'),'utf8'));
const catalog=JSON.parse(fs.readFileSync(path.join(assets,'isgada-catalog.json')));
const engine=ISGWizard.create(catalog);
const make=(a={},domain='risk')=>engine.generate(a,domain);
const ids=r=>new Set(r.rows.flatMap(x=>[x.id,...(x.catalog_alias_ids||[])]));
const cards=r=>new Set(r.cards.map(x=>x.id));
const profiles=JSON.parse(fs.readFileSync(path.join(root,'content/isg/wizard/tests/v4_profiles.json'))).profiles;
for(const profile of profiles) test('V4 accepted content preserved: '+profile.id,()=>{
 const a={...profile.answers};delete a.workplace_id;delete a.reuse;
 const r=make(a), chosen=ids(r),cc=cards(r);
 for(const id of profile.must_include)assert.ok(chosen.has(id),'missing '+id);
 for(const id of profile.must_exclude)assert.ok(!chosen.has(id),'unexpected '+id);
 for(const id of profile.must_cards)assert.ok(cc.has(id),'missing card '+id);
 for(const id of profile.must_not_cards)assert.ok(!cc.has(id),'unexpected card '+id);
 for(const family of profile.exclude_families)assert.ok(!r.rows.some(x=>x.family_id===family));
 assert.ok(r.rows.length<=profile.max_rows);assert.ok(r.summary_ids.length<=profile.max_summary);
});
test('hashes match platform crypto including Turkish and astral Unicode',()=>{
 for(const value of ['', 'abc','İSGADA şıĞ 😀','x'.repeat(130000)])assert.equal(ISGWizard.sha256(value),crypto.createHash('sha256').update(value).digest('hex'));
});
test('unscoped document succeeds without manufactured company, dates or scores',()=>{
 const r=make();assert.equal(r.answers.scope.company_id,null);assert.equal(r.answers.scope.workplace_id,null);
 assert.ok(r.rows.length>0);assert.ok(r.rows.every(x=>x.score===null&&x.current_state===null&&x.planned_residual===null));
 assert.equal(r.document_fields.valid_until,null);assert.equal(r.document_fields.assessment_on,null);assert.equal(r.document_fields.signatures,null);
 assert.equal(r.state,'editable_draft');assert.equal(r.requires_expert_approval,undefined);
});
test('company without any workplace can generate all documents',()=>{
 for(const domain of ['risk','emergency']){const r=make({scope:{company_id:'test-co',company_name:'Örnek firma'}},domain);assert.equal(r.answers.scope.workplace_id,null);assert.equal(r.answers.scope.company_name,'Örnek firma');}
});
test('scope cannot retain workplace after company is cleared',()=>{
 assert.throws(()=>make({scope:{workplace_id:'old-workplace'}}));
 assert.equal(make({scope:{company_name:'stale'}}).answers.scope.company_name,'');
 assert.equal(make({scope:{company_id:'co',workplace_name:'stale'}}).answers.scope.workplace_name,'');
});
test('explicit none, unknown and selected remain distinct',()=>{
 const unknown=make({equipment:[]}),none=make({equipment:{state:'none'}});
 assert.ok(unknown.unanswered_domains.includes('equipment'));assert.ok(!none.unanswered_domains.includes('equipment'));
 assert.throws(()=>make({equipment:{state:'none',ids:['E091']}}));
 assert.throws(()=>make({equipment:{state:'selected',ids:[]}}));
 assert.throws(()=>make({equipment:['does-not-exist']}));
 assert.throws(()=>make({equipment:Array(101).fill('E091')}));
});
test('extra context and approval inputs are rejected',()=>{
 for(const key of ['context','reuse','approved','assessed_scores','user_id'])assert.throws(()=>make({[key]:{}}));
});
test('permutation and duplicate selections give identical snapshots',()=>{
 assert.equal(make({hazards:['corrosives','compressed_gas','corrosives']}).content_sha256,make({hazards:['compressed_gas','corrosives']}).content_sha256);
});
test('each document is independent of earlier generation and caller mutation',()=>{
 const r=make({areas:['office']});const hash=r.content_sha256;r.rows[0].scenario_tr='changed';
 make({areas:['warehouse']});assert.equal(make({areas:['office']}).content_sha256,hash);
});
const scenarios=[
 ['hydraulic',{equipment:['E091']},'R-16-08'],
 ['vacuum',{equipment:['E128']},'R-16-07'],
 ['battery hydrogen',{processes:['gas_evolving_battery_charge']},'R-21-09'],
 ['tank entry',{processes:['tank_mixer']},'R-12-07'],
 ['acid dilution',{processes:['acid_dilution']},'R-18-08'],
 ['portable heater',{energy:['portable_heater']},'R-20-05'],
 ['solvent dryer',{processes:['solvent_dryer']},'R-21-08'],
 ['organic milling',{processes:['organic_dust_milling']},'R-21-10'],
 ['server gas',{emergency_systems:['server_gas_system']},'R-42-06'],
 ['ambient heat',{conditions:['hot_climate']},'R-23-13'],
 ['ammonia gas system',{energy:['ammonia','compressed_gas']},'R-17-06'],
];
for(const [name,a,id] of scenarios)test('specific reachable scenario: '+name,()=>assert.ok(ids(make({...a,preset:'comprehensive'})).has(id),id));
test('special cards and fallback cards are reachable',()=>{
 assert.ok(cards(make({processes:['switching_hv']})).has('AD-031'));
 assert.ok(cards(make({emergency_systems:['critical_automation']})).has('AD-072'));
 assert.ok(cards(make()).has('AD-040'));
 const cc=cards(make({hazards:['corrosives']}));assert.ok(cc.has('AD-021'));assert.ok(cc.has('AD-022'));
});
test('office excludes process alarms unless a critical process is declared',()=>{
 const r=make({sectors:['S172'],areas:['office']});assert.ok(!ids(r).has('R-26-10'));assert.ok(!ids(r).has('R-26-11'));
 assert.ok(ids(make({sectors:['S172'],emergency_systems:['process_alarm']})).has('R-26-10'));
 assert.equal(r.rows.find(x=>x.id==='R-24-06').suggested_owner_role_tr,'İşveren / işveren vekili');
});
test('tank equipment alone does not assume people enter it',()=>{
 assert.ok(!ids(make({equipment:['E141']})).has('R-12-07'));
});
test('conflicting negative hazard answer never hides declared hazards',()=>{
 const r=make({hazards:{state:'none'},energy:['compressed_gas']});assert.ok(r.input_conflicts.length);assert.ok(r.rows.some(x=>x.family_id==='G17'));
});
test('short package reserves a core evacuation item',()=>{
 for(const p of profiles){const a={...p.answers,preset:'sample'};delete a.workplace_id;delete a.reuse;const r=make(a);assert.ok(ids(r).has('R-49-01'));assert.equal(r.rows.length,5);}
});
test('unresolved scenarios and omitted severe risks survive into report text',()=>{
 const r=make({sectors:['S129'],hazards:['corrosives'],preset:'sample'}),text=JSON.stringify(engine.blocks(r));
 assert.ok(r.unresolved.length);assert.ok(r.omitted.some(x=>x.severe));
 for(const row of [...r.unresolved,...r.omitted]){assert.ok(text.includes(row.id));assert.ok(text.includes(row.title));}
});
test('question budget, reference integrity and reachable feature gates',()=>{
 assert.equal(engine.questions.length,13);assert.ok(engine.questions.every(x=>!x.required));
 const riskIDs=new Set(catalog.risk_catalog.map(x=>x.id)),cardIDs=new Set(catalog.cards.map(x=>x.id));
 const features=new Set(Object.values(catalog.options).flatMap(v=>Object.keys(v)));
 Object.values(catalog.taxonomy).flat().forEach(x=>{x.features.forEach(f=>features.add(f));x.risk_ids.forEach(id=>assert.ok(riskIDs.has(id),id));});
 Object.values(catalog.feature_implications).flat().forEach(f=>features.add(f));
 for(const r of catalog.risk_catalog)for(const clause of [r.requires_any_features,r.family_requires_any_features])assert.ok(!clause.length||clause.some(x=>features.has(x)),r.id);
 for(const [id,deps] of Object.entries(catalog.card_dependencies)){assert.ok(cardIDs.has(id));deps.forEach(d=>assert.ok(cardIDs.has(d)));}
 assert.equal(riskIDs.size,catalog.risk_catalog.length);assert.equal(cardIDs.size,catalog.cards.length);
});
test('feature cycles terminate',()=>{
 const b=structuredClone(catalog);b.feature_implications.hydraulic=['pressure'];b.feature_implications.pressure=['hydraulic'];
 assert.ok(ISGWizard.create(b).generate({energy:['hydraulic']},'risk').rows.length);
});
test('database hazard class vocabulary is retained in reference data',()=>{
 assert.deepEqual(Object.keys(catalog.numeric_reference_rules.support_divisors).sort(),['high','low','medium']);
 assert.equal(catalog.numeric_reference_rules.support_divisors.high,30);
});
test('snapshot contains stable engine, catalog and method profile provenance',()=>{
 const r=make();const copy={...r};delete copy.content_sha256;
 assert.equal(r.content_sha256,ISGWizard.sha256(ISGWizard.canonical(copy)));
 assert.equal(r.catalog_sha256,catalog.catalog_sha256);assert.equal(r.method_profile_id,catalog.methods.fk.id);
});
test('exports are deterministic real ZIP containers and include the exact snapshot',()=>{
 const r=make({areas:['office'],scope:{company_id:'a',company_name:'=1+1 <Şirket> & "Ortak"'}},'risk');
 for(const format of ['docx','xlsx']){
  const one=ISGWizard.exportFile(engine,r,format),two=ISGWizard.exportFile(engine,r,format);
  assert.equal(one.base64,two.base64);const bytes=Buffer.from(one.base64,'base64');assert.equal(bytes.readUInt32LE(0),0x04034b50);
  assert.ok(bytes.includes(Buffer.from(ISGWizard.canonical(r))));assert.ok(bytes.includes(Buffer.from('&lt;Şirket&gt;')));
  if(format==='xlsx'){assert.ok(bytes.includes(Buffer.from('t="inlineStr"')));assert.ok(!bytes.includes(Buffer.from('<f>')));}
 }
});

test('prototype names and malformed single values are not valid choices',()=>{
 for(const method of ['constructor','toString',{},[]])assert.throws(()=>make({method}));
 for(const preset of ['constructor','toString',{},[]])assert.throws(()=>make({preset}));
 assert.throws(()=>make({scope:'wrong'}));
});
