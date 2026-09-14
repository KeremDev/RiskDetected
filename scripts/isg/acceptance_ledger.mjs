import {readFileSync,writeFileSync,readdirSync,existsSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {ROOT} from './lib.mjs';
import {buildTestManifest} from './build_test_manifest.mjs';
import {createHash} from 'node:crypto';

const LAYERS_PATH='docs/isg/acceptance/layer-evidence.json';
const REGISTRY_PATH='docs/isg/V5_ACCEPTANCE_TEST_REGISTRY.csv';
const REPORT_PATH='docs/isg/acceptance/coverage-report.json';
const EVIDENCE_DIR='docs/isg/evidence';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');

// A legacy short-id claim remains useful inventory, but never proves a case.
// A successful run must itself bind exact scenario + layer + executed checks,
// and fingerprint every source dependency declared by the binding.
export function verifyScenarioEvidence({caseID,requiredLayers,bindings,readArtifact,hashSource}){
  const verified=new Set(), failures=[];
  for(const binding of bindings.filter(b=>b.case_id===caseID)){
    try {
      if(!requiredLayers.includes(binding.layer))throw Error('UNRELATED_LAYER');
      if(!Array.isArray(binding.check_ids)||binding.check_ids.length===0 ||
         new Set(binding.check_ids).size!==binding.check_ids.length)throw Error('MISSING_CHECKS');
      if(!Array.isArray(binding.required_sources)||binding.required_sources.length===0)throw Error('MISSING_SOURCES');
      const artifact=readArtifact(binding.evidence_file);
      if(artifact.ok!==true)throw Error('RUN_NOT_PASS');
      const checks=artifact.checks??[];
      if(binding.check_ids.some(id=>checks.filter(c=>c.id===id).length!==1 ||
          checks.find(c=>c.id===id)?.result!=='PASS'))throw Error('CHECK_NOT_PASS');
      const proof=(artifact.acceptance_checks??[]).find(p=>p.case_id===caseID&&p.layer===binding.layer&&
        binding.check_ids.every(id=>p.check_ids?.includes(id)));
      if(!proof)throw Error('NO_SCENARIO_PROOF');
      for(const path of new Set([...binding.required_sources,...Object.keys(artifact.source_sha256??{})])){
        const expected=artifact.source_sha256?.[path];
        if(!expected||expected!==hashSource(path))throw Error('STALE_SOURCE');
      }
      verified.add(binding.layer);
    }catch(error){ failures.push({layer:binding.layer,evidence_file:binding.evidence_file,reason:error.message}); }
  }
  return {verified_layers:[...verified].sort(),missing_layers:requiredLayers.filter(l=>!verified.has(l)),failures};
}

function safeEvidencePath(path){
  if(typeof path!=='string'||path.startsWith('/')||path.split(/[\\/]/).includes('..'))throw Error('INVALID_EVIDENCE_PATH');
  return resolve(ROOT,path);
}

function parseCSV(text){
  const rows=[];let row=[],field='',quoted=false;
  for(let i=0;i<text.length;i++){
    const c=text[i];
    if(quoted){ if(c==='"'){ if(text[i+1]==='"'){field+='"';i++;} else quoted=false; } else field+=c; }
    else if(c==='"')quoted=true;
    else if(c===','){row.push(field);field='';}
    else if(c==='\n'){row.push(field);rows.push(row);row=[];field='';}
    else if(c!=='\r')field+=c;
  }
  if(field||row.length){row.push(field);rows.push(row);}
  const head=rows.shift();
  return {head,rows:rows.filter(r=>r.length===head.length).map(r=>Object.fromEntries(head.map((h,i)=>[h,r[i]])))};
}
function renderCSV(head,rows){
  const cell=v=>'"'+String(v??'').replaceAll('"','""')+'"';
  return [head.map(cell).join(',')].concat(rows.map(r=>head.map(h=>cell(r[h])).join(','))).join('\n')+'\n';
}

// Every acceptance id any phase has claimed, taken from the evidence files
// themselves so a claim cannot exist without an artefact behind it.
export function collectClaims(){
  const claims=new Map();
  for(const name of readdirSync(resolve(ROOT,EVIDENCE_DIR)).sort()){
    if(!name.endsWith('.json'))continue;
    let parsed; try{parsed=JSON.parse(read(join(EVIDENCE_DIR,name)));}catch{continue;}
    const ids=parsed.acceptance_ids_covered;
    if(!Array.isArray(ids))continue;
    for(const raw of ids){
      const id=String(raw).replace(/\s*\(.*\)$/,'').trim();
      if(!claims.has(id))claims.set(id,[]);
      claims.get(id).push(join(EVIDENCE_DIR,name));
    }
  }
  return claims;
}

// A transition scenario names the phase and the method, not a layer list; the
// phase it belongs to decides which layers must answer for it.
const TRANSITION_LAYERS={
  P00:['STORAGE','DB'],P01:['DB','FAULT_INJECTION'],P02:['AUTH','NATIVE_E2E'],P03:['DB','CONCURRENCY'],
  P04:['FILE_SECURITY','NATIVE_E2E'],P05:['DOMAIN','DB','NATIVE_E2E'],P06:['DOMAIN','DB'],P07:['DOMAIN','DB'],
  P08:['DOMAIN','DB'],P09:['DOMAIN','DB'],P10:['DOMAIN','DB'],P11:['IMPORT','DOCUMENT','DB'],
  P12:['NOTIFICATION','NATIVE_E2E'],P13:['NOTES','REMINDER','DB'],P14:['BILLING','STORE_QA','DB'],
  P15:['CAMPAIGN','DB','STORE_QA'],P16:['OBSERVABILITY','ADMIN','NETWORK_PRIVACY'],P17:['DOMAIN','DB'],
  P18:['DESIGN','NATIVE_E2E'],P19:['CROSS_LAYER_ACCEPTANCE'],P20:['STORE_QA'],P21:['OPERATIONS'],
};
function transitionLayers(expected){
  const phases=[...String(expected).matchAll(/P(\d\d)/g)].map(m=>'P'+m[1]);
  const layers=new Set();
  for(const phase of phases) for(const layer of TRANSITION_LAYERS[phase]??[]) layers.add(layer);
  if(layers.size===0)layers.add('CROSS_LAYER_ACCEPTANCE');
  return [...layers].sort();
}

export function buildLedger(){
  const layers=JSON.parse(read(LAYERS_PATH)).layers;
  const manifest=buildTestManifest(ROOT);
  const registry=parseCSV(read(REGISTRY_PATH));
  const claims=collectClaims();
  const bindings=JSON.parse(read('docs/isg/acceptance/scenario-evidence.json')).bindings;
  const problems=[];

  for(const [name,entry] of Object.entries(layers)){
    if(!['full','partial','none'].includes(entry.status))problems.push(`layer ${name} has an unknown status`);
    if(entry.status==='none'&&entry.evidence.length>0)problems.push(`layer ${name} says none but lists evidence`);
    if(entry.status!=='none'&&entry.evidence.length===0)problems.push(`layer ${name} claims evidence it does not list`);
    if(entry.status!=='full'&&!entry.blocker)problems.push(`layer ${name} is not full and names no blocker`);
    for(const file of entry.evidence){
      if(!existsSync(resolve(ROOT,file)))problems.push(`layer ${name} points at missing evidence ${file}`);
    }
  }

  // DEL-01 exists under two different plan sections, so the section has to stay
  // part of the key; collapsing to the bare test id loses a real acceptance row.
  const rowsByKey=new Map(registry.rows.map(row=>[`${row.source_section}:${row.source_test_id}`,row]));
  const cases=[];
  for(const entry of manifest.cases){
    const isTransition=entry.kind==='transition';
    const id=entry.id;
    const short=isTransition?entry.id.replace('TRANSITION:',''):entry.id.split(':').at(-1);
    const source=isTransition?null:rowsByKey.get(entry.id.replace(/^V5:/,''));
    const required=isTransition?transitionLayers(entry.expected+' '+(entry.scenario??''))
      :(source?.planned_layers??'').split('+').filter(Boolean);
    if(required.length===0)problems.push(`${id} has no required layer`);
    const unknown=required.filter(layer=>!layers[layer]);
    if(unknown.length)problems.push(`${id} requires unknown layer(s) ${unknown.join(',')}`);
    const blocking=required.filter(layer=>layers[layer]?.status!=='full');
    const sameShort=manifest.cases.filter(c=>(c.kind==='transition'?c.id.replace('TRANSITION:',''):c.id.split(':').at(-1))===short);
    const claimed=claims.get(id)??(sameShort.length===1?claims.get(short)??[]:[]);
    const proof=verifyScenarioEvidence({caseID:id,requiredLayers:required,bindings,
      readArtifact:path=>JSON.parse(readFileSync(safeEvidencePath(path),'utf8')),
      hashSource:path=>createHash('sha256').update(readFileSync(safeEvidencePath(path))).digest('hex')});
    let status;
    if(proof.missing_layers.length===0&&blocking.length===0)status='covered';
    else if(claimed.length)status='partial';
    else if(blocking.some(layer=>layers[layer]?.status==='none'))status='blocked';
    else status='unclaimed';
    const reason=status==='covered'?'every required layer has current, passing, scenario-bound evidence'
      :status==='partial'?'claimed, but current scenario-bound proof or required layer coverage is incomplete'
      :status==='blocked'?'a required layer has produced nothing at all'
      :'the required layers have evidence, but no phase has mapped this scenario to a named check';
    cases.push({id,short,kind:isTransition?'transition':'source',required_layers:required,
      blocking_layers:blocking,claimed_by:claimed,verified_layers:proof.verified_layers,
      missing_proof_layers:proof.missing_layers,evidence_failures:proof.failures,status,reason});
  }

  const counts=cases.reduce((acc,entry)=>{acc[entry.status]=(acc[entry.status]??0)+1;return acc;},{});
  const covered=counts.covered??0;
  // A release claim needs every single case covered; nothing here may round up.
  const releaseReady=covered===cases.length&&problems.length===0;
  return {schema_version:1,generated_for:'P19',total:cases.length,
    source_count:manifest.source_count,transition_count:manifest.transition_count,
    counts:{covered,partial:counts.partial??0,blocked:counts.blocked??0,unclaimed:counts.unclaimed??0},
    release_ready:releaseReady,
    blocking_layers:Object.entries(layers).filter(([,e])=>e.status!=='full')
      .map(([name,e])=>({layer:name,status:e.status,blocker:e.blocker})).sort((a,b)=>a.layer.localeCompare(b.layer)),
    problems,cases,registry:{head:registry.head,rows:registry.rows}};
}

export function statusesFor(ledger){
  const byId=new Map(ledger.cases.map(entry=>[`${entry.id}`,entry]));
  return {byId};
}

if(process.argv[1]&&process.argv[1].endsWith('acceptance_ledger.mjs')){
  const ledger=buildLedger();
  const {byId}=statusesFor(ledger);
  if(process.argv.includes('--write')){
    for(const row of ledger.registry.rows){
      const entry=byId.get(`V5:${row.source_section}:${row.source_test_id}`);
      if(!entry)continue;
      row.implementation_status=entry.status==='covered'?'IMPLEMENTED'
        :entry.status==='partial'?'PARTIAL':entry.status==='blocked'?'BLOCKED':'UNCLAIMED';
      row.execution_status=entry.status==='covered'?'RUN'
        :entry.status==='partial'?'PARTIAL_RUN':'NOT_RUN';
    }
    writeFileSync(resolve(ROOT,REGISTRY_PATH),renderCSV(ledger.registry.head,ledger.registry.rows));
    const {registry,...report}=ledger;
    writeFileSync(resolve(ROOT,REPORT_PATH),JSON.stringify(report,null,2)+'\n');
  }
  if(ledger.problems.length){
    console.error('Acceptance ledger is inconsistent:');
    for(const problem of ledger.problems.slice(0,20))console.error('- '+problem);
    process.exit(1);
  }
  console.log(`Acceptance ledger: ${ledger.total} cases (${ledger.source_count} source, ${ledger.transition_count} transition); `+
    `covered=${ledger.counts.covered}, partial=${ledger.counts.partial}, blocked=${ledger.counts.blocked}, `+
    `unclaimed=${ledger.counts.unclaimed}; release_ready=${ledger.release_ready}.`);
}
