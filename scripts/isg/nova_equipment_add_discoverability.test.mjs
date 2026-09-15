import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const screens=read('App/DesignSystem/ISG/NovaEquipmentCheckScreens.swift');
const gate=read('App/Views/Components/NovaPilotEquipmentGate.swift');
const company=read('App/Views/Components/NovaCompanyManagementGate.swift');
const catalogue=JSON.parse(read('App/Localization/Localizable.xcstrings')).strings;

test('the header pill says what it does, not just a noun',()=>{
  assert.match(screens,/localizable\.nova\.equipment\.add\.short.*fallback: "Ekipman Ekle"/);
  const entry=catalogue['localizable.nova.equipment.add.short'];
  assert.equal(entry.localizations.tr.stringUnit.value,'Ekipman Ekle');
  assert.notEqual(entry.localizations.tr.stringUnit.value,'Ekipman');
});

test('the company detail strip can open the add sheet directly',()=>{
  assert.match(screens,/var onAdd: \(\(\) -> Void\)\? = nil/);
  assert.match(screens,/if let onAdd \{/);
  assert.match(company,/onAdd: \{ equipmentAdding = true; equipmentSection = section \}/);
  assert.match(company,/startInAddMode: equipmentAdding/);
});

test('startInAddMode is threaded from the gate down to the actual sheet flag',()=>{
  assert.match(gate,/var startInAddMode = false/);
  assert.match(gate,/startInAddMode: startInAddMode/);
  assert.match(screens,/var startInAddMode = false/);
  assert.match(screens,/if startInAddMode && company != nil \{ adding = true \}/);
});

test('opening in add mode never fires before a company is actually set',()=>{
  // Guards against opening the sheet with company == nil, which the add
  // sheet cannot save against.
  assert.match(screens,/company = initialCompany\n\s*companies = \(try\? await client\.companies\(\)\) \?\? \[\]\n\s*if startInAddMode && company != nil/);
});

test('equipmentAdding resets on dismiss so a later plain open is not mistaken for add mode',()=>{
  assert.match(company,/summaryRevision = UUID\(\); equipmentAdding = false/);
});

test('every new word is in the catalogue with tr and en',()=>{
  const key='localizable.nova.equipment.section.add';
  const entry=catalogue[key];
  assert.ok(entry, `${key} missing from catalogue`);
  assert.ok(entry.localizations.tr?.stringUnit?.value);
  assert.ok(entry.localizations.en?.stringUnit?.value);
  assert.notEqual(entry.localizations.tr.stringUnit.value, entry.localizations.en.stringUnit.value);
});
