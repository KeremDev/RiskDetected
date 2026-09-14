import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const models=read('App/DesignSystem/ISG/NovaEmergencyPlans.swift');
const screens=read('App/DesignSystem/ISG/NovaEmergencyPlanScreens.swift');
const sheets=read('App/DesignSystem/ISG/NovaEmergencyPlanSheets.swift');
const service=read('App/Services/Company/NovaEmergencyPlanService.swift');
const adapter=read('App/Services/Company/NovaEmergencyPlanLiveAdapter.swift');
const gate=read('App/Views/Components/NovaPilotEmergencyGate.swift');
const navigation=read('App/DesignSystem/ISG/NovaNavigation.swift');
const main=read('App/Views/Components/NovaPilotMainGate.swift');

test('the design layer never imports the SDK',()=>{
  for(const source of [models,screens,sheets]) assert.doesNotMatch(source,/^import Supabase$/m);
  assert.match(adapter,/^import Supabase$/m);
});

test('the client sends only the three keys the snapshot check accepts',()=>{
  const build=service.match(/"team": \.array\([\s\S]*?\}\)\]/)[0];
  assert.match(build,/"full_name": \.string\(member\.fullName\), "role": \.string\(member\.role\.rawValue\)/);
  assert.match(build,/entry\["contact"\] = \.string\(contact\)/);
  assert.doesNotMatch(build,/tckn|identity|employee_id/i);
});

test('only the roles the schema knows are offered',()=>{
  assert.match(models,/case coordinator, fire, other/);
  assert.match(models,/case firstAid = "first_aid"/);
  // The form prefers what the catalogue returned over the local list.
  assert.match(sheets,/catalogue\?\.roles \?\? NovaEmergencyRole\.allCases/);
});

test('publishing is the only write on this side too',()=>{
  const calls=[...service.matchAll(/"p_action": \.string\("([a-z_]+)"\)/g)].map(m=>m[1]);
  assert.deepEqual([...new Set(calls)],['publish_plan']);
  // There is no edit sheet, only a publish one.
  assert.doesNotMatch(sheets,/struct NovaEmergencyEditSheet/);
});

test('a renewal keeps the plan it renews and says what it does',()=>{
  assert.match(models,/var isRenewal: Bool \{ planID != nil \}/);
  assert.match(models,/static let renewalNote/);
  assert.match(sheets,/if draft\.isRenewal \{\n\s+NovaHelpHint\(text: NovaEmergencyWords\.renewalNote\)/);
  // The workplace of a renewal is shown rather than offered.
  assert.match(sheets,/if draft\.isRenewal \{\n\s+NovaText\(text: workplaceTitle, style: \.label\)/);
});

test('the review flag is explained and has no control',()=>{
  assert.match(models,/static let reviewNote/);
  assert.match(models,/elle kaldırılamaz/);
  // The flag is read back, never sent: nothing the client builds carries it.
  const publish=service.match(/func publish\([\s\S]*?\n    \}/)[0];
  assert.doesNotMatch(publish,/needs_review/);
  assert.doesNotMatch(sheets,/needsReview = /);
});

test('the date is attributed to the expert wherever it is shown',()=>{
  assert.match(models,/static let periodAttribution/);
  assert.match(screens,/NovaEmergencyWords\.periodAttribution/);
  assert.match(sheets,/NovaEmergencyWords\.periodAttribution/);
});

test('every state carries a reason, so no row is a colour with no explanation',()=>{
  const explain=models.match(/static func explain\(_ plan: NovaEmergencyPlan\) -> String \{[\s\S]*?\n    \}/)[0];
  for(const state of ['neverPublished','periodUnknown','expired','dueSoon','valid']){
    assert.ok(explain.includes(`case .${state}`),state);
  }
});

test('the two switches fail differently on this side as well',()=>{
  assert.match(adapter,/case "FEATURE_UNAVAILABLE": throw NovaEmergencyFailure\.featureUnavailable/);
  assert.match(adapter,/case "MODULE_UNAVAILABLE": throw NovaEmergencyFailure\.moduleUnavailable/);
  const messages=models.match(/var message: String \{[\s\S]*?\n    \}/)[0];
  assert.ok(messages.includes('case .featureUnavailable'));
  assert.ok(messages.includes('case .moduleUnavailable'));
});

test('every server refusal has its own sentence',()=>{
  const cases=[...adapter.matchAll(/case "([A-Z_]+)"[^:]*: throw NovaEmergencyFailure\.([a-zA-Z]+)/g)];
  const named=new Set(cases.map(m=>m[2]));
  for(const failure of ['preparedInFuture','roleUnknown']) assert.ok(named.has(failure),failure);
  const messages=models.match(/var message: String \{[\s\S]*?\n    \}/)[0];
  for(const failure of named) assert.ok(messages.includes(`case .${failure}`),failure);
});

test('the history shows every version with its own team',()=>{
  assert.match(models,/struct NovaEmergencyVersion[\s\S]{0,400}let team: \[NovaEmergencyMember\]/);
  assert.match(sheets,/localizable\.nova\.emergency\.detail\.versionteam/);
});

test('the filters are side by side and the list opens below',()=>{
  const row=screens.match(/HStack\(spacing: 8\) \{[\s\S]*?\n            \}/)[0];
  assert.equal((row.match(/NovaFileChooserButton/g)||[]).length,2);
  assert.match(screens,/if openChooser == "company" \{[\s\S]{0,200}NovaFileChooserPanel/);
  assert.match(screens,/if openChooser == "state" \{[\s\S]{0,200}NovaFileChooserPanel/);
});

test('the route exists, is reachable and is wired to the real gate',()=>{
  assert.match(navigation,/case emergencyPlans/);
  assert.match(navigation,/case \.emergencyPlans: return RDLocalization\.string\("localizable\.nova\.navigation\.emergency\.plans"/);
  assert.match(navigation,/static let drawer: \[Self\] = \[[^\]]*\.emergencyPlans/);
  assert.match(main,/case \.emergencyPlans:\n\s+emergencyPlans/);
  assert.match(gate,/NovaEmergencyPlanScreen\(client: client/);
});
