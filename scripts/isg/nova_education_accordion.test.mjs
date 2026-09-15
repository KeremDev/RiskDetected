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
const topicsPopup=read('App/DesignSystem/ISG/NovaEducationScopeEditor.swift');
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

test('the record has four steps: info, schedule, trainers, participants',()=>{
  assert.match(models,/case info, schedule, trainers, participants/);
  assert.match(editor,/case \.info: infoStep/);
  assert.match(editor,/case \.schedule: scheduleStep/);
  assert.match(editor,/case \.trainers: trainersStep/);
  assert.match(editor,/case \.participants: participantsStep/);
});

test('one shared template curriculum is mirrored into every scope, not edited per scope',()=>{
  // Cycle, topics, method, schedule and location are all edited on
  // `template`, one place — never on an individual `draft.scopes[i]`
  // directly from the UI, which is what made "kapsamlar" read as separate
  // parallel trainings that happened to share a screen.
  assert.match(editor,/@State private var template = NovaEducationScope/);
  assert.match(editor,/\.onChange\(of: template\) \{ value in/);
  assert.match(editor,/Picker\("", selection: \$template\.cycle\)/);
  assert.doesNotMatch(editor,/\$scope\.cycle/);
  assert.doesNotMatch(editor,/\$draft\.scopes\[index\]\.topics/);
});

test('adding a second company to the same record refuses a mismatched hazard class and otherwise shares the curriculum',()=>{
  assert.match(editor,/template\.hazard_class != wp\.hazard_class/);
  assert.match(editor,/localizable\.nova\.education\.scope\.hazardmismatch/);
  assert.match(editor,/scope\.topics = template\.topics\.map/);
});

test('topics open in their own popup bound to the shared template, not a real scope by id',()=>{
  assert.match(editor,/NovaEducationTopicsPopup\(scope: \$template, context: context, trainers: draft\.trainers,/);
  assert.match(editor,/hazardLocked: !draft\.scopes\.isEmpty/);
  assert.match(topicsPopup,/struct NovaEducationTopicsPopup: View/);
  // A topic can be switched off for a session that only covered part of the
  // curriculum, without deleting it from the record's definition.
  assert.match(topicsPopup,/includedBinding/);
  assert.doesNotMatch(topicsPopup,/struct NovaEducationScopeEditor/);
});

test('participants are grouped by company, not by a manually-added scope card',()=>{
  assert.match(editor,/private func companySection/);
  assert.match(editor,/private func participantBinding/);
  assert.match(editor,/ForEach\(companies\.filter \{ writableCompanies\.contains\(\$0\.id\) \}\) \{ company in/);
  // İşyeri ünvanı / işveren vekili are no longer typed by hand.
  assert.doesNotMatch(editor,/TextField\("İşyeri tam unvanı/);
  assert.doesNotMatch(editor,/TextField\("İşveren/);
});

test('the business logic functions are unchanged in name and are still the only writers',()=>{
  for(const fn of ['refreshRecord','initialize','add','loadPeople','save','retry','saveCurriculum'])
    assert.match(editor,new RegExp(`private func ${fn}\\(`));
  assert.equal((editor.match(/try await service\.save\(/g) ?? []).length, 3);
});

test('every step title is decoded to a real string, none of them silently blank',()=>{
  for(const step of ['info','schedule','trainers','participants'])
    assert.match(editor,new RegExp(`localizable\\.nova\\.education\\.step\\.${step}`));
});

test('every new education key has tr and en, and was actually translated',()=>{
  // "Online" is the same loanword in both languages — not an untranslated copy-paste.
  const sameInBothLanguages=new Set(['localizable.nova.education.method.online']);
  const keys=[...`${editor}\n${topicsPopup}`.matchAll(/"(localizable\.nova\.education\.[a-z.]+)"/g)].map(m=>m[1]);
  assert.ok(keys.length>=45);
  for(const key of new Set(keys)){
    const entry=catalogue[key];
    assert.ok(entry,`${key} missing from catalogue`);
    const tr=entry.localizations?.tr?.stringUnit?.value;
    const en=entry.localizations?.en?.stringUnit?.value;
    assert.ok(tr && en,`${key} lacks tr/en`);
    if(!sameInBothLanguages.has(key)) assert.notEqual(tr,en,`${key} was never translated`);
  }
});
