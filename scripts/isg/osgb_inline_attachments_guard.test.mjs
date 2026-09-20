import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');

const fileEditor = read('App/DesignSystem/ISG/IsgWorkspaceFileCreateEditor.swift');
const createEditor = read('App/DesignSystem/ISG/IsgWorkspaceDomainCreateEditor.swift');
const parityEditors = read('App/DesignSystem/ISG/IsgWorkspaceParityEditors.swift');
const domainScreen = read('App/DesignSystem/ISG/IsgWorkspaceDomainScreen.swift');
const personnelScreen = read('App/DesignSystem/ISG/IsgWorkspacePersonnelScreen.swift');
const api = read('App/Services/ISG/IsgWorkspaceAPI.swift');
const store = read('App/Services/ISG/IsgWorkspaceStore.swift');

test('inline picker defers uploads until the business form is saved', () => {
  assert.match(fileEditor, /struct IsgWorkspaceInlineAttachmentField/);
  assert.match(fileEditor, /struct IsgWorkspaceAttachmentDraft/);
  assert.match(fileEditor, /52_428_800/);
  assert.match(fileEditor, /cancelling a form does not/);
});

test('uploaded files expose their logical entry and can be attached to a parent', () => {
  assert.match(api, /struct IsgWorkspaceFileUploadResult[\s\S]*let entryID: UUID/);
  assert.match(api, /entryID = "entry_id"/);
  assert.match(api, /guard let entryID = entry\.recordID/);
  assert.match(store, /func attachFile\(/);
  assert.match(store, /"action": \.string\("attach"\)/);
});

test('every primary OSGB create flow offers an in-context attachment', () => {
  assert.match(createEditor, /private var attachmentParentKind/);
  for (const parent of [
    'training', 'risk_assessment', 'nonconformity', 'checklist', 'emergency_plan',
    'drill', 'appointment', 'ppe', 'equipment', 'katip_contract', 'annual_plan',
    'board', 'work_permit', 'site_visit'
  ]) assert.match(createEditor, new RegExp(`return "${parent}"`));
  assert.match(createEditor, /try await attach\(uploaded, to: created\.recordID\)/);
  assert.match(personnelScreen, /parentKind: "employee"/);
});

test('long flows use accordions and retain automatic dates with expert override', () => {
  assert.match(createEditor, /createAccordion\(\.record/);
  assert.match(createEditor, /createAccordion\(\.attachment/);
  assert.match(createEditor, /Otomatik geçerlilik tarihini değiştir/);
  assert.match(createEditor, /refreshAutomaticValidity/);
  assert.match(parityEditors, /case info, schedule, trainers, participants, attachment/);
  assert.match(parityEditors, /case kind, scope, reason, attachment/);
  assert.match(parityEditors, /case type, identity, period, attachment/);
  assert.match(parityEditors, /refreshSuggestedValidity/);
});

test('record actions upload evidence inline without a Files-screen prerequisite', () => {
  assert.match(domainScreen, /var acceptsAttachment: Bool/);
  assert.match(domainScreen, /Kontrol raporunu bu işlemde ekle/);
  assert.doesNotMatch(domainScreen, /Raporu önce Dosyalar alanına yükleyebilirsiniz/);
  assert.match(domainScreen, /"workspace_asset_id": assetID\.map\(IsgWorkspaceRPCValue\.id\) \?\? \.null/);
  assert.match(domainScreen, /try await attach\(uploaded\)/);
});
