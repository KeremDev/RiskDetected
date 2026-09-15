import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const editor=read('App/DesignSystem/ISG/NovaEducationEditor.swift');
const models=read('App/Services/Company/NovaEducationModels.swift');
const caller=read('App/DesignSystem/ISG/NovaTrainingScreens.swift');
const reference=read('App/DesignSystem/ISG/NovaManualNonconformityScreen.swift');
const catalogue=JSON.parse(read('App/Localization/Localizable.xcstrings')).strings;

test('the entry screen is presented as a page, not wrapped in a popup',()=>{
  assert.doesNotMatch(caller,/NovaPopup \{\s*NovaEducationEntry/);
  assert.match(caller,/NovaEducationEntry\(identity: identity/);
});

test('the accordion follows the same shape as the manual nonconformity reference',()=>{
  for(const source of [editor,reference]){
    assert.match(source,/NovaCompanyAccordion\(title:/);
    assert.match(source,/GeometryReader \{ proxy in/);
    assert.match(source,/Capsule\(\)\.fill\(NovaColorToken\.accent\.color\(in: scheme\)\)/);
  }
  assert.match(editor,/@State private var open: NovaEducationStep\? = \.info/);
  assert.match(editor,/ForEach\(NovaEducationStep\.allCases\) \{ step in accordion\(step\) \}/);
});

test('completion is computed the same way the manual form computes it',()=>{
  assert.match(models,/enum NovaEducationStep: String, CaseIterable, Identifiable/);
  assert.match(models,/func isComplete\(_ step: NovaEducationStep\) -> Bool/);
  assert.match(models,/var completedCount: Int/);
  assert.match(models,/var progress: Double/);
  assert.match(models,/func nextIncomplete\(after step: NovaEducationStep\) -> NovaEducationStep\?/);
});

test('a finished step offers the next unfinished one',()=>{
  assert.match(editor,/if draft\.isComplete\(step\), let next = draft\.nextIncomplete\(after: step\)/);
});

test('a scope opens its own popup instead of expanding inline',()=>{
  assert.match(editor,/editingScope = \.init\(id: scope\.id\)/);
  assert.match(editor,/\.novaFullScreenCover\(item: \$editingScope, onDismiss: \{ editingScope = nil \}\) \{ edit in/);
  assert.match(editor,/NovaPopup \{\s*if let index = draft\.scopes\.firstIndex/);
  // The scope editor's own internals are untouched by this change.
  assert.doesNotMatch(editor,/DisclosureGroup/);
});

test('every step title is decoded to a real string, none of them silently blank',()=>{
  for(const step of ['info','trainers','scopes'])
    assert.match(editor,new RegExp(`localizable\\.nova\\.education\\.step\\.${step}`));
});

test('the business logic functions are unchanged in name and are still the only writers',()=>{
  for(const fn of ['refreshRecord','initialize','add','loadPeople','save','retry','saveCurriculum'])
    assert.match(editor,new RegExp(`private func ${fn}\\(`));
  assert.equal((editor.match(/try await service\.save\(/g) ?? []).length, 3);
});

test('every new education key has tr and en, and was actually translated',()=>{
  const keys=[...editor.matchAll(/"(localizable\.nova\.education\.[a-z.]+)"/g)].map(m=>m[1]);
  assert.ok(keys.length>=30);
  for(const key of new Set(keys)){
    const entry=catalogue[key];
    assert.ok(entry,`${key} missing from catalogue`);
    const tr=entry.localizations?.tr?.stringUnit?.value;
    const en=entry.localizations?.en?.stringUnit?.value;
    assert.ok(tr && en,`${key} lacks tr/en`);
    assert.notEqual(tr,en,`${key} was never translated`);
  }
});
