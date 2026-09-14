import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {ROOT} from './lib.mjs';
import {compileP05PilotBundle,p05PilotBundleSources} from './p05_pilot_bundle.mjs';
import {parseRestoreMode} from './restore_mode.mjs';
import {probeP05PilotUpgrade} from './p05_pilot_upgrade_probe.mjs';
const texts=()=>p05PilotBundleSources.map(p=>readFileSync(`${ROOT}/${p}`,'utf8'));
test('pilot-only upgrade requires the explicit isolated clone lane',()=>{
  assert.deepEqual(parseRestoreMode(['--isolated-copy','--p05-pilot-upgrade']),{storage:false,sessionGuard:false,synthetic:false,p05PilotUpgrade:true});
  assert.throws(()=>parseRestoreMode(['--p05-pilot-upgrade']),/EXPLICIT_MODE_REQUIRED/);
  assert.throws(()=>parseRestoreMode(['--isolated-copy','--p05-pilot-upgrade','--with-storage']),/EXPLICIT_MODE_REQUIRED/);
  let touched=false;assert.throws(()=>probeP05PilotUpgrade({isolatedCopy:false,sql(){touched=true;}}),/ISOLATED_REQUIRED/);assert.equal(touched,false);
});
test('pilot package contains exactly six P05 candidates in one closed transaction',()=>{
  const {sql,manifest}=compileP05PilotBundle();
  assert.equal(manifest.source_count,6);
  assert.equal((sql.match(/^BEGIN;$/gm)??[]).length,1);
  assert.equal((sql.match(/^COMMIT;$/gm)??[]).length,1);
  assert.doesNotMatch(sql,/^SELECT private_isg.ensure_default\(id\) FROM public.companies/gm);
  assert.match(sql,/DROP TRIGGER companies_isg_default ON public.companies/);
  assert.equal(manifest.account_seeded,false);
  assert.equal(manifest.deployment_authorized,false);
  assert.ok(!manifest.tables.includes('notification_jobs'));
  assert.equal(manifest.tables.length,18);
  assert.ok(manifest.tables.includes('p05_pilot_accounts')&&manifest.tables.includes('p05_pilot_grants')&&manifest.tables.includes('p05_pilot_company_origins'));
});
test('compiler is deterministic and refuses source or transaction drift',()=>{
  assert.deepEqual(compileP05PilotBundle(),compileP05PilotBundle());
  assert.throws(()=>compileP05PilotBundle([]),/SOURCE_COUNT/);
  const changed=texts();changed[0]=changed[0].replace('ORDER BY id;','ORDER BY id DESC;');
  assert.throws(()=>compileP05PilotBundle(changed),/BOOTSTRAP_DRIFT/);
  const boundary=texts();boundary[1]=boundary[1].replace('COMMIT;','');
  assert.throws(()=>compileP05PilotBundle(boundary),/TRANSACTION_DRIFT/);
});
