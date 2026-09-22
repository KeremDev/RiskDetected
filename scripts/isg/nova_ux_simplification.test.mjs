import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const shell = read('App/DesignSystem/ISG/NovaExpertShell.swift');
const gate = read('App/Views/Components/NovaPilotMainGate.swift');
const personalCompany = read('App/Views/Components/NovaCompanyManagementGate.swift');
const domain = read('App/DesignSystem/ISG/IsgWorkspaceDomainScreen.swift');
const parity = read('App/DesignSystem/ISG/IsgWorkspaceParityEditors.swift');
const emergency = read('App/DesignSystem/ISG/IsgWorkspaceEmergencyPlanCreateFlow.swift');
const components = read('App/DesignSystem/ISG/NovaTaskFlowComponents.swift');

test('bottom navigation restores the legacy quick-add affordance', () => {
  const bar = shell.slice(shell.indexOf('struct NovaShellTabBar'), shell.indexOf('struct NovaPopupSurface'));
  for (const tab of ['tab(.home)', 'tab(.companies)', 'tab(.findings)', 'tab(.profile)']) assert.ok(bar.includes(tab), tab);
  assert.match(bar, /send\(\.open\(\.quickAdd\)\)/);
  assert.match(bar, /Circle\(\)\.fill\(Color\.black\)/);
  assert.match(bar, /accessibilityIdentifier\("nova\.add"\)/);
});

test('company detail is an action overview rather than a module card grid', () => {
  const overview = gate.slice(gate.indexOf('private func companyOverview('), gate.indexOf('private var search: some View'));
  for (const marker of ['Hazırlık durumu', 'Sıradaki işler', 'Firma ve kadro', 'Risk ve acil durum',
    'Kontrol ve kayıtlar', 'Eğitim ve organizasyon', 'Diğer kayıtlar']) assert.ok(overview.includes(marker), marker);
  assert.match(overview, /companyModuleStatus/);
  assert.match(overview, /Başlanmadı/);
  assert.match(overview, /Takip gerekli/);
  assert.doesNotMatch(overview, /companyModuleGrid/);
  assert.doesNotMatch(overview, /\/ 100|score/i);
});

test('personal expert company workspace uses the same low-friction action hierarchy', () => {
  const workspace = personalCompany.slice(
    personalCompany.indexOf('struct NovaCompanyWorkspace')
  );
  const body = workspace.slice(workspace.indexOf('var body: some View'), workspace.indexOf('.navigationBarBackButtonHidden(true)'));
  for (const marker of ['companyOverviewCard', 'nextWorkSection', 'companyCategorySections']) {
    assert.ok(body.includes(marker), marker);
  }
  assert.doesNotMatch(body, /NovaCompanyAccordion/);
  assert.match(workspace, /Hazırlık durumu/);
  assert.match(workspace, /Sıradaki işler/);
});

test('long create tasks use one shared full-screen progress and recovery grammar', () => {
  for (const marker of ['NovaTaskHeader', 'NovaTaskErrorSummary', 'NovaTaskStickyActions', 'NovaTaskSuccessView']) {
    assert.ok(components.includes(`struct ${marker}`), marker);
  }
  assert.match(domain, /usesFullScreenCreate[\s\S]*domain != \.files && domain != \.personnel/);
  assert.match(domain, /novaFullScreenCover\(isPresented:/);
  assert.match(parity, /case info, schedule, trainers, participants, review/);
  assert.match(parity, /case details, file, review/);
  assert.match(emergency, /case scope, dates, team, file, review/);
  for (const source of [parity, emergency]) {
    assert.match(source, /confirmationDialog/);
    assert.match(source, /NovaTaskSuccessView/);
  }
});

test('personal risk and emergency creates are no longer centered one-page popups', () => {
  const risk = read('App/DesignSystem/ISG/NovaRiskScreens.swift');
  const emergencyScreen = read('App/DesignSystem/ISG/NovaEmergencyPlanScreens.swift');
  const emergencySheet = read('App/DesignSystem/ISG/NovaEmergencyPlanSheets.swift');
  const emergencyCreate = emergencySheet.slice(emergencySheet.indexOf('struct NovaEmergencyPlanSheet'));
  assert.match(risk, /novaFullScreenCover\(isPresented: \$creating/);
  assert.match(risk, /fullScreenTask: true/);
  assert.match(risk, /private enum Step: String, CaseIterable \{ case details, file, review \}/);
  assert.match(risk, /NovaTaskSuccessView\(title: "Risk değerlendirmesi kaydedildi"/);
  assert.match(emergencyScreen, /novaFullScreenCover\(item: \$drafting/);
  assert.match(emergencyScreen, /fullScreenTask: true/);
  assert.match(emergencyCreate, /private enum Step: String, CaseIterable \{ case scope, dates, team, file, review \}/);
  assert.match(emergencyCreate, /NovaTaskSuccessView\(title: "Acil durum planı kaydedildi"/);
  assert.doesNotMatch(emergencyCreate, /NovaPopup \{/);
});

test('lists start with search, use a compact metric strip and sort actionable records first', () => {
  const hierarchy = domain.slice(domain.indexOf('NovaListHeading'), domain.indexOf('.task(id: revision)'));
  assert.ok(hierarchy.indexOf('search') < hierarchy.indexOf('metrics(snapshot.metrics)'));
  assert.match(domain, /NovaMetricStrip\(items:/);
  assert.match(domain, /actionPriority/);
  assert.match(domain, /case "overdue", "expired", "failed", "critical": return 0/);
  assert.doesNotMatch(hierarchy, /NovaHelpHint\(text: helpText\)/);
});

test('emergency plan remains tenant scoped and keeps its existing mutation contract', () => {
  assert.match(emergency, /@ObservedObject var store: IsgWorkspaceStore/);
  assert.match(emergency, /domain: \.emergencyPlan/);
  assert.match(emergency, /"entity": \.string\("plan"\)/);
  assert.match(emergency, /"action": \.string\("publish"\)/);
  assert.match(emergency, /parentKind: "emergency_plan"/);
  assert.doesNotMatch(emergency, /Supabase|CompanyService|NovaEmergencyPlanService/);
});
