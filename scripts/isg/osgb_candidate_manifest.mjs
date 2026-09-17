#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const OSGB_CANDIDATE_MIGRATIONS=Object.freeze([
  '20260917090000_osgb_workspace_foundation.sql',
  '20260917091500_osgb_personal_backfill.sql',
  '20260917093000_osgb_company_assignments.sql',
  '20260917100000_osgb_seat_entitlements.sql',
  '20260917103000_osgb_wallet_usage_storage.sql',
  '20260917110000_osgb_handover_memory.sql',
  '20260917113000_osgb_provider_billing.sql',
  '20260917120000_osgb_admin_extension.sql',
  '20260917123000_osgb_ai_jobs.sql',
  '20260917130000_osgb_asset_transport.sql',
  '20260917133000_osgb_metrics.sql',
  '20260917134500_osgb_workspace_operations.sql',
  '20260917140000_osgb_purchase_intents.sql',
  '20260917141500_osgb_member_quotas.sql',
  '20260917143000_osgb_company_canonical_bridge.sql',
  '20260917144500_osgb_personnel_domain.sql',
  '20260917150000_osgb_training_domain.sql',
  '20260917151500_osgb_risk_nonconformity_domain.sql',
  '20260917153000_osgb_emergency_ppe_domain.sql',
  '20260917154500_osgb_equipment_domain.sql',
  '20260917160000_osgb_operations_domain.sql',
  '20260917161500_osgb_file_domain.sql',
  '20260917163000_osgb_analysis_export_domain.sql',
  '20260917164500_osgb_tracking_notification_domain.sql',
]);

export function buildCandidateManifest(){
  return {
    schema_version:1,
    status:'local_candidate_not_deployed',
    base_commit:'6eebab8946c627f42d13415cff1b8dc5007cc1ce',
    generated_for:'2026-09-17',
    safety:{workspace_rollout_default:'off',domain_rollout_default:'off',production_target:false},
    candidate_count:OSGB_CANDIDATE_MIGRATIONS.length,
    candidates:OSGB_CANDIDATE_MIGRATIONS.map((name,index)=>{
      const path=`supabase/pilot-release/candidates/${name}`;
      const bytes=readFileSync(resolve(ROOT,path));
      return {order:index+1,path,bytes:bytes.length,
        sha256:createHash('sha256').update(bytes).digest('hex')};
    }),
  };
}

export const MANIFEST_PATH=resolve(ROOT,'docs/isg/OSGB_CANDIDATE_MANIFEST_2026-09-17.json');
if(process.argv[1]===fileURLToPath(import.meta.url)){
  writeFileSync(MANIFEST_PATH,`${JSON.stringify(buildCandidateManifest(),null,2)}\n`);
  console.log(`WROTE ${MANIFEST_PATH}`);
}
