import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const swift = readFileSync('App/Services/ClientFlowEvents.swift', 'utf8');
const kotlin = readFileSync('android/core/data/src/main/kotlin/com/riskdetectedan/core/data/telemetry/ClientFlowEvents.kt', 'utf8');
const sql = readFileSync('supabase/migrations/20260908134026_client_flow_diagnostics.sql', 'utf8');
for (const [plural, singular] of [['stages','stage'], ['outcomes','outcome'], ['reasons','reason']]) {
  test(`${plural} match both clients and database`, () => {
    const values = text => [...text.matchAll(/"([a-z_]+)"/g)].map(m => m[1]).sort();
    const a = values(swift.match(new RegExp(`static let ${plural}: Set<String> = \\[([^\\]]+)\\]`))[1]);
    const b = values(kotlin.match(new RegExp(`val ${plural} = setOf\\(([^)]+)\\)`))[1]);
    const c = [...sql.match(new RegExp(`${singular} in \\(([^)]+)\\)`))[1].matchAll(/'([a-z_]+)'/g)].map(m => m[1]).sort();
    assert.deepEqual(a,b); assert.deepEqual(a,c);
  });
}
test('bounded durable queue, stable dedup and no advertising transport', () => {
  for (const source of [swift, kotlin]) {
    assert.match(source, /200/); assert.match(source, /86400/);
    assert.match(source, /client_event_id/); assert.match(source, /ignoreDuplicates/);
    assert.doesNotMatch(source, /MetaAppEvents|FBSDK|advertisingId|error\.message|localizedDescription/);
  }
});
test('billing guard allows dialog-hosted paywall, not window focus', () => {
  const billing = readFileSync('android/core/data/src/main/kotlin/com/riskdetectedan/core/data/billing/BillingRepository.kt', 'utf8');
  assert.match(billing, /Lifecycle.State.RESUMED/);
  assert.doesNotMatch(billing, /hasWindowFocus\(/);
});
