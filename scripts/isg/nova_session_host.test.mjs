import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';

const read = path => readFileSync(resolve(ROOT, path), 'utf8');
const fixture = JSON.parse(read('contracts/isg/v1/fixtures/nova-session-host.json'));
test('host corpus covers every destination across release readiness, availability and stale callbacks', () => {
  const catalog = JSON.parse(read('contracts/isg/v1/design/nova-navigation.json'));
  const ids = fixture.cases.map(c => c.id);
  assert.equal(new Set(ids).size, ids.length);
  assert.equal(ids.length, 88);
  for (const d of catalog.destinations) for (const variant of ['allowed','unimplemented','disabled','stale']) {
    assert.ok(ids.includes(`destination-${d.id}-${variant}`));
  }
  assert.equal(fixture.cases.reduce((n,c)=>n+c.steps.length,0),399);
  for (const c of fixture.cases) for (const s of c.steps) {
    assert.deepEqual(Object.keys(s.expected).sort(), ['available','current','epochChanged','overlay','pending','phase','value'].sort());
    if (s.expected.phase !== 'ready') {
      assert.equal(s.expected.current, 'home'); assert.equal(s.expected.overlay, null); assert.equal(s.expected.value, null);
      assert.deepEqual(s.expected.available, ['home','profile']);
    }
  }
});
test('host corpus includes retry, owner mismatch, logout, same-user new-session and ABA regressions', () => {
  const ids = new Set(fixture.cases.map(c=>c.id));
  for (const id of ['same-session-preserves-pending','token-refresh-preserves-navigation-and-value',
    'logout-clears-overlay-value-and-rejects-late-success','account-switch-rejects-old-request',
    'same-user-new-session-rejects-old-request','aba-account-cycle-never-reuses-epoch',
    'latest-refresh-wins-success','latest-refresh-wins-failure','duplicate-success-cannot-change-capabilities',
    'success-then-late-failure-is-ignored','failure-consumes-request-retry-required',
    'foreign-owner-fails-closed-and-consumes-request','revalidation-hides-old-value-and-resets-path',
    'revalidation-revokes-overlay-immediately','missing-parent-destination-is-not-openable',
    'unimplemented-parent-is-not-openable','signed-out-duplicate-does-not-churn-epoch',
    'logout-login-same-session-still-invalidates-value','old-ui-callback-cannot-reopen-after-refresh']) assert.ok(ids.has(id));
});
test('real host sources have no credential, network, billing or metadata-based grant dependency', () => {
  for (const path of ['App/DesignSystem/ISG/NovaSessionHost.swift',
    'android/core/designsystem/src/main/kotlin/com/riskdetectedan/core/designsystem/isg/NovaSessionHost.kt']) {
    const source = read(path);
    assert.doesNotMatch(source, /import (Supabase|RevenueCat)|URLSession|OkHttp|Purchases\.|user_metadata|access_token|refresh_token|UserDefaults|Keychain/);
    assert.match(source, /implemented/); assert.match(source, /sessionID/); assert.match(source, /scope/);
  }
});
test('native test hosts use current-state guards and CI/Gradle track the shared corpus', () => {
  const swift = read('tests/isg/shell-ios/ShellHarnessApp.swift');
  assert.match(swift, /sessionHost\.acceptNavigation\(\$0, from: epoch\)/);
  assert.match(swift, /sessionHost\.phase == \.ready/);
  assert.match(swift, /sessionHost\.value\(from: noticeSnapshot\)/);
  assert.match(swift, /sessionHost\.apply\(\.navigate\(\$0\), from: renderedEpoch\)/);
  const kotlin = read('android/isg-design-preview/src/main/kotlin/com/riskdetectedan/isg/designpreview/DesignPreviewActivity.kt');
  assert.match(kotlin, /host = host\.apply\(event, epoch\)/);
  assert.match(kotlin, /host\.value\(noticeSnapshot\)/);
  assert.match(read('android/core/designsystem/build.gradle.kts'), /isgNovaSessionHostCorpus/);
  assert.match(read('.github/workflows/isg-foundation.yml'), /NovaSessionHostCorpus.swift scripts\/isg\/NovaSessionHostCheck.swift/);
  assert.match(read('tests/isg/shell-ios/ShellUITests.swift'), /func testHostHidesContentDuringRefreshAndRejectsPreviousAccountResponse/);
});
