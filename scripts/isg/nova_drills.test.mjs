import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const models=read('App/DesignSystem/ISG/NovaDrills.swift');
const screens=read('App/DesignSystem/ISG/NovaDrillScreens.swift');
const sheets=read('App/DesignSystem/ISG/NovaDrillSheets.swift');
const service=read('App/Services/Company/NovaDrillService.swift');
const adapter=read('App/Services/Company/NovaDrillLiveAdapter.swift');
const gate=read('App/Views/Components/NovaPilotDrillGate.swift');
const navigation=read('App/DesignSystem/ISG/NovaNavigation.swift');
const main=read('App/Views/Components/NovaPilotMainGate.swift');

test('the design layer never imports the SDK',()=>{
  for(const source of [models,screens,sheets]) assert.doesNotMatch(source,/^import Supabase$/m);
  assert.match(adapter,/^import Supabase$/m);
});

test('performed is read from the record, never from a date',()=>{
  assert.match(models,/let performed: Bool/);
  // The row card and the detail both go through the record's own flag.
  assert.match(sheets,/if drill\.performed \{ outcome \}/);
  assert.match(sheets,/if canWrite && !drill\.performed && drill\.state != \.cancelled \{ actions \}/);
  assert.match(models,/static let planningIsNotPerforming/);
  assert.match(screens,/NovaDrillWords\.planningIsNotPerforming/);
});

test('the client never sends a plan version',()=>{
  // It is read back, never sent: the planning payload carries only the plan.
  const planning=service.match(/func plan\(_ identity[\s\S]*?\n    \}/)[0];
  assert.doesNotMatch(planning,/plan_version/);
  assert.match(planning,/"plan_id": \.id\(plan\), "planned_on": \.string\(draft\.plannedOn\)/);
  assert.match(models,/let planVersion: Int/);
  // The form shows the version as a fact rather than offering it.
  assert.match(sheets,/localizable\.nova\.drill\.form\.version/);
  assert.match(models,/static let pinnedNote/);
});

test('participants are picked from the register and said to be frozen',()=>{
  assert.match(models,/let participantsSnapshotted: Bool/);
  assert.match(models,/static let snapshotNote/);
  // Said on the form where they are chosen and again where they are shown.
  assert.equal((sheets.match(/NovaDrillWords\.snapshotNote/g)||[]).length,2);
  assert.match(sheets,/ForEach\(catalogue\?\.employees \?\? \[\]\)/);
});

test('cancelling needs a reason on this side too',()=>{
  assert.match(sheets,/guard !trimmed\.isEmpty else \{ return \}/);
  assert.match(service,/guard !trimmed\.isEmpty else \{ throw NovaDrillFailure\.validation \}/);
});

test('every state carries a reason, so no row is a colour with no explanation',()=>{
  const explain=models.match(/static func explain\(_ drill: NovaDrill\) -> String \{[\s\S]*?\n    \}/)[0];
  for(const state of ['overdue','dueSoon','scheduled','performed','cancelled']){
    assert.ok(explain.includes(`case .${state}`),state);
  }
});

test('every state belongs to exactly one counter',()=>{
  const groups=models.match(/var states: \[NovaDrillState\] \{[\s\S]*?\n    \}/)[0];
  for(const state of ['overdue','dueSoon','scheduled','performed','cancelled']){
    assert.ok(groups.includes(`.${state}`),state);
  }
});

test('the two switches fail differently on this side as well',()=>{
  assert.match(adapter,/case "FEATURE_UNAVAILABLE": throw NovaDrillFailure\.featureUnavailable/);
  assert.match(adapter,/case "MODULE_UNAVAILABLE": throw NovaDrillFailure\.moduleUnavailable/);
});

test('every server refusal has its own sentence',()=>{
  const cases=[...adapter.matchAll(/case "([A-Z_]+)"[^:]*: throw NovaDrillFailure\.([a-zA-Z]+)/g)];
  const named=new Set(cases.map(m=>m[2]));
  for(const failure of ['performedInFuture','participantOutOfScope','alreadyPerformed']){
    assert.ok(named.has(failure),failure);
  }
  const messages=models.match(/var message: String \{[\s\S]*?\n    \}/)[0];
  for(const failure of named) assert.ok(messages.includes(`case .${failure}`),failure);
});

test('a drill with no plan says what to do rather than looking broken',()=>{
  assert.match(screens,/localizable\.nova\.drill\.empty\.noplan/);
  assert.match(sheets,/localizable\.nova\.drill\.empty\.noplan/);
});

test('the filters are side by side and the list opens below',()=>{
  const row=screens.match(/HStack\(spacing: 8\) \{[\s\S]*?\n            \}/)[0];
  assert.equal((row.match(/NovaFileChooserButton/g)||[]).length,2);
  assert.match(screens,/if openChooser == "company" \{[\s\S]{0,200}NovaFileChooserPanel/);
  assert.match(screens,/if openChooser == "state" \{[\s\S]{0,200}NovaFileChooserPanel/);
});

test('the route exists, is reachable and is wired to the real gate',()=>{
  assert.match(navigation,/case drills/);
  assert.match(navigation,/case \.drills: return RDLocalization\.string\("localizable\.nova\.navigation\.drills"/);
  assert.match(navigation,/static let drawer: \[Self\] = \[[^\]]*\.drills/);
  assert.match(main,/case \.drills:\n\s+drills/);
  assert.match(gate,/NovaDrillScreen\(client: client/);
});
