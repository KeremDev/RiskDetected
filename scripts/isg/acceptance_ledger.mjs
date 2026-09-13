import {readFileSync,writeFileSync,readdirSync,existsSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {ROOT} from './lib.mjs';
import {buildTestManifest} from './build_test_manifest.mjs';

const LAYERS_PATH='docs/isg/acceptance/layer-evidence.json';
const REGISTRY_PATH='docs/isg/V5_ACCEPTANCE_TEST_REGISTRY.csv';
const REPORT_PATH='docs/isg/acceptance/coverage-report.json';
const EVIDENCE_DIR='docs/isg/evidence';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');

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
    const claimed=claims.get(short)??[];
    let status;
    if(claimed.length&&blocking.length===0)status='covered';
    else if(claimed.length)status='partial';
    else if(blocking.some(layer=>layers[layer]?.status==='none'))status='blocked';
    else status='unclaimed';
    const reason=status==='covered'?'every required layer is full and a phase claimed it'
      :status==='partial'?'claimed, but a required layer is not full yet'
      :status==='blocked'?'a required layer has produced nothing at all'
      :'the required layers have evidence, but no phase has mapped this scenario to a named check';
    cases.push({id,short,kind:isTransition?'transition':'source',required_layers:required,
      blocking_layers:blocking,claimed_by:claimed,status,reason});
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
