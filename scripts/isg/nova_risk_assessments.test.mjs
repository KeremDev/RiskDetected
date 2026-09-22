import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const models=read('App/DesignSystem/ISG/NovaRiskAssessments.swift');
const screens=read('App/DesignSystem/ISG/NovaRiskScreens.swift');
const sheets=read('App/DesignSystem/ISG/NovaRiskSheets.swift');
const service=read('App/Services/Company/NovaRiskAssessmentService.swift');
const adapter=read('App/Services/Company/NovaRiskAssessmentLiveAdapter.swift');
const gate=read('App/Views/Components/NovaPilotRiskGate.swift');
const navigation=read('App/DesignSystem/ISG/NovaNavigation.swift');
const main=read('App/Views/Components/NovaPilotMainGate.swift');

test('the design layer never imports the SDK',()=>{
  for(const source of [models,screens,sheets]) assert.doesNotMatch(source,/^import Supabase$/m);
  // Only the live adapter knows the SDK exists.
  assert.match(adapter,/^import Supabase$/m);
});

test('the five states and four counters agree with the server words',()=>{
  const states=[...models.matchAll(/case ([a-zA-Z]+)(?: = "([a-z_]+)")?\n/g)];
  assert.ok(models.includes('case neverAssessed = "never_assessed"'));
  assert.ok(models.includes('case periodUnknown = "period_unknown"'));
  assert.ok(models.includes('case dueSoon = "due_soon"'));
  assert.ok(states.length>0);
  // Every state lands in exactly one group.
  const groups=models.match(/var states: \[NovaRiskState\] \{[\s\S]*?\n    \}/)[0];
  for(const state of ['neverAssessed','periodUnknown','expired','dueSoon','valid']){
    assert.ok(groups.includes(`.${state}`),state);
  }
});

test('every state carries a reason, so no row is a colour with no explanation',()=>{
  const explain=models.match(/static func explain\(_ row: NovaRiskRow\) -> String \{[\s\S]*?\n    \}/)[0];
  for(const state of ['neverAssessed','periodUnknown','expired','dueSoon','valid']){
    assert.ok(explain.includes(`case .${state}`),state);
  }
});

test('only a renewal may carry an assessment date, on both sides',()=>{
  assert.match(models,/var carriesAssessmentDate: Bool \{ self == \.full \}/);
  // The form does not offer the field for the other kinds.
  assert.match(sheets,/if draft\.kind\.carriesAssessmentDate \{/);
  // And the service does not send it for them either.
  assert.match(service,/if draft\.kind\.carriesAssessmentDate, NovaDayField\.date\(draft\.assessmentOn\) != nil \{/);
});

test('the verification is the signed-in expert and the client has no field for it',()=>{
  assert.doesNotMatch(service,/verified_by/);
  assert.doesNotMatch(sheets,/verified_by/);
  assert.match(sheets,/Doğrulama sizin beyanınızdır/);
});

test('a period the expert set is labelled as the expert",s everywhere it shows'.replace('",s',"'s"),()=>{
  assert.match(models,/case unapprovedFixture = "unapproved_fixture"/);
  assert.match(models,/fallback: "Uzman tarafından belirlenen"/);
  assert.match(models,/var needsReview: Bool \{ self == \.unapprovedFixture \}/);
  // Said once at the top of the board, and again beside the period itself.
  assert.match(screens,/NovaRiskWords\.periodAttribution/);
  assert.match(sheets,/mevzuat gereği olarak sunulmaz/);
});

test('the board never presents an analysis as an assessment',()=>{
  assert.match(models,/analysisNotAssessment/);
  assert.match(sheets,/NovaRiskWords\.analysisNotAssessment/);
});

test('a draft is shown beside the state, never as the state',()=>{
  assert.match(models,/let hasOpenDraft: Bool/);
  // The state enum has no draft case at all.
  assert.doesNotMatch(models,/case draftOpen/);
  assert.match(sheets,/Taslak belge değildir/);
});

test('the filters are side by side and the list opens below',()=>{
  // Two buttons in one row, then the panel for whichever was tapped, below.
  const row=screens.match(/HStack\(spacing: 8\) \{[\s\S]*?\n            \}/)[0];
  assert.equal((row.match(/NovaFileChooserButton/g)||[]).length,2);
  assert.match(screens,/if openChooser == "company" \{[\s\S]{0,200}NovaFileChooserPanel/);
  assert.match(screens,/if openChooser == "state" \{[\s\S]{0,200}NovaFileChooserPanel/);
});

test('every server refusal has its own sentence',()=>{
  const cases=[...adapter.matchAll(/case "([A-Z_]+)"[^:]*: throw NovaRiskFailure\.([a-zA-Z]+)/g)];
  const named=new Set(cases.map(m=>m[2]));
  for(const failure of ['dateInFuture','dateImmutable','draftOpen','versionFinalized','ruleNeedsReview']){
    assert.ok(named.has(failure),failure);
  }
  const messages=models.match(/var message: String \{[\s\S]*?\n    \}/)[0];
  for(const failure of named) assert.ok(messages.includes(`case .${failure}`),failure);
});

test('the route exists, is reachable and is wired to the real gate',()=>{
  assert.match(navigation,/case riskAssessments/);
  assert.match(navigation,/case \.riskAssessments: return RDLocalization\.string\("localizable\.nova\.navigation\.risk\.assessments"/);
  assert.match(navigation,/static let drawer: \[Self\] = \[[^\]]*\.riskAssessments/);
  assert.match(main,/case \.riskAssessments:\n\s+risk/);
  assert.match(adapter,/NovaExpertTransport\.shared\.capture\(\)/);
  assert.match(gate,/NovaPilotRiskGate/);
  assert.match(gate,/NovaRiskScreen\(client: client/);
});
