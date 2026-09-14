import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const models=read('App/DesignSystem/ISG/NovaAppointments.swift');
const screens=read('App/DesignSystem/ISG/NovaAppointmentScreens.swift');
const sheets=read('App/DesignSystem/ISG/NovaAppointmentSheets.swift');
const service=read('App/Services/Company/NovaAppointmentService.swift');
const adapter=read('App/Services/Company/NovaAppointmentLiveAdapter.swift');
const gate=read('App/Views/Components/NovaPilotAppointmentGate.swift');
const navigation=read('App/DesignSystem/ISG/NovaNavigation.swift');
const main=read('App/Views/Components/NovaPilotMainGate.swift');

test('the design layer never imports the SDK',()=>{
  for(const source of [models,screens,sheets]) assert.doesNotMatch(source,/^import Supabase$/m);
  assert.match(adapter,/^import Supabase$/m);
});

test('nothing on this side can claim a qualification',()=>{
  assert.doesNotMatch(service,/qualification_verified": /);
  assert.match(models,/let qualificationVerified: Bool/);
  assert.match(models,/static let noQualificationNote/);
  // Said at the top of the board, on the record, and on the form.
  assert.match(screens,/NovaAppointmentWords\.noQualificationNote/);
  assert.equal((sheets.match(/NovaAppointmentWords\.noQualificationNote/g)||[]).length,2);
});

test('the board never counts against a requirement',()=>{
  assert.match(models,/let requiredCountKnown: Bool/);
  assert.match(models,/static let noRequiredCountNote/);
  assert.match(screens,/NovaAppointmentWords\.noRequiredCountNote/);
});

test('the basis is always sent, and the usual one only fills the field',()=>{
  const record=service.match(/func record\(_ identity[\s\S]*?\n    \}/)[0];
  assert.match(record,/"basis": \.string\(draft\.basis\.rawValue\)/);
  // Choosing a role prefills the usual basis; the expert can still change it.
  assert.match(sheets,/draft\.basis = role\.usualBasis/);
  assert.match(sheets,/ForEach\(catalogue\?\.bases \?\? NovaAppointmentBasis\.allCases\)/);
});

test('only the roles the server accepts are offered, as roles and as a filter',()=>{
  assert.match(models,/case supportStaff = "support_staff"/);
  assert.match(sheets,/ForEach\(catalogue\?\.roles\n?\s*\?\? NovaAppointmentKind\.allCases/);
  assert.match(screens,/catalogue\?\.roles \?\? NovaAppointmentKind\.allCases/);
});

test('the letter itself is never sent, only where it is',()=>{
  const record=service.match(/func record\(_ identity[\s\S]*?\n    \}/)[0];
  assert.doesNotMatch(record,/asset/);
  assert.match(record,/payload\["letter_location"\] = \.string\(location\)/);
  assert.match(models,/static let letterNote/);
  assert.match(sheets,/NovaAppointmentWords\.letterNote/);
});

test('ending and correcting are the same action, and the form says which',()=>{
  assert.match(models,/var isCorrection: Bool = false/);
  assert.match(screens,/isCorrection: row\.endsBefore != nil/);
  assert.match(sheets,/draft\.isCorrection\n?\s*\? RDLocalization\.string\("localizable\.nova\.appointment\.detail\.fix"/);
  assert.match(sheets,/localizable\.nova\.appointment\.end\.after/);
});

test('every state carries a reason, so no row is a colour with no explanation',()=>{
  const explain=models.match(/static func explain\(_ entry: NovaAppointment\) -> String \{[\s\S]*?\n    \}/)[0];
  for(const state of ['active','upcoming','ended']) assert.ok(explain.includes(`case .${state}`),state);
});

test('every state is its own counter, with no group layer to disagree with',()=>{
  assert.match(models,/case active, upcoming, ended/);
  assert.doesNotMatch(models,/enum NovaAppointmentGroup/);
  assert.match(screens,/ForEach\(NovaAppointmentState\.allCases\)/);
});

test('the two switches fail differently on this side as well',()=>{
  assert.match(adapter,/case "FEATURE_UNAVAILABLE": throw NovaAppointmentFailure\.featureUnavailable/);
  assert.match(adapter,/case "MODULE_UNAVAILABLE": throw NovaAppointmentFailure\.moduleUnavailable/);
});

test('every server refusal has its own sentence',()=>{
  const cases=[...adapter.matchAll(/case "([A-Z_]+)"[^:]*: throw NovaAppointmentFailure\.([a-zA-Z]+)/g)];
  const named=new Set(cases.map(m=>m[2]));
  for(const failure of ['overlap','basisRequired']) assert.ok(named.has(failure),failure);
  const messages=models.match(/var message: String \{[\s\S]*?\n    \}/)[0];
  for(const failure of named) assert.ok(messages.includes(`case .${failure}`),failure);
});

test('the filters are side by side and the list opens below',()=>{
  const row=screens.match(/HStack\(spacing: 8\) \{[\s\S]*?\n            \}/)[0];
  assert.equal((row.match(/NovaFileChooserButton/g)||[]).length,2);
  assert.match(screens,/if openChooser == "company" \{[\s\S]{0,200}NovaFileChooserPanel/);
  assert.match(screens,/if openChooser == "role" \{[\s\S]{0,200}NovaFileChooserPanel/);
});

test('the route exists, is reachable and is wired to the real gate',()=>{
  assert.match(navigation,/case appointments/);
  assert.match(navigation,/case \.appointments: return RDLocalization\.string\("localizable\.nova\.navigation\.appointments"/);
  assert.match(navigation,/static let drawer: \[Self\] = \[[^\]]*\.appointments/);
  assert.match(main,/case \.appointments:\n\s+appointments/);
  assert.match(gate,/NovaAppointmentScreen\(client: client/);
});
