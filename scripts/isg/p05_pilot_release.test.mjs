import test from 'node:test';
import assert from 'node:assert/strict';
import {compileP05PilotRelease} from './p05_pilot_release.mjs';
test('approved release keeps six-source closed scope, transactional transport and stricter timeouts', () => {
  const {sql, manifest} = compileP05PilotRelease();
  assert.equal(manifest.source_count, 6);
  assert.equal(manifest.tables.length, 18);
  assert.equal(manifest.activation_included, false);
  assert.doesNotMatch(sql, /^BEGIN;|^COMMIT;/m);
  assert.doesNotMatch(sql, /lock_timeout\s*=\s*'5s'|statement_timeout='30s'/);
  assert.match(sql, /PILOT_RELEASE_BASELINE_CHANGED/);
  assert.match(sql, /PILOT_RELEASE_POSTFLIGHT_FAILED/);
  assert.doesNotMatch(sql, /SELECT private_isg.ensure_default\(id\) FROM public.companies/);
  assert.doesNotMatch(sql, /INSERT INTO private_isg.p05_pilot_accounts/);
  assert.equal(compileP05PilotRelease().manifest.release_sha256, manifest.release_sha256);
});
