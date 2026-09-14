import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {ROOT} from './lib.mjs';
export const p05PilotBundleSources=[
  'supabase/migrations/20260913074153_isg_personnel_owner_rpc.sql',
  'supabase/migrations/20260913081536_isg_workplace_context_assignments.sql',
  'supabase/migrations/20260913084736_isg_workspace_availability.sql',
  'supabase/migrations/20260913092642_isg_personnel_reactivation.sql',
  'supabase/migrations/20260913191226_isg_p05_readonly_pilot.sql',
  'supabase/migrations/20260913193231_isg_p05_account_pilot_creation.sql',
];
const sha=s=>createHash('sha256').update(s).digest('hex');
// Compiler only: no credentials, networking, SQL execution or output writes.
// The one reviewed bootstrap omission is explicit; any format drift fails closed.
export function compileP05PilotBundle(texts=p05PilotBundleSources.map(p=>readFileSync(`${ROOT}/${p}`,'utf8'))) {
  if(!Array.isArray(texts)||texts.length!==p05PilotBundleSources.length)throw Error('PILOT_BUNDLE_SOURCE_COUNT');
  const source_sha256=Object.fromEntries(texts.map((s,i)=>[p05PilotBundleSources[i],sha(s)]));
  const bootstrap='SELECT private_isg.ensure_default(id) FROM public.companies ORDER BY id;';
  const bodies=texts.map((source,i)=>{
    if((source.match(/^BEGIN;$/gm)??[]).length!==1||(source.match(/^COMMIT;$/gm)??[]).length!==1)throw Error('PILOT_BUNDLE_TRANSACTION_DRIFT');
    if(i===0){if(source.split(bootstrap).length!==2)throw Error('PILOT_BUNDLE_BOOTSTRAP_DRIFT');source=source.replace(bootstrap,'-- Pilot package: do not bootstrap any existing company.');}
    return `-- Source: ${p05PilotBundleSources[i]}\n`+source.replace(/^BEGIN;$/m,'').replace(/^COMMIT;$/m,'');
  });
  const sql='-- REVIEW CANDIDATE. No deployment authorization. All accounts/flags remain closed.\nBEGIN;\n'+bodies.join('\n')+'\nCOMMIT;\n';
  const tables=[...new Set(texts.flatMap(s=>[...s.matchAll(/CREATE TABLE private_isg\.([a-z_][a-z0-9_]*)/g)].map(m=>m[1])))].sort();
  return{sql,manifest:{schema_version:1,source_sha256,bundle_sha256:sha(sql),source_count:texts.length,tables,
    reviewed_transforms:['Remove per-source transaction boundaries; wrap all six candidates in one transaction','Omit first candidate global ensure_default backfill; last candidate drops the new ISG global company insert trigger'],
    production_changed:false,deployment_authorized:false,account_seeded:false,rollout_enabled:false}};
}
