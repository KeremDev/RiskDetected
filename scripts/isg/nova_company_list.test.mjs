import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = path => readFileSync(new URL('../../' + path, import.meta.url), 'utf8');

test('company corpus covers scoped request, owner, archive and stale selection boundaries', () => {
  const corpus = JSON.parse(read('contracts/isg/v1/fixtures/nova-company-list.json'));
  const ids = corpus.cases.map(c => c.id);
  assert.equal(corpus.cases.length, 34);
  assert.equal(new Set(ids).size, ids.length);
  for (const id of ['foreign-fails-entire-response','duplicate-fails-entire-response','blank-fails-entire-response',
    'latest-success-wins','late-error-ignored','aba-rejects-old-completion','same-user-new-session-rejects-completion',
    'cancel-consumes-ticket','old-cancel-keeps-new-request','selection-previous-render-rejected',
    'filter-change-hides-loaded-rows-before-next-request','filter-change-rejects-old-selection']) assert.ok(ids.includes(id));
  for (const c of corpus.cases) assert.deepEqual(Object.keys(c.expected).sort(), ['pending','phase','rows','selected']);
});

test('company source and design layers remain separated from production roots and credentials', () => {
  for (const path of ['App/DesignSystem/ISG/NovaCompanyListState.swift','App/DesignSystem/ISG/NovaCompanyDestination.swift',
    'android/core/designsystem/src/main/kotlin/com/riskdetectedan/core/designsystem/isg/NovaCompanyListState.kt',
    'android/core/designsystem/src/main/kotlin/com/riskdetectedan/core/designsystem/isg/NovaCompanyDestination.kt']) {
    const source = read(path);
    assert.doesNotMatch(source, /import (Supabase|RevenueCat)|https?:|access_token|refresh_token|UserDefaults|Keychain|user_metadata/);
    assert.match(source, /includeArchived/);
  }
  assert.match(read('App/Services/Company/NovaCompanyServiceAdapter.swift'), /CompanyService.shared.listCompanies\(includeArchived: includeArchived\)/);
  assert.match(read('android/feature/profile/src/main/kotlin/com/riskdetectedan/feature/profile/NovaCompanyRepositoryAdapter.kt'), /listCompanies\(includeArchived\)/);
});

test('UI awaits use current state, safe failures and lifecycle cancellation', () => {
  const swift = read('App/DesignSystem/ISG/NovaCompanyDestination.swift');
  assert.match(swift, /@Binding var host/);
  assert.match(swift, /\.task\(id: LoadKey/);
  assert.match(swift, /\.id\(epoch\)/);
  assert.match(swift, /try Task.checkCancellation\(\)/);
  assert.match(swift, /state.complete\(ticket, rows: rows, host: host\)/);
  const kotlin = read('android/core/designsystem/src/main/kotlin/com/riskdetectedan/core/designsystem/isg/NovaCompanyDestination.kt');
  assert.match(kotlin, /rememberUpdatedState\(host\)/);
  assert.match(kotlin, /key\(epoch\)/);
  assert.match(kotlin, /state.complete\(ticket, rows, currentHost\)/);
  assert.match(kotlin, /currentCoroutineContext\(\).ensureActive\(\)/);
  assert.doesNotMatch(swift + kotlin, /error.localizedDescription|error.message|\.printStackTrace\(/);
});

test('CI and both native harnesses track the actual company corpus and screen', () => {
  assert.match(read('.github/workflows/isg-foundation.yml'), /NovaCompanyListCheck.swift/);
  assert.match(read('android/core/designsystem/build.gradle.kts'), /isgNovaCompanyListCorpus/);
  assert.match(read('tests/isg/shell-ios/project.yml'), /NovaCompanyDestination.swift/);
  assert.match(read('tests/isg/shell-ios/ShellUITests.swift'), /testOwnedCompanyLoaderReplacesPreviousAccountRows/);
  assert.match(read('android/core/designsystem/src/test/kotlin/com/riskdetectedan/core/designsystem/isg/NovaCompanyDestinationTest.kt'), /ProviderIgnoresCancellation/);
});
