import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const editors = read('App/DesignSystem/ISG/IsgWorkspaceParityEditors.swift');
const screen = read('App/DesignSystem/ISG/IsgWorkspaceDomainScreen.swift');
const api = read('App/Services/ISG/IsgWorkspaceAPI.swift');
const store = read('App/Services/ISG/IsgWorkspaceStore.swift');
const gate = read('App/Views/Components/NovaPilotMainGate.swift');
const migration = read('supabase/pilot-release/candidates/20260918020000_osgb_personal_pilot_parity.sql');

test('OSGB realised training uses the shared guided flow and registered-curriculum behavior', () => {
  for (const source of [
    'IsgWorkspaceTrainingCreateEditor', 'case info, schedule, trainers, participants, review',
    'NovaTaskHeader', 'NovaTaskStickyActions', 'topicEditor',
    'store.trainingAdvanced(.curricula)', 'applyTemplate()', 'curriculum.topics',
    'training_link_curriculum', '"action": .string("complete")', 'store.employees()'
  ]) assert.match(editors, new RegExp(source.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.doesNotMatch(editors.slice(editors.indexOf('struct IsgWorkspaceTrainingCreateEditor'), editors.indexOf('struct IsgWorkspaceManualNonconformityEditor')), /NovaCompanyAccordion/);
  assert.doesNotMatch(editors, /plan_create|plan_activate|annualPlans/);
  assert.match(screen, /domain == \.training[\s\S]*IsgWorkspaceTrainingCreateEditor/);
});

test('OSGB risk revisions preserve the original assessment date and use the personal 2-4-6 period rule', () => {
  assert.match(editors, /case details, file, review/);
  assert.match(editors, /NovaTaskHeader\(title: assessment == nil/);
  assert.match(editors, /Text\("Kısmi revizyon"\)\.tag\("partial"\)/);
  assert.match(editors, /Text\("Bilgi düzeltmesi"\)\.tag\("metadata"\)/);
  assert.match(editors, /"assessment_on": \.string\(kind == "full" \? Self\.day\(date\) : baseDate\)/);
  assert.doesNotMatch(editors, /\.tag\("rescan"\)/);
  assert.match(screen, /case "high"[\s\S]*return 2/);
  assert.match(screen, /case "medium"[\s\S]*return 4/);
  assert.match(screen, /default: return 6/);
  for (const action of ['edit_draft', 'cancel_draft', 'finalize']) assert.ok(screen.includes(`\"action\": .string(\"${action}\")`), action);
  assert.match(screen, /expected_edit_revision/);
  assert.match(screen, /cancellation_note/);
  assert.match(api, /struct IsgWorkspaceRiskVersion/);
  assert.match(api, /editRevision: \(value\[\"edit_revision\"\] as\? NSNumber\)\?\.intValue \?\? 0/);
  for (const token of ["'edit_draft'", "'cancel_draft'", 'expected_edit_revision', 'edit_revision=edit_revision+1'])
    assert.ok(migration.includes(token), token);
});

test('OSGB periodic controls use catalog defaults and a three-step report flow', () => {
  for (const source of [
    'IsgWorkspaceEquipmentCreateEditor', 'store.equipmentCatalog()',
    'case control, details, report', 'Rapor no / harici referans',
    'İSG-KATİP ataması yapıldı', 'workspace_asset_id', 'recalculateEquipmentDueDate()'
  ]) assert.match(editors + screen, new RegExp(source.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(api, /func equipmentCatalog\(/);
  assert.match(screen, /domain == \.equipment[\s\S]*IsgWorkspaceEquipmentCreateEditor/);
  for (const action of ['"action": .string("update")', '"action": .string("set_rule")', '"action": .string("archive")'])
    assert.ok(screen.includes(action), action);
  assert.match(api, /struct IsgWorkspaceEquipmentInspection/);
});

test('OSGB detail panels reload authoritative history instead of reusing list summaries', () => {
  assert.match(api, /func domainDetail\(/);
  assert.match(api, /arguments\[\"p_id\"\]/);
  assert.match(api, /domain == \.equipment \{ request\.arguments\[\"p_kind\"\] = \.string\(\"detail\"\) \}/);
  assert.match(store, /func domainDetail\(/);
  assert.match(screen, /store\.domainDetail\(domain, id: row\.id\)/);
  assert.match(screen, /Sürüm geçmişi/);
  assert.match(screen, /Kontrol ve rapor geçmişi/);
});

test('all parity editors stay on tenant-scoped stores with no personal-service escape', () => {
  assert.doesNotMatch(editors, /NovaEducationService|NovaRiskAssessmentService|NovaEquipmentCheckService|CompanyService/);
  assert.match(editors, /@ObservedObject var store: IsgWorkspaceStore/g);
  assert.match(gate, /companyHazardClass: company\.hazardClass/);
});

test('personal and OSGB experts use the same root, route catalog and dashboard surface', () => {
  const navigation = read('App/DesignSystem/ISG/NovaNavigation.swift');
  const shell = read('App/DesignSystem/ISG/NovaExpertShell.swift');
  assert.match(navigation, /enum NovaWorkspaceRole/);
  assert.match(navigation, /static let sharedDestinations/);
  assert.match(gate, /workspaceStore == nil[\s\S]*NovaWorkspaceRole\.personnel\.destinations/);
  assert.match(gate, /NovaWorkspaceRole\.osgbExpert\.destinations/);
  assert.match(gate, /membership\.role == "expert"[\s\S]*NovaPilotRoot\(identity: identity,[\s\S]*workspaceStore: store/);
  assert.match(gate, /workspaceStore == nil[\s\S]*NovaWorkspaceRole\.personnel\.destinations[\s\S]*NovaWorkspaceRole\.osgbExpert\.destinations/);
  assert.match(gate, /NovaDashboardScreen\(data: osgbDashboardData/);
  assert.match(gate, /NovaDashboardScreen\(data: \.init\([\s\S]*metrics: metrics/);
  assert.match(shell, /destination != \.newCompany \|\| onCompanyCreate != nil/);
});

test('statutory training presets are editable and suggest class-based validity', () => {
  for (const marker of [
    'Temel İSG Eğitimi · Az Tehlikeli', 'total: 480', 'validityYears: 3',
    'Temel İSG Eğitimi · Tehlikeli', 'total: 720', 'validityYears: 2',
    'Temel İSG Eğitimi · Çok Tehlikeli', 'total: 960', 'validityYears: 1',
    'ForEach($topics)', 'Stepper("\\(topic.minutes) dakika"', 'refreshSuggestedValidity()'
  ]) assert.ok(editors.includes(marker), marker);
});

test('workspace manual nonconformity mirrors the normal expert steps and stays tenant scoped', () => {
  for (const marker of [
    'IsgWorkspaceManualNonconformityEditor',
    'case attachment, workplace, hazard, scoring, legislation, responsible',
    'NovaRiskScoreEditor(score: $score)',
    'Fotoğraf veya kanıt ekle (isteğe bağlı)',
    'store.mutateDomain(', 'domain: .nonconformity',
    'parentKind: "nonconformity"'
  ]) assert.ok(editors.includes(marker), marker);
  assert.match(screen, /domain == \.nonconformity[\s\S]*IsgWorkspaceManualNonconformityEditor/);
});
