import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const models=read('App/DesignSystem/ISG/NovaChecklists.swift');
const screens=read('App/DesignSystem/ISG/NovaChecklistScreens.swift');
const sheets=read('App/DesignSystem/ISG/NovaChecklistSheets.swift');
const service=read('App/Services/Company/NovaChecklistService.swift');
const adapter=read('App/Services/Company/NovaChecklistLiveAdapter.swift');
const gate=read('App/Views/Components/NovaPilotChecklistGate.swift');
const navigation=read('App/DesignSystem/ISG/NovaNavigation.swift');
const main=read('App/Views/Components/NovaPilotMainGate.swift');

test('the design layer never imports the SDK',()=>{
  for(const source of [models,screens,sheets]) assert.doesNotMatch(source,/^import Supabase$/m);
  assert.match(adapter,/^import Supabase$/m);
});

test('the record offer is off by default and only shown for a failing answer',()=>{
  assert.match(models,/var openNonconformity: Bool = false/);
  assert.match(sheets,/if draft\.result == \.nonconform \{ record \}/);
  // And the service only ever sends it when both are true.
  assert.match(service,/if draft\.result == \.nonconform && draft\.openNonconformity \{/);
});

test('the sentence that it never converts on its own is on every surface that answers',()=>{
  assert.match(models,/static let neverAutomatic/);
  // The run sheet says it once at the top and again beside the offer.
  assert.equal((sheets.match(/NovaChecklistWords\.neverAutomatic/g)||[]).length,2);
});

test('"not applicable" is only offered where the list allows it',()=>{
  assert.match(models,/let allowsNotApplicable: Bool/);
  assert.match(sheets,/draft\.allowsNotApplicable \? NovaChecklistResult\.allCases : \[\.conform, \.nonconform\]/);
  assert.match(sheets,/if !draft\.allowsNotApplicable \{/);
});

test('the product ships no list and the screens say so rather than looking empty',()=>{
  assert.match(models,/static let noProductList/);
  assert.match(screens,/NovaChecklistWords\.noProductList/);
  assert.match(sheets,/NovaChecklistWords\.noProductList/);
  assert.match(models,/let productTemplatesOffered: Bool/);
});

test('publishing is said to be the expert own approval, not a regulatory one',()=>{
  assert.match(models,/static let selfApproved/);
  assert.match(models,/mevzuat onayı değildir/);
  assert.match(sheets,/NovaChecklistWords\.selfApproved/);
  // The client has no field for naming an approver.
  assert.doesNotMatch(service,/approver/);
});

test('the pinned version is stated as a fact about the run',()=>{
  assert.match(models,/let templateVersion: Int/);
  assert.match(sheets,/localizable\.nova\.checklist\.run\.pinned/);
});

test('a submitted run is closed on screen as well as on the server',()=>{
  assert.match(sheets,/if canWrite && run\.state == \.open \{ actions \}/);
  assert.match(sheets,/guard canWrite, run\.state == \.open else \{ return \}/);
});

test('a completed run cannot be submitted while a question is unanswered',()=>{
  assert.match(sheets,/\.disabled\(working \|\| run\.remaining > 0\)/);
  assert.match(sheets,/localizable\.nova\.checklist\.run\.remaining/);
});

test('every state carries a reason, so no row is a colour with no explanation',()=>{
  const explain=models.match(/static func explain\(_ run: NovaChecklistRun\) -> String \{[\s\S]*?\n    \}/)[0];
  for(const state of ['open','submitted','cancelled']) assert.ok(explain.includes(`case .${state}`),state);
});

test('every server refusal has its own sentence',()=>{
  const cases=[...adapter.matchAll(/case "([A-Z_]+)"[^:]*: throw NovaChecklistFailure\.([a-zA-Z]+)/g)];
  const named=new Set(cases.map(m=>m[2]));
  for(const failure of ['runSubmitted','runIncomplete','templatePublished']) assert.ok(named.has(failure),failure);
  const messages=models.match(/var message: String \{[\s\S]*?\n    \}/)[0];
  for(const failure of named) assert.ok(messages.includes(`case .${failure}`),failure);
});

test('the filters are side by side and the list opens below',()=>{
  const row=screens.match(/HStack\(spacing: 8\) \{[\s\S]*?\n            \}/)[0];
  assert.equal((row.match(/NovaFileChooserButton/g)||[]).length,2);
  assert.match(screens,/if openChooser == "company" \{[\s\S]{0,200}NovaFileChooserPanel/);
  assert.match(screens,/if openChooser == "state" \{[\s\S]{0,200}NovaFileChooserPanel/);
});

test('the route exists, is reachable and is wired to the real gate',()=>{
  assert.match(navigation,/case checklists/);
  assert.match(navigation,/case \.checklists: return RDLocalization\.string\("localizable\.nova\.navigation\.checklists"/);
  assert.match(navigation,/static let drawer: \[Self\] = \[[^\]]*\.checklists/);
  assert.match(main,/case \.checklists:\n\s+checklists/);
  assert.match(gate,/NovaChecklistScreen\(client: client/);
});
