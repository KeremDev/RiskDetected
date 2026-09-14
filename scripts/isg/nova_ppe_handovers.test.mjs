import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const models=read('App/DesignSystem/ISG/NovaPPEHandovers.swift');
const screens=read('App/DesignSystem/ISG/NovaPPEScreens.swift');
const sheets=read('App/DesignSystem/ISG/NovaPPESheets.swift');
const service=read('App/Services/Company/NovaPPEService.swift');
const adapter=read('App/Services/Company/NovaPPELiveAdapter.swift');
const gate=read('App/Views/Components/NovaPilotPPEGate.swift');
const navigation=read('App/DesignSystem/ISG/NovaNavigation.swift');
const main=read('App/Views/Components/NovaPilotMainGate.swift');

test('the design layer never imports the SDK',()=>{
  for(const source of [models,screens,sheets]) assert.doesNotMatch(source,/^import Supabase$/m);
  assert.match(adapter,/^import Supabase$/m);
});

test('the client never sends a signed copy flag, only where the form is',()=>{
  const handover=service.match(/func recordHandover\([\s\S]*?\n    \}/)[0];
  assert.doesNotMatch(handover,/signed_copy"/);
  assert.match(handover,/payload\["signed_copy_location"\] = \.string\(location\)/);
  assert.match(models,/let signedCopyStored: Bool/);
  assert.match(models,/static let signedCopyNote/);
  // Said at the top of the board and again beside the field.
  assert.match(screens,/NovaPPEWords\.signedCopyNote/);
  assert.match(sheets,/NovaPPEWords\.signedCopyNote/);
});

test('only the units and conditions the server accepts are offered',()=>{
  assert.match(sheets,/ForEach\(catalogue\?\.units \?\? NovaPPEUnit\.allCases\)/);
  assert.match(sheets,/ForEach\(catalogue\?\.conditions \?\? NovaPPECondition\.allCases\)/);
  assert.match(models,/case piece, pair, set, metre, litre/);
  assert.match(models,/case reusable, worn, damaged, lost/);
});

test('every state is its own counter, with no group layer to disagree with',()=>{
  assert.match(models,/case outstanding, partial, closed/);
  assert.doesNotMatch(models,/enum NovaPPEGroup/);
  assert.match(screens,/ForEach\(NovaPPEState\.allCases\)/);
});

test('every state carries a reason, so no row is a colour with no explanation',()=>{
  const explain=models.match(/static func explain\(_ handover: NovaPPEHandover\) -> String \{[\s\S]*?\n    \}/)[0];
  for(const state of ['outstanding','partial','closed']) assert.ok(explain.includes(`case .${state}`),state);
});

test('the return form says what is still out before anything is typed',()=>{
  assert.match(models,/var outstanding: Double = 0/);
  assert.match(models,/var unit: NovaPPEUnit = \.piece/);
  assert.match(sheets,/localizable\.nova\.ppe\.return\.outstanding/);
  assert.match(sheets,/NovaPPEWords\.amount\(draft\.outstanding, draft\.unit\)/);
});

test('taking a return back is offered as a correction',()=>{
  assert.match(sheets,/localizable\.nova\.ppe\.detail\.remove/);
  assert.match(service,/func removeReturn\(/);
});

test('no fixed equipment list is offered, and the form says so',()=>{
  assert.match(models,/let itemCatalogueOffered: Bool/);
  assert.match(models,/static let noCatalogueNote/);
  assert.match(sheets,/NovaPPEWords\.noCatalogueNote/);
});

test('the two switches fail differently on this side as well',()=>{
  assert.match(adapter,/case "FEATURE_UNAVAILABLE": throw NovaPPEFailure\.featureUnavailable/);
  assert.match(adapter,/case "MODULE_UNAVAILABLE": throw NovaPPEFailure\.moduleUnavailable/);
});

test('every server refusal has its own sentence',()=>{
  const cases=[...adapter.matchAll(/case "([A-Z_]+)"[^:]*: throw NovaPPEFailure\.([a-zA-Z]+)/g)];
  const named=new Set(cases.map(m=>m[2]));
  for(const failure of ['handedInFuture','returnedInFuture','returnBeforeHandover','returnExceedsHandover']){
    assert.ok(named.has(failure),failure);
  }
  const messages=models.match(/var message: String \{[\s\S]*?\n    \}/)[0];
  for(const failure of named) assert.ok(messages.includes(`case .${failure}`),failure);
});

test('a whole quantity is shown as a whole number',()=>{
  const amount=models.match(/static func amount\([\s\S]*?\n    \}/)[0];
  assert.match(amount,/rounded == rounded\.rounded\(\)/);
  assert.match(amount,/String\(Int\(rounded\)\)/);
});

test('the filters are side by side and the list opens below',()=>{
  const row=screens.match(/HStack\(spacing: 8\) \{[\s\S]*?\n            \}/)[0];
  assert.equal((row.match(/NovaFileChooserButton/g)||[]).length,2);
  assert.match(screens,/if openChooser == "company" \{[\s\S]{0,200}NovaFileChooserPanel/);
  assert.match(screens,/if openChooser == "state" \{[\s\S]{0,200}NovaFileChooserPanel/);
});

test('the route exists, is reachable and is wired to the real gate',()=>{
  assert.match(navigation,/case ppeHandovers/);
  assert.match(navigation,/case \.ppeHandovers: return RDLocalization\.string\("localizable\.nova\.navigation\.ppe"/);
  assert.match(navigation,/static let drawer: \[Self\] = \[[^\]]*\.ppeHandovers/);
  assert.match(main,/case \.ppeHandovers:\n\s+ppe/);
  assert.match(gate,/NovaPPEScreen\(client: client/);
});
