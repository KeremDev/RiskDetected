import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '../..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('education uses a five-step flow with schedule, trainers, self-add and review', () => {
  const model = read('App/Services/Company/NovaEducationModels.swift');
  const editor = read('App/DesignSystem/ISG/NovaEducationEditor.swift');
  assert.match(model, /case info, schedule, trainers, participants, review/);
  assert.match(editor, /NovaEducationStep\.allCases/);
  assert.match(editor, /Eğitici ekle/);
  assert.match(editor, /Kendimi ekle/);
  assert.match(editor, /Toplam süre/);
  assert.match(editor, /scheduleDays/);
});

test('analysis and home creation surfaces use compact metrics and equal actions', () => {
  const analysis = read('App/DesignSystem/ISG/NovaAnalysisListScreen.swift');
  const reports = read('App/DesignSystem/ISG/NovaAnalysisReportsScreen.swift');
  const shell = read('App/DesignSystem/ISG/NovaExpertShell.swift');
  assert.match(analysis, /NovaMetricStrip\(items:/);
  assert.match(reports, /NovaMetricStrip\(items:/);
  assert.match(shell, /Fotoğraftan analiz/);
  assert.match(shell, /Elle uygunsuzluk/);
});

test('emergency plan separates unpublished draft from publish', () => {
  const screen = read('App/DesignSystem/ISG/NovaEmergencyPlanScreens.swift');
  const sheet = read('App/DesignSystem/ISG/NovaEmergencyPlanSheets.swift');
  const osgb = read('App/DesignSystem/ISG/IsgWorkspaceEmergencyPlanCreateFlow.swift');
  assert.match(sheet, /onSaveDraft/);
  assert.match(sheet, /primaryTitle: currentStep == \.review \? "Yayımla"/);
  assert.match(screen, /savedDraft/);
  assert.match(osgb, /Taslak olarak kaydet/);
});

test('long rationale and acceptance plan have a progressive-disclosure component', () => {
  const components = read('App/DesignSystem/ISG/NovaTaskFlowComponents.swift');
  const docs = read('docs/isg/ISGADA_EK_EKRANLAR_UYGULAMA_DURUMU_2026-09-21.md');
  assert.match(components, /struct NovaWhyDisclosure/);
  assert.match(components, /Neden\?/);
  assert.match(docs, /P0–P3 önceliği/);
  assert.match(docs, /Kabul kontrol listesi/);
  assert.match(docs, /```mermaid/);
});
